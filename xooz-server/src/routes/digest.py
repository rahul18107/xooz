from fastapi import APIRouter, HTTPException
import hashlib
import json
from datetime import datetime, timezone
from src.services.database import (
    get_day_transcripts,
    get_tasks,
    save_digest,
    get_digest,
    get_digests,
    delete_digest,
    update_digest,
    today_local_date,
    day_bounds_utc,
)

router = APIRouter()


def _completed(transcripts: list) -> list:
    return [t for t in transcripts if t.get("status") == "completed" and (t.get("text") or "").strip()]


def _fingerprint(transcripts: list) -> str:
    inputs = [{"id": t["id"], "text": t.get("text"),
               "speaker_labels": t.get("speaker_labels"),
               "speaker_names": t.get("speaker_names")}
              for t in sorted(transcripts, key=lambda t: t["id"])]
    return hashlib.sha256(("grounded-v4:" + json.dumps(inputs, sort_keys=True)).encode()).hexdigest()


def _current_digest(user_id: str, date: str, transcripts: list, force: bool = False):
    completed = _completed(transcripts)
    existing = get_digest(user_id=user_id, date=date)
    if not completed:
        return None, False
    fingerprint = _fingerprint(completed)
    if existing and not force and existing.get("source_fingerprint") == fingerprint:
        return existing, True
    retry_bucket = datetime.now(timezone.utc).strftime("%Y%m%d%H")
    fallback_fingerprint = f"fallback:{fingerprint}:{retry_bucket}"
    if (existing and not force and existing.get("source_fingerprint") == fallback_fingerprint
            and not existing.get("summary")):
        return existing, True
    from src.services.summarization import summarize_structured_with_status
    summary, structured, is_fallback = summarize_structured_with_status(completed)
    source_ids = [t["id"] for t in completed]
    stored_fingerprint = fallback_fingerprint if is_fallback else fingerprint
    summary = "" if is_fallback else (summary or "")
    if existing:
        return update_digest(user_id, date, summary, source_ids, stored_fingerprint,
                             None if is_fallback else structured), False
    return save_digest(user_id, summary, date, source_ids, stored_fingerprint,
                       None if is_fallback else structured), False


def _word_count(value: str) -> int:
    return len((value or "").split())


def _recording_seconds(transcript: dict) -> float:
    duration = transcript.get("duration_seconds")
    if isinstance(duration, (int, float)) and duration > 0:
        return float(duration)

    text = transcript.get("text") or ""
    words = _word_count(text)
    return (words / 150.0) * 60.0 if words else 0.0


def _conversation_importance_score(transcript: dict, task_counts: dict) -> int:
    """Higher score means the recording is more useful as a recap highlight."""
    transcript_id = transcript.get("id")
    text = transcript.get("text") or ""
    summary = transcript.get("summary") or ""
    title = transcript.get("title") or ""
    category = (transcript.get("category") or "").lower()
    tags = transcript.get("tags") or []

    score = 0

    # Conversations with extracted tasks are the strongest signal that the
    # user needs to remember or act on this recording.
    score += task_counts.get(transcript_id, 0) * 100

    if transcript.get("starred"):
        score += 80
    if category == "work":
        score += 30
    elif category in {"personal", "social"}:
        score += 15

    score += min(len(tags), 5) * 4 if isinstance(tags, list) else 0
    if title:
        score += 10
    if summary:
        score += 12

    words = _word_count(text)
    if words >= 80:
        score += 20
    elif words >= 35:
        score += 10

    important_terms = (
        "todo",
        "to-do",
        "follow up",
        "deadline",
        "due",
        "decision",
        "decide",
        "agreed",
        "plan",
        "meeting",
        "call",
        "remind",
        "need to",
        "have to",
        "should",
    )
    lower_text = text.lower()
    score += sum(8 for term in important_terms if term in lower_text)

    return score


def _select_highlights(transcripts: list, day_tasks: list, limit: int = 5) -> list:
    completed = _completed(transcripts)
    if not completed:
        return []

    task_counts = {}
    for task in day_tasks:
        source_id = task.get("source_transcript_id")
        if source_id:
            task_counts[source_id] = task_counts.get(source_id, 0) + 1

    ranked = sorted(
        completed,
        key=lambda t: (
            _conversation_importance_score(t, task_counts),
            t.get("recorded_at") or "",
        ),
        reverse=True,
    )

    meaningful = [
        transcript
        for transcript in ranked
        if task_counts.get(transcript.get("id"), 0) > 0
        or transcript.get("starred")
        or _conversation_importance_score(transcript, task_counts) >= 35
    ]

    return meaningful[:limit]


@router.get("/recap/{user_id}")
async def get_recap(user_id: str, date: str = None, force: bool = False):
    """Everything the Daily Recap screen needs for one day:
    digest text + that day's recordings + stats."""
    try:
        date = date or today_local_date(user_id)

        # digest for the day — generate fresh for today if it doesn't exist yet
        transcripts = get_day_transcripts(user_id=user_id, date=date)
        digest, _ = _current_digest(user_id, date, transcripts, force=force)

        completed = _completed(transcripts)
        seconds = sum(_recording_seconds(t) for t in completed)
        minutes = round(seconds / 60.0, 1) if seconds else 0.0

        # tasks of that day: linked to one of the day's transcripts,
        # or created that day (local timezone)
        start_iso, end_iso = day_bounds_utc(user_id, date)
        transcript_ids = {t["id"] for t in transcripts}
        try:
            tasks = get_tasks(user_id=user_id, limit=200)
            day_tasks = [
                task for task in tasks
                if (task.get("source_transcript_id") in transcript_ids)
                or (task.get("created_at") and start_iso <= task["created_at"] < end_iso)
            ]
        except Exception:
            day_tasks = []

        structured_summary = dict((digest or {}).get("structured_summary") or {})
        # Saved tasks are the canonical action items; the model's phrasing may
        # not correspond to any task the user can actually open.
        structured_summary["action_items"] = [
            {"text": task["title"], "recording_id": task["source_transcript_id"],
             "task_id": task["id"]}
            for task in day_tasks
            if task.get("id") and task.get("title")
            and task.get("source_transcript_id") in {t["id"] for t in completed}
        ]

        return {
            "success": True,
            "date": date,
            "digest": ((digest or {}).get("summary") or "") if not ((digest or {}).get("source_fingerprint") or "").startswith("fallback:") else "",
            "structured_summary": structured_summary,
            "recap_status": ("unavailable" if ((digest or {}).get("source_fingerprint") or "").startswith("fallback:")
                             else "ready" if digest else "empty"),
            "source_recordings": [t for t in transcripts if t.get("id") in
                                  ((digest or {}).get("source_transcript_ids") or [])],
            "stats": {
                "recordings": len(completed),
                "minutes": minutes,
                "tasks": len(day_tasks),
            },
            "recordings": _select_highlights(transcripts, day_tasks),
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@router.get("/digest/{user_id}")
async def get_daily_digest(user_id: str, date: str = None):
    date = date or today_local_date(user_id)
    transcripts = get_day_transcripts(user_id=user_id, date=date)
    digest, cached = _current_digest(user_id, date, transcripts)
    if not digest:
        return {
            "success": True,
            "digest": "No conversations recorded on this day.",
            "date": date,
            "cached": False
        }
    unavailable = (digest.get("source_fingerprint") or "").startswith("fallback:")
    return {
        "success": True,
        "digest": "Daily summary unavailable. Try again later." if unavailable else digest["summary"],
        "date": digest["date"],
        "cached": cached
    }


@router.post("/digest/{user_id}")
async def generate_daily_digest(user_id: str, date: str = None):
    date = date or today_local_date(user_id)
    try:
        transcripts = get_day_transcripts(user_id=user_id, date=date)
        digest, cached = _current_digest(user_id, date, transcripts, force=True)
        if not digest:
            raise HTTPException(status_code=404, detail="No conversations recorded on this day")

        unavailable = (digest.get("source_fingerprint") or "").startswith("fallback:")
        if unavailable:
            raise HTTPException(status_code=503, detail="Daily summary unavailable. Please try again.")
        return {
            "success": True,
            "digest": digest["summary"],
            "date": digest["date"],
            "cached": cached,
        }
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@router.get("/digests/{user_id}")
async def list_digests(user_id: str, month: str = None, limit: int = 60):
    """Digest history for 'Daily Recaps → View All' and the calendar.
    Optional `month` = 'YYYY-MM'."""
    if month and (len(month) != 7 or month[4] != "-"):
        raise HTTPException(status_code=400, detail="month must be in YYYY-MM format")
    try:
        digests = get_digests(user_id=user_id, month=month, limit=limit)
        digests = [digest for digest in digests
                   if digest.get("summary") and not (digest.get("source_fingerprint") or "").startswith("fallback:")]
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
    return {"success": True, "digests": digests, "count": len(digests)}


@router.delete("/digests/{user_id}")
async def remove_digest(user_id: str, date: str):
    if not date:
        raise HTTPException(status_code=400, detail="date is required")
    try:
        deleted = delete_digest(user_id=user_id, date=date)
        if not deleted:
            raise HTTPException(status_code=404, detail="Digest not found")
        return {"success": True, "digest": deleted}
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
