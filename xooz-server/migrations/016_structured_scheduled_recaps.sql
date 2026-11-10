-- Apply before enabling scheduled recaps. Existing recap text and UI remain valid.
alter table digests add column if not exists structured_summary jsonb;
alter table profiles add column if not exists daily_recap_enabled boolean not null default false;
alter table profiles add column if not exists daily_recap_hour integer not null default 21
  check (daily_recap_hour between 0 and 23);

create table if not exists scheduled_recap_claims (
  user_id text not null,
  recap_date date not null,
  claim_token uuid not null default gen_random_uuid(),
  claimed_at timestamptz not null default now(),
  completed_at timestamptz,
  primary key (user_id, recap_date)
);

revoke all on scheduled_recap_claims from anon, authenticated;
grant select, insert, update, delete on scheduled_recap_claims to service_role;

-- A lease permits a crashed worker to retry; completed days are never claimed again.
create or replace function claim_scheduled_recap(p_user_id text, p_recap_date date)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  token uuid;
begin
  insert into scheduled_recap_claims (user_id, recap_date, claim_token)
  values (p_user_id, p_recap_date, gen_random_uuid())
  on conflict (user_id, recap_date) do update
    set claimed_at = now(), claim_token = excluded.claim_token
    where scheduled_recap_claims.completed_at is null
      and scheduled_recap_claims.claimed_at < now() - interval '30 minutes'
  returning claim_token into token;
  return token;
end;
$$;

revoke all on function claim_scheduled_recap(text, date) from public;
grant execute on function claim_scheduled_recap(text, date) to service_role;
