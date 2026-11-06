-- Per-recording summary (Summary tab in transcript detail).
-- Run in Supabase SQL editor. Safe to re-run.

alter table transcripts add column if not exists summary text;
