import unittest
from types import SimpleNamespace
from unittest.mock import patch

from src.services.transcription import assemblyai


class AssemblyAIMetadataTest(unittest.TestCase):
    @patch.object(assemblyai.aai, "Transcriber")
    def test_transcript_metadata(self, transcriber):
        transcriber.return_value.transcribe.return_value = SimpleNamespace(
            status=assemblyai.aai.TranscriptStatus.completed,
            text="Alice met Bob in Paris.",
            utterances=[SimpleNamespace(speaker="A", text="Alice met Bob in Paris.", start=10, end=2000)],
            entities=[
                SimpleNamespace(entity_type="person_name", text="Alice"),
                SimpleNamespace(entity_type="person", text="Bob"),
                SimpleNamespace(entity_type="person_name", text="Alice"),
                SimpleNamespace(entity_type="location", text="Paris"),
            ],
            iab_categories=SimpleNamespace(summary={
                "sixth": 0.1, "first": 0.9, "third": 0.7,
                "second": 0.8, "fifth": 0.5, "fourth": 0.6,
            }),
            language_code="fr",
        )

        result = assemblyai.transcribe("memo.wav")

        config = transcriber.call_args.kwargs["config"]
        self.assertTrue(config.speaker_labels)
        self.assertTrue(config.entity_detection)
        self.assertTrue(config.iab_categories)
        self.assertEqual(result["people"], ["Alice", "Bob"])
        self.assertEqual(result["places"], ["Paris"])
        self.assertEqual(result["tags"], ["first", "second", "third", "fourth", "fifth"])
        self.assertEqual(result["speaker_labels"], [
            {"speaker": "A", "text": "Alice met Bob in Paris.", "start": 10, "end": 2000}
        ])
        self.assertEqual(result["language"], "fr")

    @patch.object(assemblyai.aai, "Transcriber")
    def test_missing_optional_metadata(self, transcriber):
        transcriber.return_value.transcribe.return_value = SimpleNamespace(
            status=assemblyai.aai.TranscriptStatus.completed,
            text="Hello.",
            utterances=None,
            entities=None,
            iab_categories=None,
            language_code=None,
        )

        result = assemblyai.transcribe("memo.wav")

        self.assertEqual(result["speaker_labels"], [])
        self.assertEqual(result["people"], [])
        self.assertEqual(result["places"], [])
        self.assertEqual(result["tags"], [])
        self.assertEqual(result["language"], "en")


if __name__ == "__main__":
    unittest.main()
