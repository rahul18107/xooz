alter table profiles add column if not exists transcription_vocabulary jsonb not null default '[]'::jsonb;
