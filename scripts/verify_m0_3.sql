-- =====================================================================
-- scripts/verify_m0_3.sql
-- Run AFTER applying 0001-0013 against a fresh DB.
--   psql "$DIRECT_URL" -v ON_ERROR_STOP=1 -f scripts/verify_m0_3.sql
-- Prints a readable report, then hard-asserts the load-bearing invariants
-- (raises and aborts on any mismatch). Schema correctness only — RLS and
-- cross-tenant behaviour are verified in M0-4 / M0-6.
-- =====================================================================
\pset pager off

\echo '== Extensions (expect pgcrypto, vector) =='
select extname from pg_extension where extname in ('pgcrypto','vector') order by extname;

\echo '== Public tables (expect 16) =='
select count(*) as table_count
from information_schema.tables
where table_schema = 'public' and table_type = 'BASE TABLE';

select table_name
from information_schema.tables
where table_schema = 'public' and table_type = 'BASE TABLE'
order by table_name;

\echo '== Enum types (expect 26) =='
select count(*) as enum_count
from pg_type t join pg_namespace n on n.oid = t.typnamespace
where t.typtype = 'e' and n.nspname = 'public';

\echo '== Hard-dedup unique on leads (company_id, source, external_lead_id) =='
select conname
from pg_constraint
where conrelid = 'public.leads'::regclass and contype = 'u'
  and pg_get_constraintdef(oid) ilike '%(company_id, source, external_lead_id)%';

\echo '== Soft-dedup columns on leads =='
select column_name, data_type, is_nullable, column_default
from information_schema.columns
where table_schema='public' and table_name='leads'
  and column_name in ('is_potential_duplicate','duplicate_of_lead_id')
order by column_name;

\echo '== updated_at triggers (expect 10) =='
select count(*) as updated_at_triggers
from pg_trigger
where not tgisinternal
  and tgfoid = 'public.set_updated_at'::regproc;

\echo '== Soft-dedup trigger on leads (expect trg_leads_flag_duplicate, BEFORE INSERT) =='
select tgname
from pg_trigger
where not tgisinternal and tgrelid = 'public.leads'::regclass
  and tgfoid = 'public.flag_potential_duplicate_lead'::regproc;

\echo '== HNSW vector index on document_chunks =='
select indexname
from pg_indexes
where schemaname='public' and tablename='document_chunks'
  and indexdef ilike '%using hnsw%';

-- ---------------------------------------------------------------------
-- HARD ASSERTIONS (abort on mismatch)
-- ---------------------------------------------------------------------
do $$
declare
  v_tables  int;
  v_enums   int;
  v_upd      int;
  v_dedup_fn int;
  v_hnsw     int;
  v_hard_u   int;
begin
  select count(*) into v_tables
    from information_schema.tables
    where table_schema='public' and table_type='BASE TABLE';
  if v_tables <> 16 then
    raise exception 'M0-3 FAIL: expected 16 tables, found %', v_tables;
  end if;

  select count(*) into v_enums
    from pg_type t join pg_namespace n on n.oid=t.typnamespace
    where t.typtype='e' and n.nspname='public';
  if v_enums <> 26 then
    raise exception 'M0-3 FAIL: expected 26 enum types, found %', v_enums;
  end if;

  select count(*) into v_upd
    from pg_trigger
    where not tgisinternal and tgfoid='public.set_updated_at'::regproc;
  if v_upd <> 10 then
    raise exception 'M0-3 FAIL: expected 10 updated_at triggers, found %', v_upd;
  end if;

  select count(*) into v_dedup_fn
    from pg_trigger
    where not tgisinternal and tgrelid='public.leads'::regclass
      and tgfoid='public.flag_potential_duplicate_lead'::regproc;
  if v_dedup_fn <> 1 then
    raise exception 'M0-3 FAIL: soft-dedup trigger missing on leads (found %)', v_dedup_fn;
  end if;

  select count(*) into v_hnsw
    from pg_indexes
    where schemaname='public' and tablename='document_chunks'
      and indexdef ilike '%using hnsw%';
  if v_hnsw < 1 then
    raise exception 'M0-3 FAIL: HNSW index missing on document_chunks';
  end if;

  select count(*) into v_hard_u
    from pg_constraint
    where conrelid='public.leads'::regclass and contype='u'
      and pg_get_constraintdef(oid) ilike '%(company_id, source, external_lead_id)%';
  if v_hard_u < 1 then
    raise exception 'M0-3 FAIL: hard-dedup unique constraint missing on leads';
  end if;

  raise notice 'M0-3 PASS: 16 tables, 26 enums, 10 updated_at triggers, soft-dedup trigger, HNSW index, hard-dedup unique all present.';
end$$;
