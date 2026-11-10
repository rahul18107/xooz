import unittest
from unittest.mock import MagicMock, patch

from src.services import personal_facts


class PersonalFactsTest(unittest.TestCase):
    def test_question_type(self):
        self.assertTrue(personal_facts.is_personal_fact_question("What is my favorite food?"))
        self.assertFalse(personal_facts.is_personal_fact_question("When did I eat pizza?"))

    def test_index_rejects_quote_not_in_recording(self):
        db = MagicMock()
        response = '{"facts":[{"fact":"I like tea","quote":"I really like tea."}]}'
        with patch.object(personal_facts, "client", db), \
             patch.object(personal_facts, "_call_llm", return_value=response):
            personal_facts.index_personal_facts("user-1", "recording-1", "I really like coffee.")
        db.table.assert_not_called()

    def test_personal_fact_returns_source_recording(self):
        db = MagicMock()
        db.table.return_value.select.return_value.eq.return_value.limit.return_value.execute.return_value.data = [
            {"source_transcript_id": "recording-1", "fact": "I like coffee", "quote": "I really like coffee."},
        ]
        db.table.return_value.select.return_value.eq.return_value.eq.return_value.in_.return_value.execute.return_value.data = [
            {"id": "recording-1", "status": "completed", "recorded_at": "2026-11-08T10:00:00Z"},
        ]
        with patch.object(personal_facts, "client", db):
            rows = personal_facts.find_personal_fact_recordings("user-1", "What do I like?")
        self.assertEqual(rows[0]["id"], "recording-1")
        self.assertEqual(rows[0]["text"], "I really like coffee.")


if __name__ == "__main__":
    unittest.main()
