from fastapi import APIRouter, UploadFile, File, Form, HTTPException, BackgroundTasks
import tempfile
import os
from src.services.transcription.index import transcribe
from src.services.database import client as supabase, save_transcript, update_transcript, increment_minutes_used, get_profile
from src.services.insights import extract_tasks

router = APIRouter()

STORAGE_BUCKET = "recordings"

ALLOWED_EXTENSIONS = (".wav", ".mp3", ".m4a", ".webm", ".ogg", ".mp4")


def _store_audio(user_id: str, transcript_id: str, contents: bytes, content_type: str | None) -> str | None:
    """Upload the recording to Supabase Storage and return its public URL (None on failure)."""
    try:
        ext = "m4a"
        storage_path = f"{user_id}/{transcript_id}.{ext}"
        supabase.storage.from_(STORAGE_BUCKET).upload(
            path=storage_path,
            file=contents,
            file_options={"content-type": content_type or "audio/mp4"},
        )
        return supabase.storage.from_(STORAGE_BUCKET).get_public_url(storage_path)
    except Exception as e:
        # audio storage should never block a successful transcription
        print(f"audio storage failed: {e}")
        return None


def _post_process(user_id: str, transcript_id: str, text: str):
    """Runs after the upload response is sent:
    extracts tasks and accounts for usage."""

    try:
        tasks = extract_tasks(text)
        if tasks:
            from src.services.database import save_tasks
            save_tasks(user_id=user_id, tasks=tasks, source_transcript_id=transcript_id)
    except Exception:
        pass

    try:
        from src.services.chat_retrieval import index_transcript
        index_transcript(transcript_id, text)
    except Exception as exc:
        print(f"chat embedding indexing failed: {exc}")

    try:
        from src.services.personal_facts import index_personal_facts
        index_personal_facts(user_id, transcript_id, text)
    except Exception as exc:
        print(f"personal fact indexing failed: {exc}")

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
    duration_seconds: float | None = Form(None),
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
        try:
            profile = get_profile(user_id) or {}
            keyterms = profile.get("transcription_vocabulary") or []
        except Exception:
            keyterms = []
        result = transcribe(tmp_path, keyterms=keyterms)

        # save to database (failure leaves a 'failed' row so it shows in Activity → Needs Attention)
        transcript = save_transcript(
            user_id=user_id,
            text=result["text"],
            speaker_labels=result["speaker_labels"],
            status="completed",
            extra={"duration_seconds": max(0, duration_seconds or 0)},
        )

        metadata = {
            "speaker_labels": result.get("speaker_labels") or [],
            "tags": result.get("tags") or [],
            "people": result.get("people") or [],
            "places": result.get("places") or [],
            "language": result.get("language") or "en",
        }
        transcript = update_transcript(transcript["id"], metadata) or {**transcript, **metadata}

        # keep the audio so the user can replay the recording later
        audio_url = _store_audio(user_id, transcript["id"], contents, file.content_type)
        if audio_url:
            try:
                update_transcript(transcript["id"], {"audio_url": audio_url})
            except Exception as e:
                # The transcript is already saved. A missing audio_url column
                # must not turn a successful transcription into an upload error.
                print(f"audio URL update failed: {e}")
                audio_url = None

        # extract tasks and account for usage in the background
        background_tasks.add_task(_post_process, user_id, transcript["id"], result["text"])

        transcript = {**transcript, "audio_url": audio_url}
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
