-- Search bounded passages so relevant facts are not lost in long recordings.
create schema if not exists extensions;
create extension if not exists vector with schema extensions;
set search_path to public, extensions;

create table if not exists transcript_passages (
  transcript_id uuid not null references transcripts(id) on delete cascade,
  passage_index integer not null,
  text text not null,
  content_hash text not null,
  embedding vector(768),
  primary key (transcript_id, passage_index)
);

create index if not exists transcript_passages_fts_idx
  on transcript_passages using gin (to_tsvector('english', text));
create index if not exists transcript_passages_cosine_idx
  on transcript_passages using hnsw (embedding vector_cosine_ops);

create or replace function search_chat_passages(
  p_user_id text,
  p_query text,
  p_embedding vector(768) default null,
  p_limit integer default 8
)
returns table (transcript_id uuid, passage_index integer, text text, score double precision)
language sql stable set search_path = public, extensions
as $$
  with keyword as (
    select p.transcript_id, p.passage_index, row_number() over (
      order by ts_rank_cd(to_tsvector('english', p.text), to_tsquery('english', p_query)) desc,
               t.recorded_at desc
    ) as rank
    from transcript_passages p
    join transcripts t on t.id = p.transcript_id
    where t.user_id = p_user_id and t.status = 'completed'
      and to_tsvector('english', p.text) @@ to_tsquery('english', p_query)
    limit 40
  ),
  semantic as (
    select p.transcript_id, p.passage_index, row_number() over (
      order by p.embedding <=> p_embedding
    ) as rank
    from transcript_passages p
    join transcripts t on t.id = p.transcript_id
    where p_embedding is not null and p.embedding is not null
      and t.user_id = p_user_id and t.status = 'completed'
    order by p.embedding <=> p_embedding
    limit 40
  )
  select p.transcript_id, p.passage_index, p.text,
         (coalesce(1.0 / (50 + k.rank), 0) +
          coalesce(1.0 / (50 + s.rank), 0))::double precision as score
  from keyword k
  full outer join semantic s
    on s.transcript_id = k.transcript_id and s.passage_index = k.passage_index
  join transcript_passages p on p.transcript_id = coalesce(k.transcript_id, s.transcript_id)
    and p.passage_index = coalesce(k.passage_index, s.passage_index)
  order by score desc
  limit greatest(1, least(p_limit, 20));
$$;
