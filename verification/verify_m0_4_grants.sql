-- =====================================================================
-- verify_m0_4_grants.sql  —  M0-4-R post-apply verification
-- Prints the effective table-grant matrix, then HARD-ASSERTS (raises on
-- mismatch) that:
--   (a) every REQUIRED grant is present  -> fixes "permission denied",
--   (b) no EXTRA grant exists            -> least privilege (authenticated)
--                                           + append-only preserved
--                                           (service_role has no U/D on the
--                                            two immutable tables),
--   (c) all 16 public tables still have RLS + FORCE -> RLS not weakened.
-- Authoritative via has_table_privilege(). Safe to re-run.
-- Run as a privileged role after applying 0017 (on top of 0014-0016).
-- =====================================================================
\echo '================ M0-4-R GRANTS VERIFICATION ================'

-- ---- reusable inputs: the 16 tenant tables + the two API roles ----
-- (defined inline in each query/assert below)

-- ---- 1. Effective grant matrix per (role, table) ----
\echo '--- effective DML grants: authenticated & service_role ---'
select r.role_name,
       t.table_name,
       concat_ws(', ',
         case when has_table_privilege(r.role_name,'public.'||t.table_name,'SELECT') then 'SELECT' end,
         case when has_table_privilege(r.role_name,'public.'||t.table_name,'INSERT') then 'INSERT' end,
         case when has_table_privilege(r.role_name,'public.'||t.table_name,'UPDATE') then 'UPDATE' end,
         case when has_table_privilege(r.role_name,'public.'||t.table_name,'DELETE') then 'DELETE' end
       ) as granted
from (values ('authenticated'),('service_role')) r(role_name)
cross join (values
  ('companies'),('users'),('prompts'),('knowledge_bases'),('agent_configs'),
  ('leads'),('lead_notes'),('call_schedules'),('calls'),('transcripts'),
  ('recordings'),('messages'),('documents'),('document_chunks'),
  ('usage_logs'),('audit_logs')) t(table_name)
order by r.role_name, t.table_name;

-- ---- 2. Append-only spotlight: nobody may UPDATE/DELETE the immutable tables ----
\echo '--- append-only check: usage_logs / audit_logs UPDATE+DELETE must be f for both roles ---'
select r.role_name, t.table_name,
       has_table_privilege(r.role_name,'public.'||t.table_name,'UPDATE') as can_update,
       has_table_privilege(r.role_name,'public.'||t.table_name,'DELETE') as can_delete
from (values ('authenticated'),('service_role')) r(role_name)
cross join (values ('usage_logs'),('audit_logs')) t(table_name)
order by r.role_name, t.table_name;

-- ---- 3. RLS + FORCE still on every public table ----
\echo '--- RLS / FORCE per public table (must remain t/t for all 16) ---'
select c.relname as table_name, c.relrowsecurity as rls_enabled, c.relforcerowsecurity as rls_forced
from pg_class c join pg_namespace n on n.oid=c.relnamespace
where n.nspname='public' and c.relkind='r'
order by c.relname;

-- ===================== HARD ASSERTS =====================
do $$
declare
  n_missing int;
  n_extra   int;
  n_unforced int;
  n_usage   int;
  detail    text;
begin
  -- expected grant set (role_name, table_name, priv)
  create temporary table _expected on commit drop as
  with priv(p) as (values ('SELECT'),('INSERT'),('UPDATE'),('DELETE'))
  -- authenticated: full DML
  select 'authenticated'::text as role_name, t as table_name, p.p as priv
    from (values ('users'),('prompts'),('knowledge_bases'),('agent_configs'),
                 ('leads'),('lead_notes'),('call_schedules'),('documents')) x(t)
    cross join priv p
  union all
  -- authenticated: companies select+update
  select 'authenticated','companies', p from (values ('SELECT'),('UPDATE')) y(p)
  union all
  -- authenticated: messages select+insert
  select 'authenticated','messages', p from (values ('SELECT'),('INSERT')) y(p)
  union all
  -- authenticated: select-only tables
  select 'authenticated', t, 'SELECT'
    from (values ('calls'),('transcripts'),('recordings'),('document_chunks'),
                 ('usage_logs'),('audit_logs')) x(t)
  union all
  -- service_role: full DML on operational tables
  select 'service_role', t, p.p
    from (values ('companies'),('users'),('prompts'),('knowledge_bases'),('agent_configs'),
                 ('leads'),('lead_notes'),('call_schedules'),('calls'),('transcripts'),
                 ('recordings'),('messages'),('documents'),('document_chunks')) x(t)
    cross join priv p
  union all
  -- service_role: insert+select only on immutable tables (append-only)
  select 'service_role', t, p
    from (values ('usage_logs'),('audit_logs')) x(t)
    cross join (values ('SELECT'),('INSERT')) y(p);

  -- universe of all candidate cells (2 roles x 16 tables x 4 privs)
  create temporary table _actual on commit drop as
  select r.role_name, t.table_name, p.p as priv,
         has_table_privilege(r.role_name,'public.'||t.table_name,p.p) as granted
  from (values ('authenticated'),('service_role')) r(role_name)
  cross join (values
    ('companies'),('users'),('prompts'),('knowledge_bases'),('agent_configs'),
    ('leads'),('lead_notes'),('call_schedules'),('calls'),('transcripts'),
    ('recordings'),('messages'),('documents'),('document_chunks'),
    ('usage_logs'),('audit_logs')) t(table_name)
  cross join (values ('SELECT'),('INSERT'),('UPDATE'),('DELETE')) p(p);

  -- (a) MISSING: expected grant that is not effective
  select count(*) into n_missing
  from _expected e
  where not has_table_privilege(e.role_name,'public.'||e.table_name,e.priv);
  if n_missing > 0 then
    select string_agg(e.role_name||'/'||e.table_name||'/'||e.priv, ', ' order by e.role_name,e.table_name,e.priv)
      into detail
    from _expected e
    where not has_table_privilege(e.role_name,'public.'||e.table_name,e.priv);
    raise exception 'FAIL: % required grant(s) MISSING: %', n_missing, detail;
  end if;

  -- (b) EXTRA: effective grant that is not in the expected set
  select count(*) into n_extra
  from _actual a
  where a.granted
    and not exists (select 1 from _expected e
                    where e.role_name=a.role_name and e.table_name=a.table_name and e.priv=a.priv);
  if n_extra > 0 then
    select string_agg(a.role_name||'/'||a.table_name||'/'||a.priv, ', ' order by a.role_name,a.table_name,a.priv)
      into detail
    from _actual a
    where a.granted
      and not exists (select 1 from _expected e
                      where e.role_name=a.role_name and e.table_name=a.table_name and e.priv=a.priv);
    raise exception 'FAIL: % EXTRA grant(s) beyond least-privilege/append-only: %', n_extra, detail;
  end if;

  -- (c) RLS + FORCE intact on all 16 public tables
  select count(*) into n_unforced
  from pg_class c join pg_namespace n on n.oid=c.relnamespace
  where n.nspname='public' and c.relkind='r'
    and not (c.relrowsecurity and c.relforcerowsecurity);
  if n_unforced <> 0 then
    raise exception 'FAIL: % public table(s) lost RLS+FORCE', n_unforced;
  end if;

  -- schema usage present for both API roles
  select count(*) into n_usage
  from (values ('authenticated'),('service_role')) r(role_name)
  where has_schema_privilege(r.role_name,'public','USAGE');
  if n_usage <> 2 then
    raise exception 'FAIL: schema USAGE on public missing for an API role (found %/2)', n_usage;
  end if;

  raise notice 'PASS: M0-4-R grants — all required grants present, 0 extra (append-only preserved), RLS+FORCE intact on 16 tables, schema USAGE present.';
end $$;
\echo '================ END GRANTS VERIFICATION ================'
