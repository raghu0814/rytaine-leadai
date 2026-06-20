-- =====================================================================
-- verify_m0_4.sql  —  M0-4 post-apply verification
-- Prints a report, then HARD-ASSERTS (raises on mismatch). Safe to re-run.
-- Run as a privileged role after applying 0014-0016.
-- =====================================================================
\echo '================ M0-4 VERIFICATION ================'

-- ---- 1. Helper functions present + STABLE ----
\echo '--- helper functions ---'
select p.proname,
       case p.provolatile when 's' then 'STABLE' when 'i' then 'IMMUTABLE' else 'VOLATILE' end as volatility
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname='public' and p.proname in ('current_company_id','current_user_role')
order by p.proname;

-- ---- 2. RLS + FORCE on every public table ----
\echo '--- RLS / FORCE per public table ---'
select c.relname as table_name, c.relrowsecurity as rls_enabled, c.relforcerowsecurity as rls_forced
from pg_class c join pg_namespace n on n.oid=c.relnamespace
where n.nspname='public' and c.relkind='r'
order by c.relname;

-- ---- 3. Policy count per table ----
\echo '--- policies per public table ---'
select tablename, count(*) as policies
from pg_policies where schemaname='public'
group by tablename order by tablename;

-- ---- 4. Storage buckets ----
\echo '--- storage buckets ---'
select id, public from storage.buckets where id in ('documents','recordings') order by id;

\echo '--- storage.objects policies ---'
select policyname, cmd from pg_policies
where schemaname='storage' and tablename='objects' order by policyname;

-- ===================== HARD ASSERTS =====================
do $$
declare
  n_helpers     int;
  n_unprotected int;
  n_buckets     int;
  n_public_bkt  int;
  n_store_pol   int;
  missing       text;
begin
  -- 1. both helpers exist
  select count(*) into n_helpers
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname in ('current_company_id','current_user_role');
  if n_helpers <> 2 then
    raise exception 'FAIL: expected 2 helper functions, found %', n_helpers;
  end if;

  -- 2. no public table without RLS+FORCE
  select count(*) into n_unprotected
  from pg_class c join pg_namespace n on n.oid=c.relnamespace
  where n.nspname='public' and c.relkind='r'
    and not (c.relrowsecurity and c.relforcerowsecurity);
  if n_unprotected <> 0 then
    select string_agg(c.relname, ', ') into missing
    from pg_class c join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='public' and c.relkind='r'
      and not (c.relrowsecurity and c.relforcerowsecurity);
    raise exception 'FAIL: % public table(s) missing RLS+FORCE: %', n_unprotected, missing;
  end if;

  -- 3. every public table has at least one policy (no silently-locked table)
  select string_agg(c.relname, ', ') into missing
  from pg_class c join pg_namespace n on n.oid=c.relnamespace
  where n.nspname='public' and c.relkind='r'
    and not exists (select 1 from pg_policies pp where pp.schemaname='public' and pp.tablename=c.relname);
  if missing is not null then
    raise exception 'FAIL: public table(s) with RLS but no policy: %', missing;
  end if;

  -- 4. buckets exist and are private
  select count(*) into n_buckets from storage.buckets where id in ('documents','recordings');
  if n_buckets <> 2 then
    raise exception 'FAIL: expected 2 storage buckets, found %', n_buckets;
  end if;
  select count(*) into n_public_bkt from storage.buckets where id in ('documents','recordings') and public;
  if n_public_bkt <> 0 then
    raise exception 'FAIL: % target bucket(s) are PUBLIC; must be private', n_public_bkt;
  end if;

  -- 5. storage.objects has tenant policies
  select count(*) into n_store_pol from pg_policies where schemaname='storage' and tablename='objects';
  if n_store_pol < 5 then
    raise exception 'FAIL: expected >=5 storage.objects policies, found %', n_store_pol;
  end if;

  raise notice 'PASS: M0-4 verification — 2 helpers, all public tables RLS+FORCE+policied, 2 private buckets, % storage policies.', n_store_pol;
end $$;
\echo '================ END VERIFICATION ================'
