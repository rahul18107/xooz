import asyncio
import io
import unittest
from types import SimpleNamespace
from unittest.mock import patch

from fastapi import BackgroundTasks, UploadFile

from src.routes import audio, transcripts


class AudioUploadRetryTest(unittest.TestCase):
    def setUp(self):
        self.recording = {
            "id": "c39f01e5-68ab-47f2-bb19-7c7e6f4867df",
            "user_id": "test_user_1",
            "text": "Hello there",
            "status": "completed",
            "recorded_at": "2026-11-13T12:00:00+00:00",
            "audio_url": "https://example.com/audio.m4a",
        }

    def test_retry_returns_existing_recording_without_transcription(self):
        upload = UploadFile(filename="memo.m4a", file=io.BytesIO(b"audio"))
        with patch.object(audio, "_existing_upload", return_value=self.recording), \
             patch.object(audio, "transcribe") as transcribe:
            result = asyncio.run(audio.upload_audio(
                BackgroundTasks(), upload, "test_user_1", 5.0, "phone-id"
            ))
        self.assertEqual(result["transcript_id"], self.recording["id"])
        transcribe.assert_not_called()

    def test_new_upload_saves_client_id(self):
        upload = UploadFile(filename="memo.m4a", file=io.BytesIO(b"audio"))
        result = {"text": "Hello there", "speaker_labels": []}
        with patch.object(audio, "_existing_upload", return_value=None), \
             patch.object(audio, "get_profile", return_value={}), \
             patch.object(audio, "transcribe", return_value=result), \
             patch.object(audio, "save_transcript", return_value=self.recording) as save, \
             patch.object(audio, "update_transcript", return_value=self.recording), \
             patch.object(audio, "_store_audio", return_value=None):
            response = asyncio.run(audio.upload_audio(
                BackgroundTasks(), upload, "test_user_1", 5.0, "phone-id"
            ))
        self.assertEqual(response["transcript_id"], self.recording["id"])
        self.assertEqual(save.call_args.kwargs["extra"]["client_recording_id"], "phone-id")

    def test_delete_removes_the_stored_audio(self):
        removed = []
        storage = SimpleNamespace(remove=lambda paths: removed.extend(paths))
        with patch.object(transcripts, "get_transcript_by_id", return_value=self.recording), \
             patch.object(transcripts, "delete_transcript", return_value=self.recording), \
             patch.object(transcripts.supabase.storage, "from_", return_value=storage) as bucket:
            response = asyncio.run(transcripts.remove_transcript(self.recording["id"]))
        self.assertTrue(response["success"])
        bucket.assert_called_once_with("recordings")
        self.assertEqual(removed, [f"test_user_1/{self.recording['id']}.m4a"])

    def test_queued_upload_failure_does_not_create_failed_row(self):
        upload = UploadFile(filename="memo.m4a", file=io.BytesIO(b"audio"))
        with patch.object(audio, "_existing_upload", return_value=None), \
             patch.object(audio, "get_profile", return_value={}), \
             patch.object(audio, "transcribe", side_effect=RuntimeError("offline")), \
             patch.object(audio, "save_transcript") as save:
            with self.assertRaises(Exception):
                asyncio.run(audio.upload_audio(
                    BackgroundTasks(), upload, "test_user_1", 5.0, "phone-id"
                ))
        save.assert_not_called()


if __name__ == "__main__":
    unittest.main()
