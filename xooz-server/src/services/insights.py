import httpx
import json
import re
from datetime import datetime, timedelta, timezone
from src.config import CLOUDFLARE_ACCOUNT_ID, CLOUDFLARE_API_TOKEN

CLOUDFLARE_URL = f"https://api.cloudflare.com/client/v4/accounts/{CLOUDFLARE_ACCOUNT_ID}/ai/run/@cf/meta/llama-3.1-8b-instruct"

SYSTEM_PROMPT = "You are Xooz, a personal assistant that processes a person's daily conversations captured via their smartwatch."

def _call_llm(prompt: str, max_tokens: int = 512) -> str:
    headers = {
        "Authorization": f"Bearer {CLOUDFLARE_API_TOKEN}",
        "Content-Type": "application/json",
    }
    payload = {
        "messages": [
            {"role": "system", "content": SYSTEM_PROMPT},
            {"role": "user", "content": prompt},
        ],
        "max_tokens": max_tokens,
    }
    response = httpx.post(CLOUDFLARE_URL, headers=headers, json=payload, timeout=60.0)
    response.raise_for_status()
    result = response.json()
    if not result.get("success"):
        raise Exception(f"Cloudflare LLM call failed: {result.get('errors')}")
    return result["result"]["response"]


def _parse_json(text, fallback) -> dict:
    """LLMs sometimes wrap JSON in code fences or prose — extract the first JSON object."""
    if isinstance(text, dict):
        return text
    if isinstance(text, list):
        return fallback
    try:
        return json.loads(text)
    except (json.JSONDecodeError, TypeError):
        pass
    match = re.search(r"\{.*\}", text, re.DOTALL)
    if match:
        try:
            return json.loads(match.group(0))
        except json.JSONDecodeError:
            pass
    return fallback


def _recording_chunks(text: str, max_chars: int = 3500) -> list[str]:
    words = list(re.finditer(r"\S+", text))
    chunks = []
    start = 0
    while start < len(words):
        end = start
        while end < len(words) and words[end].end() - words[start].start() <= max_chars:
            end += 1
        end = max(start + 1, end)
        chunks.append(text[words[start].start():words[end - 1].end()])
        start = end
    return chunks


def _long_recording_evidence(recording: str) -> str:
    facts = []
    for chunk in _recording_chunks(recording):
        prompt = f"""Extract up to 3 important decisions, commitments, or discussion points from this part of a recording.
Return only JSON: {{"facts":[{{"text":"one factual sentence","quote":"exact contiguous quote from the recording"}}]}}.
If nothing important was said, return {{"facts":[]}}. Do not infer speaker identity or invent details.

Recording part:
{chunk}"""
        try:
            data = _parse_json(_call_llm(prompt, max_tokens=450), {"facts": []})
        except Exception:
            continue
        for fact in (data.get("facts") or [])[:3]:
            if not isinstance(fact, dict):
                continue
            statement, quote = fact.get("text"), fact.get("quote")
            if not isinstance(statement, str) or not isinstance(quote, str):
                continue
            if len(quote.strip()) < 8 or " ".join(quote.split()).casefold() not in " ".join(chunk.split()).casefold():
                continue
            details = re.findall(r"\b[A-Z][a-z]+\b|\b\d[\d./-]*\b", statement)
            quote_words = set(re.findall(r"[a-z0-9]+", quote.casefold()))
            if any(detail.casefold() not in quote_words for detail in details
                   if detail not in {"The", "A", "An", "We", "They", "It", "This", "That"}):
                continue
            facts.append(f"{statement.strip()} Evidence: {quote.strip()}")
    if len(facts) > 24:
        facts = [facts[int(i * len(facts) / 24)] for i in range(24)]
    return "\n".join(facts)


def summarize_transcript(text: str, speaker_labels: list | None = None, speaker_names: dict | None = None) -> dict:
    """Summarize ONE recording for the transcript detail screen.
    Returns {"title": one-liner headline, "summary": bullet list}."""
    fallback_title = None
    turns = [
        f"{(speaker_names or {}).get(str(utterance['speaker'])) or 'Speaker ' + str(utterance['speaker'])}: {utterance['text']}"
        for utterance in (speaker_labels or [])
        if utterance.get("speaker") and utterance.get("text")
    ]
    recording = "\n".join(turns) if turns else text
    if not recording or not recording.strip():
        return {"title": "Empty recording", "summary": "This recording has no transcript content."}

    if len(recording) > 4000:
        evidence = _long_recording_evidence(recording)
        if not evidence:
            return {"title": "Recording", "summary": "A reliable summary is not available for this recording."}
        recording = evidence

    prompt = f"""Summarize this single conversation recording. Format your response EXACTLY like this:
Line 1: a plain title of max 8 words (no quotes, no dash, no bullet)
Then 2-5 bullet lines starting with "- " covering what was discussed, decisions made, and commitments.
Write in the recording's dominant language. Keep names and places as spoken.
When speaker labels are present, attribute statements and commitments to the correct speaker.
Use the provided speaker names when present; otherwise use Speaker A, Speaker B, etc.

Recording:
{recording}"""

    response = _call_llm(prompt, max_tokens=400)

    lines = [l.strip() for l in response.strip().split('\n') if l.strip()]
    title = None
    if lines and not lines[0].startswith(('-', '•')):
        candidate = lines[0].lstrip('#* ').strip()
        if candidate:
            title = candidate[:60]
            lines = lines[1:]

    summary = '\n'.join(lines) if lines else response.strip()
    if not title and summary:
        fallback_title = summary.splitlines()[0].lstrip('-• ').strip()[:60]

    return {"title": title or fallback_title or "Recording", "summary": summary}


_WEEKDAYS = {
    "monday": 0, "tuesday": 1, "wednesday": 2, "thursday": 3,
    "friday": 4, "saturday": 5, "sunday": 6,
}


def task_briefs(tasks: list, transcript_text: str) -> dict:
    """One 2-line practical summary per task of a conversation, in a single LLM call."""
    ids = [t["id"] for t in tasks]
    listing = "\n".join(f"- id: {t['id']} | task: {t['title']}" for t in tasks)
    source = (transcript_text or "").strip()
    prompt = f"""You are Xooz. A conversation was recorded and these tasks were extracted from it:

{listing}

The conversation:
---
{(source or '(conversation not available)')[:4000]}
---

For EACH task id above, write a short practical summary (maximum 2 lines, plain text, no markdown, no asterisks) of exactly what the user should do about it, using concrete details from the conversation (names, places, deadlines, amounts). If a task is vague, keep the summary simple.
Respond ONLY with a JSON object, no extra text:

{{
  "briefs": [
    {{"id": "<task id>", "summary": "<max 2 short lines>"}}
  ]
}}"""
    try:
        parsed = _parse_json(_call_llm(prompt, max_tokens=600), {"briefs": []})
        briefs = {}
        for item in parsed.get("briefs") or []:
            if isinstance(item, dict) and item.get("id") in ids:
                summary = " ".join(str(item.get("summary", "")).split())
                if summary:
                    briefs[item["id"]] = summary
        return briefs
    except Exception:
        return {}


def _normalize_due_date(due):
    """Turn LLM date output like 'Friday' / 'tomorrow' into YYYY-MM-DD."""
    if not isinstance(due, str):
        return None
    due = due.strip().lower().removeprefix("by ").removeprefix("next ").removeprefix("this ").strip()
    if due in ("today",):
        return datetime.now(timezone.utc).strftime("%Y-%m-%d")
    if due in ("tomorrow",):
        return (datetime.now(timezone.utc) + timedelta(days=1)).strftime("%Y-%m-%d")
    weekday = _WEEKDAYS.get(due)
    if weekday is not None:
        today = datetime.now(timezone.utc).date()
        days_ahead = (weekday - today.weekday()) % 7 or 7
        return (today + timedelta(days=days_ahead)).strftime("%Y-%m-%d")
    if re.fullmatch(r"\d{4}-\d{2}-\d{2}", due):
        # sanity: a to-do dated more than 60 days in the past is almost
        # certainly a hallucinated year from the model — drop it
        try:
            parsed = datetime.strptime(due, "%Y-%m-%d").date()
        except ValueError:
            return None
        if (datetime.now(timezone.utc).date() - parsed).days > 60:
            return None
        return due
    return None


def extract_tasks(text: str) -> list:
    """Pull actionable to-dos out of a transcript."""
    if not text or not text.strip():
        return []

    today = datetime.now(timezone.utc)
    prompt = f"""Extract actionable tasks/to-dos the speaker committed to in this conversation.
Respond ONLY with a JSON object (no extra text). If there are no tasks, return {{"tasks": []}}.
Today's date is {today.strftime('%Y-%m-%d')} ({today.strftime('%A')}) — use it to resolve relative days like 'tomorrow' or weekday names into concrete YYYY-MM-DD dates.

{{
  "tasks": [
    {{"title": "short imperative task description", "due_date": "YYYY-MM-DD or null"}}
  ]
}}

Transcript:
{text[:4000]}"""

    try:
        data = _call_llm(prompt, max_tokens=400)
        parsed = _parse_json(data, {"tasks": []})
        tasks = parsed.get("tasks") or []
        return [
            {"title": str(t.get("title", "")).strip(),
             "due_date": _normalize_due_date(t.get("due_date"))}
            for t in tasks
            if isinstance(t, dict) and t.get("title")
        ][:10]
    except Exception:
        return []


def task_plan(title: str, due_date: str | None, transcript_text: str) -> str:
    """A short practical action plan for one task, grounded in the conversation it came from."""
    conversation = (transcript_text or "").strip()
    source = (
        f"The conversation the task came from:\n---\n{conversation[:4000]}\n---"
        if conversation
        else "The source conversation is not available."
    )
    prompt = f"""You are Xooz, helping the user complete one to-do extracted from a phone conversation.

Task: {title}
Due: {due_date or 'no due date'}

{source}

Write a short, practical action plan for this task. Rules:
- Plain text only, no markdown, no headings, no bold, no asterisks.
- Maximum 5 short bullet lines, each starting with "- ".
- Use what was actually said in the conversation: names, places, amounts, deadlines as given.
- If the conversation lacks details for a step, keep that step simple and generic.
Return only the bullet lines."""
    try:
        return _call_llm(prompt, max_tokens=300).strip()
    except Exception:
        return ""


def task_status_for_question(message: str) -> str | None:
    """Choose the task state requested by the user; None means all states."""
    lower = message.lower()
    if re.search(r"\b(?:all|every) (?:my )?tasks\b", lower):
        return None
    if re.search(r"\b(?:completed|finished|done)\b|\b(?:did i|have i) finish\b", lower):
        return "done"
    if re.search(r"\b(?:snoozed|postponed)\b", lower):
        return "snoozed"
    return "open"


def answer_question(message: str, context: dict, used_source_ids: list[str] | None = None) -> str:
    """Answer a user question grounded in their own recordings.
    context keys: transcripts (list), tasks (list), history (list of {role, content}),
    resolved_question (str|None)."""
    if not message or not message.strip():
        return ""

    transcripts = context.get("transcripts") or []
    tasks = context.get("tasks") or []
    event_day = context.get("event_day")
    if event_day:
        from src.services.temporal_evidence import quote_supports_day
        from datetime import date
        target_day = date.fromisoformat(event_day)
        tasks = [task for task in tasks if task.get("due_date") == event_day]
    intent_question = context.get("resolved_question") or message
    asks_completion_time = task_status_for_question(intent_question) == "done" and bool(re.search(
        r"\b(?:today|yesterday|when|this week|last week|this month|last month)\b",
        intent_question, re.IGNORECASE,
    ))
    if asks_completion_time and not any(task.get("completed_at") for task in tasks):
        return "I can't confirm when those tasks were completed from the saved task history."
    if not transcripts and not tasks:
        if event_day:
            return f"I couldn't confirm anything scheduled for {event_day} from your recordings or tasks."
        return (
            "I don't have any recordings or saved tasks to check right now. "
            "Record something first, then I can help pull out important things to do."
        )

    evidence = {}
    context_parts = []
    for i, task in enumerate(tasks, 1):
        source = f"task-{i}"
        details = (f"{task.get('title')} (status: {task.get('status') or 'open'}; "
                   f"due: {task.get('due_date') or 'not specified'})")
        if task.get("completed_at"):
            details += f" (completed at: {task.get('completed_at_local') or task['completed_at']})"
        evidence[source] = details
        context_parts.append(f"[{source}] {details}")
    for i, t in enumerate(transcripts, 1):
        text = (t.get("text") or "").strip()
        if text:
            source = f"recording-{i}"
            evidence[source] = text
            context_parts.append(f"[{source}] ({t.get('recorded_at')}):\n{text[:3500]}")

    context_text = "\n\n".join(context_parts)

    history = ""
    for msg in context.get("history", []):
        role = "User" if msg["role"] == "user" else "You"
        history += f"{role}: {msg['content']}\n"

    prompt = f"""Answer the question using only the evidence below. Return only JSON:
{{"claims": [{{"text": "one short factual sentence", "source": "recording-1 or task-1", "quote": "exact contiguous quote copied from that source"}}]}}
Give at most 4 claims. Every claim needs its own quote. Use an empty claims list if the evidence does not answer the question. Do not invent names, dates, tasks, decisions, or facts. Do not cite chat history as evidence. A plan in a recording does not prove a task was completed; only a task with status done does. The due date is not the completion date. For completion-time questions, use only a task's completed-at timestamp. {f'For this question, the requested event date is {event_day}. A recording date alone does not mean an event happens on that date. Only answer with an explicit date in the quote or a task due on that date; otherwise return no claims.' if event_day else ''}

{context_text}

{"Recent chat:\n" + history if history else ""}
Question: {message}

JSON:"""

    try:
        result = _parse_json(_call_llm(prompt, max_tokens=700), {"claims": []})
        answers = []
        for claim in (result.get("claims") or [])[:4]:
            if not isinstance(claim, dict):
                continue
            source, quote, statement = claim.get("source"), claim.get("quote"), claim.get("text")
            if not all(isinstance(item, str) for item in (source, quote, statement)):
                continue
            if len(quote.strip()) < 8 or not statement.strip() or source not in evidence:
                continue
            if task_status_for_question(intent_question) == "done" and source.startswith("recording-"):
                continue
            if asks_completion_time and source.startswith("task-"):
                task_index = int(source.removeprefix("task-")) - 1
                if not tasks[task_index].get("completed_at"):
                    continue
            if " ".join(quote.split()).casefold() not in " ".join(evidence[source].split()).casefold():
                continue
            if event_day and source.startswith("recording-"):
                recording_index = int(source.removeprefix("recording-")) - 1
                if not quote_supports_day(quote, transcripts[recording_index].get("recorded_at"),
                                          target_day, context.get("user_tz") or timezone.utc):
                    continue
            if event_day and re.search(r"\b(?:today|tonight|tomorrow|yesterday)\b", statement, re.I):
                from src.services.temporal_evidence import requested_day
                if not context.get("local_today") or requested_day(
                    statement, date.fromisoformat(context["local_today"])
                ) != target_day:
                    continue
            details = re.findall(r"\b[A-Z][a-z]+\b|\b\d[\d./-]*\b", statement)
            quote_words = set(re.findall(r"[a-z0-9]+", quote.casefold()))
            if any(not set(re.findall(r"[a-z0-9]+", detail.casefold())).issubset(quote_words)
                   for detail in details
                   if detail not in {"The", "A", "An", "I", "We", "They", "It", "This", "That"}):
                continue
            if source.startswith("recording-"):
                recording_index = int(source.removeprefix("recording-")) - 1
                recording_id = transcripts[recording_index].get("id")
                if used_source_ids is not None and recording_id:
                    if recording_id not in used_source_ids:
                        used_source_ids.append(recording_id)
            answers.append(statement.strip())
        if answers:
            return " ".join(answers)
        if event_day:
            return f"I couldn't confirm anything scheduled for {event_day} from your recordings or tasks."
        return "I don't have enough recorded information to answer that reliably."
    except Exception as e:
        raise Exception(f"Chat failed: {e}")
