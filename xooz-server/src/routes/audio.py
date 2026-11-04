from fastapi import APIRouter, UploadFile, File, Form, HTTPException, BackgroundTasks
import tempfile
import os
from src.services.transcription.index import transcribe
from src.services.database import save_transcript, update_transcript, increment_minutes_used
from src.services.insights import classify_transcript, extract_tasks

router = APIRouter()

ALLOWED_EXTENSIONS = (".wav", ".mp3", ".m4a", ".webm", ".ogg", ".mp4")


def _post_process(user_id: str, transcript_id: str, text: str):
    """Runs after the upload response is sent:
    tags the transcript (category/people/places for search) and extracts tasks."""
    try:
        classification = classify_transcript(text)
        update_transcript(transcript_id, classification)
    except Exception:
        pass  # non-critical — transcript stays usable without tags

    try:
        tasks = extract_tasks(text)
        if tasks:
            from src.services.database import save_tasks
            save_tasks(user_id=user_id, tasks=tasks, source_transcript_id=transcript_id)
    except Exception:
        pass

    try:
        words = len(text.split())
        increment_minutes_used(user_id, minutes=words / 150.0)  # ~150 wpm speech
    except Exception:
        pass


@router.post("/audio")
async def upload_audio(
    background_tasks: BackgroundTasks,
    file: UploadFile = File(...),
    user_id: str = Form(...),
):
    # validate file type
    if not file.filename or not file.filename.lower().endswith(ALLOWED_EXTENSIONS):
        raise HTTPException(status_code=400, detail="Unsupported audio format")

    # save uploaded file to a temp location
    with tempfile.NamedTemporaryFile(delete=False, suffix=os.path.splitext(file.filename)[1]) as tmp:
        contents = await file.read()
        tmp.write(contents)
        tmp_path = tmp.name

    try:
        # transcribe
        result = transcribe(tmp_path)

        # save to database (failure leaves a 'failed' row so it shows in Activity → Needs Attention)
        transcript = save_transcript(
            user_id=user_id,
            text=result["text"],
            speaker_labels=result["speaker_labels"],
            status="completed",
        )

        # tag + extract tasks + usage accounting in the background
        background_tasks.add_task(_post_process, user_id, transcript["id"], result["text"])

        return {
            "success": True,
            # top-level fields kept for backward compatibility with the app
            "transcript_id": transcript["id"],
            "text": result["text"],
            "recorded_at": transcript["recorded_at"],
            "transcript": transcript,
        }

    except HTTPException:
        raise
    except Exception as e:
        # best effort: leave a failed row so "Needs Attention" can show it
        try:
            save_transcript(user_id=user_id, text="", speaker_labels=[], status="failed",
                            extra={"error_message": str(e)[:500]})
        except Exception:
            pass
        raise HTTPException(status_code=500, detail=str(e))

    finally:
        # always clean up temp file
        os.unlink(tmp_path)
