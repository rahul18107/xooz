import httpx
import base64
from src.config import CLOUDFLARE_ACCOUNT_ID, CLOUDFLARE_API_TOKEN

API_URL = f"https://api.cloudflare.com/client/v4/accounts/{CLOUDFLARE_ACCOUNT_ID}/ai/run/@cf/openai/whisper-large-v3-turbo"

def transcribe(audio_file_path: str) -> dict:
    with open(audio_file_path, "rb") as audio_file:
        audio_data = base64.b64encode(audio_file.read()).decode("utf-8")

    headers = {
        "Authorization": f"Bearer {CLOUDFLARE_API_TOKEN}",
        "Content-Type": "application/json"
    }

    payload = {
        "audio": audio_data
    }

    response = httpx.post(API_URL, headers=headers, json=payload, timeout=60.0)
    response.raise_for_status()

    result = response.json()

    if not result.get("success"):
        raise Exception(f"Cloudflare transcription failed: {result.get('errors')}")

    return {
        "text": result["result"]["text"],
        "speaker_labels": []
    }