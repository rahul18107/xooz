-- Stable people per user; A/B labels remain local to each recording.
create table if not exists speakers (
  id uuid primary key default gen_random_uuid(),
  user_id text not null,
  name text not null check (length(trim(name)) between 1 and 80),
  created_at timestamptz not null default now(),
  unique (user_id, name),
  unique (id, user_id)
);

create index if not exists speakers_user_name_idx on speakers (user_id, name);

alter table transcripts
  add column if not exists speaker_ids jsonb not null default '{}'::jsonb;

-- Preserve names already assigned on older recordings.
insert into speakers (user_id, name)
select distinct t.user_id, trim(value)
from transcripts t
cross join lateral jsonb_each_text(coalesce(t.speaker_names, '{}'::jsonb)) as names(label, value)
where trim(value) <> ''
on conflict (user_id, name) do nothing;

update transcripts t
set speaker_ids = coalesce((
  select jsonb_object_agg(names.label, s.id::text)
  from jsonb_each_text(coalesce(t.speaker_names, '{}'::jsonb)) as names(label, value)
  join speakers s on s.user_id = t.user_id and s.name = trim(names.value)
), '{}'::jsonb)
where t.speaker_names is not null and t.speaker_names <> '{}'::jsonb;
