from fastapi import APIRouter, HTTPException, Query
from src.services.database import create_device, get_devices
import secrets

router = APIRouter()

@router.post("/devices/pair")
async def pair_device(body: dict):
    """Start pairing a Xooz Watch: body {"user_id": "...", "name": "..."}.
    Returns a 6-digit pairing code to confirm on the watch."""
    user_id = body.get("user_id")
    if not user_id:
        raise HTTPException(status_code=400, detail="user_id is required")
    name = (body.get("name") or "Xooz Watch").strip()

    try:
        device = create_device(user_id=user_id, name=name, pairing_code=f"{secrets.randbelow(1000000):06d}")
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
    return {"success": True, "device": device}

@router.get("/devices")
async def list_devices(user_id: str = Query(...)):
    try:
        devices = get_devices(user_id=user_id)
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
    return {"success": True, "devices": devices, "count": len(devices)}
