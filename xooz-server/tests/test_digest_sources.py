import asyncio
import httpx
import unittest
from datetime import datetime, timezone
from unittest.mock import patch
from fastapi import HTTPException

from src.routes import digest
from src.services import database, summarization


class DigestSourcesTest(unittest.TestCase):
    def setUp(self):
        self.recordings = [{"id": "one", "status": "completed", "text": "Discussed train travel", "speaker_names": {}, "recorded_at": "2026-11-08T10:00:00Z"}]

    def test_unchanged_inputs_use_cached_digest(self):
        existing = {"summary": "Train travel", "source_fingerprint": digest._fingerprint(self.recordings)}
        with patch.object(digest, "get_digest", return_value=existing), \
             patch.object(digest, "update_digest") as update:
            result, cached = digest._current_digest("user", "2026-11-08", self.recordings)
        self.assertIs(result, existing)
        self.assertTrue(cached)
        update.assert_not_called()

    def test_day_fetch_paginates_without_truncating_recordings(self):
        rows = [{"id": str(i)} for i in range(5)]
        with patch.object(database, "client") as client, \
             patch.object(database, "day_bounds_utc", return_value=("start", "end")):
            query = client.table.return_value
            query.select.return_value = query
            query.eq.return_value = query
            query.gte.return_value = query
            query.lt.return_value = query
            query.order.return_value = query
            query.range.return_value = query
            query.execute.side_effect = [
                type("Result", (), {"data": rows[:2]})(),
                type("Result", (), {"data": rows[2:4]})(),
                type("Result", (), {"data": rows[4:]})(),
            ]
            result = database.get_day_transcripts("user", "2026-11-08", page_size=2)
        self.assertEqual(result, rows)
        self.assertEqual([call.args for call in query.range.call_args_list],
                         [(0, 1), (2, 3), (4, 5)])

    def test_new_recording_refreshes_existing_digest(self):
        structured = {"title": "Train day", "paragraphs": []}
        with patch.object(digest, "get_digest", return_value={"summary": "old"}), \
             patch.object(digest, "update_digest", return_value={"summary": "new"}) as update, \
             patch("src.services.summarization.summarize_structured_with_status", return_value=("new", structured, False)):
            result, cached = digest._current_digest("user", "2026-11-08", self.recordings)
        self.assertFalse(cached)
        self.assertEqual(result["summary"], "new")
        self.assertEqual(update.call_args.args[3], ["one"])
        self.assertEqual(update.call_args.args[5], structured)

    def test_incomplete_recordings_are_not_summarized(self):
        with patch.object(digest, "get_digest", return_value=None), \
             patch("src.services.summarization.summarize_structured_with_status") as summarize:
            result, _ = digest._current_digest("user", "2026-11-08", [{"id": "pending", "status": "processing"}])
        self.assertIsNone(result)
        summarize.assert_not_called()

    def test_completed_recording_without_speech_is_not_recap_evidence(self):
        with patch.object(digest, "get_digest", return_value=None), \
             patch("src.services.summarization.summarize_structured_with_status") as summarize:
            result, _ = digest._current_digest(
                "user", "2026-11-08", [{"id": "silent", "status": "completed", "text": "  "}]
            )
        self.assertIsNone(result)
        summarize.assert_not_called()

    def test_recap_requires_exact_quote_from_source(self):
        recording = {**self.recordings[0], "recorded_at": "2026-11-08T10:00:00Z"}
        valid = '{"title":"Train discussion","paragraphs":[{"text":"Train travel was discussed.","recording_id":"one","quote":"Discussed train travel"}]}'
        invented = valid.replace("Discussed train travel", "Booked train tickets")
        self.assertIn("Train travel was discussed.", summarization._validated_recap(valid, [recording]))
        self.assertIsNone(summarization._validated_recap(invented, [recording]))
        self.assertIsNone(summarization._validated_recap(valid.replace("Train travel was discussed", "Priya discussed train travel"), [recording]))
        self.assertTrue(summarization._validated_recap(valid.replace("Train discussion", "Mumbai discussion"), [recording]).startswith("Discussed train travel"))

    def test_quote_validation_tolerates_punctuation_but_not_changed_words(self):
        recording = {**self.recordings[0], "text": "Priya said, book the train."}
        valid = {"title": "Train booking", "paragraphs": [{
            "text": "Priya said to book the train.", "recording_id": "one",
            "quote": "Priya said book the train",
        }]}
        self.assertIsNotNone(summarization._validated_recap_data(valid, [recording]))
        valid["paragraphs"][0]["quote"] = "Priya said cancel the train"
        self.assertIsNone(summarization._validated_recap_data(valid, [recording]))

    def test_valid_paragraph_survives_invalid_paragraph(self):
        raw = '{"title":"Train discussion","paragraphs":[{"text":"Train travel was discussed.","recording_id":"one","quote":"Discussed train travel"},{"text":"Priya booked a flight.","recording_id":"one","quote":"Nonexistent flight booking"}]}'
        result = summarization._validated_recap(raw, self.recordings)
        self.assertIn("Train travel was discussed.", result)
        self.assertNotIn("flight", result)

    def test_structured_items_require_real_source_quotes(self):
        raw = {"title": "Train discussion", "paragraphs": [{
            "text": "Train travel was discussed.", "recording_id": "one",
            "quote": "Discussed train travel",
        }], "action_items": [{
            "text": "Book a flight tomorrow.", "recording_id": "one",
            "quote": "Flight booking tomorrow",
        }], "decisions": [], "unresolved_questions": []}
        structured = summarization._validated_recap_data(raw, self.recordings)
        self.assertEqual(structured["action_items"], [])
        self.assertEqual(len(structured["paragraphs"]), 1)
        self.assertEqual(structured["highlights"], structured["paragraphs"])
        self.assertEqual(structured["headline"], "Train discussion")

    def test_provider_failure_does_not_use_transcript_as_summary(self):
        with patch.object(summarization, "_summarize_cloudflare", side_effect=RuntimeError("offline")), \
             patch.object(summarization, "ACTIVE_SUMMARIZATION_PROVIDER", "cloudflare"):
            result, fallback = summarization.summarize_with_status(self.recordings)
        self.assertTrue(fallback)
        self.assertIsNone(result)

    def test_old_incomplete_speaker_labels_do_not_break_prompt(self):
        recording = {**self.recordings[0], "speaker_labels": [None, {"speaker": "A"}, {"speaker": "B", "text": "Discussed train travel"}]}
        prompt = summarization._build_prompt([recording])
        self.assertIn("Speaker B: Discussed train travel", prompt)

    def test_fallback_retries_after_bucket_expires(self):
        fingerprint = digest._fingerprint(self.recordings)
        with patch.object(digest, "get_digest", return_value={"summary": "old", "source_fingerprint": f"fallback:{fingerprint}:2000010100"}), \
             patch.object(digest, "update_digest", return_value={"summary": "better"}) as update, \
             patch("src.services.summarization.summarize_structured_with_status", return_value=("better", {}, False)):
            result, cached = digest._current_digest("user", "2026-11-08", self.recordings)
        self.assertFalse(cached)
        self.assertEqual(result["summary"], "better")
        self.assertEqual(update.call_args.args[4], fingerprint)

    def test_legacy_transcript_preview_is_regenerated_immediately(self):
        fingerprint = digest._fingerprint(self.recordings)
        bucket = datetime.now(timezone.utc).strftime("%Y%m%d%H")
        existing = {"summary": "Discussed train travel", "source_fingerprint": f"fallback:{fingerprint}:{bucket}"}
        with patch.object(digest, "get_digest", return_value=existing), \
             patch.object(digest, "update_digest", return_value={"summary": "Train travel was discussed."}) as update, \
             patch("src.services.summarization.summarize_structured_with_status", return_value=("Train travel was discussed.", {}, False)):
            result, cached = digest._current_digest("user", "2026-11-08", self.recordings)
        self.assertFalse(cached)
        self.assertEqual(result["summary"], "Train travel was discussed.")
        self.assertEqual(update.call_args.args[2], "Train travel was discussed.")

    def test_invalid_generation_does_not_use_transcript_excerpt(self):
        with patch.object(summarization, "_summarize_cloudflare", return_value="not json"), \
             patch.object(summarization, "ACTIVE_SUMMARIZATION_PROVIDER", "cloudflare"):
            result = summarization.summarize(self.recordings)
        self.assertIsNone(result)

    def test_invalid_first_response_retries_then_returns_real_summary(self):
        valid = ('{"title":"Train discussion","paragraphs":[{'
                 '"text":"Train travel was discussed.","recording_id":"one",'
                 '"quote":"Discussed train travel"}]}')
        with patch.object(summarization, "_summarize_cloudflare",
                          side_effect=["not json", valid]) as generate, \
             patch.object(summarization, "ACTIVE_SUMMARIZATION_PROVIDER", "cloudflare"):
            result, fallback = summarization.summarize_with_status(self.recordings)
        self.assertFalse(fallback)
        self.assertEqual(generate.call_count, 2)
        self.assertIn("Train travel was discussed.", result)
        self.assertNotIn("action_items", generate.call_args.args[0])

    def test_extra_model_paragraphs_keep_first_five_valid_ones(self):
        paragraphs = [{"text": "Train travel was discussed.", "recording_id": "one",
                       "quote": "Discussed train travel"} for _ in range(6)]
        data = summarization._validated_recap_data(
            {"title": "Train discussion", "paragraphs": paragraphs}, self.recordings)
        self.assertEqual(len(data["paragraphs"]), 5)

    def test_temporary_cloudflare_failure_retries_once(self):
        request = httpx.Request("POST", summarization.CLOUDFLARE_URL)
        failure = httpx.Response(503, request=request)
        success = httpx.Response(200, request=request, json={
            "success": True, "result": {"response": "ready"},
        })
        with patch.object(summarization.httpx, "post", side_effect=[failure, success]) as post, \
             patch.object(summarization.time, "sleep"):
            result = summarization._summarize_cloudflare("prompt")
        self.assertEqual(result, "ready")
        self.assertEqual(post.call_count, 2)

    def test_cloudflare_object_response_generates_recap(self):
        recap = {"title": "Train discussion", "paragraphs": [{
            "text": "Train travel was discussed.",
            "recording_id": "one", "quote": "Discussed train travel",
        }]}
        with patch.object(summarization.httpx, "post") as post, \
             patch.object(summarization, "ACTIVE_SUMMARIZATION_PROVIDER", "cloudflare"):
            post.return_value.json.return_value = {"success": True, "result": {"response": recap}}
            result, unavailable = summarization.summarize_with_status(self.recordings)
        self.assertFalse(unavailable)
        self.assertIn("Train travel was discussed.", result)
        self.assertEqual(post.call_count, 1)

    def test_failed_generation_stores_no_partial_or_raw_text(self):
        with patch.object(digest, "get_digest", return_value=None), \
             patch.object(digest, "save_digest", return_value={"summary": "", "source_fingerprint": "fallback:abc"}) as save, \
             patch("src.services.summarization.summarize_structured_with_status", return_value=("partial recap", None, True)):
            digest._current_digest("user", "2026-11-08", self.recordings)
        self.assertEqual(save.call_args.args[1], "")
        self.assertTrue(save.call_args.args[4].startswith("fallback:"))

    def test_generate_endpoint_rejects_unavailable_recap(self):
        failed = {"summary": "", "date": "2026-11-08", "source_fingerprint": "fallback:abc"}
        with patch.object(digest, "get_day_transcripts", return_value=self.recordings), \
             patch.object(digest, "_current_digest", return_value=(failed, False)):
            with self.assertRaises(HTTPException) as raised:
                asyncio.run(digest.generate_daily_digest("user", "2026-11-08"))
        self.assertEqual(raised.exception.status_code, 503)

    def test_generate_endpoint_returns_successful_summary(self):
        ready = {"summary": "A fuller recap", "date": "2026-11-08", "source_fingerprint": "ready"}
        with patch.object(digest, "get_day_transcripts", return_value=self.recordings), \
             patch.object(digest, "_current_digest", return_value=(ready, False)):
            response = asyncio.run(digest.generate_daily_digest("user", "2026-11-08"))
        self.assertEqual(response["digest"], "A fuller recap")

    def test_recap_action_items_link_to_saved_tasks(self):
        ready = {"summary": "Train planning", "source_fingerprint": "ready",
                 "source_transcript_ids": ["one"], "structured_summary": {
                     "action_items": [{"text": "Maybe book a flight", "recording_id": "one"}],
                     "decisions": [{"text": "Take the train", "recording_id": "one"}],
                 }}
        tasks = [
            {"id": "task-one", "title": "Book the train", "source_transcript_id": "one"},
            {"id": "task-other", "title": "Book a flight", "source_transcript_id": "other"},
        ]
        with patch.object(digest, "get_day_transcripts", return_value=self.recordings), \
             patch.object(digest, "_current_digest", return_value=(ready, True)), \
             patch.object(digest, "day_bounds_utc", return_value=("2026-11-08", "2026-11-09")), \
             patch.object(digest, "get_tasks", return_value=tasks):
            response = asyncio.run(digest.get_recap("user", "2026-11-08"))
        self.assertEqual(response["structured_summary"]["action_items"], [
            {"text": "Book the train", "recording_id": "one", "task_id": "task-one"}
        ])
        self.assertEqual(response["structured_summary"]["decisions"], ready["structured_summary"]["decisions"])
        self.assertEqual(ready["structured_summary"]["action_items"][0]["text"], "Maybe book a flight")

    def test_validated_recap_accepts_date_supported_by_quote(self):
        recording = {**self.recordings[0], "text": "We met Priya on 2026-11-08."}
        raw = ('{"title":"Priya meeting 2026-11-08","paragraphs":[{'
               '"text":"We met Priya on 2026-11-08.","recording_id":"one",'
               '"quote":"We met Priya on 2026-11-08."}]}')
        self.assertIn("We met Priya", summarization._validated_recap(raw, [recording]))


if __name__ == "__main__":
    unittest.main()
