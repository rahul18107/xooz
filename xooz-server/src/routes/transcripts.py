from fastapi import APIRouter, BackgroundTasks, HTTPException, Query
from src.services.database import get_transcripts, get_transcript_by_id, update_transcript, delete_transcript, get_digest, get_profile_tz, get_speakers, get_or_create_speaker, client as supabase
from datetime import datetime
import asyncio
import uuid

def _validate_uuid(value: str) -> str:
    try:
        return str(uuid.UUID(value))
    except ValueError:
        raise HTTPException(status_code=404, detail="Transcript not found")

router = APIRouter()

@router.get("/speakers")
async def list_speakers(user_id: str = Query(...)):
    return {"success": True, "speakers": get_speakers(user_id)}

def _refresh_speaker_recap(user_id: str, date: str):
    if not get_digest(user_id, date):
        return
    from src.routes.digest import _current_digest
    day_transcripts = get_transcripts(user_id=user_id, date=date, limit=200)
    _current_digest(user_id, date, day_transcripts)

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

@router.post("/transcripts/{transcript_id}/speaker-suggestion")
async def get_speaker_suggestion(transcript_id: str, label: str, user_id: str):
    tid = _validate_uuid(transcript_id)
    transcript = get_transcript_by_id(tid)
    if not transcript or transcript.get("user_id") != user_id:
        raise HTTPException(status_code=404, detail="Transcript not found")
    if label not in {str(turn.get("speaker")) for turn in transcript.get("speaker_labels") or []}:
        raise HTTPException(status_code=400, detail="Unknown speaker label")
    from src.services.speaker_voice import suggest_speaker
    try:
        suggestion = await asyncio.to_thread(suggest_speaker, tid, label, user_id)
    except Exception as exc:
        print(f"speaker suggestion failed: transcript={tid} label={label}: {exc}")
        suggestion = None
    return {"success": True, "suggestion": suggestion}

@router.patch("/transcripts/{transcript_id}")
async def patch_transcript(transcript_id: str, body: dict, background_tasks: BackgroundTasks):
    """Update a transcript's title, starred state, or speaker names."""
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
    names_changed = False
    if "speaker_names" in body:
        names = body["speaker_names"]
        if not isinstance(names, dict):
            raise HTTPException(status_code=400, detail="speaker_names must be an object")
        speakers = {str(u.get("speaker")) for u in transcript.get("speaker_labels") or [] if u.get("speaker")}
        if any(key not in speakers for key in names):
            raise HTTPException(status_code=400, detail="Unknown speaker label")
        if any(not isinstance(name, str) or len(name.strip()) > 80 for name in names.values()):
            raise HTTPException(status_code=400, detail="Speaker names must be text of at most 80 characters")
        clean_names = {key: name.strip() for key, name in names.items() if name.strip()}
        names_changed = clean_names != (transcript.get("speaker_names") or {})
        if names_changed:
            speaker_ids = dict(transcript.get("speaker_ids") or {})
            canonical_names = {}
            for label, name in clean_names.items():
                if name == (transcript.get("speaker_names") or {}).get(label) and label in speaker_ids:
                    canonical_names[label] = name
                    continue
                speaker = get_or_create_speaker(transcript["user_id"], name)
                speaker_ids[label] = speaker["id"]
                canonical_names[label] = speaker["name"]
            for label in set(speaker_ids) - set(clean_names):
                speaker_ids.pop(label)
            updates["speaker_names"] = canonical_names
            updates["speaker_ids"] = speaker_ids
            updates["summary"] = None
    if not updates:
        return {"success": True, "transcript": transcript}

    updated = update_transcript(tid, updates)
    if names_changed:
        from src.services.speaker_voice import remove_voice_sample, enroll_in_background
        previous_ids = transcript.get("speaker_ids") or {}
        current_ids = updated.get("speaker_ids") or {}
        for label in set(previous_ids) | set(current_ids):
            if previous_ids.get(label) == current_ids.get(label):
                continue
            if previous_ids.get(label):
                background_tasks.add_task(remove_voice_sample, tid, label, previous_ids[label])
            if current_ids.get(label) and updated.get("audio_url"):
                background_tasks.add_task(enroll_in_background, tid, label, current_ids[label])
        recorded_at = datetime.fromisoformat(transcript["recorded_at"].replace("Z", "+00:00"))
        day = recorded_at.astimezone(get_profile_tz(transcript["user_id"])).date().isoformat()
        background_tasks.add_task(_refresh_speaker_recap, transcript["user_id"], day)
    return {"success": True, "transcript": updated}

@router.delete("/transcripts/{transcript_id}")
async def remove_transcript(transcript_id: str):
    tid = _validate_uuid(transcript_id)
    transcript = get_transcript_by_id(tid)
    if not transcript:
        raise HTTPException(status_code=404, detail="Transcript not found")
    deleted = delete_transcript(tid)
    if not deleted:
        raise HTTPException(status_code=404, detail="Transcript not found")
    try:
        from src.routes.audio import STORAGE_BUCKET
        path = f"{transcript['user_id']}/{tid}.m4a"
        supabase.storage.from_(STORAGE_BUCKET).remove([path])
    except Exception as exc:
        print(f"audio cleanup failed for transcript {tid}: {exc}")
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
        transcript.get("text") or "", transcript.get("speaker_labels") or [],
        transcript.get("speaker_names") or {},
    )
    update_transcript(tid, {"summary": result["summary"], "title": result["title"]})

    return {
        "success": True,
        "summary": result["summary"],
        "title": result["title"],
        "cached": False,
    }
