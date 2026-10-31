from fastapi import APIRouter, HTTPException
from src.services.database import get_transcripts_for_today, save_digest, get_digest

router = APIRouter()

@router.get("/digest/{user_id}")
async def get_daily_digest(user_id: str, date: str = None):
    # check if digest already exists for today
    existing = get_digest(user_id=user_id, date=date)
    if existing:
        return {
            "success": True,
            "digest": existing["summary"],
            "date": existing["date"],
            "cached": True
        }

    # fetch today's transcripts
    transcripts = get_transcripts_for_today(user_id=user_id)
    if not transcripts:
        return {
            "success": True,
            "digest": "No conversations recorded today.",
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