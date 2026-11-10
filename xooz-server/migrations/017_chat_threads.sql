-- Index chat threads without moving or rewriting existing messages.
create table if not exists chat_threads (
  user_id text not null,
  session_id text not null,
  title text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (user_id, session_id)
);

create index if not exists chat_threads_recent_idx
  on chat_threads (user_id, updated_at desc);

-- Preserve the original single-session chat as a selectable thread.
insert into chat_threads (user_id, session_id, title, created_at, updated_at)
select m.user_id, m.session_id,
       coalesce(nullif(left(trim((select u.content from chat_messages u
         where u.user_id = m.user_id and u.session_id = m.session_id
           and u.role = 'user'
         order by u.created_at, u.id limit 1)), 80), ''), 'Chat'),
       min(m.created_at), max(m.created_at)
from chat_messages m
group by m.user_id, m.session_id
on conflict (user_id, session_id) do nothing;
