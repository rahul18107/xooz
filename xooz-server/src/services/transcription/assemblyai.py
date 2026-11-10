import assemblyai as aai
from src.config import ASSEMBLYAI_API_KEY

aai.settings.api_key = ASSEMBLYAI_API_KEY

def transcribe(audio_file_path: str, keyterms: list[str] | None = None) -> dict:
    options = dict(
        speech_models=["universal-3-5-pro", "universal-2"],
        language_detection=True,
        speaker_labels=True,
        entity_detection=True,
        iab_categories=True,
    )
    if keyterms:
        options["keyterms_prompt"] = keyterms[:200]

    transcript = aai.Transcriber(config=aai.TranscriptionConfig(**options)).transcribe(audio_file_path)

    if transcript.status == aai.TranscriptStatus.error and any(
        term in (transcript.error or "").lower()
        for term in ("iab_categories", "entity_detection", "topic detection", "entity detection", "not available in this language")
    ):
        options["iab_categories"] = False
        options["entity_detection"] = False
        transcript = aai.Transcriber(config=aai.TranscriptionConfig(**options)).transcribe(audio_file_path)

    if (transcript.status == aai.TranscriptStatus.error and
            "speaker_labels" in (transcript.error or "").lower()):
        options["speaker_labels"] = False
        transcript = aai.Transcriber(config=aai.TranscriptionConfig(**options)).transcribe(audio_file_path)

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

    entities = transcript.entities or []
    categories = transcript.iab_categories
    scores = (categories.summary or {}) if categories else {}

    return {
        "text": transcript.text,
        "speaker_labels": speaker_labels,
        "people": list(dict.fromkeys(
            entity.text for entity in entities
            if entity.entity_type in ("person", "person_name")
        )),
        "places": list(dict.fromkeys(
            entity.text for entity in entities
            if entity.entity_type == "location"
        )),
        "tags": [label for label, _ in sorted(
            scores.items(), key=lambda item: item[1], reverse=True
        )[:5]],
        "language": transcript.language_code or "en",
    }
