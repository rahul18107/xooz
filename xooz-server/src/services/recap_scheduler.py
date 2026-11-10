"""Best-effort local-time recap generation while the API server is running."""

from datetime import datetime, timedelta, timezone
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from src.services.database import client, get_day_transcripts, get_scheduled_recap_profiles


def due_recap_date(profile: dict, now: datetime) -> str | None:
    try:
        local = now.astimezone(ZoneInfo(profile["timezone"]))
        hour = int(profile["daily_recap_hour"])
    except (KeyError, TypeError, ValueError, ZoneInfoNotFoundError):
        return None
    if not 0 <= hour <= 23 or local.hour < hour:
        return None
    day = local.date() - timedelta(days=1) if hour < 12 else local.date()
    return day.isoformat()


def _claim(user_id: str, date: str) -> str | None:
    result = client.rpc("claim_scheduled_recap", {
        "p_user_id": user_id, "p_recap_date": date,
    }).execute()
    return result.data


def _finish(user_id: str, date: str, token: str, success: bool):
    if success:
        (client.table("scheduled_recap_claims")
         .update({"completed_at": datetime.now(timezone.utc).isoformat()})
         .eq("user_id", user_id).eq("recap_date", date).eq("claim_token", token)
         .execute())
    else:
        (client.table("scheduled_recap_claims").delete()
         .eq("user_id", user_id).eq("recap_date", date).eq("claim_token", token)
         .execute())


def run_scheduled_recaps_once(now: datetime | None = None):
    now = now or datetime.now(timezone.utc)
    from src.routes.digest import _completed, _current_digest

    for profile in get_scheduled_recap_profiles():
        user_id = profile["id"]
        due = due_recap_date(profile, now)
        if not due:
            continue
        try:
            token = _claim(user_id, due)
            if not token:
                continue
            try:
                recordings = get_day_transcripts(user_id, due)
                if not _completed(recordings):
                    success = False
                else:
                    result, _ = _current_digest(user_id, due, recordings)
                    success = bool(result and result.get("summary") and
                                   not (result.get("source_fingerprint") or "").startswith("fallback:"))
            except Exception:
                _finish(user_id, due, token, False)
                raise
            _finish(user_id, due, token, success)
        except Exception as exc:
            print(f"scheduled recap failed for {user_id} on {due}: {exc}")
