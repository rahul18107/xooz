import httpx
import json
import re
from src.config import CLOUDFLARE_ACCOUNT_ID, CLOUDFLARE_API_TOKEN

CLOUDFLARE_URL = f"https://api.cloudflare.com/client/v4/accounts/{CLOUDFLARE_ACCOUNT_ID}/ai/run/@cf/meta/llama-3.1-8b-instruct"

SYSTEM_PROMPT = "You are Xooz, a personal assistant that processes a person's daily conversations captured via their smartwatch."

VALID_CATEGORIES = {"work", "personal", "social", "other"}


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


def _parse_json(text: str, fallback) -> dict:
    """LLMs sometimes wrap JSON in code fences or prose — extract the first JSON object."""
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


def classify_transcript(text: str) -> dict:
    """Tag a transcript so search categories (Work / Personal / Social, People, Places) work."""
    fallback = {"category": "other", "tags": [], "people": [], "places": []}
    if not text or not text.strip():
        return fallback

    prompt = f"""Analyze this conversation transcript and respond ONLY with a JSON object (no extra text):

{{
  "category": "work" | "personal" | "social" | "other",
  "tags": ["up to 5 lowercase topic tags"],
  "people": ["names of people spoken about or with"],
  "places": ["locations mentioned"]
}}

Transcript:
{text[:4000]}"""

    try:
        data = _call_llm(prompt, max_tokens=300)
        parsed = _parse_json(data, fallback)
        category = parsed.get("category", "other")
        if category not in VALID_CATEGORIES:
            category = "other"
        return {
            "category": category,
            "tags": list(parsed.get("tags") or [])[:5],
            "people": list(parsed.get("people") or []),
            "places": list(parsed.get("places") or []),
        }
    except Exception:
        return fallback


def summarize_transcript(text: str, speaker_labels: list | None = None) -> dict:
    """Summarize ONE recording for the transcript detail screen.
    Returns {"title": one-liner headline, "summary": bullet list}."""
    fallback_title = None
    turns = [
        f"Speaker {utterance['speaker']}: {utterance['text']}"
        for utterance in (speaker_labels or [])
        if utterance.get("speaker") and utterance.get("text")
    ]
    recording = "\n".join(turns) if turns else text
    if not recording or not recording.strip():
        return {"title": "Empty recording", "summary": "This recording has no transcript content."}

    prompt = f"""Summarize this single conversation recording. Format your response EXACTLY like this:
Line 1: a plain title of max 8 words (no quotes, no dash, no bullet)
Then 2-5 bullet lines starting with "- " covering what was discussed, decisions made, and commitments.
When speaker labels are present, attribute statements and commitments to the correct speaker.
Use Speaker A, Speaker B, etc. unless the recording explicitly identifies a person by name.

Recording:
{recording[:4000]}"""

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


def extract_tasks(text: str) -> list:
    """Pull actionable to-dos out of a transcript."""
    if not text or not text.strip():
        return []

    prompt = f"""Extract actionable tasks/to-dos the speaker committed to in this conversation.
Respond ONLY with a JSON object (no extra text). If there are no tasks, return {{"tasks": []}}.

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
            {"title": str(t.get("title", "")).strip(), "due_date": t.get("due_date")}
            for t in tasks
            if isinstance(t, dict) and t.get("title")
        ][:10]
    except Exception:
        return []


def answer_question(message: str, context: dict) -> str:
    """Answer a user question grounded in their own recordings.
    context keys: digest (str|None), transcripts (list), history (list of {role, content})."""
    if not message or not message.strip():
        return ""

    context_parts = []
    if context.get("digest"):
        context_parts.append(f"Today's digest:\n{context['digest']}")
    for i, t in enumerate(context.get("transcripts", []), 1):
        context_parts.append(f"--- Conversation {i} ({t.get('recorded_at')}) ---\n{t['text']}")

    context_text = "\n\n".join(context_parts) if context_parts else "No conversations recorded yet."

    history = ""
    for msg in context.get("history", []):
        role = "User" if msg["role"] == "user" else "You"
        history += f"{role}: {msg['content']}\n"

    prompt = f"""Below are the user's recorded conversations from today.

{context_text}

{"Recent chat:\n" + history if history else ""}
Question: {message}

Answer using only the recorded conversations above. If the answer is not in them, say you
don't have a recording covering that. Keep the answer short and natural."""

    try:
        return _call_llm(prompt, max_tokens=512).strip()
    except Exception as e:
        raise Exception(f"Chat failed: {e}")
