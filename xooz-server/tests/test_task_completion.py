import asyncio
import unittest
from unittest.mock import patch

from src.routes import tasks


TASK_ID = "11111111-1111-4111-8111-111111111111"


class TaskCompletionTest(unittest.TestCase):
    def test_mark_done_sets_completion_time(self):
        task = {"id": TASK_ID, "status": "open"}
        with patch.object(tasks, "get_task_by_id", return_value=task), \
             patch.object(tasks, "update_task", return_value=task) as update:
            asyncio.run(tasks.patch_task(TASK_ID, {"status": "done"}))
        self.assertEqual(update.call_args.args[1]["status"], "done")
        self.assertIn("completed_at", update.call_args.args[1])

    def test_reopening_clears_completion_time(self):
        task = {"id": TASK_ID, "status": "done", "completed_at": "2026-11-09T10:00:00Z"}
        with patch.object(tasks, "get_task_by_id", return_value=task), \
             patch.object(tasks, "update_task", return_value=task) as update:
            asyncio.run(tasks.patch_task(TASK_ID, {"status": "open"}))
        self.assertIsNone(update.call_args.args[1]["completed_at"])

    def test_repeating_done_keeps_original_completion_time(self):
        task = {"id": TASK_ID, "status": "done", "completed_at": "2026-11-09T10:00:00Z"}
        with patch.object(tasks, "get_task_by_id", return_value=task), \
             patch.object(tasks, "update_task", return_value=task) as update:
            asyncio.run(tasks.patch_task(TASK_ID, {"status": "done"}))
        self.assertNotIn("completed_at", update.call_args.args[1])


if __name__ == "__main__":
    unittest.main()
