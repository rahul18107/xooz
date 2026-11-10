-- Keep the recordings cited by each assistant reply across app restarts.
alter table chat_messages add column if not exists source_ids jsonb not null default '[]'::jsonb;
