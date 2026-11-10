from fastapi import APIRouter, HTTPException, Query
from src.services.database import (
    day_bounds_utc,
    get_tasks,
    get_task_by_id,
    get_transcripts,
    get_transcript_by_id,
    update_task,
    delete_task,
)
from src.services.insights import task_plan, task_briefs
import uuid
from datetime import datetime, timezone

def _validate_uuid(value: str) -> str:
    try:
        return str(uuid.UUID(value))
    except ValueError:
        raise HTTPException(status_code=404, detail="Task not found")

router = APIRouter()

ALLOWED_STATUSES = {"open", "done", "snoozed"}

@router.get("/tasks")
async def list_tasks(
    user_id: str = Query(...),
    status: str = None,
    date: str = None,
    limit: int = Query(100, ge=1, le=200),
):
    """Tasks extracted from conversations. status = open | done | snoozed."""
    if status and status not in ALLOWED_STATUSES:
        raise HTTPException(status_code=400, detail="status must be one of: open, done, snoozed")
    try:
        tasks = get_tasks(user_id=user_id, status=status, limit=limit)
        if date:
            start_iso, end_iso = day_bounds_utc(user_id, date)
            transcripts = get_transcripts(user_id=user_id, date=date, limit=200)
            transcript_ids = {t["id"] for t in transcripts}
            tasks = [
                task for task in tasks
                if (task.get("source_transcript_id") in transcript_ids)
                or (task.get("created_at") and start_iso <= task["created_at"] < end_iso)
            ]
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
    return {"success": True, "tasks": tasks, "count": len(tasks)}

@router.patch("/tasks/{task_id}")
async def patch_task(task_id: str, body: dict):
    """Update a task: {"status": "done"} or {"status": "snoozed", "due_date": "YYYY-MM-DD"}"""
    updates = {}
    if "status" in body:
        if body["status"] not in ALLOWED_STATUSES:
            raise HTTPException(status_code=400, detail="status must be one of: open, done, snoozed")
        updates["status"] = body["status"]
    if "due_date" in body:
        updates["due_date"] = body["due_date"]

    task = get_task_by_id(_validate_uuid(task_id))
    if not task:
        raise HTTPException(status_code=404, detail="Task not found")

    if "status" in updates and updates["status"] != task["status"]:
        updates["completed_at"] = (datetime.now(timezone.utc).isoformat()
                                   if updates["status"] == "done" else None)

    updated = update_task(task_id, updates or {"status": task["status"]})
    return {"success": True, "task": updated}

@router.delete("/tasks/{task_id}")
async def remove_task(task_id: str, user_id: str = Query(...)):
    if not delete_task(_validate_uuid(task_id), user_id):
        raise HTTPException(status_code=404, detail="Task not found")
    return {"success": True}

@router.get("/tasks/briefs")
async def task_briefs_endpoint(
    user_id: str = Query(...),
    transcript_id: str = Query(...),
):
    """2-line AI summaries for all tasks extracted from ONE conversation."""
    try:
        tasks = get_tasks(user_id=user_id, limit=200)
        cluster = [
            t for t in tasks
            if t.get("source_transcript_id") == transcript_id
        ]
        if not cluster:
            return {"success": True, "briefs": {}}
        transcript = get_transcript_by_id(transcript_id)
        text = (transcript or {}).get("text") or ""
        briefs = task_briefs(cluster, text)
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
    return {"success": True, "briefs": briefs}

@router.get("/tasks/{task_id}/plan")
async def get_task_plan(task_id: str):
    """AI-generated action steps for one task, grounded in the conversation it came from."""
    task = get_task_by_id(_validate_uuid(task_id))
    if not task:
        raise HTTPException(status_code=404, detail="Task not found")
    try:
        transcript_text = ""
        if task.get("source_transcript_id"):
            transcript = get_transcript_by_id(task["source_transcript_id"])
            transcript_text = (transcript or {}).get("text") or ""
        plan = task_plan(task["title"], task.get("due_date"), transcript_text)
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
    return {"success": True, "plan": plan}
