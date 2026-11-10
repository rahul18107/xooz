import asyncio
import unittest
from datetime import datetime, timezone, timedelta
from unittest.mock import MagicMock, patch

from src.routes import chat
from src.services import chat_retrieval
from src.services import insights
from src.services import database
from src.services.temporal_evidence import quote_supports_day, requested_day


class ChatRetrievalTest(unittest.TestCase):
    def test_first_chat_message_indexes_thread_without_renaming_on_follow_up(self):
        db = MagicMock()
        db.table.return_value.insert.return_value.execute.return_value.data = [{
            "id": "message-1", "created_at": "2026-11-10T10:00:00Z",
        }]
        with patch.object(database, "client", db):
            database.save_chat_message("user-1", "thread-1", "user", "Travel plans?")
        upsert = db.table.return_value.upsert
        self.assertEqual(upsert.call_args.args[0]["title"], "Travel plans?")
        self.assertTrue(upsert.call_args.kwargs["ignore_duplicates"])
        self.assertEqual(upsert.call_args.kwargs["on_conflict"], "user_id,session_id")
        title_update = db.table.return_value.update.call_args_list[0]
        self.assertEqual(title_update.args[0], {"title": "Travel plans?"})

    def test_new_chat_thread_is_created_only_on_explicit_request(self):
        with patch.object(chat, "create_chat_thread", return_value={
            "session_id": "chat-123", "title": "New chat",
        }) as create:
            response = asyncio.run(chat.new_chat_thread({"user_id": "user-1"}))
        self.assertEqual(response["thread"]["title"], "New chat")
        self.assertEqual(create.call_args.args[0], "user-1")
        self.assertTrue(create.call_args.args[1].startswith("chat-"))

    def test_chat_threads_list_is_scoped_to_user(self):
        with patch.object(chat, "get_chat_threads", return_value=[{
            "session_id": "thread-1", "title": "Trip planning",
        }]) as get:
            response = asyncio.run(chat.chat_threads("user-1", 20))
        get.assert_called_once_with("user-1", 20)
        self.assertEqual(response["threads"][0]["session_id"], "thread-1")

    def test_delete_chat_thread_reports_missing_thread(self):
        with patch.object(chat, "delete_chat_thread", return_value=False) as delete:
            with self.assertRaises(chat.HTTPException) as error:
                asyncio.run(chat.remove_chat_thread("thread-1", "user-1"))
        delete.assert_called_once_with("user-1", "thread-1")
        self.assertEqual(error.exception.status_code, 404)

    def test_relative_event_dates_use_recording_local_day(self):
        ist = timezone(timedelta(hours=5, minutes=30))
        self.assertEqual(requested_day("Plans tomorrow?", datetime(2026, 11, 10).date()).isoformat(),
                         "2026-11-11")
        self.assertTrue(quote_supports_day("Travel to Pune tomorrow.",
                        "2026-11-10T20:00:00Z", datetime(2026, 11, 12).date(), ist))
        self.assertFalse(quote_supports_day("Travel to Pune tomorrow.",
                         "2026-11-08T10:00:00Z", datetime(2026, 11, 11).date(), ist))
        self.assertTrue(quote_supports_day("Travel to Pune on November 11, 2026.",
                        "2026-11-01T10:00:00Z", datetime(2026, 11, 11).date(), ist))
        self.assertFalse(quote_supports_day("Travel to Pune next week.",
                         "2026-11-10T10:00:00Z", datetime(2026, 11, 11).date(), ist))

    def test_event_answer_rejects_old_plan_without_matching_date(self):
        context = {"transcripts": [{"id": "old", "text": "We travel to Pune tomorrow.",
                    "recorded_at": "2026-11-01T10:00:00Z"}], "tasks": [], "history": [],
                   "event_day": "2026-11-11", "user_tz": timezone.utc}
        response = ('{"claims":[{"text":"We travel to Pune tomorrow.",'
                    '"source":"recording-1","quote":"We travel to Pune tomorrow."}]}')
        with patch.object(insights, "_call_llm", return_value=response):
            answer = insights.answer_question("Do I have travel plans tomorrow?", context)
        self.assertIn("couldn't confirm", answer)

    def test_event_answer_accepts_prior_recording_with_explicit_target_date(self):
        context = {"transcripts": [{"id": "prior", "text": "We travel to Pune on 2026-11-11.",
                    "recorded_at": "2026-11-08T10:00:00Z"}], "tasks": [], "history": [],
                   "event_day": "2026-11-11", "user_tz": timezone.utc}
        response = ('{"claims":[{"text":"We travel to Pune on 2026-11-11.",'
                    '"source":"recording-1","quote":"We travel to Pune on 2026-11-11."}]}')
        with patch.object(insights, "_call_llm", return_value=response):
            answer = insights.answer_question("Do I have travel plans tomorrow?", context)
        self.assertIn("Pune", answer)

    def test_old_relative_word_cannot_be_repeated_as_current_tomorrow(self):
        context = {"transcripts": [{"id": "yesterday", "text": "Travel to Pune tomorrow.",
                    "recorded_at": "2026-11-09T10:00:00Z"}], "tasks": [], "history": [],
                   "event_day": "2026-11-10", "local_today": "2026-11-10",
                   "user_tz": timezone.utc}
        response = ('{"claims":[{"text":"Travel to Pune tomorrow.",'
                    '"source":"recording-1","quote":"Travel to Pune tomorrow."}]}')
        with patch.object(insights, "_call_llm", return_value=response):
            answer = insights.answer_question("Any travel plans today?", context)
        self.assertIn("couldn't confirm", answer)

    def test_chat_searches_all_dates_for_scheduled_event(self):
        older = {"id": "prior", "text": "Travel to Pune on 2026-11-11.",
                 "recorded_at": "2026-11-08T10:00:00Z"}
        with patch.object(chat, "get_chat_history", return_value=[]), \
             patch.object(chat, "save_chat_message", side_effect=[{"id": "u"}, {"id": "a"}]), \
             patch.object(chat, "today_local_date", return_value="2026-11-10"), \
             patch.object(chat, "get_profile_tz", return_value=timezone.utc), \
             patch.object(chat, "find_recordings", return_value=[older]) as find, \
             patch.object(chat, "get_tasks", return_value=[]) as tasks, \
             patch.object(chat, "answer_question", return_value="Travel to Pune.") as answer:
            asyncio.run(chat.chat({"user_id": "test", "message": "Any travel plans tomorrow?"}))
        find.assert_called_once_with("test", "Any travel plans ?")
        self.assertEqual(answer.call_args.args[1]["event_day"], "2026-11-11")
        self.assertEqual(tasks.call_args.kwargs["due_date"], "2026-11-11")

    def test_completion_day_keeps_completion_time_filter(self):
        with patch.object(chat, "get_chat_history", return_value=[]), \
             patch.object(chat, "save_chat_message", side_effect=[{"id": "u"}, {"id": "a"}]), \
             patch.object(chat, "today_local_date", return_value="2026-11-10"), \
             patch.object(chat, "day_bounds_utc", return_value=("start", "end")) as bounds, \
             patch.object(chat, "find_recordings", return_value=[]), \
             patch.object(chat, "get_tasks", return_value=[]), \
             patch.object(chat, "answer_question", return_value="Unknown") as answer:
            asyncio.run(chat.chat({"user_id": "test", "message": "What tasks did I finish yesterday?"}))
        self.assertIsNone(answer.call_args.args[1]["event_day"])
        bounds.assert_called_once_with("test", "2026-11-09")

    def test_due_date_filters_task_evidence_for_event_day(self):
        context = {"transcripts": [], "history": [], "event_day": "2026-11-11",
                   "tasks": [{"title": "Travel to Pune", "status": "open", "due_date": "2026-11-03"}]}
        with patch.object(insights, "_call_llm") as llm:
            answer = insights.answer_question("Any travel plans tomorrow?", context)
        self.assertIn("couldn't confirm", answer)
        llm.assert_not_called()

    def test_follow_up_rewrites_search_but_answers_original_question(self):
        history = [{"role": "user", "content": "What did Priya say about the train?"},
                   {"role": "assistant", "content": "Priya discussed the train."}]
        with patch.object(chat, "get_chat_history", return_value=history), \
             patch.object(chat, "save_chat_message", side_effect=[{"id": "u"}, {"id": "a"}]), \
             patch.object(chat, "find_recordings", return_value=[]) as find, \
             patch.object(chat, "get_tasks", return_value=[]), \
             patch.object(chat, "answer_question", return_value="No evidence") as answer, \
             patch.object(chat_retrieval, "_call_llm", return_value='{"query":"What did Priya say about the train booking?"}'):
            asyncio.run(chat.chat({"user_id": "test", "message": "What about the booking?"}))
        find.assert_called_once_with("test", "What did Priya say about the train booking?")
        self.assertEqual(answer.call_args.args[0], "What about the booking?")

    def test_self_contained_question_skips_rewrite(self):
        with patch.object(chat_retrieval, "_call_llm") as llm:
            query = chat_retrieval.search_question(
                "What did Priya say about Mumbai?",
                [{"role": "user", "content": "Where is the train?"}],
            )
        self.assertEqual(query, "What did Priya say about Mumbai?")
        llm.assert_not_called()

    def test_follow_up_rewrite_failure_uses_original_question(self):
        with patch.object(chat_retrieval, "_call_llm", side_effect=RuntimeError("offline")):
            query = chat_retrieval.search_question(
                "When was that?", [{"role": "user", "content": "When did Priya book the train?"}],
            )
        self.assertEqual(query, "When was that?")

    def test_yesterday_uses_local_day_and_excludes_other_days(self):
        yesterday = (datetime.now(timezone(timedelta(hours=5, minutes=30))).date()
                     - timedelta(days=1)).isoformat()
        rows = [{"id": "match", "status": "completed", "text": "Priya approved the train.",
                 "recorded_at": "2026-11-08T18:00:00+00:00"},
                {"id": "pending", "status": "processing", "text": "Priya discussed the train."}]
        with patch.object(chat_retrieval, "get_profile_tz", return_value=timezone(timedelta(hours=5, minutes=30))), \
             patch.object(chat_retrieval, "get_transcripts", return_value=rows) as get:
            result = chat_retrieval.find_recordings("user-1", "What did Priya say yesterday?")
        self.assertEqual(get.call_args.kwargs["date"], yesterday)
        self.assertEqual([row["id"] for row in result], ["match"])

    def test_last_time_prefers_newest_matching_recording(self):
        rows = [{"id": "new", "status": "completed", "text": "Priya booked a train.",
                 "recorded_at": "2026-11-09T10:00:00+00:00"},
                {"id": "unrelated", "status": "completed", "text": "Hotel options.",
                 "recorded_at": "2026-11-08T10:00:00+00:00"},
                {"id": "old", "status": "completed", "text": "Priya checked train times.",
                 "recorded_at": "2026-11-07T10:00:00+00:00"}]
        with patch.object(chat_retrieval, "get_transcripts", return_value=rows):
            result = chat_retrieval.find_recordings("user-1", "When did I last talk about Priya?", limit=1)
        self.assertEqual([row["id"] for row in result], ["new"])

    def test_ranks_older_relevant_recording(self):
        self.assertEqual(chat_retrieval._keyword_query("What did Priya say about Mumbai?"), "priya | mumbai")

    def test_chat_excludes_incomplete_and_returns_sources(self):
        recordings = [
            {"id": "pending", "status": "processing", "text": "Priya Mumbai"},
            {"id": "old", "status": "completed", "text": "Priya Mumbai", "recorded_at": "2026-11-01"},
        ]
        def answer_with_source(message, context, used_source_ids):
            used_source_ids.append("old")
            return "Priya discussed Mumbai. [Recording 1]"

        with patch.object(chat, "get_chat_history", return_value=[]), \
             patch.object(chat, "save_chat_message", side_effect=[{"id": "u"}, {"id": "a"}]) as save, \
             patch.object(chat, "find_recordings", return_value=[recordings[1]]), \
             patch.object(chat, "get_tasks", return_value=[]), \
             patch.object(chat, "answer_question", side_effect=answer_with_source) as answer:
            result = asyncio.run(chat.chat({"user_id": "test", "message": "Priya Mumbai"}))
        self.assertEqual([source["id"] for source in result["sources"]], ["old"])
        self.assertEqual([r["id"] for r in answer.call_args.args[1]["transcripts"]], ["old"])
        self.assertEqual(save.call_args.kwargs["source_ids"], ["old"])

    def test_answer_tracks_only_validated_recording_sources(self):
        context = {"transcripts": [
            {"id": "unused", "text": "We discussed hotel options."},
            {"id": "used", "text": "Priya approved the Pune train booking."},
        ], "tasks": [], "history": []}
        response = ('{"claims":[{"text":"Priya approved the Pune train booking.",'
                    '"source":"recording-2","quote":"Priya approved the Pune train booking."}]}')
        used_sources = []
        with patch.object(insights, "_call_llm", return_value=response):
            answer = insights.answer_question("What did Priya approve?", context, used_sources)
        self.assertEqual(used_sources, ["used"])
        self.assertEqual(answer, "Priya approved the Pune train booking.")

    def test_multiple_claims_keep_sources_without_inline_recording_labels(self):
        context = {"transcripts": [
            {"id": "first", "text": "Priya booked the Pune train."},
            {"id": "second", "text": "Rahul reserved the hotel."},
        ], "tasks": [], "history": []}
        response = ('{"claims":['
                    '{"text":"Priya booked the Pune train.","source":"recording-1",'
                    '"quote":"Priya booked the Pune train."},'
                    '{"text":"Rahul reserved the hotel.","source":"recording-2",'
                    '"quote":"Rahul reserved the hotel."}]}')
        used_sources = []
        with patch.object(insights, "_call_llm", return_value=response):
            answer = insights.answer_question("What did they arrange?", context, used_sources)
        self.assertEqual(answer, "Priya booked the Pune train. Rahul reserved the hotel.")
        self.assertEqual(used_sources, ["first", "second"])

    def test_chat_loads_completed_tasks_for_finished_question(self):
        with patch.object(chat, "get_chat_history", return_value=[]), \
             patch.object(chat, "save_chat_message", side_effect=[{"id": "u"}, {"id": "a"}]), \
             patch.object(chat, "find_recordings", return_value=[]), \
             patch.object(chat, "get_tasks", return_value=[]) as tasks, \
             patch.object(chat, "answer_question", return_value="No completed tasks found."):
            asyncio.run(chat.chat({"user_id": "test", "message": "What tasks did I finish?"}))
        self.assertEqual(tasks.call_args.kwargs["status"], "done")

    def test_retry_returns_saved_reply_without_reanswering(self):
        turn = [
            {"id": "u", "role": "user", "content": "What did Priya say?"},
            {"id": "a", "role": "assistant", "content": "Priya approved it.",
             "source_ids": ["recording-1"]},
        ]
        with patch.object(chat, "get_chat_turn", return_value=turn), \
             patch.object(chat, "get_chat_history") as history, \
             patch.object(chat, "save_chat_message") as save, \
             patch.object(chat, "answer_question") as answer:
            result = asyncio.run(chat.chat({"user_id": "test", "session_id": "main",
                                            "client_request_id": "request-1",
                                            "message": "What did Priya say?"}))
        self.assertEqual(result["reply"], "Priya approved it.")
        self.assertEqual(result["sources"], [{"id": "recording-1"}])
        history.assert_not_called()
        save.assert_not_called()
        answer.assert_not_called()

    def test_retry_rejects_reused_request_id_with_other_message(self):
        with patch.object(chat, "get_chat_turn", return_value=[
            {"id": "u", "role": "user", "content": "First question"}
        ]):
            with self.assertRaises(chat.HTTPException) as error:
                asyncio.run(chat.chat({"user_id": "test", "session_id": "main",
                                        "client_request_id": "request-1",
                                        "message": "Different question"}))
        self.assertEqual(error.exception.status_code, 409)

    def test_task_status_selection(self):
        self.assertEqual(insights.task_status_for_question("What tasks did I finish?"), "done")
        self.assertEqual(insights.task_status_for_question("What tasks are snoozed?"), "snoozed")
        self.assertEqual(insights.task_status_for_question("What tasks are left?"), "open")
        self.assertIsNone(insights.task_status_for_question("Show all my tasks"))

    def test_completed_task_answer_requires_done_task_evidence(self):
        context = {"transcripts": [{"id": "recording", "text": "I will book the train by Friday."}],
                   "tasks": [], "history": []}
        claim = ('{"claims":[{"text":"I finished booking the train.",'
                 '"source":"recording-1","quote":"I will book the train by Friday."}]}')
        with patch.object(insights, "_call_llm", return_value=claim):
            answer = insights.answer_question("What tasks did I finish?", context)
        self.assertIn("don't have enough recorded information", answer)

    def test_done_task_status_is_in_evidence(self):
        context = {"transcripts": [], "tasks": [
            {"title": "Book the train", "status": "done", "due_date": "2026-11-10"}
        ], "history": []}
        response = ('{"claims":[{"text":"Book the train is done.","source":"task-1",'
                    '"quote":"Book the train (status: done; due: 2026-11-10)"}]}')
        with patch.object(insights, "_call_llm", return_value=response):
            answer = insights.answer_question("What tasks did I finish?", context)
        self.assertIn("Book the train is done.", answer)

    def test_does_not_invent_task_completion_date(self):
        context = {"transcripts": [], "tasks": [
            {"title": "Book the train", "status": "done", "due_date": "2026-11-10"}
        ], "history": []}
        with patch.object(insights, "_call_llm") as llm:
            answer = insights.answer_question("What tasks did I finish yesterday?", context)
        self.assertIn("can't confirm when", answer)
        llm.assert_not_called()

    def test_completion_question_uses_saved_completion_time(self):
        context = {"transcripts": [], "tasks": [{
            "title": "Book the train", "status": "done", "due_date": None,
            "completed_at": "2026-11-09T10:00:00+00:00",
        }], "history": []}
        response = ('{"claims":[{"text":"Book the train was completed at 2026-11-09T10:00:00+00:00.",'
                    '"source":"task-1","quote":"Book the train (status: done; due: not specified) '
                    '(completed at: 2026-11-09T10:00:00+00:00)"}]}')
        with patch.object(insights, "_call_llm", return_value=response):
            answer = insights.answer_question("When did I finish booking the train?", context)
        self.assertIn("completed at", answer)

    def test_yesterday_completed_task_query_uses_local_day_bounds(self):
        with patch.object(chat, "today_local_date", return_value="2026-11-09"), \
             patch.object(chat, "day_bounds_utc", return_value=("start", "end")) as bounds, \
             patch.object(chat, "get_tasks", return_value=[]) as tasks:
            result = chat._task_context("user-1", "What tasks did I finish yesterday?")
        self.assertEqual(result, [])
        bounds.assert_called_once_with("user-1", "2026-11-08")
        self.assertEqual(tasks.call_args.kwargs["completed_start"], "start")
        self.assertEqual(tasks.call_args.kwargs["completed_end"], "end")

    def test_follow_up_task_intent_uses_resolved_question(self):
        history = [{"role": "user", "content": "What tasks did I finish?"}]
        with patch.object(chat, "get_chat_history", return_value=history), \
             patch.object(chat, "save_chat_message", side_effect=[{"id": "u"}, {"id": "a"}]), \
             patch.object(chat, "search_question", return_value="What tasks did I finish yesterday?"), \
             patch.object(chat, "find_recordings", return_value=[]), \
             patch.object(chat, "today_local_date", return_value="2026-11-09"), \
             patch.object(chat, "day_bounds_utc", return_value=("start", "end")), \
             patch.object(chat, "get_tasks", return_value=[]) as tasks, \
             patch.object(chat, "answer_question", return_value="Unknown"):
            asyncio.run(chat.chat({"user_id": "test", "message": "What about yesterday?"}))
        self.assertEqual(tasks.call_args.kwargs["status"], "done")

    def test_hybrid_search_keeps_database_rank_and_user_filter(self):
        db = MagicMock()
        db.rpc.return_value.execute.return_value.data = [
            {"transcript_id": "older"}, {"transcript_id": "newer"},
        ]
        db.table.return_value.select.return_value.eq.return_value.eq.return_value.in_.return_value.execute.return_value.data = [
            {"id": "newer", "text": "new"}, {"id": "older", "text": "old"},
        ]
        with patch.object(chat_retrieval, "client", db), \
             patch.object(chat_retrieval, "_embed", return_value=[0.1] * 768):
            rows = chat_retrieval.find_recordings("user-1", "budget discussion")
        self.assertEqual([row["id"] for row in rows], ["older", "newer"])
        self.assertEqual(db.rpc.call_args.args[1]["p_user_id"], "user-1")

    def test_embedding_failure_uses_keyword_search(self):
        db = MagicMock()
        db.rpc.return_value.execute.return_value.data = []
        with patch.object(chat_retrieval, "client", db), \
             patch.object(chat_retrieval, "_embed", side_effect=RuntimeError("offline")):
            self.assertEqual(chat_retrieval.find_recordings("user-1", "train booking"), [])
        self.assertIsNone(db.rpc.call_args.args[1]["p_embedding"])

    def test_empty_indexed_search_retries_once_with_alternative_wording(self):
        db = MagicMock()
        db.rpc.return_value.execute.return_value.data = []
        with patch.object(chat_retrieval, "client", db), \
             patch.object(chat_retrieval, "_embed", return_value=[0.1] * 768), \
             patch.object(chat_retrieval, "_call_llm", return_value='{"query":"Where did Priya reserve the train?"}') as llm:
            self.assertEqual(chat_retrieval.find_recordings("user-1", "Where did Priya book the train?"), [])
        self.assertEqual(llm.call_count, 1)
        queries = [call.args[1]["p_query"] for call in db.rpc.call_args_list]
        self.assertIn("priya | reserve | the | train", queries)

    def test_alternative_query_cannot_drop_person_name(self):
        with patch.object(chat_retrieval, "_call_llm", return_value='{"query":"Where did they reserve the train?"}'):
            self.assertIsNone(chat_retrieval._alternative_query("Where did Priya book the train?"))

    def test_date_scoped_question_does_not_retry_outside_day(self):
        with patch.object(chat_retrieval, "get_profile_tz", return_value=timezone.utc), \
             patch.object(chat_retrieval, "get_transcripts", return_value=[]), \
             patch.object(chat_retrieval, "_call_llm") as llm:
            self.assertEqual(chat_retrieval.find_recordings("user-1", "What did Priya say yesterday?"), [])
        llm.assert_not_called()

    def test_embedding_response_dimensions(self):
        response = MagicMock()
        response.json.return_value = {"success": True, "result": {"data": [[0.1] * 768]}}
        with patch.object(chat_retrieval, "CLOUDFLARE_ACCOUNT_ID", "account"), \
             patch.object(chat_retrieval, "CLOUDFLARE_API_TOKEN", "token"), \
             patch.object(chat_retrieval.httpx, "post", return_value=response) as post:
            vector = chat_retrieval._embed("train booking")
        self.assertEqual(len(vector), 768)
        self.assertEqual(post.call_args.kwargs["json"], {"text": ["train booking"]})

    def test_excerpt_reaches_match_near_end(self):
        text = "unrelated " * 800 + "Priya confirmed the train booking"
        excerpt = chat_retrieval._evidence_excerpt(text, "priya | train")
        self.assertIn("Priya confirmed", excerpt)
        self.assertLessEqual(len(excerpt), 3400)

    def test_passages_cover_end_of_long_recording(self):
        text = "first discussion " * 200 + "Priya approved the Pune train booking."
        passages = chat_retrieval._passages(text)
        self.assertGreater(len(passages), 1)
        self.assertIn("Priya approved the Pune train booking.", passages[-1])
        self.assertTrue(all(len(passage) <= 1200 for passage in passages))

    def test_passage_search_returns_relevant_excerpt(self):
        db = MagicMock()
        db.rpc.return_value.execute.return_value.data = [
            {"transcript_id": "old", "passage_index": 2,
             "text": "Priya approved the Pune train booking."},
        ]
        db.table.return_value.select.return_value.eq.return_value.eq.return_value.in_.return_value.execute.return_value.data = [
            {"id": "old", "text": "unrelated " * 500 + "Priya approved the Pune train booking."},
        ]
        with patch.object(chat_retrieval, "client", db), \
             patch.object(chat_retrieval, "_embed", return_value=[0.1] * 768):
            rows = chat_retrieval.find_recordings("user-1", "Pune booking")
        self.assertEqual(rows[0]["text"], "Priya approved the Pune train booking.")

    def test_answer_rejects_quote_not_in_recording(self):
        context = {"transcripts": [{"text": "Priya approved the Pune train booking."}],
                   "tasks": [], "history": []}
        fabricated = '{"claims":[{"text":"Priya approved a flight.","source":"recording-1","quote":"Priya approved a flight."}]}'
        with patch.object(insights, "_call_llm", return_value=fabricated):
            answer = insights.answer_question("What did Priya approve?", context)
        self.assertIn("don't have enough recorded information", answer)


if __name__ == "__main__":
    unittest.main()
