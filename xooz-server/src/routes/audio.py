from fastapi import APIRouter, UploadFile, File, Form, HTTPException
import tempfile
import os
from src.services.transcription.index import transcribe
from src.services.database import save_transcript

router = APIRouter()

@router.post("/audio")
async def upload_audio(
    file: UploadFile = File(...),
    user_id: str = Form(...)
):
    # validate file type
    if not file.filename.endswith((".wav", ".mp3", ".m4a", ".webm", ".ogg",".mp4")):
        raise HTTPException(status_code=400, detail="Unsupported audio format")

    # save uploaded file to a temp location
    with tempfile.NamedTemporaryFile(delete=False, suffix=os.path.splitext(file.filename)[1]) as tmp:
        contents = await file.read()
        tmp.write(contents)
        tmp_path = tmp.name

    try:
        # transcribe
        result = transcribe(tmp_path)

        # save to database
        transcript = save_transcript(
            user_id=user_id,
            text=result["text"],
            speaker_labels=result["speaker_labels"]
        )

        return {
            "success": True,
            "transcript_id": transcript["id"],
            "text": result["text"]
        }

    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

    finally:
        # always clean up temp file
        os.unlink(tmp_path)