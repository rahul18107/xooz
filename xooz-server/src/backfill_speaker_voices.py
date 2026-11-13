"""Enroll voice samples for already named recordings after migration 020.

Run: python -m src.backfill_speaker_voices --user-id YOUR_USER_ID
"""

import argparse

from src.services.database import client, get_or_create_speaker, update_transcript
from src.services.speaker_voice import enroll_in_background


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--user-id", required=True)
    args = parser.parse_args()

    offset = 0
    while True:
        rows = (client.table("transcripts")
                .select("id,speaker_ids,speaker_names,audio_url")
                .eq("user_id", args.user_id)
                .order("recorded_at")
                .range(offset, offset + 99).execute().data)
        if not rows:
            break
        for row in rows:
            speaker_ids = dict(row.get("speaker_ids") or {})
            for label, name in (row.get("speaker_names") or {}).items():
                if label not in speaker_ids and isinstance(name, str) and name.strip():
                    speaker_ids[label] = get_or_create_speaker(args.user_id, name.strip())["id"]
            if speaker_ids != (row.get("speaker_ids") or {}):
                update_transcript(row["id"], {"speaker_ids": speaker_ids})
            if not row.get("audio_url"):
                continue
            for label, speaker_id in speaker_ids.items():
                existing = (client.table("speaker_voice_samples").select("speaker_id")
                            .eq("transcript_id", row["id"]).eq("speaker_label", label)
                            .limit(1).execute().data)
                if not existing or existing[0]["speaker_id"] != speaker_id:
                    enroll_in_background(row["id"], label, speaker_id)
        offset += len(rows)


if __name__ == "__main__":
    main()
