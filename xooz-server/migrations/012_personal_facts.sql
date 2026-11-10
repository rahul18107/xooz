-- Explicit, source-linked personal facts for questions about stable preferences.
create table if not exists personal_facts (
  id uuid primary key default gen_random_uuid(),
  user_id text not null,
  source_transcript_id uuid not null references transcripts(id) on delete cascade,
  fact text not null,
  quote text not null,
  created_at timestamptz not null default now(),
  unique (source_transcript_id, fact)
);

create index if not exists personal_facts_user_idx
  on personal_facts (user_id, created_at desc);
