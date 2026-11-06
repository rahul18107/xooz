from fastapi import APIRouter, HTTPException, Query
from src.services.database import get_transcripts, get_transcript_by_id, update_transcript, delete_transcript
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
    limit: int = Query(50, ge=1, le=200),
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

@router.patch("/transcripts/{transcript_id}")
async def patch_transcript(transcript_id: str, body: dict):
    """Update a transcript: {"title": "...", "starred": true}"""
    tid = _validate_uuid(transcript_id)
    transcript = get_transcript_by_id(tid)
    if not transcript:
        raise HTTPException(status_code=404, detail="Transcript not found")

    updates = {}
    if "title" in body:
        title = (body["title"] or "").strip()
        if not title:
            raise HTTPException(status_code=400, detail="title cannot be empty")
        updates["title"] = title[:80]
    if "starred" in body:
        updates["starred"] = bool(body["starred"])
    if not updates:
        return {"success": True, "transcript": transcript}

    updated = update_transcript(tid, updates)
    return {"success": True, "transcript": updated}

@router.delete("/transcripts/{transcript_id}")
async def remove_transcript(transcript_id: str):
    tid = _validate_uuid(transcript_id)
    deleted = delete_transcript(tid)
    if not deleted:
        raise HTTPException(status_code=404, detail="Transcript not found")
    return {"success": True}

@router.post("/transcripts/{transcript_id}/summary")
async def generate_transcript_summary(
    transcript_id: str,
    force: bool = False,
):
    """Generate (or return cached) AI summary for one recording."""
    tid = _validate_uuid(transcript_id)
    transcript = get_transcript_by_id(tid)
    if not transcript:
        raise HTTPException(status_code=404, detail="Transcript not found")

    # return cached summary unless force=True
    if transcript.get("summary") and not force:
        return {
            "success": True,
            "summary": transcript["summary"],
            "title": transcript.get("title"),
            "cached": True,
        }

    from src.services.insights import summarize_transcript
    result = summarize_transcript(
        transcript.get("text") or "", transcript.get("speaker_labels") or []
    )
    update_transcript(tid, {"summary": result["summary"], "title": result["title"]})

    return {
        "success": True,
        "summary": result["summary"],
        "title": result["title"],
        "cached": False,
    }
