-- =====================================================================
-- m0_4_rls.test.sql  —  M0-4 pgTAP suite
-- Proves helpers + RLS + storage policies under the REAL enforcement path:
-- each behavioral check runs as `authenticated` (or `service_role`) with the
-- JWT claims injected exactly as the FastAPI request layer will inject them.
--
-- Run wrapped in BEGIN/ROLLBACK (the runner does this) so the seed data and
-- the test-harness helper functions never persist.
-- Requires: pgtap extension; migrations 0014-0016 applied.
-- =====================================================================
begin;
select plan(24);

-- ---------- harness helpers (dropped on rollback) ----------
-- Run an operation as <db_role> with injected JWT claims, then auto-restore
-- role/claims at function exit. SECURITY INVOKER: caller is superuser and we
-- DROP privileges via `set local role`, so RLS applies as the impersonated role.
create function _claims(company uuid, claim_role text) returns void
language plpgsql as $$
begin
  perform set_config('request.jwt.claims',
    json_build_object('app_metadata',
      json_build_object('company_id', company, 'role', claim_role))::text, true);
end $$;

create function t_count(db_role name, company uuid, claim_role text, q text)
returns bigint language plpgsql as $$
declare res bigint;
begin
  perform _claims(company, claim_role);
  execute format('set local role %I', db_role);
  execute q into res;
  return res;
end $$;

create function t_rowcount(db_role name, company uuid, claim_role text, dml text)
returns bigint language plpgsql as $$
declare n bigint;
begin
  perform _claims(company, claim_role);
  execute format('set local role %I', db_role);
  execute dml;
  get diagnostics n = row_count;
  return n;
end $$;

create function t_blocked(db_role name, company uuid, claim_role text, dml text)
returns boolean language plpgsql as $$
begin
  perform _claims(company, claim_role);
  execute format('set local role %I', db_role);
  execute dml;
  return false;                      -- write succeeded => not blocked
exception
  when insufficient_privilege then    -- SQLSTATE 42501 (RLS / no policy)
    return true;
end $$;

-- ---------- seed two tenants (as superuser; bypasses RLS) ----------
\set A '''11111111-1111-1111-1111-111111111111'''
\set B '''22222222-2222-2222-2222-222222222222'''

insert into companies(id,name,slug) values
  (:A::uuid,'Tenant A','tenant-a'),
  (:B::uuid,'Tenant B','tenant-b');

insert into leads(company_id,source,phone) values
  (:A::uuid,'website','+919000000001'),
  (:A::uuid,'website','+919000000002'),
  (:B::uuid,'website','+919000000101'),
  (:B::uuid,'website','+919000000102'),
  (:B::uuid,'website','+919000000103');

insert into usage_logs(company_id,provider) values
  (:A::uuid,'elevenlabs'),
  (:B::uuid,'elevenlabs');

insert into knowledge_bases(id,company_id,name) values
  ('aa000000-0000-0000-0000-0000000000a1'::uuid,:A::uuid,'KB A'),
  ('bb000000-0000-0000-0000-0000000000b1'::uuid,:B::uuid,'KB B');
insert into documents(id,company_id,knowledge_base_id,title) values
  ('aa000000-0000-0000-0000-0000000000a2'::uuid,:A::uuid,'aa000000-0000-0000-0000-0000000000a1'::uuid,'Doc A'),
  ('bb000000-0000-0000-0000-0000000000b2'::uuid,:B::uuid,'bb000000-0000-0000-0000-0000000000b1'::uuid,'Doc B');
insert into document_chunks(company_id,document_id,knowledge_base_id,chunk_index,content) values
  (:A::uuid,'aa000000-0000-0000-0000-0000000000a2'::uuid,'aa000000-0000-0000-0000-0000000000a1'::uuid,0,'a-chunk-0'),
  (:A::uuid,'aa000000-0000-0000-0000-0000000000a2'::uuid,'aa000000-0000-0000-0000-0000000000a1'::uuid,1,'a-chunk-1'),
  (:B::uuid,'bb000000-0000-0000-0000-0000000000b2'::uuid,'bb000000-0000-0000-0000-0000000000b1'::uuid,0,'b-chunk-0');

insert into storage.objects(bucket_id,name) values
  ('documents','11111111-1111-1111-1111-111111111111/spec.pdf'),
  ('documents','22222222-2222-2222-2222-222222222222/spec.pdf'),
  ('recordings','11111111-1111-1111-1111-111111111111/call.mp3'),
  ('recordings','22222222-2222-2222-2222-222222222222/call.mp3');

-- ======================= STRUCTURAL =======================
select has_function('current_company_id', 'helper current_company_id() exists');
select has_function('current_user_role',  'helper current_user_role() exists');
select is((select count(*)::int from pg_tables where schemaname='public'),
          16, 'public schema has the 16 M0-3 tables');
select is((select count(*)::int from pg_class c join pg_namespace n on n.oid=c.relnamespace
           where n.nspname='public' and c.relkind='r'
             and c.relrowsecurity and c.relforcerowsecurity),
          16, 'all 16 public tables have RLS + FORCE');
select is((select count(*)::int from storage.buckets
           where id in ('documents','recordings') and public=false),
          2, 'documents + recordings buckets exist and are private');

-- ======================= READ ISOLATION =======================
select is(t_count('authenticated', :A::uuid, 'agent', 'select count(*) from leads'),
          2::bigint, 'Tenant A sees only its own 2 leads');
select is(t_count('authenticated', :A::uuid, 'agent', 'select count(*) from companies'),
          1::bigint, 'Tenant A sees only its own company row');
select is(t_count('authenticated', :B::uuid, 'agent', 'select count(*) from leads'),
          3::bigint, 'Tenant B sees only its own 3 leads');
select is(t_count('service_role', :A::uuid, 'admin', 'select count(*) from leads'),
          5::bigint, 'service_role bypasses RLS and sees all 5 leads');

-- ======================= WRITE / ROLE ISOLATION =======================
select is(t_rowcount('authenticated', :A::uuid, 'manager',
            'update leads set status=''contacted'' where company_id='||quote_literal(:A)),
          2::bigint, 'A manager can update its own 2 leads');
select is(t_rowcount('authenticated', :A::uuid, 'manager',
            'update leads set status=''x'' where company_id='||quote_literal(:B)),
          0::bigint, 'A manager cross-tenant UPDATE of B leads affects 0 rows');
select is(t_rowcount('authenticated', :A::uuid, 'manager',
            'delete from leads where company_id='||quote_literal(:B)),
          0::bigint, 'A manager cross-tenant DELETE of B leads affects 0 rows');
select is(t_blocked('authenticated', :A::uuid, 'manager',
            'insert into leads(company_id,source,phone) values ('||quote_literal(:A)||',''web'',''+919000009999'')'),
          false, 'A manager can INSERT a lead in its own tenant');
select is(t_blocked('authenticated', :A::uuid, 'viewer',
            'insert into leads(company_id,source,phone) values ('||quote_literal(:A)||',''web'',''+919000008888'')'),
          true, 'A viewer is denied INSERT on leads (manager+ required)');
select is(t_blocked('authenticated', :A::uuid, 'manager',
            'insert into leads(company_id,source,phone) values ('||quote_literal(:B)||',''web'',''+919000007777'')'),
          true, 'A manager cross-tenant INSERT (company_id=B) raises 42501');

-- ======================= APPEND-ONLY / ADMIN-READ =======================
select is(t_count('authenticated', :A::uuid, 'admin', 'select count(*) from usage_logs'),
          1::bigint, 'A admin can read its own usage_logs');
select is(t_count('authenticated', :A::uuid, 'agent', 'select count(*) from usage_logs'),
          0::bigint, 'A non-admin cannot read usage_logs (admin-only)');
select is(t_rowcount('authenticated', :A::uuid, 'admin',
            'update usage_logs set provider=''x'' where company_id='||quote_literal(:A)),
          0::bigint, 'usage_logs UPDATE blocked (append-only, no client update policy)');
select is(t_rowcount('authenticated', :A::uuid, 'admin',
            'delete from usage_logs where company_id='||quote_literal(:A)),
          0::bigint, 'usage_logs DELETE blocked (append-only)');

-- ======================= RAG ISOLATION =======================
select is(t_count('authenticated', :A::uuid, 'agent', 'select count(*) from document_chunks'),
          2::bigint, 'A sees only its own 2 document_chunks (RAG tenant floor)');
select is(t_count('authenticated', :B::uuid, 'agent', 'select count(*) from document_chunks'),
          1::bigint, 'B sees only its own 1 document_chunk');

-- ======================= STORAGE ISOLATION =======================
select is(t_count('authenticated', :A::uuid, 'admin',
            'select count(*) from storage.objects where bucket_id=''documents'''),
          1::bigint, 'A sees only its own documents object (folder = company_id)');
select is(t_count('authenticated', :A::uuid, 'agent',
            'select count(*) from storage.objects where bucket_id=''recordings'''),
          1::bigint, 'A sees only its own recordings object');
select is(t_count('service_role', :A::uuid, 'admin',
            'select count(*) from storage.objects where bucket_id=''documents'''),
          2::bigint, 'service_role sees all documents objects (bypass)');

select * from finish();
rollback;
