from fastapi import APIRouter, HTTPException
from src.services.database import get_or_create_profile, count_transcripts

router = APIRouter()

@router.get("/me")
async def get_me(user_id: str):
    """Profile for the Settings screen header (creates a bare profile on first call)."""
    try:
        profile = get_or_create_profile(user_id)
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
    return {"success": True, "profile": profile}

@router.get("/usage")
async def get_usage(user_id: str):
    """Plan & Usage screen (Settings → Plan & Usage)."""
    try:
        profile = get_or_create_profile(user_id)
        recording_count = count_transcripts(user_id=user_id)
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

    plan = profile.get("plan") or "free"
    # generous prototype limits so nothing blocks a new user
    limits = {"free": 120, "premium": 600}
    limit = limits.get(plan, 120)
    used = float(profile.get("monthly_minutes_used") or 0)

    return {
        "success": True,
        "plan": plan,
        "minutes_used": round(used, 1),
        "minutes_limit": limit,
        "minutes_remaining": max(0.0, round(limit - used, 1)),
        "recordings_count": recording_count,
        "timezone": profile.get("timezone") or "UTC",
    }
