from openai import OpenAI
from src.config import OPENAI_API_KEY

client = OpenAI(api_key=OPENAI_API_KEY)

def transcribe(audio_file_path: str) -> str:
    with open(audio_file_path, "rb") as audio_file:
        response = client.audio.transcriptions.create(
            model="whisper-1",
            file=audio_file,
            response_format="text"
        )
    return response