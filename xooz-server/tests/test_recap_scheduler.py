import unittest
from datetime import datetime, timezone
from unittest.mock import patch

from src.services import recap_scheduler


class RecapSchedulerTest(unittest.TestCase):
    def test_local_evening_uses_current_day(self):
        profile = {"timezone": "Asia/Kolkata", "daily_recap_hour": 21}
        self.assertIsNone(recap_scheduler.due_recap_date(
            profile, datetime(2026, 11, 9, 14, 0, tzinfo=timezone.utc)))
        self.assertEqual(recap_scheduler.due_recap_date(
            profile, datetime(2026, 11, 9, 15, 30, tzinfo=timezone.utc)), "2026-11-09")

    def test_local_morning_uses_previous_day(self):
        profile = {"timezone": "Asia/Kolkata", "daily_recap_hour": 9}
        self.assertEqual(recap_scheduler.due_recap_date(
            profile, datetime(2026, 11, 9, 4, 0, tzinfo=timezone.utc)), "2026-11-08")

    def test_silent_day_releases_claim_without_generating(self):
        profile = {"id": "user", "timezone": "Asia/Kolkata", "daily_recap_hour": 21}
        with patch.object(recap_scheduler, "get_scheduled_recap_profiles", return_value=[profile]), \
             patch.object(recap_scheduler, "get_day_transcripts", return_value=[
                 {"id": "silent", "status": "completed", "text": " "}]), \
             patch.object(recap_scheduler, "_claim", return_value="token") as claim, \
             patch.object(recap_scheduler, "_finish") as finish, \
             patch("src.routes.digest._current_digest") as generate:
            recap_scheduler.run_scheduled_recaps_once(
                datetime(2026, 11, 9, 16, 0, tzinfo=timezone.utc))
        claim.assert_called_once()
        finish.assert_called_once_with("user", "2026-11-09", "token", False)
        generate.assert_not_called()

    def test_successful_scheduled_recap_finishes_claim(self):
        profile = {"id": "user", "timezone": "Asia/Kolkata", "daily_recap_hour": 21}
        recording = {"id": "one", "status": "completed", "text": "Discussed train travel"}
        with patch.object(recap_scheduler, "get_scheduled_recap_profiles", return_value=[profile]), \
             patch.object(recap_scheduler, "get_day_transcripts", return_value=[recording]), \
             patch.object(recap_scheduler, "_claim", return_value="token") as claim, \
             patch.object(recap_scheduler, "_finish") as finish, \
             patch("src.routes.digest._current_digest", return_value=(
                 {"summary": "Train travel", "source_fingerprint": "ready"}, False)):
            recap_scheduler.run_scheduled_recaps_once(
                datetime(2026, 11, 9, 16, 0, tzinfo=timezone.utc))
        claim.assert_called_once_with("user", "2026-11-09")
        finish.assert_called_once_with("user", "2026-11-09", "token", True)

    def test_failed_generation_releases_claim_for_retry(self):
        profile = {"id": "user", "timezone": "Asia/Kolkata", "daily_recap_hour": 21}
        recording = {"id": "one", "status": "completed", "text": "Discussed train travel"}
        with patch.object(recap_scheduler, "get_scheduled_recap_profiles", return_value=[profile]), \
             patch.object(recap_scheduler, "get_day_transcripts", return_value=[recording]), \
             patch.object(recap_scheduler, "_claim", return_value="token"), \
             patch.object(recap_scheduler, "_finish") as finish, \
             patch("src.routes.digest._current_digest", return_value=(
                 {"summary": "", "source_fingerprint": "fallback:failed"}, False)):
            recap_scheduler.run_scheduled_recaps_once(
                datetime(2026, 11, 9, 16, 0, tzinfo=timezone.utc))
        finish.assert_called_once_with("user", "2026-11-09", "token", False)


if __name__ == "__main__":
    unittest.main()
