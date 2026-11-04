from fastapi import APIRouter, HTTPException, Query
from src.services.database import get_transcripts, get_transcript_by_id
import uuid

def _validate_uuid(value: str) -> str:
    try:
        return str(uuid.UUID(value))
    except ValueError:
        raise HTTPException(status_code=404, detail="Transcript not found")

router = APIRouter()

@router.get("/transcripts")
async def list_transcripts(
    user_id: str = Query(...),
    date: str = None,
    limit: int = Query(50, ge=1, le=100),
):
    """List a user's transcripts, newest first. Optional `date` (YYYY-MM-DD)
    filters to that day in the user's timezone."""
    try:
        transcripts = get_transcripts(user_id=user_id, date=date, limit=limit)
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

    return {"success": True, "transcripts": transcripts, "count": len(transcripts)}

@router.get("/transcripts/{transcript_id}")
async def get_transcript(transcript_id: str):
    transcript = get_transcript_by_id(_validate_uuid(transcript_id))
    if not transcript:
        raise HTTPException(status_code=404, detail="Transcript not found")
    return {"success": True, "transcript": transcript}
