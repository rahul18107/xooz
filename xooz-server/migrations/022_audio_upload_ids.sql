-- A retried phone upload must resolve to the same transcript.
alter table transcripts add column if not exists client_recording_id text;

create unique index if not exists transcripts_user_recording_id_idx
  on transcripts (user_id, client_recording_id)
  where client_recording_id is not null;
