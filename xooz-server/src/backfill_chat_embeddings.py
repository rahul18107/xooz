"""Run after migrations 009 and 010: python -m src.backfill_chat_embeddings."""

from src.services.database import client
from src.services.chat_retrieval import index_transcript


def main() -> None:
    offset = 0
    indexed = 0
    while True:
        rows = (client.table("transcripts").select("id,text")
                .eq("status", "completed")
                .order("recorded_at")
                .range(offset, offset + 99).execute().data or [])
        if not rows:
            break
        for row in rows:
            try:
                index_transcript(row["id"], row.get("text") or "")
                indexed += 1
            except Exception as exc:
                print(f"Embedding failed for {row['id']}: {exc}")
        offset += len(rows)
        print(f"Processed {offset} recordings")
    print(f"Finished checking {indexed} recordings")


if __name__ == "__main__":
    main()
