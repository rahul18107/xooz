-- Make retries of a chat turn safe after a network timeout.
alter table chat_messages add column if not exists client_request_id text;

create unique index if not exists chat_messages_request_role_idx
  on chat_messages (user_id, session_id, client_request_id, role)
  where client_request_id is not null;
