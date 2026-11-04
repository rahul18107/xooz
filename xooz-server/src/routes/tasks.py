from fastapi import APIRouter, HTTPException, Query
from src.services.database import get_tasks, get_task_by_id, update_task
import uuid

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
    limit: int = Query(100, ge=1, le=200),
):
    """Tasks extracted from conversations. status = open | done | snoozed."""
    if status and status not in ALLOWED_STATUSES:
        raise HTTPException(status_code=400, detail="status must be one of: open, done, snoozed")
    try:
        tasks = get_tasks(user_id=user_id, status=status, limit=limit)
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

    updated = update_task(task_id, updates or {"status": task["status"]})
    return {"success": True, "task": updated}
