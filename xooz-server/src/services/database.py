from supabase import create_client
from src.config import SUPABASE_URL, SUPABASE_KEY
from datetime import datetime, timezone, timedelta
from zoneinfo import ZoneInfo

client = create_client(SUPABASE_URL, SUPABASE_KEY)

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
            # non-today dates: filter on the string date prefix (UTC storage)
            query = query.gte("recorded_at", f"{date}T00:00:00+00:00")
            query = query.lt("recorded_at", f"{date}T23:59:59.999+00:00")
    return query.execute().data

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

def save_digest(user_id: str, summary: str):
    data = {
        "user_id": user_id,
        "summary": summary,
        "date": today_local_date(user_id),
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

def get_tasks(user_id: str, status: str = None, limit: int = 100):
    query = (
        client.table("tasks")
        .select("*")
        .eq("user_id", user_id)
        .order("created_at", desc=True)
        .limit(limit)
    )
    if status:
        query = query.eq("status", status)
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

# ------------------------------------------------------------------
# chat
# ------------------------------------------------------------------

def save_chat_message(user_id: str, session_id: str, role: str, content: str):
    result = (
        client.table("chat_messages")
        .insert({"user_id": user_id, "session_id": session_id, "role": role, "content": content})
        .execute()
    )
    return result.data[0]

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
