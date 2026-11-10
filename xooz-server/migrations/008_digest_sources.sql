-- Track the completed recordings used to generate each daily recap.
alter table digests add column if not exists source_transcript_ids jsonb not null default '[]'::jsonb;
alter table digests add column if not exists source_fingerprint text;
