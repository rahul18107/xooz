from supabase import create_client
from src.config import SUPABASE_URL, SUPABASE_SERVICE_KEY
from datetime import datetime, timezone, timedelta
from zoneinfo import ZoneInfo
import re

client = create_client(SUPABASE_URL, SUPABASE_SERVICE_KEY)

# ------------------------------------------------------------------
# time helpers (local "today" aware of the user's timezone)
# ------------------------------------------------------------------

def _safe_tz(name: str):
    if not name:
        return timezone.utc
    try:
        return ZoneInfo(name)
    except Exception:
        return timezone.utc

def get_profile_tz(user_id: str):
    try:
        profile = get_profile(user_id)
        tz_name = (profile or {}).get("timezone") or "UTC"
        return _safe_tz(tz_name)
    except Exception:
        # profiles table may not exist yet — fall back to UTC
        return timezone.utc

def today_bounds_utc(user_id: str) -> tuple[str, str]:
    """Return [start, end) of the user's local day as UTC ISO strings,
    matching the format used in the `recorded_at` column."""
    tz = get_profile_tz(user_id)
    now_local = datetime.now(tz)
    start = now_local.replace(hour=0, minute=0, second=0, microsecond=0)
    end = start + timedelta(days=1)
    return start.astimezone(timezone.utc).isoformat(), end.astimezone(timezone.utc).isoformat()

def today_local_date(user_id: str) -> str:
    tz = get_profile_tz(user_id)
    return datetime.now(tz).date().isoformat()

def day_bounds_utc(user_id: str, date: str) -> tuple[str, str]:
    """[start, end) of the given local day ('YYYY-MM-DD') as UTC ISO strings."""
    tz = get_profile_tz(user_id)
    start = datetime.fromisoformat(date).replace(tzinfo=tz)
    end = start + timedelta(days=1)
    return start.astimezone(timezone.utc).isoformat(), end.astimezone(timezone.utc).isoformat()

def month_bounds_utc(user_id: str, month: str) -> tuple[str, str]:
    """month = 'YYYY-MM' -> [start, end) of that local month as UTC ISO strings."""
    tz = get_profile_tz(user_id)
    year, month_num = int(month[:4]), int(month[5:7])
    start = datetime(year, month_num, 1, tzinfo=tz)
    if month_num == 12:
        end = datetime(year + 1, 1, 1, tzinfo=tz)
    else:
        end = datetime(year, month_num + 1, 1, tzinfo=tz)
    return start.astimezone(timezone.utc).isoformat(), end.astimezone(timezone.utc).isoformat()

# ------------------------------------------------------------------
# transcripts
# ------------------------------------------------------------------

def save_transcript(user_id: str, text: str, speaker_labels: list = None,
                    status: str = "completed", extra: dict = None):
    data = {
        "user_id": user_id,
        "text": text,
        "speaker_labels": speaker_labels or [],
        "recorded_at": datetime.now(timezone.utc).isoformat(),
        "status": status,
    }
    if extra:
        data.update(extra)
    result = client.table("transcripts").insert(data).execute()
    return result.data[0]


def get_speakers(user_id: str) -> list[dict]:
    speakers = (client.table("speakers").select("id,name")
                .eq("user_id", user_id).order("name").execute().data)
    return [speaker for speaker in speakers
            if not re.fullmatch(r"Unknown Speaker #\d+", speaker["name"])]


def get_or_create_speaker(user_id: str, name: str) -> dict:
    for speaker in get_speakers(user_id):
        if speaker["name"].casefold() == name.casefold():
            return speaker
    return (client.table("speakers").insert({"user_id": user_id, "name": name})
            .execute().data[0])


def get_transcripts(user_id: str, date: str = None, limit: int = 50):
    """Transcripts for a user, newest first. `date` (YYYY-MM-DD) filters to that
    day in the user's own timezone."""
    query = (
        client.table("transcripts")
        .select("*")
        .eq("user_id", user_id)
        .order("recorded_at", desc=True)
        .limit(limit)
    )
    if date:
        if date == today_local_date(user_id):
            start, end = today_bounds_utc(user_id)
            query = query.gte("recorded_at", start).lt("recorded_at", end)
        else:
            start, end = day_bounds_utc(user_id, date)
            query = query.gte("recorded_at", start).lt("recorded_at", end)
    return query.execute().data


def get_day_transcripts(user_id: str, date: str, page_size: int = 200):
    """Fetch every recording for a local day, including days over one API page."""
    start, end = day_bounds_utc(user_id, date)
    recordings = []
    while True:
        page = (
            client.table("transcripts")
            .select("*")
            .eq("user_id", user_id)
            .gte("recorded_at", start)
            .lt("recorded_at", end)
            .order("recorded_at", desc=True)
            .order("id", desc=True)
            .range(len(recordings), len(recordings) + page_size - 1)
            .execute()
            .data
        )
        recordings.extend(page)
        if len(page) < page_size:
            return recordings

def get_transcripts_for_today(user_id: str):
    start, end = today_bounds_utc(user_id)
    result = (
        client.table("transcripts")
        .select("*")
        .eq("user_id", user_id)
        .gte("recorded_at", start)
        .lt("recorded_at", end)
        .order("recorded_at", desc=False)
        .execute()
    )
    return result.data

def get_failed_transcripts(user_id: str, limit: int = 50):
    result = (
        client.table("transcripts")
        .select("*")
        .eq("user_id", user_id)
        .in_("status", ["failed", "processing"])
        .order("recorded_at", desc=True)
        .limit(limit)
        .execute()
    )
    return result.data

def get_transcript_by_id(transcript_id: str):
    result = (
        client.table("transcripts")
        .select("*")
        .eq("id", transcript_id)
        .execute()
    )
    return result.data[0] if result.data else None

def delete_transcript(transcript_id: str):
    query = client.table("transcripts").delete().eq("id", transcript_id).execute()
    return (query.data or [None])[0]

def update_transcript(transcript_id: str, updates: dict):
    result = (
        client.table("transcripts")
        .update(updates)
        .eq("id", transcript_id)
        .execute()
    )
    return result.data[0] if result.data else None

def search_transcripts(user_id: str, query: str, limit: int = 20):
    result = (
        client.table("transcripts")
        .select("*")
        .eq("user_id", user_id)
        .eq("status", "completed")
        .ilike("text", f"%{query}%")
        .order("recorded_at", desc=True)
        .limit(limit)
        .execute()
    )
    return result.data

def count_transcripts(user_id: str, category: str = None, starred: bool = None) -> int:
    query = client.table("transcripts").select("*", count="exact", head=True).eq("user_id", user_id)
    if category is not None:
        query = query.eq("category", category)
    if starred is not None:
        query = query.eq("starred", starred)
    result = query.execute()
    return result.count or 0

def get_transcript_lists(user_id: str):
    """All completed transcripts with their category / people / places,"
    for building search category counts."""
    result = (
        client.table("transcripts")
        .select("category, people, places, starred")
        .eq("user_id", user_id)
        .execute()
    )
    return result.data

# ------------------------------------------------------------------
# digests
# ------------------------------------------------------------------

def save_digest(user_id: str, summary: str, date: str = None,
                source_transcript_ids: list = None, source_fingerprint: str = None,
                structured_summary: dict = None):
    data = {
        "user_id": user_id,
        "summary": summary,
        "date": date or today_local_date(user_id),
        "source_transcript_ids": source_transcript_ids or [],
        "source_fingerprint": source_fingerprint,
        "structured_summary": structured_summary,
    }
    result = client.table("digests").insert(data).execute()
    return result.data[0]

def get_digest(user_id: str, date: str = None):
    if not date:
        date = today_local_date(user_id)
    result = (
        client.table("digests")
        .select("*")
        .eq("user_id", user_id)
        .eq("date", date)
        .execute()
    )
    return result.data[0] if result.data else None

def delete_digest(user_id: str, date: str):
    result = (
        client.table("digests")
        .delete()
        .eq("user_id", user_id)
        .eq("date", date)
        .execute()
    )
    return result.data[0] if result.data else None

def update_digest(user_id: str, date: str, summary: str,
                  source_transcript_ids: list = None, source_fingerprint: str = None,
                  structured_summary: dict = None):
    updates = {"summary": summary, "structured_summary": structured_summary}
    if source_transcript_ids is not None:
        updates["source_transcript_ids"] = source_transcript_ids
    if source_fingerprint is not None:
        updates["source_fingerprint"] = source_fingerprint
    result = (
        client.table("digests")
        .update(updates)
        .eq("user_id", user_id)
        .eq("date", date)
        .execute()
    )
    return result.data[0] if result.data else None

def get_digests(user_id: str, month: str = None, limit: int = 60):
    """Digest history for recaps/calendar. `month` = 'YYYY-MM'."""
    query = (
        client.table("digests")
        .select("*")
        .eq("user_id", user_id)
        .order("date", desc=True)
        .limit(limit)
    )
    if month:
        start, end = month_bounds_utc(user_id, month)
        # digests store a plain local date string, so filter on the date range strings
        year, month_num = int(month[:4]), int(month[5:7])
        query = (
            client.table("digests")
            .select("*")
            .eq("user_id", user_id)
            .gte("date", f"{year}-{month_num:02d}-01")
            .lte("date", f"{year}-{month_num:02d}-31")
            .order("date", desc=True)
            .limit(limit)
        )
    return query.execute().data

def search_digests(user_id: str, query: str, limit: int = 20):
    result = (
        client.table("digests")
        .select("*")
        .eq("user_id", user_id)
        .ilike("summary", f"%{query}%")
        .order("date", desc=True)
        .limit(limit)
        .execute()
    )
    return result.data

def count_digests(user_id: str) -> int:
    result = (
        client.table("digests")
        .select("*", count="exact", head=True)
        .eq("user_id", user_id)
        .execute()
    )
    return result.count or 0

# ------------------------------------------------------------------
# tasks
# ------------------------------------------------------------------

def save_tasks(user_id: str, tasks: list, source_transcript_id: str = None):
    """tasks = [{"title": str, "due_date": 'YYYY-MM-DD' | None}, ...]"""
    if not tasks:
        return []
    rows = [
        {
            "user_id": user_id,
            "title": t["title"],
            "due_date": t.get("due_date"),
            "source_transcript_id": source_transcript_id,
            "status": "open",
        }
        for t in tasks
        if t.get("title")
    ]
    if not rows:
        return []
    result = client.table("tasks").insert(rows).execute()
    return result.data

def get_tasks(user_id: str, status: str = None, limit: int = 100,
              completed_start: str = None, completed_end: str = None,
              due_date: str = None, created_before: str = None):
    query = (
        client.table("tasks")
        .select("*")
        .eq("user_id", user_id)
        .order("completed_at" if completed_start or completed_end else "created_at", desc=True)
        .limit(limit)
    )
    if status:
        query = query.eq("status", status)
    if due_date:
        query = query.eq("due_date", due_date)
    if created_before:
        query = query.lt("created_at", created_before)
    if completed_start:
        query = query.gte("completed_at", completed_start)
    if completed_end:
        query = query.lt("completed_at", completed_end)
    return query.execute().data

def search_tasks(user_id: str, query: str, limit: int = 20):
    result = (
        client.table("tasks")
        .select("*")
        .eq("user_id", user_id)
        .ilike("title", f"%{query}%")
        .order("created_at", desc=True)
        .limit(limit)
        .execute()
    )
    return result.data

def get_task_by_id(task_id: str):
    result = client.table("tasks").select("*").eq("id", task_id).execute()
    return result.data[0] if result.data else None

def update_task(task_id: str, updates: dict):
    result = client.table("tasks").update(updates).eq("id", task_id).execute()
    return result.data[0] if result.data else None

def delete_task(task_id: str, user_id: str):
    result = (client.table("tasks").delete().eq("id", task_id)
              .eq("user_id", user_id).execute())
    return bool(result.data)

# ------------------------------------------------------------------
# chat
# ------------------------------------------------------------------

def save_chat_message(user_id: str, session_id: str, role: str, content: str,
                      source_ids: list[str] | None = None,
                      client_request_id: str | None = None):
    data = {"user_id": user_id, "session_id": session_id, "role": role, "content": content}
    if source_ids is not None:
        data["source_ids"] = source_ids
    if client_request_id is not None:
        data["client_request_id"] = client_request_id
    result = (
        client.table("chat_messages")
        .insert(data)
        .execute()
    )
    saved = result.data[0]
    if role == "user":
        client.table("chat_threads").upsert({
            "user_id": user_id, "session_id": session_id,
            "title": content.strip()[:80] or "Chat",
            "created_at": saved["created_at"], "updated_at": saved["created_at"],
        }, on_conflict="user_id,session_id", ignore_duplicates=True).execute()
        client.table("chat_threads").update({"title": content.strip()[:80] or "Chat"}).eq(
            "user_id", user_id).eq("session_id", session_id).eq(
            "title", "New chat").execute()
    client.table("chat_threads").update({"updated_at": saved["created_at"]}).eq(
        "user_id", user_id).eq("session_id", session_id).execute()
    return saved


def get_chat_threads(user_id: str, limit: int = 50) -> list[dict]:
    return (client.table("chat_threads").select("session_id,title,created_at,updated_at")
            .eq("user_id", user_id).order("updated_at", desc=True)
            .limit(limit).execute().data or [])


def create_chat_thread(user_id: str, session_id: str) -> dict:
    result = (client.table("chat_threads").insert({
        "user_id": user_id, "session_id": session_id, "title": "New chat",
    }).execute())
    return result.data[0]


def delete_chat_thread(user_id: str, session_id: str) -> bool:
    thread = (client.table("chat_threads").select("session_id")
              .eq("user_id", user_id).eq("session_id", session_id)
              .limit(1).execute().data or [])
    if not thread:
        return False
    client.table("chat_messages").delete().eq("user_id", user_id).eq(
        "session_id", session_id).execute()
    client.table("chat_threads").delete().eq("user_id", user_id).eq(
        "session_id", session_id).execute()
    return True


def get_chat_turn(user_id: str, session_id: str, client_request_id: str) -> list[dict]:
    return (client.table("chat_messages").select("*")
            .eq("user_id", user_id).eq("session_id", session_id)
            .eq("client_request_id", client_request_id)
            .execute().data or [])

def get_chat_history(user_id: str, session_id: str = None, limit: int = 20):
    query = (
        client.table("chat_messages")
        .select("*")
        .eq("user_id", user_id)
        .order("created_at", desc=True)
        .limit(limit)
    )
    if session_id:
        query = query.eq("session_id", session_id)
    # return oldest first
    return list(reversed(query.execute().data))

# ------------------------------------------------------------------
# profiles
# ------------------------------------------------------------------

def get_profile(user_id: str):
    result = client.table("profiles").select("*").eq("id", user_id).execute()
    return result.data[0] if result.data else None


def get_scheduled_recap_profiles(page_size: int = 200):
    offset = 0
    while True:
        page = (
            client.table("profiles")
            .select("id,timezone,daily_recap_hour")
            .eq("daily_recap_enabled", True)
            .order("id")
            .range(offset, offset + page_size - 1)
            .execute()
            .data
        )
        yield from page
        if len(page) < page_size:
            return
        offset += len(page)

def get_or_create_profile(user_id: str):
    profile = get_profile(user_id)
    if profile:
        return profile
    result = client.table("profiles").insert({"id": user_id}).execute()
    return result.data[0]

def update_profile(user_id: str, updates: dict):
    result = client.table("profiles").update(updates).eq("id", user_id).execute()
    return result.data[0] if result.data else None

def increment_minutes_used(user_id: str, minutes: float):
    profile = get_or_create_profile(user_id)
    used = float(profile.get("monthly_minutes_used") or 0) + max(0.0, minutes)
    return update_profile(user_id, {"monthly_minutes_used": round(used, 2)})

# ------------------------------------------------------------------
# devices
# ------------------------------------------------------------------

def create_device(user_id: str, name: str, pairing_code: str):
    result = (
        client.table("devices")
        .insert({"user_id": user_id, "name": name, "pairing_code": pairing_code, "status": "pending"})
        .execute()
    )
    return result.data[0]

def get_devices(user_id: str):
    result = (
        client.table("devices")
        .select("*")
        .eq("user_id", user_id)
        .order("created_at", desc=True)
        .execute()
    )
    return result.data
