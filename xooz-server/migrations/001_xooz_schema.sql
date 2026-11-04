-- Xooz schema extension (run in Supabase SQL editor)
-- The FastAPI server talks to Supabase with the service role key,
-- which bypasses RLS, so no extra policies are required.

-- ============================================================
-- transcripts: add status / metadata columns
-- ============================================================
alter table transcripts add column if not exists status text not null default 'completed';
alter table transcripts add column if not exists category text;
alter table transcripts add column if not exists starred boolean not null default false;
alter table transcripts add column if not exists tags jsonb not null default '[]'::jsonb;
alter table transcripts add column if not exists people jsonb not null default '[]'::jsonb;
alter table transcripts add column if not exists places jsonb not null default '[]'::jsonb;
alter table transcripts add column if not exists duration_seconds numeric;
alter table transcripts add column if not exists error_message text;

create index if not exists transcripts_user_recorded_idx on transcripts (user_id, recorded_at desc);

-- ============================================================
-- tasks: extracted from conversations
-- ============================================================
create table if not exists tasks (
  id uuid primary key default gen_random_uuid(),
  user_id text not null,
  title text not null,
  source_transcript_id uuid references transcripts (id) on delete cascade,
  status text not null default 'open',           -- open | done | snoozed
  due_date date,
  created_at timestamptz not null default now()
);

create index if not exists tasks_user_status_idx on tasks (user_id, status, created_at desc);

-- ============================================================
-- chat_messages: "Ask Anything" history
-- ============================================================
create table if not exists chat_messages (
  id uuid primary key default gen_random_uuid(),
  user_id text not null,
  session_id text not null,
  role text not null check (role in ('user', 'assistant')),
  content text not null,
  created_at timestamptz not null default now()
);

create index if not exists chat_messages_session_idx on chat_messages (user_id, session_id, created_at);

-- ============================================================
-- profiles: who the user is + plan/usage + timezone
-- ============================================================
create table if not exists profiles (
  id text primary key,                            -- same value as user_id for now (real auth comes later)
  display_name text,
  email text,
  plan text not null default 'free',
  timezone text not null default 'UTC',
  monthly_minutes_used numeric not null default 0,
  created_at timestamptz not null default now()
);

-- seed the test user the app hardcodes in lib/config/api.dart
insert into profiles (id, display_name, email, timezone)
values ('test_user_1', 'Test User', 'test@xooz.app', 'Asia/Kolkata')
on conflict (id) do nothing;

-- ============================================================
-- devices: Xooz Watch pairing
-- ============================================================
create table if not exists devices (
  id uuid primary key default gen_random_uuid(),
  user_id text not null,
  name text not null,
  pairing_code text,
  status text not null default 'pending',         -- pending | connected | disconnected
  last_seen_at timestamptz,
  created_at timestamptz not null default now()
);

create index if not exists devices_user_idx on devices (user_id);
