-- Indexed keyword search plus optional 768-dimensional semantic search for chat.
create schema if not exists extensions;
create extension if not exists vector with schema extensions;
set search_path to public, extensions;

create index if not exists transcripts_chat_fts_idx on transcripts using gin (
  to_tsvector('english', coalesce(text, '') || ' ' || coalesce(title, ''))
);

create table if not exists transcript_embeddings (
  transcript_id uuid primary key references transcripts(id) on delete cascade,
  content_hash text not null,
  embedding vector(768) not null
);

create index if not exists transcript_embeddings_cosine_idx
  on transcript_embeddings using hnsw (embedding vector_cosine_ops);

create or replace function search_chat_recordings(
  p_user_id text,
  p_query text,
  p_embedding vector(768) default null,
  p_limit integer default 5
)
returns table (transcript_id uuid, score double precision)
language sql stable set search_path = public, extensions
as $$
  with keyword as (
    select t.id, row_number() over (
      order by ts_rank_cd(
        to_tsvector('english', coalesce(t.text, '') || ' ' || coalesce(t.title, '')),
        to_tsquery('english', p_query)
      ) desc, t.recorded_at desc
    ) as rank
    from transcripts t
    where t.user_id = p_user_id and t.status = 'completed'
      and to_tsvector('english', coalesce(t.text, '') || ' ' || coalesce(t.title, ''))
          @@ to_tsquery('english', p_query)
    limit 30
  ),
  semantic as (
    select e.transcript_id as id, row_number() over (
      order by e.embedding <=> p_embedding
    ) as rank
    from transcript_embeddings e
    join transcripts t on t.id = e.transcript_id
    where p_embedding is not null and t.user_id = p_user_id and t.status = 'completed'
    order by e.embedding <=> p_embedding
    limit 30
  )
  select coalesce(k.id, s.id) as transcript_id,
         (coalesce(1.0 / (50 + k.rank), 0) + coalesce(1.0 / (50 + s.rank), 0))::double precision as score
  from keyword k full outer join semantic s on s.id = k.id
  order by score desc
  limit greatest(1, least(p_limit, 10));
$$;
