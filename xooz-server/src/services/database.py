from supabase import create_client
from src.config import SUPABASE_URL, SUPABASE_KEY
from datetime import datetime, timezone

client = create_client(SUPABASE_URL, SUPABASE_KEY)

def save_transcript(user_id: str, text: str, speaker_labels: list = None):
    data = {
        "user_id": user_id,
        "text": text,
        "speaker_labels": speaker_labels,
        "recorded_at": datetime.now(timezone.utc).isoformat()
    }
    result = client.table("transcripts").insert(data).execute()
    return result.data[0]

def get_transcripts_for_today(user_id: str):
    today = datetime.now(timezone.utc).date().isoformat()
    result = (
        client.table("transcripts")
        .select("*")
        .eq("user_id", user_id)
        .gte("recorded_at", f"{today}T00:00:00+00:00")
        .lte("recorded_at", f"{today}T23:59:59+00:00")
        .execute()
    )
    return result.data

def save_digest(user_id: str, summary: str):
    today = datetime.now(timezone.utc).date().isoformat()
    data = {
        "user_id": user_id,
        "summary": summary,
        "date": today
    }
    result = client.table("digests").insert(data).execute()
    return result.data[0]

def get_digest(user_id: str, date: str = None):
    if not date:
        date = datetime.now(timezone.utc).date().isoformat()
    result = (
        client.table("digests")
        .select("*")
        .eq("user_id", user_id)
        .eq("date", date)
        .execute()
    )
    return result.data[0] if result.data else None