from fastapi import APIRouter, HTTPException
from src.services.database import (
    get_transcripts_for_today,
    get_transcripts,
    get_tasks,
    save_digest,
    get_digest,
    get_digests,
    today_local_date,
    day_bounds_utc,
)

router = APIRouter()


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
    completed = [t for t in transcripts if t.get("status") == "completed"]
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
async def get_recap(user_id: str, date: str = None):
    """Everything the Daily Recap screen needs for one day:
    digest text + that day's recordings + stats."""
    try:
        date = date or today_local_date(user_id)

        # digest for the day — generate fresh for today if it doesn't exist yet
        digest = get_digest(user_id=user_id, date=date)
        if not digest and date == today_local_date(user_id):
            day_transcripts = get_transcripts_for_today(user_id=user_id)
            if day_transcripts:
                from src.services.summarization import summarize
                summary = summarize(day_transcripts)
                digest = save_digest(user_id=user_id, summary=summary)

        # the day's recordings (recap is read-only, list limit is fine)
        transcripts = get_transcripts(user_id=user_id, date=date, limit=200)

        completed = [t for t in transcripts if t.get("status") == "completed"]
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

        return {
            "success": True,
            "date": date,
            "digest": (digest or {}).get("summary"),
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
    # check if digest already exists for the requested day
    existing = get_digest(user_id=user_id, date=date)
    if existing:
        return {
            "success": True,
            "digest": existing["summary"],
            "date": existing["date"],
            "cached": True
        }

    # if asking for an older day that has no digest, don't backfill automatically
    if date and date != today_local_date(user_id):
        return {
            "success": True,
            "digest": "No conversations recorded on this day.",
            "date": date,
            "cached": False
        }

    # fetch today's transcripts and generate the digest
    transcripts = get_transcripts_for_today(user_id=user_id)
    if not transcripts:
        return {
            "success": True,
            "digest": "No conversations recorded today.",
            "date": today_local_date(user_id),
            "cached": False
        }

    # summarize
    from src.services.summarization import summarize
    summary = summarize(transcripts)

    # save digest
    digest = save_digest(user_id=user_id, summary=summary)

    return {
        "success": True,
        "digest": digest["summary"],
        "date": digest["date"],
        "cached": False
    }

@router.get("/digests/{user_id}")
async def list_digests(user_id: str, month: str = None, limit: int = 60):
    """Digest history for 'Daily Recaps → View All' and the calendar.
    Optional `month` = 'YYYY-MM'."""
    if month and (len(month) != 7 or month[4] != "-"):
        raise HTTPException(status_code=400, detail="month must be in YYYY-MM format")
    try:
        digests = get_digests(user_id=user_id, month=month, limit=limit)
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
    return {"success": True, "digests": digests, "count": len(digests)}
