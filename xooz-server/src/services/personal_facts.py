import re

from src.services.database import client
from src.services.insights import _call_llm, _parse_json


def is_personal_fact_question(question: str) -> bool:
    return bool(re.search(
        r"\b(?:what(?:'s| is| are) my|who is my|where do i live|do i like|"
        r"what do i (?:like|prefer)|what (?:kind|type) of .+ do i (?:like|prefer))\b",
        question, re.IGNORECASE,
    ))


def index_personal_facts(user_id: str, transcript_id: str, text: str) -> None:
    """Keep only explicitly stated stable facts, with an exact recording quote."""
    prompt = f"""Extract up to 8 explicit, stable facts about the recording owner's identity, preferences, or relationships.
Exclude plans, temporary activities, guesses, and facts about other speakers.
Return only JSON: {{"facts":[{{"fact":"short first-person fact","quote":"exact contiguous recording quote"}}]}}.
Return an empty list when speaker identity is unclear or there are no explicit stable facts.

Recording:
{text[:10000]}
JSON:"""
    data = _parse_json(_call_llm(prompt, max_tokens=550), {"facts": []})
    rows = []
    for item in (data.get("facts") or [])[:8]:
        if not isinstance(item, dict):
            continue
        fact, quote = item.get("fact"), item.get("quote")
        if not isinstance(fact, str) or not isinstance(quote, str):
            continue
        fact, quote = fact.strip(), quote.strip()
        if not fact or len(quote) < 8 or len(fact) > 240:
            continue
        if " ".join(quote.split()).casefold() not in " ".join(text.split()).casefold():
            continue
        rows.append({"user_id": user_id, "source_transcript_id": transcript_id,
                     "fact": fact, "quote": quote})
    if rows:
        client.table("personal_facts").upsert(rows, on_conflict="source_transcript_id,fact").execute()


def find_personal_fact_recordings(user_id: str, question: str, limit: int = 5) -> list[dict]:
    if not is_personal_fact_question(question):
        return []
    facts = (client.table("personal_facts").select("source_transcript_id,fact,quote")
             .eq("user_id", user_id).limit(100).execute().data or [])
    terms = {word for word in re.findall(r"[a-z0-9]+", question.lower())
             if len(word) > 2 and word not in {"what", "where", "which", "about", "like", "prefer", "your", "mine"}}
    ranked = sorted(
        facts,
        key=lambda row: sum(term in (row.get("fact") or "").lower() for term in terms),
        reverse=True,
    )
    if terms and any(sum(term in (row.get("fact") or "").lower() for term in terms) for row in ranked):
        ranked = [row for row in ranked if any(term in (row.get("fact") or "").lower() for term in terms)]
    ids = list(dict.fromkeys(str(row["source_transcript_id"]) for row in ranked))[:limit]
    if not ids:
        return []
    transcripts = (client.table("transcripts").select("id,title,recorded_at,status")
                   .eq("user_id", user_id).eq("status", "completed")
                   .in_("id", ids).execute().data or [])
    by_id = {str(row["id"]): row for row in transcripts}
    return [{**by_id[transcript_id],
             "text": "\n".join(row["quote"] for row in ranked
                               if str(row["source_transcript_id"]) == transcript_id)[:3500]}
            for transcript_id in ids if transcript_id in by_id]
