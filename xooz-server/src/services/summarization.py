import httpx
import json
import re
import time
from src.config import CLOUDFLARE_ACCOUNT_ID, CLOUDFLARE_API_TOKEN, ACTIVE_SUMMARIZATION_PROVIDER

CLOUDFLARE_URL = f"https://api.cloudflare.com/client/v4/accounts/{CLOUDFLARE_ACCOUNT_ID}/ai/run/@cf/meta/llama-3.1-8b-instruct"

def _summarize_cloudflare(prompt: str) -> str | dict:
    headers = {
        "Authorization": f"Bearer {CLOUDFLARE_API_TOKEN}",
        "Content-Type": "application/json"
    }

    payload = {
        "messages": [
            {"role": "system", "content": "You are a personal assistant that summarizes a person's daily conversations captured via their smartwatch."},
            {"role": "user", "content": prompt}
        ],
        "max_tokens": 2600
    }

    for attempt in range(2):
        try:
            response = httpx.post(CLOUDFLARE_URL, headers=headers, json=payload, timeout=60.0)
            response.raise_for_status()
            break
        except (httpx.TimeoutException, httpx.NetworkError, httpx.RemoteProtocolError,
                httpx.HTTPStatusError) as exc:
            retryable = not isinstance(exc, httpx.HTTPStatusError) or exc.response.status_code in (429, 500, 502, 503, 504)
            if attempt or not retryable:
                raise
            time.sleep(0.75)

    result = response.json()

    if not result.get("success"):
        raise Exception(f"Cloudflare summarization failed: {result.get('errors')}")

    return result["result"]["response"]


def _raw_excerpt(text: str, limit: int = 2200) -> str:
    if len(text) <= limit:
        return text
    third = limit // 3
    middle = len(text) // 2
    return (text[:third] + "\n[omitted]\n" +
            text[middle - third // 2:middle + third // 2] +
            "\n[omitted]\n" + text[-third:])

def _conversation_context(transcripts: list) -> str:
    if not transcripts:
        return ""

    combined = ""
    for i, transcript in enumerate(transcripts, 1):
        combined += f"\n--- Conversation {i}, id {transcript.get('id')} ({transcript.get('recorded_at')}) ---\n"
        text = transcript.get('text') or ''
        combined += f"Raw transcript: {_raw_excerpt(text)}\n"
        if len(text) > 2200:
            combined += "[Only an excerpt of this recording is shown.]\n"

        turns = transcript.get("speaker_labels")
        if isinstance(turns, list) and turns:
            combined += "Speaker turns:\n"
            names = transcript.get("speaker_names")
            if not isinstance(names, dict):
                names = {}
            speaker_context = ""
            for utterance in turns:
                if not isinstance(utterance, dict) or not utterance.get("text"):
                    continue
                speaker = str(utterance.get("speaker") or "?")
                name = names.get(speaker)
                speaker_context += f"{name or 'Speaker ' + speaker}: {utterance['text']}\n"
                if len(speaker_context) >= 700:
                    break
            combined += speaker_context[:700]

    return combined


def _build_prompt(transcripts: list) -> str:
    if not transcripts:
        return ""
    return f"""Here are completed conversations recorded on one day:
{_conversation_context(transcripts)}

Return only a JSON object with this shape:
{{"title":"Specific 3-6 word title", "paragraphs":[{{"text":"One or two factual sentences.", "recording_id":"exact conversation id", "quote":"exact verbatim span from that conversation's transcript"}}], "action_items":[], "decisions":[], "unresolved_questions":[]}}
Write up to 5 substantive paragraphs (2-3 factual sentences each) when there is enough distinct evidence.
Cover the day's main topics, decisions, commitments, and follow-ups in chronological order when supported;
use fewer paragraphs for a short or repetitive day. Do not repeat the same point.
Write in the dominant language of the day's conversations.
Each paragraph must be supported by its own exact, contiguous quote copied from the Raw transcript.
For action_items, decisions, and unresolved_questions, include only explicit items stated in the recording.
Each item must use the same text, recording_id, and exact quote fields as a paragraph; empty arrays are fine.
If a paragraph needs evidence from two recordings, split it into two paragraphs.
Do not add names, dates, locations, decisions, or commitments not explicitly present in the quote.
If speaker identity is uncertain, do not attribute a commitment to a person.
Use no markdown, filler, or invented detail. The provided text may be excerpts;
do not claim to cover everything said in a recording."""


def _repair_prompt(transcripts: list) -> str:
    return f"""Summarize only one well-supported fact from these conversations.
{_conversation_context(transcripts)}

Return only JSON with this exact shape:
{{"title":"Short factual title", "paragraphs":[{{"text":"One factual sentence.", "recording_id":"exact id above", "quote":"exact contiguous words from that recording's Raw transcript"}}]}}
Copy the quote verbatim, including names and numbers used in the sentence.
Do not include any detail not present in the quote. Do not include other fields."""


def _prompt_batches(transcripts: list, max_chars: int = 14000) -> list[list]:
    batches = []
    batch = []
    for transcript in transcripts:
        candidate = batch + [transcript]
        if batch and len(_build_prompt(candidate)) > max_chars:
            batches.append(batch)
            batch = [transcript]
        else:
            batch = candidate
    if batch:
        batches.append(batch)
    return batches


def _source_title(transcripts: list) -> str:
    for transcript in transcripts:
        for candidate in (transcript.get("title"), transcript.get("text")):
            words = re.findall(r"[\w'-]+", (candidate or "").strip(), re.UNICODE)
            if words and (candidate or "").strip().casefold() not in {
                "recorded conversations", "recording", "daily recap", "conversation recap"
            }:
                title = " ".join(words[:7])
                return title[0].upper() + title[1:]
    return "Conversation recap"


def _parse_json_object(raw: str | dict) -> dict | None:
    if isinstance(raw, dict):
        return raw
    if not isinstance(raw, str):
        return None
    try:
        start, end = raw.index("{"), raw.rindex("}") + 1
        data = json.loads(raw[start:end])
        return data if isinstance(data, dict) else None
    except (ValueError, TypeError):
        return None


def _quote_present(quote: str, source: str) -> bool:
    words = re.findall(r"\w+", quote.casefold())
    if not words:
        return False
    source_words = re.findall(r"\w+", source.casefold())
    return ("\0" + "\0".join(words) + "\0") in ("\0" + "\0".join(source_words) + "\0")


def _validated_recap_data(raw: str | dict, transcripts: list) -> dict | None:
    try:
        data = _parse_json_object(raw)
        if data is None:
            return None
        title = data["title"]
        paragraphs = data["paragraphs"]
        if not isinstance(title, str) or not isinstance(paragraphs, list) or not paragraphs:
            return None
        sources = {str(t["id"]): t.get("text") or "" for t in transcripts}
        all_words = set(re.findall(r"[a-z0-9]+", " ".join(sources.values()).casefold()))
        title_details = re.findall(r"\b[A-Z][a-z]+\b|\b\d[\d./-]*\b", title)
        if (not title.strip() or title.strip().casefold() == "recorded conversations"
                or any(not set(re.findall(r"[a-z0-9]+", detail.casefold())).issubset(all_words)
                       for detail in title_details
                       if detail not in {"Daily", "Recorded", "Conversation"})):
            title = _source_title(transcripts)
        def validate_item(item):
            if not isinstance(item, dict):
                return None
            body, quote, source_id = item.get("text"), item.get("quote"), str(item.get("recording_id"))
            if not isinstance(body, str) or not body.strip() or not isinstance(quote, str) or len(quote.strip()) < 6:
                return None
            if source_id not in sources or not _quote_present(quote, sources[source_id]):
                return None
            quoted_words = set(re.findall(r"[a-z0-9]+", quote.casefold()))
            claimed_details = re.findall(r"\b[A-Z][a-z]+\b|\b\d[\d./-]*\b", body)
            generic_starts = {"The", "A", "An", "We", "They", "It", "This", "That", "During", "After", "Before"}
            if any(not set(re.findall(r"[a-z0-9]+", detail.casefold())).issubset(quoted_words)
                   for detail in claimed_details if detail not in generic_starts):
                return None
            return {"text": body.strip(), "recording_id": source_id, "quote": quote}

        output = [valid for item in paragraphs if (valid := validate_item(item))][:5]
        if not output:
            return None
        structured = {
            "title": title.strip(),
            "headline": title.strip(),
            "overview": " ".join(item["text"] for item in output),
            "paragraphs": output,
            "highlights": output,
        }
        for field in ("action_items", "decisions", "unresolved_questions"):
            items = data.get(field)
            structured[field] = ([valid for item in items if (valid := validate_item(item))][:10]
                                 if isinstance(items, list) else [])
        return structured
    except (ValueError, KeyError, TypeError):
        return None


def _validated_recap(raw: str, transcripts: list) -> str | None:
    data = _validated_recap_data(raw, transcripts)
    if not data:
        return None
    return data["title"] + "\n\n" + "\n\n".join(
        paragraph["text"] for paragraph in data["paragraphs"]
    )


def _generate_validated(transcripts: list) -> dict | None:
    prompt = _build_prompt(transcripts)
    data = _validated_recap_data(_summarize_cloudflare(prompt), transcripts)
    if data:
        return data
    print("daily recap response did not contain a valid source quote; retrying with a shorter request")
    repaired = _validated_recap_data(_summarize_cloudflare(_repair_prompt(transcripts)), transcripts)
    if not repaired:
        print("daily recap retry also failed quote validation")
    return repaired

def summarize_structured_with_status(transcripts: list) -> tuple[str | None, dict | None, bool]:
    if not transcripts:
        return "No conversations recorded today.", None, False

    if ACTIVE_SUMMARIZATION_PROVIDER == "cloudflare":
        batches = _prompt_batches(transcripts)
        if len(batches) == 1:
            try:
                data = _generate_validated(transcripts)
                if data:
                    return _validated_recap(json.dumps(data), transcripts), data, False
            except Exception as exc:
                print(f"daily recap generation failed: {exc}")
        else:
            candidates = []
            sections = {field: [] for field in ("action_items", "decisions", "unresolved_questions")}
            incomplete = False
            for batch_number, batch in enumerate(batches, 1):
                try:
                    data = _generate_validated(batch)
                    if data:
                        candidates.extend(data["paragraphs"])
                        for field in sections:
                            sections[field].extend(data[field])
                    else:
                        incomplete = True
                        print(f"daily recap batch {batch_number}/{len(batches)} failed validation")
                except Exception as exc:
                    print(f"daily recap batch {batch_number}/{len(batches)} failed: {exc}")
                    incomplete = True
            if candidates:
                if len(candidates) > 24:
                    candidates = [candidates[int(i * len(candidates) / 24)] for i in range(24)]
                indices = sorted({round(i * (len(candidates) - 1) / 4) for i in range(5)})
                title = _source_title(transcripts)
                try:
                    choices = _parse_json_object(_summarize_cloudflare(
                        "Select up to 5 important, distinct recap paragraphs spanning the day's topics. "
                        "Return only JSON with a specific short title and their zero-based indices: "
                        '{"title":"...","indices":[0,1,2,3,4]}\n' +
                        json.dumps([{"index": i, **item} for i, item in enumerate(candidates)])
                    )) or {}
                    selected = choices.get("indices")
                    if isinstance(selected, list):
                        valid = [i for i in selected if isinstance(i, int) and 0 <= i < len(candidates)]
                        if valid:
                            indices = list(dict.fromkeys(valid))[:5]
                    # Invalid selection still leaves the validated, quoted candidates usable.
                    if isinstance(choices.get("title"), str) and choices["title"].strip():
                        title = choices["title"]
                except Exception as exc:
                    print(f"daily recap selection failed: {exc}")
                selected_data = {"title": title, "paragraphs": [candidates[i] for i in indices]}
                for field, items in sections.items():
                    selected_data[field] = list({(item["recording_id"], item["text"]): item
                                                 for item in items}.values())[:10]
                validated_data = _validated_recap_data(selected_data, transcripts)
                if validated_data:
                    return _validated_recap(json.dumps(validated_data), transcripts), validated_data, incomplete
        return None, None, True
    else:
        raise Exception(f"Unknown summarization provider: {ACTIVE_SUMMARIZATION_PROVIDER}")


def summarize_with_status(transcripts: list) -> tuple[str | None, bool]:
    summary, _, unavailable = summarize_structured_with_status(transcripts)
    return summary, unavailable


def summarize(transcripts: list) -> str | None:
    return summarize_with_status(transcripts)[0]
