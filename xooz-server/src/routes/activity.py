from fastapi import APIRouter, HTTPException
from src.services.database import get_failed_transcripts, get_transcripts_for_today

router = APIRouter()

@router.get("/activity/{user_id}")
async def get_activity(user_id: str):
    """Feed for the Activity screen:
    - needs_attention: recordings that failed (or are stuck processing)
    - today: completed conversations recorded today
    """
    try:
        needs_attention = get_failed_transcripts(user_id=user_id)
        all_today = get_transcripts_for_today(user_id=user_id)
        today = [t for t in all_today if t.get("status") == "completed"]

        return {
            "success": True,
            "needs_attention": needs_attention,
            "today": today,
            "counts": {
                "needs_attention": len(needs_attention),
                "today": len(today),
            },
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
