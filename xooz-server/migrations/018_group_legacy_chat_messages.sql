-- Older app versions gave each question a UUID session. They had no explicit
-- New Chat action, so fold those messages into the user's original chat.
-- Sessions created by the current app use a different ID format and stay separate.
begin;

update chat_messages
set session_id = user_id || '-main'
where session_id ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$';

delete from chat_threads t
where t.session_id ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
  and not exists (
    select 1 from chat_messages m
    where m.user_id = t.user_id and m.session_id = t.session_id
  );

insert into chat_threads (user_id, session_id, title, created_at, updated_at)
select m.user_id, m.session_id, 'Previous chat',
       min(m.created_at), max(m.created_at)
from chat_messages m
where m.session_id = m.user_id || '-main'
group by m.user_id, m.session_id
on conflict (user_id, session_id) do update
set title = 'Previous chat',
    created_at = least(chat_threads.created_at, excluded.created_at),
    updated_at = greatest(chat_threads.updated_at, excluded.updated_at);

commit;
