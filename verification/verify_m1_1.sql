-- =====================================================================
-- verify_m1_1.sql  —  M1.1 (source_connectors / 0020) post-apply verification
-- Prints the effective state, then HARD-ASSERTS (raises on mismatch):
--   (a) grant surface is exactly service_role{full DML} /
--       authenticated{SELECT only} / anon{none},
--   (b) D-CONN-SEC Option A secret hiding: authenticated CANNOT read the secret
--       column (column privilege), CAN read a non-secret column, service_role
--       CAN read secret,
--   (c) nobody holds TRUNCATE on source_connectors,
--   (d) RLS enabled+forced; exactly the admin-only SELECT policy; exactly one
--       (updated_at) user trigger,
--   (e) FK is ON DELETE CASCADE; 4 CHECKs; company index + both PARTIAL-UNIQUE
--       routing indexes present,
--   (f) NO REGRESSION: lead_events (0018) still append-only + forced, and every
--       M0 RLS table is STILL forced (named set, not a brittle total count) ->
--       M0-9 floor + M1.0 guarantees preserved while a new table is added.
-- Authoritative via has_table_privilege() / has_column_privilege() + catalog.
-- Safe to re-run. Run as a privileged role after applying 0020 (on 0001-0019).
-- =====================================================================
\echo '================ M1.1 source_connectors VERIFICATION ================'

\echo '--- table grant matrix (service_role / authenticated / anon) ---'
select r.role_name,
       concat_ws(', ',
         case when has_table_privilege(r.role_name,'public.source_connectors','SELECT')   then 'SELECT'   end,
         case when has_table_privilege(r.role_name,'public.source_connectors','INSERT')   then 'INSERT'   end,
         case when has_table_privilege(r.role_name,'public.source_connectors','UPDATE')   then 'UPDATE'   end,
         case when has_table_privilege(r.role_name,'public.source_connectors','DELETE')   then 'DELETE'   end,
         case when has_table_privilege(r.role_name,'public.source_connectors','TRUNCATE') then 'TRUNCATE' end
       ) as granted
from (values ('service_role'),('authenticated'),('anon')) r(role_name)
order by r.role_name;

\echo '--- secret-column readability (must be: authenticated=f, service_role=t) ---'
select has_column_privilege('authenticated','public.source_connectors','secret','SELECT') as auth_reads_secret,
       has_column_privilege('authenticated','public.source_connectors','field_map','SELECT') as auth_reads_field_map,
       has_column_privilege('service_role','public.source_connectors','secret','SELECT')  as svc_reads_secret;

\echo '--- RLS / policy / trigger / FK ---'
select c.relrowsecurity as rls_enabled, c.relforcerowsecurity as rls_forced
from pg_class c where c.oid='public.source_connectors'::regclass;
select policyname, cmd, roles from pg_policies where tablename='source_connectors';
select (select count(*) from pg_trigger t join pg_class c on c.oid=t.tgrelid
        where c.relname='source_connectors' and not t.tgisinternal) as user_triggers;
select conname, confdeltype from pg_constraint
 where conrelid='public.source_connectors'::regclass and contype='f';

-- ===================== HARD ASSERTS =====================
do $$
declare
  m0 text[] := array[
    'companies','users','prompts','knowledge_bases','agent_configs','leads',
    'lead_notes','call_schedules','calls','transcripts','recordings','messages',
    'documents','document_chunks','usage_logs','audit_logs'];
  t text;
  n int;
begin
  -- table exists
  if to_regclass('public.source_connectors') is null then
    raise exception 'FAIL: source_connectors does not exist';
  end if;

  -- (a) table grant surface exact
  if not (has_table_privilege('service_role','public.source_connectors','SELECT')
          and has_table_privilege('service_role','public.source_connectors','INSERT')
          and has_table_privilege('service_role','public.source_connectors','UPDATE')
          and has_table_privilege('service_role','public.source_connectors','DELETE')) then
    raise exception 'FAIL: service_role missing full DML';
  end if;
  if has_table_privilege('authenticated','public.source_connectors','SELECT') then
    raise exception 'FAIL: authenticated holds TABLE-LEVEL SELECT (must be column-level only)';
  end if;
  if has_table_privilege('authenticated','public.source_connectors','INSERT')
     or has_table_privilege('authenticated','public.source_connectors','UPDATE')
     or has_table_privilege('authenticated','public.source_connectors','DELETE') then
    raise exception 'FAIL: authenticated has a write privilege (must be SELECT only)';
  end if;
  if has_table_privilege('anon','public.source_connectors','SELECT')
     or has_table_privilege('anon','public.source_connectors','INSERT') then
    raise exception 'FAIL: anon has a privilege (must be none)';
  end if;

  -- (b) secret hiding (D-CONN-SEC Option A)
  if has_column_privilege('authenticated','public.source_connectors','secret','SELECT') then
    raise exception 'FAIL: authenticated can read the secret column (must be hidden)';
  end if;
  if not has_column_privilege('authenticated','public.source_connectors','field_map','SELECT') then
    raise exception 'FAIL: authenticated cannot read field_map (non-secret must be readable)';
  end if;
  if not has_column_privilege('service_role','public.source_connectors','secret','SELECT') then
    raise exception 'FAIL: service_role cannot read secret';
  end if;

  -- (c) nobody holds TRUNCATE
  foreach t in array array['service_role','authenticated','anon'] loop
    if has_table_privilege(t,'public.source_connectors','TRUNCATE') then
      raise exception 'FAIL: % holds TRUNCATE on source_connectors', t;
    end if;
  end loop;

  -- (d) RLS + forced; exactly one admin SELECT policy; exactly one user trigger
  if not (select relrowsecurity and relforcerowsecurity
            from pg_class where oid='public.source_connectors'::regclass) then
    raise exception 'FAIL: RLS not enabled+forced on source_connectors';
  end if;
  select count(*) into n from pg_policies where tablename='source_connectors';
  if n <> 1 then raise exception 'FAIL: expected exactly 1 policy, found %', n; end if;
  if not exists (select 1 from pg_policies
                  where tablename='source_connectors' and policyname='source_connectors_select_admin'
                    and cmd='SELECT' and roles = '{authenticated}') then
    raise exception 'FAIL: source_connectors_select_admin (SELECT, authenticated) missing/wrong';
  end if;
  select count(*) into n from pg_trigger tg join pg_class c on c.oid=tg.tgrelid
    where c.relname='source_connectors' and not tg.tgisinternal;
  if n <> 1 then raise exception 'FAIL: expected exactly 1 user trigger, found %', n; end if;

  -- (e) FK CASCADE; 4 CHECKs; indexes
  if (select confdeltype from pg_constraint
        where conrelid='public.source_connectors'::regclass and contype='f') <> 'c' then
    raise exception 'FAIL: company_id FK is not ON DELETE CASCADE';
  end if;
  select count(*) into n from pg_constraint
    where conrelid='public.source_connectors'::regclass and contype='c';
  if n <> 4 then raise exception 'FAIL: expected 4 CHECK constraints, found %', n; end if;
  if not exists (select 1 from pg_indexes where indexname='idx_source_connectors_company') then
    raise exception 'FAIL: idx_source_connectors_company missing';
  end if;
  if not exists (select 1 from pg_indexes where indexname='uq_source_connectors_meta_page'
                   and indexdef like '%UNIQUE%'
                   and indexdef like '%WHERE (meta_page_id IS NOT NULL)%') then
    raise exception 'FAIL: uq_source_connectors_meta_page missing/non-partial-unique';
  end if;
  if not exists (select 1 from pg_indexes where indexname='uq_source_connectors_google_form'
                   and indexdef like '%UNIQUE%'
                   and indexdef like '%WHERE (google_form_id IS NOT NULL)%') then
    raise exception 'FAIL: uq_source_connectors_google_form missing/non-partial-unique';
  end if;

  -- (f) NO REGRESSION: lead_events append-only + forced; M0 RLS set still forced
  if not (select relrowsecurity and relforcerowsecurity
            from pg_class where oid='public.lead_events'::regclass) then
    raise exception 'FAIL: lead_events lost RLS enable+force';
  end if;
  foreach t in array array['service_role','authenticated','anon'] loop
    if has_table_privilege(t,'public.lead_events','UPDATE')
       or has_table_privilege(t,'public.lead_events','DELETE')
       or has_table_privilege(t,'public.lead_events','TRUNCATE') then
      raise exception 'FAIL: % gained UPDATE/DELETE/TRUNCATE on lead_events (M1.0 append-only breached)', t;
    end if;
  end loop;
  foreach t in array m0 loop
    if not (select coalesce(bool_and(c.relrowsecurity and c.relforcerowsecurity), false)
              from pg_class c join pg_namespace ns on ns.oid=c.relnamespace
              where ns.nspname='public' and c.relname=t and c.relkind='r') then
      raise exception 'FAIL: M0 RLS guarantee lost on table %', t;
    end if;
  end loop;

  raise notice 'M1.1 VERIFICATION PASSED: source_connectors contract intact (secret hidden); M1.0 + M0 RLS set preserved.';
end $$;
