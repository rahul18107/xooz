import json
import unittest
from unittest.mock import patch

from src.services import insights


class LongTranscriptSummaryTest(unittest.TestCase):
    def test_chunks_cover_entire_recording(self):
        recording = "opening " * 600 + "Closing decision: book the train to Pune."
        chunks = insights._recording_chunks(recording)
        self.assertGreater(len(chunks), 1)
        self.assertIn("Closing decision: book the train to Pune.", chunks[-1])
        self.assertTrue(all(len(chunk) <= 3500 for chunk in chunks))

    def test_summary_uses_evidence_from_last_chunk(self):
        recording = "opening " * 600 + "Closing decision: book the train to Pune."

        def generate(prompt, max_tokens=512):
            if "Extract up to 3" in prompt:
                if "Closing decision: book the train to Pune." in prompt:
                    return json.dumps({"facts": [{
                        "text": "Book the train to Pune.",
                        "quote": "Closing decision: book the train to Pune.",
                    }]})
                return '{"facts":[]}'
            self.assertIn("Closing decision: book the train to Pune.", prompt)
            return "Train to Pune\n- Book the train to Pune."

        with patch.object(insights, "_call_llm", side_effect=generate):
            summary = insights.summarize_transcript(recording)
        self.assertIn("Book the train to Pune", summary["summary"])


if __name__ == "__main__":
    unittest.main()
