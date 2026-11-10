import asyncio
import unittest
from unittest.mock import patch

from fastapi import BackgroundTasks, HTTPException

from src.routes import transcripts
from src.routes import digest
from src.services import insights, summarization


class SpeakerNamesTest(unittest.TestCase):
    def setUp(self):
        self.transcript = {
            "id": "c39f01e5-68ab-47f2-bb19-7c7e6f4867df",
            "user_id": "test_user_1",
            "recorded_at": "2026-11-07T16:19:43+00:00",
            "text": "Hello there",
            "status": "completed",
            "speaker_labels": [{"speaker": "A", "text": "Hello there"}],
            "speaker_names": {},
        }

    def test_rename_invalidates_summary_and_recap(self):
        tasks = BackgroundTasks()
        with patch.object(transcripts, "get_transcript_by_id", return_value=self.transcript), \
             patch.object(transcripts, "update_transcript") as update, \
             patch.object(transcripts, "get_digest", return_value={"summary": "old"}), \
             patch.object(transcripts, "get_transcripts", return_value=[{**self.transcript, "speaker_names": {"A": "Priya"}}]), \
             patch.object(digest, "get_digest", return_value={"summary": "old"}), \
             patch.object(digest, "update_digest") as update_recap, \
             patch("src.services.summarization.summarize_structured_with_status", return_value=("Priya agreed.", {}, False)), \
             patch.object(transcripts, "get_profile_tz") as tz:
            from datetime import timezone
            tz.return_value = timezone.utc
            update.side_effect = lambda _, values: {**self.transcript, **values}
            result = asyncio.run(transcripts.patch_transcript(
                self.transcript["id"], {"speaker_names": {"A": "Priya"}}, tasks
            ))
            update_recap.assert_not_called()
            asyncio.run(tasks())
        self.assertEqual(result["transcript"]["speaker_names"], {"A": "Priya"})
        self.assertIsNone(update.call_args.args[1]["summary"])
        self.assertEqual(update_recap.call_args.args[:3], ("test_user_1", "2026-11-07", "Priya agreed."))

    def test_rejects_unknown_speaker(self):
        with patch.object(transcripts, "get_transcript_by_id", return_value=self.transcript):
            with self.assertRaises(HTTPException) as error:
                asyncio.run(transcripts.patch_transcript(
                    self.transcript["id"], {"speaker_names": {"B": "Priya"}}, BackgroundTasks()
                ))
        self.assertEqual(error.exception.status_code, 400)

    def test_prompts_use_saved_name(self):
        with patch.object(insights, "_call_llm", return_value="Meeting\n- Priya agreed.") as llm:
            insights.summarize_transcript("Hello there", self.transcript["speaker_labels"], {"A": "Priya"})
        self.assertIn("Priya: Hello there", llm.call_args.args[0])
        daily_prompt = summarization._build_prompt([{**self.transcript, "speaker_names": {"A": "Priya"}}])
        self.assertIn("Priya: Hello there", daily_prompt)


if __name__ == "__main__":
    unittest.main()
