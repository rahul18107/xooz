import asyncio
import unittest
from unittest.mock import patch

from fastapi import HTTPException

from src.routes import profile


class RecapProfileSettingsTest(unittest.TestCase):
    def test_valid_local_schedule_is_saved(self):
        payload = {"user_id": "user", "daily_recap_enabled": True,
                   "daily_recap_hour": 21, "timezone": "Asia/Kolkata"}
        with patch.object(profile, "get_or_create_profile"), \
             patch.object(profile, "update_profile", return_value=payload) as update:
            result = asyncio.run(profile.update_me(payload))
        self.assertTrue(result["profile"]["daily_recap_enabled"])
        update.assert_called_once_with("user", {
            "daily_recap_enabled": True, "daily_recap_hour": 21,
            "timezone": "Asia/Kolkata",
        })

    def test_invalid_hour_and_timezone_are_rejected(self):
        for field, value in (("daily_recap_hour", 24),
                             ("daily_recap_hour", True),
                             ("timezone", "Mars/Capital")):
            with self.subTest(field=field, value=value), self.assertRaises(HTTPException) as error:
                asyncio.run(profile.update_me({"user_id": "user", field: value}))
            self.assertEqual(error.exception.status_code, 400)


if __name__ == "__main__":
    unittest.main()
