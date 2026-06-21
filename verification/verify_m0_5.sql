-- =====================================================================
-- verification/verify_m0_5.sql
-- Run AFTER applying migrations 0001-0016 AND loading supabase/seed.sql:
--   psql "$DIRECT_URL" -v ON_ERROR_STOP=1 -f verification/verify_m0_5.sql
--
-- Prints a readable report, then HARD-ASSERTS every load-bearing seed
-- invariant (raises and aborts on the first mismatch). Data correctness
-- only; cross-tenant RLS behaviour is exercised separately (M0-4 rig).
-- Safe to run repeatedly; the seed is idempotent.
-- =====================================================================
\pset pager off
\set ON_ERROR_STOP on
\set company_id '11111111-1111-1111-1111-111111111111'

\echo '== Tenant (expect 1 row: RYtaine Demo Realty / demo-rytaine / active) =='
select id, slug, status, plan, timezone from companies where id = :'company_id';

\echo '== Users (expect 3: admin, manager, agent — all active) =='
select email, role, status from users where company_id = :'company_id' order by role;

\echo '== Agent layer (expect: 1 active prompt, 1 default KB, 1 active config) =='
select 'prompts_active'   as item, count(*) from prompts        where company_id = :'company_id' and is_active
union all
select 'kb_default',              count(*) from knowledge_bases where company_id = :'company_id' and is_default
union all
select 'configs_active',          count(*) from agent_configs   where company_id = :'company_id' and is_active;

\echo '== Leads (expect 6 total; 1 flagged soft-duplicate) =='
select lead_status, source, is_potential_duplicate, phone
from leads where company_id = :'company_id' order by created_at;

\echo '== RAG (expect 1 document ready, 3 chunks, all 1536-d embeddings) =='
select d.title, d.status, d.chunk_count,
       (select count(*) from document_chunks c where c.document_id = d.id) as actual_chunks,
       (select count(*) from document_chunks c where c.document_id = d.id and c.embedding is not null) as embedded
from documents d where d.company_id = :'company_id';

\echo '== Call lifecycle (expect 1 completed call, 1 transcript, 1 recording) =='
select c.call_status, c.sentiment, c.duration_seconds,
       (select count(*) from transcripts t where t.call_id = c.id) as transcripts,
       (select count(*) from recordings  r where r.call_id = c.id) as recordings
from calls c where c.company_id = :'company_id';

\echo '== Identity claims (expect app_metadata.company_id = demo for all 3) =='
select email,
       raw_app_meta_data->>'company_id' as company_id_claim,
       raw_app_meta_data->>'role'       as role_claim
from auth.users
where id in ('a0000000-0000-0000-0000-000000000001',
             'a0000000-0000-0000-0000-000000000002',
             'a0000000-0000-0000-0000-000000000003')
order by email;

-- =====================================================================
-- HARD ASSERTIONS
-- =====================================================================
do $$
declare
  cid uuid := '11111111-1111-1111-1111-111111111111';
  n   int;
  dup_target uuid;
begin
  -- tenant root
  select count(*) into n from companies where id = cid and status = 'active';
  if n <> 1 then raise exception 'FAIL: expected 1 active demo company, found %', n; end if;

  -- users: exactly one of each role
  select count(*) into n from users where company_id = cid;
  if n <> 3 then raise exception 'FAIL: expected 3 users, found %', n; end if;
  select count(distinct role) into n from users where company_id = cid;
  if n <> 3 then raise exception 'FAIL: expected 3 distinct roles, found %', n; end if;

  -- agent layer singletons
  select count(*) into n from prompts where company_id = cid and is_active;
  if n <> 1 then raise exception 'FAIL: expected 1 active prompt, found %', n; end if;
  select count(*) into n from knowledge_bases where company_id = cid and is_default;
  if n <> 1 then raise exception 'FAIL: expected 1 default KB, found %', n; end if;
  select count(*) into n from agent_configs where company_id = cid and is_active;
  if n <> 1 then raise exception 'FAIL: expected 1 active agent_config, found %', n; end if;

  -- leads + soft-dedup
  select count(*) into n from leads where company_id = cid;
  if n < 6 then raise exception 'FAIL: expected >=6 leads, found %', n; end if;
  select count(*) into n from leads where company_id = cid and is_potential_duplicate;
  if n <> 1 then raise exception 'FAIL: expected exactly 1 flagged duplicate, found %', n; end if;
  select duplicate_of_lead_id into dup_target
    from leads where company_id = cid and is_potential_duplicate;
  if dup_target is null then raise exception 'FAIL: flagged duplicate has null duplicate_of_lead_id'; end if;

  -- RAG: chunk_count integrity + embedding dimensionality
  select count(*) into n from documents d
   where d.company_id = cid
     and d.chunk_count <> (select count(*) from document_chunks c where c.document_id = d.id);
  if n <> 0 then raise exception 'FAIL: % document(s) have chunk_count mismatch', n; end if;
  select count(*) into n from document_chunks
   where company_id = cid and (embedding is null or vector_dims(embedding) <> 1536);
  if n <> 0 then raise exception 'FAIL: % chunk(s) missing/ wrong-dim embedding', n; end if;

  -- call lifecycle
  select count(*) into n from calls where company_id = cid and call_status = 'completed';
  if n < 1 then raise exception 'FAIL: expected >=1 completed call, found %', n; end if;
  select count(*) into n from transcripts where company_id = cid;
  if n < 1 then raise exception 'FAIL: expected >=1 transcript, found %', n; end if;
  select count(*) into n from recordings
   where company_id = cid and storage_path like (cid::text || '/recordings/%');
  if n < 1 then raise exception 'FAIL: recording path not tenant-prefixed'; end if;

  -- identity claims carry the tenant
  select count(*) into n from auth.users
   where id in ('a0000000-0000-0000-0000-000000000001',
                'a0000000-0000-0000-0000-000000000002',
                'a0000000-0000-0000-0000-000000000003')
     and raw_app_meta_data->>'company_id' = cid::text;
  if n <> 3 then raise exception 'FAIL: expected 3 users with tenant claim, found %', n; end if;

  -- cost + audit
  select count(*) into n from usage_logs where company_id = cid;
  if n < 3 then raise exception 'FAIL: expected >=3 usage_logs, found %', n; end if;
  select count(*) into n from audit_logs where company_id = cid and action = 'seed.load';
  if n < 1 then raise exception 'FAIL: missing seed.load audit marker'; end if;

  raise notice 'ALL M0-5 SEED ASSERTIONS PASSED';
end $$;

\echo '== M0-5 verification complete =='
