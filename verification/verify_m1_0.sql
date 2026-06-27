-- =====================================================================
-- verify_m1_0.sql  —  M1.0 (lead_events / 0018) post-apply verification
-- Prints the effective state, then HARD-ASSERTS (raises on mismatch):
--   (a) grant surface is exactly service_role{SELECT,INSERT} /
--       authenticated{SELECT} / anon{none}  -> least privilege,
--   (b) append-only: NOBODY may UPDATE/DELETE/TRUNCATE lead_events
--       (service_role included; grants are the only DB-level control),
--   (c) RLS enabled + forced; exactly the admin-only SELECT policy; NO triggers,
--   (d) FK is ON DELETE RESTRICT; idempotency UNIQUE + 3 CHECKs + both indexes
--       (incl. the partial) present,
--   (e) lead_events is forced AND every M0 RLS table is STILL forced
--       -> M0 guarantees preserved while a new RLS table is added
--          (forward-compatible; no brittle total-count assertion).
-- Authoritative via has_table_privilege() + catalog. Safe to re-run.
-- Run as a privileged role after applying 0018 (on top of 0001-0017).
-- =====================================================================
\echo '================ M1.0 lead_events VERIFICATION ================'

\echo '--- grant matrix (service_role / authenticated / anon) ---'
select r.role_name,
       concat_ws(', ',
         case when has_table_privilege(r.role_name,'public.lead_events','SELECT')   then 'SELECT'   end,
         case when has_table_privilege(r.role_name,'public.lead_events','INSERT')   then 'INSERT'   end,
         case when has_table_privilege(r.role_name,'public.lead_events','UPDATE')   then 'UPDATE'   end,
         case when has_table_privilege(r.role_name,'public.lead_events','DELETE')   then 'DELETE'   end,
         case when has_table_privilege(r.role_name,'public.lead_events','TRUNCATE') then 'TRUNCATE' end
       ) as granted
from (values ('service_role'),('authenticated'),('anon')) r(role_name)
order by r.role_name;

\echo '--- RLS / policy / triggers / FK ---'
select c.relrowsecurity as rls_enabled, c.relforcerowsecurity as rls_forced
from pg_class c where c.oid='public.lead_events'::regclass;
select policyname, cmd, roles from pg_policies where tablename='lead_events';
select (select count(*) from pg_trigger t join pg_class c on c.oid=t.tgrelid
        where c.relname='lead_events' and not t.tgisinternal) as user_triggers;
select conname, confdeltype from pg_constraint
 where conrelid='public.lead_events'::regclass and contype='f';

\echo '--- forced-RLS public table count (informational; 17 post-0018) ---'
select count(*) as forced_rls_public_tables
from pg_class c join pg_namespace n on n.oid=c.relnamespace
where n.nspname='public' and c.relkind='r' and c.relrowsecurity and c.relforcerowsecurity;

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
  if to_regclass('public.lead_events') is null then
    raise exception 'FAIL: lead_events does not exist';
  end if;

  -- (a) grant surface exact
  if not (has_table_privilege('service_role','public.lead_events','SELECT')
          and has_table_privilege('service_role','public.lead_events','INSERT')) then
    raise exception 'FAIL: service_role missing SELECT/INSERT';
  end if;
  if not has_table_privilege('authenticated','public.lead_events','SELECT') then
    raise exception 'FAIL: authenticated missing SELECT';
  end if;
  if has_table_privilege('authenticated','public.lead_events','INSERT')
     or has_table_privilege('authenticated','public.lead_events','UPDATE')
     or has_table_privilege('authenticated','public.lead_events','DELETE') then
    raise exception 'FAIL: authenticated has a write privilege (must be SELECT only)';
  end if;
  if has_table_privilege('anon','public.lead_events','SELECT')
     or has_table_privilege('anon','public.lead_events','INSERT') then
    raise exception 'FAIL: anon has a privilege (must be none)';
  end if;

  -- (b) append-only: nobody may UPDATE/DELETE/TRUNCATE (service_role included)
  foreach t in array array['service_role','authenticated','anon'] loop
    if has_table_privilege(t,'public.lead_events','UPDATE')
       or has_table_privilege(t,'public.lead_events','DELETE')
       or has_table_privilege(t,'public.lead_events','TRUNCATE') then
      raise exception 'FAIL: % has UPDATE/DELETE/TRUNCATE on lead_events (append-only breached)', t;
    end if;
  end loop;

  -- (c) RLS + forced; exactly one admin SELECT policy; no triggers
  if not (select relrowsecurity and relforcerowsecurity
            from pg_class where oid='public.lead_events'::regclass) then
    raise exception 'FAIL: RLS not enabled+forced on lead_events';
  end if;
  select count(*) into n from pg_policies where tablename='lead_events';
  if n <> 1 then raise exception 'FAIL: expected exactly 1 policy, found %', n; end if;
  if not exists (select 1 from pg_policies
                  where tablename='lead_events' and policyname='lead_events_select_admin'
                    and cmd='SELECT' and roles = '{authenticated}') then
    raise exception 'FAIL: lead_events_select_admin (SELECT, authenticated) missing/wrong';
  end if;
  select count(*) into n from pg_trigger tg join pg_class c on c.oid=tg.tgrelid
    where c.relname='lead_events' and not tg.tgisinternal;
  if n <> 0 then raise exception 'FAIL: lead_events has % user trigger(s); M1.0 is grant-based', n; end if;

  -- (d) FK RESTRICT; UNIQUE gate; 3 CHECKs; both indexes incl. partial
  if (select confdeltype from pg_constraint
        where conrelid='public.lead_events'::regclass and contype='f') <> 'r' then
    raise exception 'FAIL: company_id FK is not ON DELETE RESTRICT';
  end if;
  if not exists (select 1 from pg_constraint
                  where conname='lead_events_company_idem_key'
                    and conrelid='public.lead_events'::regclass and contype='u') then
    raise exception 'FAIL: UNIQUE(company_id, idempotency_key) missing';
  end if;
  select count(*) into n from pg_constraint
    where conrelid='public.lead_events'::regclass and contype='c';
  if n <> 3 then raise exception 'FAIL: expected 3 CHECK constraints, found %', n; end if;
  if not exists (select 1 from pg_indexes where indexname='idx_lead_events_company_time') then
    raise exception 'FAIL: idx_lead_events_company_time missing';
  end if;
  if not exists (select 1 from pg_indexes where indexname='idx_lead_events_company_source_ext'
                   and indexdef like '%WHERE (external_lead_id IS NOT NULL)%') then
    raise exception 'FAIL: partial idx_lead_events_company_source_ext missing/non-partial';
  end if;

  -- (e) lead_events forced AND every M0 RLS table still forced (M0 preserved)
  if not (select relrowsecurity and relforcerowsecurity
            from pg_class where oid='public.lead_events'::regclass) then
    raise exception 'FAIL: lead_events not in the forced-RLS set';
  end if;
  foreach t in array m0 loop
    if not (select coalesce(bool_and(c.relrowsecurity and c.relforcerowsecurity), false)
              from pg_class c join pg_namespace ns on ns.oid=c.relnamespace
              where ns.nspname='public' and c.relname=t and c.relkind='r') then
      raise exception 'FAIL: M0 RLS guarantee lost on table %', t;
    end if;
  end loop;

  raise notice 'M1.0 VERIFICATION PASSED: lead_events contract intact; M0 RLS set preserved.';
end $$;
