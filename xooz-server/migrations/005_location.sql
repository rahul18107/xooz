-- Store where each recording was captured (for the recap day map).
alter table transcripts add column if not exists latitude double precision;
alter table transcripts add column if not exists longitude double precision;
