from fastapi import APIRouter, HTTPException, Query
from src.services.database import (
    save_chat_message,
    get_chat_history,
    get_digest,
    get_transcripts_for_today,
)
from src.services.insights import answer_question
import uuid

router = APIRouter()

@router.post("/chat")
async def chat(body: dict):
    """'Ask Anything' — answers grounded in the user's own conversations.
    body: {"user_id": required, "message": required, "session_id": optional}"""
    user_id = body.get("user_id")
    message = (body.get("message") or "").strip()
    if not user_id:
        raise HTTPException(status_code=400, detail="user_id is required")
    if not message:
        raise HTTPException(status_code=400, detail="message is required")

    session_id = body.get("session_id") or str(uuid.uuid4())

    try:
        history = get_chat_history(user_id=user_id, session_id=session_id, limit=10)

        # save the user's message first so it appears in next-call history too
        save_chat_message(user_id=user_id, session_id=session_id, role="user", content=message)
        history = history + [{"role": "user", "content": message}]

        context = {
            "digest": (get_digest(user_id=user_id) or {}).get("summary"),
            "transcripts": get_transcripts_for_today(user_id=user_id),
            "history": history,
        }

        reply = answer_question(message, context)

        saved = save_chat_message(user_id=user_id, session_id=session_id, role="assistant", content=reply)

        return {
            "success": True,
            "session_id": session_id,
            "reply": reply,
            "message_id": saved["id"],
        }
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@router.get("/chat/history")
async def chat_history(user_id: str = Query(...), session_id: str = Query(...)):
    try:
        messages = get_chat_history(user_id=user_id, session_id=session_id, limit=50)
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
    return {"success": True, "messages": messages, "session_id": session_id}
