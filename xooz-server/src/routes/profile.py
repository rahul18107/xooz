from fastapi import APIRouter, HTTPException
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError
from src.services.database import get_or_create_profile, update_profile, count_transcripts

router = APIRouter()

@router.get("/me")
async def get_me(user_id: str):
    """Profile for the Settings screen header (creates a bare profile on first call)."""
    try:
        profile = get_or_create_profile(user_id)
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
    return {"success": True, "profile": profile}


@router.patch("/me")
async def update_me(body: dict):
    user_id = body.get("user_id")
    if not user_id:
        raise HTTPException(status_code=400, detail="user_id is required")
    updates = {}
    if "transcription_vocabulary" in body:
        vocabulary = body["transcription_vocabulary"]
        if not isinstance(vocabulary, list) or len(vocabulary) > 200:
            raise HTTPException(status_code=400, detail="Invalid transcription vocabulary")
        if any(not isinstance(term, str) or not term.strip() or len(term.strip()) > 50
               or len(term.split()) > 6 for term in vocabulary):
            raise HTTPException(status_code=400, detail="Each term must be 1-6 words and at most 50 characters")
        updates["transcription_vocabulary"] = list(dict.fromkeys(term.strip() for term in vocabulary))
    if "daily_recap_enabled" in body:
        if not isinstance(body["daily_recap_enabled"], bool):
            raise HTTPException(status_code=400, detail="daily_recap_enabled must be a boolean")
        updates["daily_recap_enabled"] = body["daily_recap_enabled"]
    if "daily_recap_hour" in body:
        hour = body["daily_recap_hour"]
        if type(hour) is not int or not 0 <= hour <= 23:
            raise HTTPException(status_code=400, detail="daily_recap_hour must be 0-23")
        updates["daily_recap_hour"] = hour
    if "timezone" in body:
        name = body["timezone"]
        try:
            if not isinstance(name, str) or not name or len(name) > 80:
                raise ValueError("Invalid timezone")
            ZoneInfo(name)
        except (ValueError, ZoneInfoNotFoundError):
            raise HTTPException(status_code=400, detail="Use an IANA timezone, such as Asia/Kolkata")
        updates["timezone"] = name
    if not updates:
        raise HTTPException(status_code=400, detail="No profile settings supplied")
    try:
        get_or_create_profile(user_id)
        profile = update_profile(user_id, updates)
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc))
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
