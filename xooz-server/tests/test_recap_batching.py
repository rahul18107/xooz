import json
import unittest
from unittest.mock import patch

from src.services import summarization


class RecapBatchingTest(unittest.TestCase):
    def test_even_a_short_recording_requires_two_supported_paragraphs(self):
        recording = {"id": "one", "text": "Discussed train travel and hotel options.",
                     "summary": "- Train travel was discussed.\n- Hotel options were discussed."}
        one_paragraph = {"title": "Train travel", "paragraphs": [{
            "text": "Train travel was discussed.", "recording_id": "one",
            "quote": recording["text"],
        }]}
        with patch.object(summarization, "_summarize_cloudflare", return_value=json.dumps(one_paragraph)), \
             patch.object(summarization, "ACTIVE_SUMMARIZATION_PROVIDER", "cloudflare"):
            _, structured, unavailable = summarization.summarize_structured_with_status([recording])
        self.assertFalse(unavailable)
        self.assertEqual(len(structured["paragraphs"]), 2)

    def test_one_unsupported_fact_is_not_padded_to_two_paragraphs(self):
        recording = {"id": "one", "text": "Discussed train travel."}
        one_paragraph = {"title": "Train travel", "paragraphs": [{
            "text": "Train travel was discussed.", "recording_id": "one",
            "quote": recording["text"],
        }]}
        with patch.object(summarization, "_summarize_cloudflare", return_value=json.dumps(one_paragraph)), \
             patch.object(summarization, "ACTIVE_SUMMARIZATION_PROVIDER", "cloudflare"):
            _, structured, unavailable = summarization.summarize_structured_with_status([recording])
        self.assertTrue(unavailable)
        self.assertIsNone(structured)

    def test_fallback_skips_unsupported_bullet_before_valid_evidence(self):
        recording = {"id": "one", "text": "Discussed train travel.",
                     "summary": "- Booked a flight to Mars.\n- Train travel was discussed."}
        data = summarization._summary_backed_data(recording, limit=1)
        self.assertEqual(len(data["paragraphs"]), 1)
        self.assertIn("train travel", data["paragraphs"][0]["text"])

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

    def test_thin_multi_recording_recap_is_not_accepted(self):
        recordings = [{"id": str(i), "text": f"Decision {i}: book train tickets for Pune."}
                      for i in range(4)]
        one_paragraph = {"title": "Train tickets", "paragraphs": [{
            "text": "Train tickets for Pune were discussed.",
            "recording_id": "0", "quote": recordings[0]["text"],
        }]}
        with patch.object(summarization, "_summarize_cloudflare", return_value=json.dumps(one_paragraph)), \
             patch.object(summarization, "ACTIVE_SUMMARIZATION_PROVIDER", "cloudflare"):
            summary, structured, unavailable = summarization.summarize_structured_with_status(recordings)
        self.assertIsNone(summary)
        self.assertIsNone(structured)
        self.assertTrue(unavailable)

    def test_saved_recording_summaries_fill_missing_day_topics_when_grounded(self):
        recordings = [{"id": str(i), "text": f"We discussed topic {i} and agreed on plan {i}.",
                       "summary": f"Topic {i} and plan {i} were discussed."}
                      for i in range(4)]
        one_paragraph = {"title": "Day plans", "paragraphs": [{
            "text": "Topic 0 and plan 0 were discussed.",
            "recording_id": "0", "quote": recordings[0]["text"],
        }]}
        with patch.object(summarization, "_summarize_cloudflare", return_value=json.dumps(one_paragraph)), \
             patch.object(summarization, "ACTIVE_SUMMARIZATION_PROVIDER", "cloudflare"):
            summary, structured, unavailable = summarization.summarize_structured_with_status(recordings)
        self.assertFalse(unavailable)
        self.assertGreaterEqual(len(structured["paragraphs"]), 3)
        self.assertIn("topic 1", summary)

    def test_summary_fallback_strips_unsupported_speaker_name(self):
        recording = {"id": "one", "text": "We discussed a train trip to Pune.",
                     "summary": "- Speaker A (Invented): Discussed a train trip to Pune."}
        data = summarization._summary_backed_data(recording)
        self.assertIsNotNone(data)
        self.assertNotIn("Invented", data["paragraphs"][0]["text"])

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
        self.assertTrue(fallback)
        self.assertIsNone(result)

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
        self.assertTrue(preview)
        self.assertIsNone(result)

    def test_selection_failure_deduplicates_repeated_facts_across_day(self):
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
        self.assertTrue(unavailable)
        self.assertIsNone(result)

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
        self.assertTrue(unavailable)
        self.assertIsNone(result)


if __name__ == "__main__":
    unittest.main()
