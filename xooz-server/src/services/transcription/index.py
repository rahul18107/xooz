from src.config import ACTIVE_TRANSCRIPTION_PROVIDER
from src.services.transcription import whisper, assemblyai, cloudflare

def transcribe(audio_file_path: str, keyterms: list[str] | None = None) -> dict:
    if ACTIVE_TRANSCRIPTION_PROVIDER == "whisper":
        text = whisper.transcribe(audio_file_path)
        return {
            "text": text,
            "speaker_labels": []
        }
    
    elif ACTIVE_TRANSCRIPTION_PROVIDER == "assemblyai":
        return assemblyai.transcribe(audio_file_path, keyterms=keyterms)
    
    elif ACTIVE_TRANSCRIPTION_PROVIDER == "cloudflare":
        return cloudflare.transcribe(audio_file_path)
    
    else:
        raise Exception(f"Unknown transcription provider: {ACTIVE_TRANSCRIPTION_PROVIDER}")
