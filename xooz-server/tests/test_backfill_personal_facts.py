import unittest
from unittest.mock import MagicMock, patch

from src import backfill_personal_facts


class BackfillPersonalFactsTest(unittest.TestCase):
    def test_dry_run_is_user_scoped_and_calls_no_llm(self):
        db = MagicMock()
        db.table.return_value.select.return_value.eq.return_value.eq.return_value.order.return_value.range.return_value.execute.return_value.data = [
            {"id": "recording-1", "text": "I like coffee."},
        ]
        db.table.return_value.select.return_value.eq.return_value.eq.return_value.limit.return_value.execute.return_value.data = []
        with patch.object(backfill_personal_facts, "client", db), \
             patch.object(backfill_personal_facts, "index_personal_facts") as index:
            checked, indexed = backfill_personal_facts.backfill("user-1", 1, dry_run=True)
        self.assertEqual((checked, indexed), (1, 0))
        index.assert_not_called()
        db.table.return_value.select.return_value.eq.assert_called_with("user_id", "user-1")


if __name__ == "__main__":
    unittest.main()
