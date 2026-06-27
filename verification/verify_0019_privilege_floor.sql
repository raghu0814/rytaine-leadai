\set ON_ERROR_STOP on
\echo '================ 0019 PRIVILEGE-FLOOR VERIFICATION ================'
\echo '--- effective grant surface (service_role / authenticated; anon shown if any) ---'
select table_name, grantee,
       string_agg(privilege_type, ', ' order by privilege_type) as privileges
from information_schema.role_table_grants
where table_schema = 'public'
  and table_name in (
    'companies','users','prompts','knowledge_bases','agent_configs','leads',
    'lead_notes','call_schedules','calls','transcripts','recordings','messages',
    'documents','document_chunks','usage_logs','audit_logs','lead_events')
  and grantee in ('anon','authenticated','service_role','PUBLIC')
group by table_name, grantee
order by table_name, grantee;

do $$
declare
  app_tables text[] := array[
    'companies','users','prompts','knowledge_bases','agent_configs','leads',
    'lead_notes','call_schedules','calls','transcripts','recordings','messages',
    'documents','document_chunks','usage_logs','audit_logs','lead_events'];
  t   text;
  r   text;
  bad int;
  m   text;
begin
  -- (1) TRUNCATE must be ABSENT for all three roles on every application table.
  foreach t in array app_tables loop
    foreach r in array array['anon','authenticated','service_role'] loop
      if has_table_privilege(r, format('public.%I', t), 'TRUNCATE') then
        raise exception 'FAIL: % holds TRUNCATE on public.% (must be absent)', r, t;
      end if;
    end loop;
  end loop;

  -- (2) anon and PUBLIC must hold NO privilege on any application table.
  select count(*) into bad
  from information_schema.role_table_grants
  where table_schema = 'public'
    and table_name = any(app_tables)
    and grantee in ('anon','PUBLIC');
  if bad > 0 then
    raise exception 'FAIL: anon/PUBLIC hold % grant(s) on application tables (must be 0)', bad;
  end if;

  -- (3) EXACT surface for service_role and authenticated: actual must equal intent.
  for m in
    with expected(tbl, grantee, privs) as (
      values
        -- service_role: operational tables -> full DML
        ('companies','service_role','DELETE,INSERT,SELECT,UPDATE'),
        ('users','service_role','DELETE,INSERT,SELECT,UPDATE'),
        ('prompts','service_role','DELETE,INSERT,SELECT,UPDATE'),
        ('knowledge_bases','service_role','DELETE,INSERT,SELECT,UPDATE'),
        ('agent_configs','service_role','DELETE,INSERT,SELECT,UPDATE'),
        ('leads','service_role','DELETE,INSERT,SELECT,UPDATE'),
        ('lead_notes','service_role','DELETE,INSERT,SELECT,UPDATE'),
        ('call_schedules','service_role','DELETE,INSERT,SELECT,UPDATE'),
        ('calls','service_role','DELETE,INSERT,SELECT,UPDATE'),
        ('transcripts','service_role','DELETE,INSERT,SELECT,UPDATE'),
        ('recordings','service_role','DELETE,INSERT,SELECT,UPDATE'),
        ('messages','service_role','DELETE,INSERT,SELECT,UPDATE'),
        ('documents','service_role','DELETE,INSERT,SELECT,UPDATE'),
        ('document_chunks','service_role','DELETE,INSERT,SELECT,UPDATE'),
        -- service_role: immutable / append-only -> SELECT + INSERT only
        ('usage_logs','service_role','INSERT,SELECT'),
        ('audit_logs','service_role','INSERT,SELECT'),
        ('lead_events','service_role','INSERT,SELECT'),
        -- authenticated: policy-mirrored least privilege
        ('users','authenticated','DELETE,INSERT,SELECT,UPDATE'),
        ('prompts','authenticated','DELETE,INSERT,SELECT,UPDATE'),
        ('knowledge_bases','authenticated','DELETE,INSERT,SELECT,UPDATE'),
        ('agent_configs','authenticated','DELETE,INSERT,SELECT,UPDATE'),
        ('leads','authenticated','DELETE,INSERT,SELECT,UPDATE'),
        ('lead_notes','authenticated','DELETE,INSERT,SELECT,UPDATE'),
        ('call_schedules','authenticated','DELETE,INSERT,SELECT,UPDATE'),
        ('documents','authenticated','DELETE,INSERT,SELECT,UPDATE'),
        ('companies','authenticated','SELECT,UPDATE'),
        ('messages','authenticated','INSERT,SELECT'),
        ('calls','authenticated','SELECT'),
        ('transcripts','authenticated','SELECT'),
        ('recordings','authenticated','SELECT'),
        ('document_chunks','authenticated','SELECT'),
        ('usage_logs','authenticated','SELECT'),
        ('audit_logs','authenticated','SELECT'),
        ('lead_events','authenticated','SELECT')
    ),
    actual as (
      select table_name as tbl, grantee,
             string_agg(privilege_type, ',' order by privilege_type) as privs
      from information_schema.role_table_grants
      where table_schema = 'public'
        and table_name = any(app_tables)
        and grantee in ('service_role','authenticated')
      group by table_name, grantee
    )
    select format('%s/%s expected=[%s] actual=[%s]',
                  coalesce(e.tbl, a.tbl), coalesce(e.grantee, a.grantee),
                  coalesce(e.privs, '<none>'), coalesce(a.privs, '<none>'))
    from expected e
    full outer join actual a on a.tbl = e.tbl and a.grantee = e.grantee
    where coalesce(e.privs,'') <> coalesce(a.privs,'')
  loop
    raise exception 'FAIL: surface mismatch: %', m;
  end loop;

  raise notice '0019 PRIVILEGE-FLOOR VERIFICATION PASSED: all 17 application tables at intended least privilege; no TRUNCATE for anon/authenticated/service_role; anon and PUBLIC hold nothing.';
end $$;
