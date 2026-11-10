import importlib.util
from pathlib import Path
import sys
import types
import unittest
from unittest.mock import patch


class MultilingualTranscriptionTest(unittest.TestCase):
    def setUp(self):
        self.configs = []
        self.responses = []
        fake = types.ModuleType("assemblyai")
        fake.settings = types.SimpleNamespace(api_key=None)
        fake.TranscriptStatus = types.SimpleNamespace(error="error")
        fake.TranscriptionConfig = lambda **options: self.configs.append(options) or options
        fake.Transcriber = lambda config: types.SimpleNamespace(
            transcribe=lambda path: self.responses.pop(0))
        path = Path(__file__).resolve().parents[1] / "src/services/transcription/assemblyai.py"
        spec = importlib.util.spec_from_file_location("_assemblyai_under_test", path)
        module = importlib.util.module_from_spec(spec)
        with patch.dict(sys.modules, {"assemblyai": fake}):
            spec.loader.exec_module(module)
        self.module = module

    def test_detects_language_and_passes_vocabulary(self):
        self.responses = [types.SimpleNamespace(
            status="completed", error=None, text="Namaste",
            utterances=[], entities=[], iab_categories=None, language_code="hi")]
        result = self.module.transcribe("audio.wav", keyterms=["Priya Sharma"])
        self.assertTrue(self.configs[0]["language_detection"])
        self.assertEqual(self.configs[0]["speech_models"], ["universal-3-5-pro", "universal-2"])
        self.assertEqual(self.configs[0]["keyterms_prompt"], ["Priya Sharma"])
        self.assertEqual(result["language"], "hi")

    def test_unsupported_enrichment_retries_without_it(self):
        self.responses = [
            types.SimpleNamespace(status="error", error="iab_categories not available in this language"),
            types.SimpleNamespace(status="completed", error=None, text="Namaste",
                                  utterances=[], entities=[], iab_categories=None, language_code="hi"),
        ]
        result = self.module.transcribe("audio.wav")
        self.assertEqual(result["text"], "Namaste")
        self.assertFalse(self.configs[1]["iab_categories"])
        self.assertFalse(self.configs[1]["entity_detection"])
        self.assertTrue(self.configs[1]["speaker_labels"])


if __name__ == "__main__":
    unittest.main()
