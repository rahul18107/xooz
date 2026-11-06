-- Link to the stored audio recording (Supabase Storage, public 'recordings' bucket).
-- Run in Supabase SQL editor. Safe to re-run.

alter table transcripts add column if not exists audio_url text;
