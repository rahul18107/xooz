-- Confirmed, source-linked voice samples for future cross-recording matching.
create table if not exists speaker_voice_samples (
  speaker_id uuid not null references speakers(id) on delete cascade,
  transcript_id uuid not null references transcripts(id) on delete cascade,
  speaker_label text not null,
  embedding jsonb not null,
  speech_seconds numeric not null,
  created_at timestamptz not null default now(),
  primary key (transcript_id, speaker_label),
  check (jsonb_typeof(embedding) = 'array'),
  check (speech_seconds > 0)
);

create index if not exists speaker_voice_samples_speaker_idx
  on speaker_voice_samples (speaker_id);

-- The backend service role owns these records; clients do not read raw voice vectors.
alter table speakers enable row level security;
alter table speaker_voice_samples enable row level security;
