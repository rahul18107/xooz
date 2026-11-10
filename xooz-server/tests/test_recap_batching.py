import json
import unittest
from unittest.mock import patch

from src.services import summarization


class RecapBatchingTest(unittest.TestCase):
    def test_long_recording_prompt_is_bounded_and_includes_end(self):
        recording = {"id": "one", "text": "opening " * 1000 + "Closing decision: book the train."}
        prompt = summarization._build_prompt([recording])
        self.assertIn("Closing decision: book the train.", prompt)
        self.assertLess(len(prompt), 5000)

    def test_five_grounded_paragraphs_are_allowed_for_a_full_day(self):
        recordings = [{"id": str(i), "text": f"Decision {i}: book train tickets for Pune."}
                      for i in range(5)]
        response = {"title": "Train tickets for Pune", "paragraphs": [
            {"text": f"Decision {i} was to book train tickets for Pune.",
             "recording_id": str(i), "quote": recordings[i]["text"]}
            for i in range(5)
        ]}
        recap = summarization._validated_recap(response, recordings)
        self.assertIsNotNone(recap)
        self.assertEqual(recap.count("book train tickets for Pune."), 5)

    def test_busy_day_uses_bounded_batches_and_validated_quotes(self):
        recordings = [
            {"id": str(i), "text": f"Decision {i}: book train tickets for Pune." + " More discussion." * 100,
             "recorded_at": "2026-11-08T10:00:00Z"}
            for i in range(20)
        ]
        self.assertGreater(len(summarization._prompt_batches(recordings)), 1)

        def generate(prompt):
            if "zero-based indices" in prompt:
                return json.dumps({"title": "Train tickets for Pune", "indices": [0, 1]})
            first = next(t for t in recordings if f"id {t['id']} " in prompt)
            return json.dumps({"title": "Train tickets for Pune", "paragraphs": [{
                "text": "Train tickets for Pune were discussed.",
                "recording_id": first["id"], "quote": first["text"],
            }]})

        with patch.object(summarization, "_summarize_cloudflare", side_effect=generate), \
             patch.object(summarization, "ACTIVE_SUMMARIZATION_PROVIDER", "cloudflare"):
            result, fallback = summarization.summarize_with_status(recordings)
        self.assertFalse(fallback)
        self.assertIn("Train tickets for Pune were discussed.", result)

    def test_invalid_selection_keeps_validated_candidates(self):
        recordings = [
            {"id": str(i), "text": f"Decision {i}: book train tickets for Pune." + " More discussion." * 100}
            for i in range(20)
        ]

        def generate(prompt):
            if "zero-based indices" in prompt:
                return '{"title":"Train tickets for Pune","indices":[999]}'
            first = next(t for t in recordings if f"id {t['id']} " in prompt)
            return json.dumps({"title": "Train tickets for Pune", "paragraphs": [{
                "text": "Train tickets for Pune were discussed.",
                "recording_id": first["id"], "quote": first["text"],
            }]})

        with patch.object(summarization, "_summarize_cloudflare", side_effect=generate), \
             patch.object(summarization, "ACTIVE_SUMMARIZATION_PROVIDER", "cloudflare"):
            result, preview = summarization.summarize_with_status(recordings)
        self.assertFalse(preview)
        self.assertIn("Train tickets for Pune were discussed.", result)

    def test_selection_failure_uses_candidates_across_day(self):
        recordings = [
            {"id": str(i), "text": f"Decision {i}: book train tickets for Pune." + " More discussion." * 100}
            for i in range(20)
        ]

        def generate(prompt):
            if "zero-based indices" in prompt:
                raise RuntimeError("selection offline")
            first = next(t for t in recordings if f"id {t['id']} " in prompt)
            return json.dumps({"title": "Train tickets for Pune", "paragraphs": [{
                "text": "Train tickets for Pune were discussed.",
                "recording_id": first["id"], "quote": first["text"],
            }]})

        with patch.object(summarization, "_summarize_cloudflare", side_effect=generate), \
             patch.object(summarization, "ACTIVE_SUMMARIZATION_PROVIDER", "cloudflare"):
            result, unavailable = summarization.summarize_with_status(recordings)
        self.assertFalse(unavailable)
        self.assertEqual(result.count("Train tickets for Pune were discussed."), 3)

    def test_object_response_for_final_selection(self):
        recordings = [
            {"id": str(i), "text": f"Decision {i}: book train tickets for Pune." + " More discussion." * 100}
            for i in range(20)
        ]

        def generate(prompt):
            if "zero-based indices" in prompt:
                return {"title": "Train tickets for Pune", "indices": [1]}
            first = next(t for t in recordings if f"id {t['id']} " in prompt)
            return {"title": "Train tickets for Pune", "paragraphs": [{
                "text": "Train tickets for Pune were discussed.",
                "recording_id": first["id"], "quote": first["text"],
            }]}

        with patch.object(summarization, "_summarize_cloudflare", side_effect=generate), \
             patch.object(summarization, "ACTIVE_SUMMARIZATION_PROVIDER", "cloudflare"):
            result, unavailable = summarization.summarize_with_status(recordings)
        self.assertFalse(unavailable)
        self.assertEqual(result.count("Train tickets for Pune were discussed."), 1)


if __name__ == "__main__":
    unittest.main()
