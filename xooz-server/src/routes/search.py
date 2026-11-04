from fastapi import APIRouter, HTTPException, Query
from src.services.database import (
    search_transcripts,
    search_digests,
    search_tasks,
    get_transcript_lists,
    count_digests,
    count_transcripts,
)

router = APIRouter()

@router.get("/search")
async def search(
    user_id: str = Query(...),
    q: str = Query(..., min_length=1),
    limit: int = Query(20, ge=1, le=50),
):
    """Search across transcripts, digests and tasks for the Search screen results view."""
    try:
        return {
            "success": True,
            "query": q,
            "transcripts": search_transcripts(user_id=user_id, query=q, limit=limit),
            "digests": search_digests(user_id=user_id, query=q, limit=limit),
            "tasks": search_tasks(user_id=user_id, query=q, limit=limit),
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@router.get("/categories/counts")
async def category_counts(user_id: str = Query(...)):
    """Counts for the Search screen category grid:
    Starred / Work / Personal / Social / Recaps / Memories / People / Places."""
    try:
        rows = get_transcript_lists(user_id=user_id)

        people, places = set(), set()
        for row in rows:
            for p in row.get("people") or []:
                people.add(str(p))
            for p in row.get("places") or []:
                places.add(str(p))
        memories = set()
        for row in rows:
            for tag in row.get("tags") or []:
                remember_words = ("remember", "memory")
                if str(tag) in remember_words:
                    memories.add(str(tag))

        return {
            "success": True,
            "categories": {
                "Starred": count_transcripts(user_id=user_id, starred=True),
                "Work": count_transcripts(user_id=user_id, category="work"),
                "Personal": count_transcripts(user_id=user_id, category="personal"),
                "Social": count_transcripts(user_id=user_id, category="social"),
                "Recaps": count_digests(user_id=user_id),
                # Memories: distinct memory-related tags (placeholder until memory storage exists)
                "Memories": len(memories),
                "People": len(people),
                "Places": len(places),
            },
            "people": sorted(people),
            "places": sorted(places),
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
