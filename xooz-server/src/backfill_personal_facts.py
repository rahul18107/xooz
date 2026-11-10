"""Index old recordings after migration 012.

Run: python -m src.backfill_personal_facts --user-id test_user_1 --max-recordings 100
Each recording sent to the configured LLM incurs usage; dry-run makes no LLM calls.
"""

import argparse

from src.services.database import client
from src.services.personal_facts import index_personal_facts


def backfill(user_id: str, max_recordings: int, dry_run: bool = False) -> tuple[int, int]:
    offset = 0
    checked = 0
    indexed = 0
    while checked < max_recordings:
        batch_size = min(50, max_recordings - checked)
        rows = (client.table("transcripts").select("id,text")
                .eq("user_id", user_id).eq("status", "completed")
                .order("recorded_at").range(offset, offset + batch_size - 1)
                .execute().data or [])
        if not rows:
            break
        offset += len(rows)
        for row in rows:
            checked += 1
            if not (row.get("text") or "").strip():
                continue
            existing = (client.table("personal_facts").select("id")
                        .eq("user_id", user_id).eq("source_transcript_id", row["id"])
                        .limit(1).execute().data or [])
            if existing or dry_run:
                continue
            try:
                index_personal_facts(user_id, row["id"], row["text"])
                indexed += 1
            except Exception as exc:
                print(f"Could not index recording {row['id']}: {exc}")
    return checked, indexed


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--user-id", required=True)
    parser.add_argument("--max-recordings", type=int, default=100)
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()
    if args.max_recordings < 1:
        parser.error("--max-recordings must be positive")
    checked, indexed = backfill(args.user_id, args.max_recordings, args.dry_run)
    print(f"Checked {checked} recordings; sent {indexed} to the LLM")


if __name__ == "__main__":
    main()
