from fastapi import APIRouter, HTTPException, Query
from src.services.database import (
    save_chat_message,
    get_chat_turn,
    get_chat_history,
    get_chat_threads,
    create_chat_thread,
    delete_chat_thread,
    get_tasks,
    today_bounds_utc,
    day_bounds_utc,
    get_profile_tz,
    today_local_date,
)
from src.services.insights import answer_question, task_status_for_question, asks_prior_open_tasks
from src.services.chat_retrieval import find_recordings, search_question
from src.services.personal_facts import find_personal_fact_recordings
from src.services.temporal_evidence import requested_day, asks_about_recording_day
from datetime import date, datetime, timedelta
import re
import uuid

router = APIRouter()


@router.get("/chat/threads")
async def chat_threads(user_id: str = Query(...), limit: int = Query(50, ge=1, le=100)):
    try:
        return {"success": True, "threads": get_chat_threads(user_id, limit)}
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc))


@router.post("/chat/threads")
async def new_chat_thread(body: dict):
    user_id = body.get("user_id")
    if not isinstance(user_id, str) or not user_id.strip():
        raise HTTPException(status_code=400, detail="user_id is required")
    try:
        return {"success": True, "thread": create_chat_thread(user_id, f"chat-{uuid.uuid4()}")}
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc))


@router.delete("/chat/threads/{session_id}")
async def remove_chat_thread(session_id: str, user_id: str = Query(...)):
    try:
        if not delete_chat_thread(user_id, session_id):
            raise HTTPException(status_code=404, detail="Chat not found")
        return {"success": True}
    except HTTPException:
        raise
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc))


def _task_context(user_id: str, message: str, event_day: str | None = None) -> list[dict]:
    status = task_status_for_question(message)
    kwargs = {"user_id": user_id, "status": status, "limit": 50}
    if asks_prior_open_tasks(message):
        kwargs["created_before"] = today_bounds_utc(user_id)[0]
        kwargs["limit"] = 200
    elif event_day:
        kwargs["due_date"] = event_day
    if status == "done":
        lower = message.lower()
        if re.search(r"\btoday\b|\byesterday\b", lower):
            day = date.fromisoformat(today_local_date(user_id))
            if re.search(r"\byesterday\b", lower):
                day -= timedelta(days=1)
            kwargs["completed_start"], kwargs["completed_end"] = day_bounds_utc(
                user_id, day.isoformat())
    tasks = get_tasks(**kwargs)
    if any(task.get("completed_at") for task in tasks):
        tz = get_profile_tz(user_id)
        for task in tasks:
            if not task.get("completed_at"):
                continue
            completed = datetime.fromisoformat(task["completed_at"].replace("Z", "+00:00"))
            task["completed_at_local"] = completed.astimezone(tz).isoformat()
    return tasks

@router.get("/chat/history")
async def chat_history(
    user_id: str = Query(...),
    session_id: str = Query(...),
    limit: int = Query(100, ge=1, le=200),
):
    """Load previous messages of one chat session, oldest first."""
    try:
        messages = get_chat_history(
            user_id=user_id, session_id=session_id, limit=limit
        )
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
    return {"success": True, "messages": messages}

@router.post("/chat")
async def chat(body: dict):
    """'Ask Anything' — answers grounded in the user's own conversations.
    body: {"user_id": required, "message": required, "session_id": optional}"""
    user_id = body.get("user_id")
    message = (body.get("message") or "").strip()
    request_id = body.get("client_request_id")
    if not user_id:
        raise HTTPException(status_code=400, detail="user_id is required")
    if not message:
        raise HTTPException(status_code=400, detail="message is required")
    if request_id is not None and (not isinstance(request_id, str) or
                                   not 1 <= len(request_id) <= 100):
        raise HTTPException(status_code=400, detail="Invalid client_request_id")

    session_id = body.get("session_id") or str(uuid.uuid4())

    try:
        turn = get_chat_turn(user_id, session_id, request_id) if request_id else []
        previous_user = next((item for item in turn if item.get("role") == "user"), None)
        previous_reply = next((item for item in turn if item.get("role") == "assistant"), None)
        if previous_user and previous_user.get("content") != message:
            raise HTTPException(status_code=409, detail="Request ID already used for another message")
        if previous_reply:
            source_ids = previous_reply.get("source_ids") or []
            return {"success": True, "session_id": session_id,
                    "reply": previous_reply["content"], "message_id": previous_reply["id"],
                    "sources": [{"id": source_id} for source_id in source_ids]}
        history = get_chat_history(user_id=user_id, session_id=session_id, limit=10)

        if not previous_user:
            save_chat_message(user_id=user_id, session_id=session_id, role="user",
                              content=message, client_request_id=request_id)
            history = history + [{"role": "user", "content": message}]

        query = search_question(message, history[:-1])
        prior_open_tasks = asks_prior_open_tasks(query)
        target_day = requested_day(query, date.fromisoformat(today_local_date(user_id)))
        event_day = (target_day if target_day and not asks_about_recording_day(query)
                     and task_status_for_question(query) != "done" else None)
        # Event-day questions may be answered by a recording made before that day.
        # Search all dates, then let quote-level validation decide what applies.
        retrieval_query = re.sub(r"\b(?:yesterday|today|tomorrow|tonight)\b", "", query,
                                 flags=re.I).strip() if event_day else query
        matches = [] if prior_open_tasks else find_recordings(user_id, retrieval_query)
        try:
            fact_matches = [] if target_day or prior_open_tasks else find_personal_fact_recordings(user_id, query)
            matches = (fact_matches + [row for row in matches
                                       if row["id"] not in {fact["id"] for fact in fact_matches}])[:5]
        except Exception as exc:
            print(f"personal fact search unavailable: {exc}")
        context = {
            "transcripts": matches,
            "tasks": _task_context(user_id, query, event_day.isoformat() if event_day else None),
            "prior_open_tasks": prior_open_tasks,
            "history": history,
            "resolved_question": query,
            "event_day": event_day.isoformat() if event_day else None,
            "local_today": today_local_date(user_id) if event_day else None,
            "user_tz": get_profile_tz(user_id) if event_day else None,
        }

        used_source_ids = []
        reply = answer_question(message, context, used_source_ids=used_source_ids)

        saved = save_chat_message(user_id=user_id, session_id=session_id, role="assistant",
                                  content=reply, source_ids=used_source_ids,
                                  client_request_id=request_id)

        return {
            "success": True,
            "session_id": session_id,
            "reply": reply,
            "message_id": saved["id"],
            "sources": [{"id": r["id"], "recorded_at": r.get("recorded_at"), "title": r.get("title")}
                        for source_id in used_source_ids for r in matches if r["id"] == source_id],
        }
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
