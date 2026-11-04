from fastapi import APIRouter, HTTPException
from src.services.database import (
    get_transcripts_for_today,
    save_digest,
    get_digest,
    get_digests,
    today_local_date,
)

router = APIRouter()

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
