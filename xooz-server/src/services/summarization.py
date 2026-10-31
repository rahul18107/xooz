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

Create a clean end-of-day digest with:
- A one line overview of the day
- Key topics discussed
- Important decisions or action items mentioned
- People talked to (if identifiable)

Keep it concise, clear and useful."""

def summarize(transcripts: list) -> str:
    if not transcripts:
        return "No conversations recorded today."

    prompt = _build_prompt(transcripts)

    if ACTIVE_SUMMARIZATION_PROVIDER == "cloudflare":
        return _summarize_cloudflare(prompt)
    else:
        raise Exception(f"Unknown summarization provider: {ACTIVE_SUMMARIZATION_PROVIDER}")