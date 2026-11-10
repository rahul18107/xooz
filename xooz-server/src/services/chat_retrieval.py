import hashlib
import re
from datetime import datetime, timedelta

import httpx

from src.config import CLOUDFLARE_ACCOUNT_ID, CLOUDFLARE_API_TOKEN
from src.services.database import client, get_profile_tz, get_transcripts
from src.services.insights import _call_llm, _parse_json

EMBEDDING_MODEL = "@cf/baai/bge-base-en-v1.5"
EMBEDDING_URL = (
    f"https://api.cloudflare.com/client/v4/accounts/{CLOUDFLARE_ACCOUNT_ID}/ai/run/{EMBEDDING_MODEL}"
)
_STOP_WORDS = {"about", "after", "again", "been", "could", "from", "have", "into", "last", "that", "them", "there", "this", "today", "yesterday", "what", "when", "where", "which", "with", "would", "your", "did", "say", "said", "who", "how", "can", "was"}


def search_question(message: str, history: list[dict]) -> str:
    """Resolve a context-dependent follow-up for retrieval, not for answering."""
    previous = [item for item in history if item.get("role") == "user"]
    if not previous or not re.search(
        r"\b(it|its|they|them|their|that|those|this|these|he|she|his|her|there)\b"
        r"|\bwhat about\b|\bhow about\b|\band (?:what|when|where|who|how)\b",
        message, re.IGNORECASE,
    ):
        return message

    recent = history[-6:]
    conversation = "\n".join(
        f"{item.get('role', 'user')}: {str(item.get('content') or '')[:400]}"
        for item in recent
    )
    prompt = f"""Rewrite the last user's question as one standalone search query about their recorded conversations.
Resolve references using the recent chat. Preserve names, dates, and constraints from the question.
Do not answer the question or add facts. Return only JSON: {{"query":"standalone question"}}.

Recent chat:
{conversation}
user: {message[:500]}
JSON:"""
    try:
        result = _parse_json(_call_llm(prompt, max_tokens=120), {})
        query = result.get("query")
        if isinstance(query, str) and 3 <= len(query.strip()) <= 500:
            return query.strip()
    except Exception:
        pass
    return message


def _keyword_query(message: str) -> str:
    terms = list(dict.fromkeys(word for word in re.findall(r"[a-z0-9]+", message.lower())
                               if len(word) > 2 and word not in _STOP_WORDS))
    return " | ".join(terms[:12])


def _alternative_query(message: str) -> str | None:
    """Ask for one broader search phrasing only after indexed retrieval misses."""
    prompt = f"""Write one alternative search question for finding the same event in a voice transcript.
Use common synonyms or simpler wording, but preserve every person name, place name, number, and date.
Do not answer or add details. Return only JSON: {{"query":"alternative search question"}}.

Question: {message[:500]}
JSON:"""
    try:
        data = _parse_json(_call_llm(prompt, max_tokens=120), {})
        alternative = data.get("query")
        if not isinstance(alternative, str) or not 3 <= len(alternative.strip()) <= 500:
            return None
        alternative = alternative.strip()
        required = [term for term in re.findall(r"\b[A-Z][a-z]+\b|\b\d[\d./-]*\b", message)
                    if term.casefold() not in {"what", "when", "where", "who", "how", "did", "do", "does", "can", "was", "is", "are"}]
        alternate_words = set(re.findall(r"[a-z0-9]+", alternative.casefold()))
        if any(term.casefold() not in alternate_words for term in required):
            return None
        if not _keyword_query(alternative) or alternative.casefold() == message.casefold():
            return None
        return alternative
    except Exception:
        return None


def _evidence_excerpt(text: str, query: str, max_chars: int = 3400) -> str:
    if len(text) <= max_chars:
        return text
    terms = [term.strip() for term in query.split("|") if term.strip()]
    matches = [[match.start() for match in re.finditer(
        rf"\b{re.escape(term)}\b", text, re.IGNORECASE)] for term in terms]
    matched_terms = [positions for positions in matches if positions]
    if not matched_terms:
        return text[:max_chars]
    start = max(0, min(matched_terms, key=len)[0] - 500)
    return text[start:start + max_chars]


def _embed(text: str) -> list[float]:
    if not CLOUDFLARE_ACCOUNT_ID or not CLOUDFLARE_API_TOKEN:
        raise RuntimeError("Cloudflare embeddings are not configured")
    response = httpx.post(
        EMBEDDING_URL,
        headers={"Authorization": f"Bearer {CLOUDFLARE_API_TOKEN}"},
        json={"text": [text[:1800]]},
        timeout=20.0,
    )
    response.raise_for_status()
    payload = response.json()
    if not payload.get("success"):
        raise RuntimeError(f"Embedding request failed: {payload.get('errors')}")
    vector = payload["result"]["data"][0]
    if len(vector) != 768:
        raise RuntimeError("Unexpected embedding dimensions")
    return vector


def _passages(text: str, size: int = 1200, overlap: int = 180) -> list[str]:
    words = list(re.finditer(r"\S+", text))
    if not words:
        return []
    passages = []
    start = 0
    while start < len(words):
        end = start
        while end < len(words) and words[end].end() - words[start].start() <= size:
            end += 1
        end = max(start + 1, end)
        passages.append(text[words[start].start():words[end - 1].end()])
        if end == len(words):
            break
        next_start = end - 1
        while next_start > start and words[end - 1].end() - words[next_start].start() < overlap:
            next_start -= 1
        start = max(start + 1, next_start)
    return passages


def _dated_recordings(user_id: str, message: str, limit: int) -> list[dict] | None:
    """Keep relative-day and recency questions inside their intended time scope."""
    lower = message.lower()
    is_today = bool(re.search(r"\btoday\b|\bthis morning\b|\bthis afternoon\b|\btonight\b", lower))
    is_yesterday = bool(re.search(r"\byesterday\b|\blast night\b", lower))
    is_latest = bool(re.search(
        r"\blast time\b|\bmost recent\b|\blatest\b"
        r"|\blast (?:talk|spoke|speak|discuss|discussed|mention|mentioned|meet|met|see|saw)\b",
        lower,
    ))
    if not (is_today or is_yesterday or is_latest):
        return None

    date = None
    if is_today or is_yesterday:
        local_date = datetime.now(get_profile_tz(user_id)).date()
        date = (local_date - timedelta(days=1 if is_yesterday else 0)).isoformat()
    rows = [row for row in get_transcripts(user_id=user_id, date=date, limit=100)
            if row.get("status") == "completed" and (row.get("text") or "").strip()]
    if not rows:
        return []

    terms = [term for term in re.findall(r"[a-z0-9]+", lower)
             if len(term) > 2 and term not in _STOP_WORDS
             and term not in {"night", "morning", "afternoon", "time", "recent", "latest"}]
    ranked = []
    for row in rows:
        chunks = _passages(row["text"])
        scored = sorted(
            ((sum(term in chunk.lower() for term in terms), index, chunk)
             for index, chunk in enumerate(chunks)),
            key=lambda item: (-item[0], item[1]),
        )
        best = scored[0][0]
        ranked.append((best, row, scored))
    if terms and any(score > 0 for score, _, _ in ranked):
        ranked = [item for item in ranked if item[0] > 0]
    elif terms and is_latest:
        return []

    if not is_latest:
        ranked.sort(key=lambda item: (item[0], item[1].get("recorded_at") or ""), reverse=True)
    # Recency questions keep the database's newest-first order.
    selected = ranked[:limit]
    return [{**row, "text": "\n...\n".join(chunk for _, _, chunk in scored[:2])}
            for _, row, scored in selected]


def index_transcript(transcript_id: str, text: str) -> None:
    content = text.strip()
    if not content:
        return
    digest = hashlib.sha256(content[:1800].encode()).hexdigest()
    existing = (client.table("transcript_embeddings").select("content_hash")
                .eq("transcript_id", transcript_id).execute().data)
    if not existing or existing[0]["content_hash"] != digest:
        vector = _embed(content)
        client.table("transcript_embeddings").upsert({
            "transcript_id": transcript_id, "content_hash": digest,
            "embedding": vector,
        }).execute()

    passages = _passages(content)
    for index, passage in enumerate(passages):
        passage_hash = hashlib.sha256(passage.encode()).hexdigest()
        rows = (client.table("transcript_passages").select("content_hash")
                .eq("transcript_id", transcript_id).eq("passage_index", index)
                .execute().data)
        if rows and rows[0]["content_hash"] == passage_hash:
            continue
        client.table("transcript_passages").upsert({
            "transcript_id": transcript_id, "passage_index": index,
            "text": passage, "content_hash": passage_hash,
            "embedding": _embed(passage),
        }).execute()
    (client.table("transcript_passages").delete().eq("transcript_id", transcript_id)
     .gte("passage_index", len(passages)).execute())


def _find_indexed_recordings(user_id: str, message: str, limit: int,
                             allow_retry: bool = True) -> list:
    query = _keyword_query(message)
    if not query:
        return [t for t in get_transcripts(user_id=user_id, limit=5)
                if t.get("status") == "completed"]
    try:
        embedding = _embed(message)
    except (httpx.HTTPError, RuntimeError, KeyError, IndexError, TypeError) as exc:
        print(f"chat semantic search unavailable: {exc}")
        embedding = None
    try:
        passages = client.rpc("search_chat_passages", {
            "p_user_id": user_id, "p_query": query,
            "p_embedding": embedding, "p_limit": limit * 2,
        }).execute().data or []
    except Exception as exc:
        print(f"chat passage search unavailable: {exc}")
        passages = []
    if passages and all("text" in row for row in passages):
        ids = list(dict.fromkeys(str(row["transcript_id"]) for row in passages))[:limit]
        rows = (client.table("transcripts").select("*").eq("user_id", user_id)
                .eq("status", "completed").in_("id", ids).execute().data)
        by_id = {str(row["id"]): row for row in rows}
        excerpts = {}
        for row in passages:
            transcript_id = str(row["transcript_id"])
            if transcript_id in by_id:
                excerpts.setdefault(transcript_id, []).append(row["text"])
        return [{**by_id[id], "text": "\n...\n".join(excerpts[id][:2])}
                for id in ids if id in by_id]

    matches = client.rpc("search_chat_recordings", {
        "p_user_id": user_id, "p_query": query,
        "p_embedding": embedding, "p_limit": limit,
    }).execute().data or []
    ids = [str(row["transcript_id"]) for row in matches]
    if not ids:
        if embedding is None or not allow_retry:
            return []
        alternative = _alternative_query(message)
        if alternative:
            return _find_indexed_recordings(user_id, alternative, limit, allow_retry=False)
        return []
    rows = (client.table("transcripts").select("*").eq("user_id", user_id)
            .eq("status", "completed").in_("id", ids).execute().data)
    by_id = {str(row["id"]): row for row in rows}
    return [{**by_id[transcript_id],
             "text": _evidence_excerpt(by_id[transcript_id].get("text") or "", query)}
            for transcript_id in ids if transcript_id in by_id]


def find_recordings(user_id: str, message: str, limit: int = 5) -> list:
    dated = _dated_recordings(user_id, message, limit)
    if dated is not None:
        return dated
    return _find_indexed_recordings(user_id, message, limit)
