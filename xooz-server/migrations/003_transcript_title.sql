-- One-liner title per recording (heading of the transcript detail screen).
-- Run in Supabase SQL editor. Safe to re-run.

alter table transcripts add column if not exists title text;
