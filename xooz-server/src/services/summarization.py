import httpx
from src.config import CLOUDFLARE_ACCOUNT_ID, CLOUDFLARE_API_TOKEN, ACTIVE_SUMMARIZATION_PROVIDER

CLOUDFLARE_URL = f"https://api.cloudflare.com/client/v4/accounts/{CLOUDFLARE_ACCOUNT_ID}/ai/run/@cf/meta/llama-3.1-8b-instruct"

def _summarize_cloudflare(prompt: str) -> str:
    headers = {
        "Authorization": f"Bearer {CLOUDFLARE_API_TOKEN}",
        "Content-Type": "application/json"
    }

    payload = {
        "messages": [
            {"role": "system", "content": "You are a personal assistant that summarizes a person's daily conversations captured via their smartwatch."},
            {"role": "user", "content": prompt}
        ],
        "max_tokens": 1024
    }

    response = httpx.post(CLOUDFLARE_URL, headers=headers, json=payload, timeout=60.0)
    response.raise_for_status()

    result = response.json()

    if not result.get("success"):
        raise Exception(f"Cloudflare summarization failed: {result.get('errors')}")

    return result["result"]["response"]

def _build_prompt(transcripts: list) -> str:
    if not transcripts:
        return ""

    combined = ""
    for i, transcript in enumerate(transcripts, 1):
        combined += f"\n--- Conversation {i} ({transcript['recorded_at']}) ---\n"

        if transcript.get("speaker_labels"):
            for utterance in transcript["speaker_labels"]:
                combined += f"Speaker {utterance['speaker']}: {utterance['text']}\n"
        else:
            combined += transcript["text"] + "\n"

    return f"""Here are all conversations recorded today:
{combined}

Write a clear daily recap in this exact format:
Line 1: a direct, specific title of 3-6 words about what actually happened.
Do not start the title with "Today's recap", "Today's conversations", "The day",
"A day", "Overview", or "Summary".
Blank line.
One paragraph of 2-3 complete sentences summarizing the main event with useful context.
Blank line.
Two short paragraphs covering other topics, decisions, commitments, follow-ups, and any
notable people or places when the transcript supports them.
Attribute statements to speakers only when the transcript supports it.

Use plain text with normal punctuation. End every sentence with a period, question mark,
or exclamation mark. Do not use markdown, bullet points, or section labels.
Do not explain what the digest is. Do not write filler like "This digest provides"
or "This summary highlights". Avoid repeating the title or the same fact in multiple
paragraphs. Aim for 120-180 words when there is enough conversation content."""

def summarize(transcripts: list) -> str:
    if not transcripts:
        return "No conversations recorded today."

    prompt = _build_prompt(transcripts)

    if ACTIVE_SUMMARIZATION_PROVIDER == "cloudflare":
        return _summarize_cloudflare(prompt)
    else:
        raise Exception(f"Unknown summarization provider: {ACTIVE_SUMMARIZATION_PROVIDER}")
