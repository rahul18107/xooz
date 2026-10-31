import assemblyai as aai
from src.config import ASSEMBLYAI_API_KEY

aai.settings.api_key = ASSEMBLYAI_API_KEY

def transcribe(audio_file_path: str) -> dict:
    config = aai.TranscriptionConfig(
        speech_model=aai.SpeechModel.universal,
        speaker_labels=True,
    )

    transcriber = aai.Transcriber(config=config)
    transcript = transcriber.transcribe(audio_file_path)

    if transcript.status == aai.TranscriptStatus.error:
        raise Exception(f"AssemblyAI transcription error: {transcript.error}")

    speaker_labels = []
    if transcript.utterances:
        for utterance in transcript.utterances:
            speaker_labels.append({
                "speaker": utterance.speaker,
                "text": utterance.text,
                "start": utterance.start,
                "end": utterance.end
            })

    return {
        "text": transcript.text,
        "speaker_labels": speaker_labels
    }