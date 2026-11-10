-- Existing done tasks remain NULL: their historical completion time is unknown.
alter table tasks add column if not exists completed_at timestamptz;

create index if not exists tasks_user_completed_idx
  on tasks (user_id, completed_at desc) where status = 'done';
