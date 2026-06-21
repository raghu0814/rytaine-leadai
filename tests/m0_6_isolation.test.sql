-- =====================================================================
-- tests/m0_6_isolation.test.sql  —  M0-6 pgTAP isolation suite
-- ---------------------------------------------------------------------
-- Milestone : M0-6 (DB tenant-isolation suite). DB-ISOLATION-ONLY.
-- Proves: multi-tenant data isolation is enforced by the DATABASE alone —
--         RLS + helper functions + storage policies (migrations 0014-0016)
--         on top of the 0001-0013 schema. No application layer involved.
--
-- Enforcement path mirrors production exactly: every behavioural check runs
-- as `authenticated` / `anon` / `service_role` with the verified JWT claims
-- injected into `request.jwt.claims` precisely as the FastAPI DB-session
-- dependency will inject them in M0-7. Claims are injected at the DB layer
-- here; the app-layer SET LOCAL plumbing is OUT OF SCOPE (deferred to M0-7).
--
-- Run model: wrapped in BEGIN/ROLLBACK so fixtures + harness functions never
-- persist. SEED-INDEPENDENT by design — fixtures use dedicated tenant UUIDs
-- (6a…/6b…) that cannot collide with the dev seed (1111…) or the M0-4 suite
-- (1111…/2222…), and every cross-tenant / bypass assertion is scoped to the
-- fixture tenant set. Therefore this suite is correct whether or not
-- supabase/seed.sql has been loaded (e.g. after `supabase db reset`).
--
-- Requires: pgtap; migrations 0014-0016 applied; the Supabase-provided roles
--           (anon, authenticated, service_role) and storage schema, which the
--           local stack / hosted project supply and the bare-PG rig emulates.
-- =====================================================================
begin;
create extension if not exists pgtap;
select plan(67);

-- =====================================================================
-- Harness helpers (SECURITY INVOKER; dropped on rollback).
-- The caller is a superuser; each helper DROPS privileges via `set local
-- role`, so RLS evaluates as the impersonated role under the injected claims.
-- =====================================================================
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
  return false;                         -- statement succeeded => NOT blocked
exception
  when insufficient_privilege then       -- SQLSTATE 42501 (RLS USING/CHECK or no policy)
    return true;
end $$;

-- =====================================================================
-- Two-tenant fixtures (inserted as superuser; BYPASSRLS).
-- Dedicated UUIDs => no collision with seed or the M0-4 suite.
-- =====================================================================
\set A  '''6a000000-0000-0000-0000-0000000000aa'''
\set B  '''6b000000-0000-0000-0000-0000000000bb'''
\set AK '''6a000000-0000-0000-0000-00000000a101'''
\set BK '''6b000000-0000-0000-0000-00000000b101'''
\set AD '''6a000000-0000-0000-0000-00000000a102'''
\set BD '''6b000000-0000-0000-0000-00000000b102'''
\set AL '''6a000000-0000-0000-0000-00000000a103'''
\set BL '''6b000000-0000-0000-0000-00000000b103'''
\set AC '''6a000000-0000-0000-0000-00000000a104'''
\set BC '''6b000000-0000-0000-0000-00000000b104'''
\set AU '''6a000000-0000-0000-0000-00000000a105'''
\set BU '''6b000000-0000-0000-0000-00000000b105'''

-- tenant roots
insert into companies(id,name,slug) values
  (:A::uuid,'Iso Tenant A','iso-tenant-a'),
  (:B::uuid,'Iso Tenant B','iso-tenant-b');

-- auth.users backing public.users (FK users.id -> auth.users.id)
insert into auth.users(id,email) values
  (:AU::uuid,'a@iso.test'),
  (:BU::uuid,'b@iso.test');
insert into users(id,company_id,email) values
  (:AU::uuid,:A::uuid,'a@iso.test'),
  (:BU::uuid,:B::uuid,'b@iso.test');

insert into prompts(company_id,name,system_prompt) values
  (:A::uuid,'P A','sys a'),(:B::uuid,'P B','sys b');
insert into knowledge_bases(id,company_id,name) values
  (:AK::uuid,:A::uuid,'KB A'),(:BK::uuid,:B::uuid,'KB B');
insert into agent_configs(company_id,name) values
  (:A::uuid,'AC A'),(:B::uuid,'AC B');

insert into leads(id,company_id,phone,source) values
  (:AL::uuid,:A::uuid,'+919000000001','manual'),
  (:BL::uuid,:B::uuid,'+919000000101','manual');
insert into lead_notes(company_id,lead_id,note) values
  (:A::uuid,:AL::uuid,'note a'),(:B::uuid,:BL::uuid,'note b');
insert into call_schedules(company_id,lead_id,scheduled_at) values
  (:A::uuid,:AL::uuid,now()),(:B::uuid,:BL::uuid,now());
insert into calls(id,company_id,lead_id) values
  (:AC::uuid,:A::uuid,:AL::uuid),(:BC::uuid,:B::uuid,:BL::uuid);
insert into transcripts(company_id,call_id) values
  (:A::uuid,:AC::uuid),(:B::uuid,:BC::uuid);
insert into recordings(company_id,call_id,storage_path) values
  (:A::uuid,:AC::uuid,'6a000000-0000-0000-0000-0000000000aa/call.mp3'),
  (:B::uuid,:BC::uuid,'6b000000-0000-0000-0000-0000000000bb/call.mp3');
insert into messages(company_id,lead_id,channel) values
  (:A::uuid,:AL::uuid,'sms'),(:B::uuid,:BL::uuid,'sms');

insert into documents(id,company_id,knowledge_base_id,title) values
  (:AD::uuid,:A::uuid,:AK::uuid,'Doc A'),(:BD::uuid,:B::uuid,:BK::uuid,'Doc B');
insert into document_chunks(company_id,document_id,knowledge_base_id,chunk_index,content) values
  (:A::uuid,:AD::uuid,:AK::uuid,0,'a chunk'),
  (:B::uuid,:BD::uuid,:BK::uuid,0,'b chunk');

insert into usage_logs(company_id,service,operation,unit) values
  (:A::uuid,'elevenlabs','tts','characters'),
  (:B::uuid,'elevenlabs','tts','characters');
insert into audit_logs(company_id,action,entity_type) values
  (:A::uuid,'created','lead'),(:B::uuid,'created','lead');

insert into storage.objects(bucket_id,name) values
  ('documents', '6a000000-0000-0000-0000-0000000000aa/spec.pdf'),
  ('documents', '6b000000-0000-0000-0000-0000000000bb/spec.pdf'),
  ('recordings','6a000000-0000-0000-0000-0000000000aa/call.mp3'),
  ('recordings','6b000000-0000-0000-0000-0000000000bb/call.mp3');

-- =====================================================================
-- 0. STRUCTURAL ISOLATION GUARANTEES
-- =====================================================================
select has_function('current_company_id', 'helper current_company_id() exists');
select has_function('current_user_role',  'helper current_user_role() exists');
select is(
  (select count(*)::int from pg_class c join pg_namespace n on n.oid=c.relnamespace
     where n.nspname='public' and c.relkind='r'
       and c.relrowsecurity and c.relforcerowsecurity),
  16, 'all 16 public tables have RLS + FORCE (no table left open)');
select is(
  (select count(*)::int from pg_policies p
     where p.schemaname='public' and 'anon' = any(p.roles)),
  0, 'no public RLS policy targets anon => anon denied by default');

-- =====================================================================
-- 1. SELECT ISOLATION — every public table: tenant A (admin) sees ONLY
--    its own row. (companies keys on id; the other 15 on company_id.)
-- =====================================================================
select is(t_count('authenticated', :A::uuid,'admin','select count(*) from companies'),       1::bigint, 'companies: A sees only its own company row');
select is(t_count('authenticated', :A::uuid,'admin','select count(*) from users'),            1::bigint, 'users: A sees only its own user');
select is(t_count('authenticated', :A::uuid,'admin','select count(*) from prompts'),          1::bigint, 'prompts: A sees only its own');
select is(t_count('authenticated', :A::uuid,'admin','select count(*) from knowledge_bases'),  1::bigint, 'knowledge_bases: A sees only its own');
select is(t_count('authenticated', :A::uuid,'admin','select count(*) from agent_configs'),    1::bigint, 'agent_configs: A sees only its own');
select is(t_count('authenticated', :A::uuid,'admin','select count(*) from leads'),            1::bigint, 'leads: A sees only its own');
select is(t_count('authenticated', :A::uuid,'admin','select count(*) from lead_notes'),       1::bigint, 'lead_notes: A sees only its own');
select is(t_count('authenticated', :A::uuid,'admin','select count(*) from call_schedules'),   1::bigint, 'call_schedules: A sees only its own');
select is(t_count('authenticated', :A::uuid,'admin','select count(*) from calls'),            1::bigint, 'calls: A sees only its own');
select is(t_count('authenticated', :A::uuid,'admin','select count(*) from transcripts'),      1::bigint, 'transcripts: A sees only its own');
select is(t_count('authenticated', :A::uuid,'admin','select count(*) from recordings'),       1::bigint, 'recordings: A sees only its own');
select is(t_count('authenticated', :A::uuid,'admin','select count(*) from messages'),         1::bigint, 'messages: A sees only its own');
select is(t_count('authenticated', :A::uuid,'admin','select count(*) from documents'),        1::bigint, 'documents: A sees only its own');
select is(t_count('authenticated', :A::uuid,'admin','select count(*) from document_chunks'),  1::bigint, 'document_chunks: A sees only its own (RAG tenant floor)');
select is(t_count('authenticated', :A::uuid,'admin','select count(*) from usage_logs'),       1::bigint, 'usage_logs: A admin sees only its own');
select is(t_count('authenticated', :A::uuid,'admin','select count(*) from audit_logs'),       1::bigint, 'audit_logs: A admin sees only its own');

-- =====================================================================
-- 2. CROSS-TENANT SELECT LEAKAGE = 0 — A (admin) cannot read any of B's
--    rows, explicitly filtered to B's key. PII / call content emphasised.
-- =====================================================================
select is(t_count('authenticated', :A::uuid,'admin','select count(*) from companies where id='||quote_literal(:B)),               0::bigint, 'companies: A cannot see B''s company');
select is(t_count('authenticated', :A::uuid,'admin','select count(*) from users where company_id='||quote_literal(:B)),           0::bigint, 'users: A cannot see B''s users');
select is(t_count('authenticated', :A::uuid,'admin','select count(*) from prompts where company_id='||quote_literal(:B)),         0::bigint, 'prompts: A cannot see B''s prompts');
select is(t_count('authenticated', :A::uuid,'admin','select count(*) from knowledge_bases where company_id='||quote_literal(:B)), 0::bigint, 'knowledge_bases: A cannot see B''s KBs');
select is(t_count('authenticated', :A::uuid,'admin','select count(*) from agent_configs where company_id='||quote_literal(:B)),   0::bigint, 'agent_configs: A cannot see B''s configs');
select is(t_count('authenticated', :A::uuid,'admin','select count(*) from leads where company_id='||quote_literal(:B)),           0::bigint, 'leads: A cannot see B''s leads (PII)');
select is(t_count('authenticated', :A::uuid,'admin','select count(*) from lead_notes where company_id='||quote_literal(:B)),      0::bigint, 'lead_notes: A cannot see B''s notes');
select is(t_count('authenticated', :A::uuid,'admin','select count(*) from call_schedules where company_id='||quote_literal(:B)),  0::bigint, 'call_schedules: A cannot see B''s schedules');
select is(t_count('authenticated', :A::uuid,'admin','select count(*) from calls where company_id='||quote_literal(:B)),           0::bigint, 'calls: A cannot see B''s calls');
select is(t_count('authenticated', :A::uuid,'admin','select count(*) from transcripts where company_id='||quote_literal(:B)),     0::bigint, 'transcripts: A cannot see B''s transcripts (content)');
select is(t_count('authenticated', :A::uuid,'admin','select count(*) from recordings where company_id='||quote_literal(:B)),      0::bigint, 'recordings: A cannot see B''s recordings (content)');
select is(t_count('authenticated', :A::uuid,'admin','select count(*) from messages where company_id='||quote_literal(:B)),        0::bigint, 'messages: A cannot see B''s messages');
select is(t_count('authenticated', :A::uuid,'admin','select count(*) from documents where company_id='||quote_literal(:B)),       0::bigint, 'documents: A cannot see B''s documents');
select is(t_count('authenticated', :A::uuid,'admin','select count(*) from document_chunks where company_id='||quote_literal(:B)), 0::bigint, 'document_chunks: A cannot see B''s chunks (RAG leak floor)');
select is(t_count('authenticated', :A::uuid,'admin','select count(*) from usage_logs where company_id='||quote_literal(:B)),      0::bigint, 'usage_logs: A cannot see B''s usage');
select is(t_count('authenticated', :A::uuid,'admin','select count(*) from audit_logs where company_id='||quote_literal(:B)),      0::bigint, 'audit_logs: A cannot see B''s audit trail');

-- =====================================================================
-- 3. CROSS-TENANT WRITE ISOLATION — client-writable tables.
--    UPDATE/DELETE of B's rows affect 0 (USING hides them);
--    INSERT with company_id=B raises 42501 (WITH CHECK fails).
-- =====================================================================
-- leads (manager+ write)
select is(t_rowcount('authenticated', :A::uuid,'manager','update leads set lead_status=''contacted'' where company_id='||quote_literal(:B)), 0::bigint, 'leads: A manager cross-tenant UPDATE of B affects 0 rows');
select is(t_rowcount('authenticated', :A::uuid,'manager','delete from leads where company_id='||quote_literal(:B)),                       0::bigint, 'leads: A manager cross-tenant DELETE of B affects 0 rows');
select is(t_blocked ('authenticated', :A::uuid,'manager','insert into leads(company_id,phone,source) values ('||quote_literal(:B)||',''+919000007777'',''manual'')'), true, 'leads: A manager cross-tenant INSERT (company_id=B) raises 42501');
-- documents (admin write)
select is(t_rowcount('authenticated', :A::uuid,'admin','update documents set title=''x'' where company_id='||quote_literal(:B)),          0::bigint, 'documents: A admin cross-tenant UPDATE of B affects 0 rows');
select is(t_blocked ('authenticated', :A::uuid,'admin','insert into documents(company_id,knowledge_base_id,title) values ('||quote_literal(:B)||','||quote_literal(:BK)||',''X'')'), true, 'documents: A admin cross-tenant INSERT (company_id=B) blocked');
-- prompts (admin write)
select is(t_rowcount('authenticated', :A::uuid,'admin','update prompts set name=''x'' where company_id='||quote_literal(:B)),             0::bigint, 'prompts: A admin cross-tenant UPDATE of B affects 0 rows');
-- knowledge_bases (admin write)
select is(t_blocked ('authenticated', :A::uuid,'admin','insert into knowledge_bases(company_id,name) values ('||quote_literal(:B)||',''X'')'), true, 'knowledge_bases: A admin cross-tenant INSERT (company_id=B) blocked');
-- agent_configs (admin write)
select is(t_rowcount('authenticated', :A::uuid,'admin','update agent_configs set name=''x'' where company_id='||quote_literal(:B)),       0::bigint, 'agent_configs: A admin cross-tenant UPDATE of B affects 0 rows');
-- call_schedules (manager+ write)
select is(t_blocked ('authenticated', :A::uuid,'manager','insert into call_schedules(company_id,lead_id,scheduled_at) values ('||quote_literal(:B)||','||quote_literal(:BL)||',now())'), true, 'call_schedules: A manager cross-tenant INSERT (company_id=B) blocked');
-- lead_notes (agent+ insert)
select is(t_blocked ('authenticated', :A::uuid,'agent','insert into lead_notes(company_id,lead_id,note) values ('||quote_literal(:B)||','||quote_literal(:BL)||',''x'')'), true, 'lead_notes: A agent cross-tenant INSERT (company_id=B) blocked');
-- users (admin write)
select is(t_rowcount('authenticated', :A::uuid,'admin','update users set email=''x@x'' where company_id='||quote_literal(:B)),            0::bigint, 'users: A admin cross-tenant UPDATE of B affects 0 rows');
-- messages (manager+ insert)
select is(t_blocked ('authenticated', :A::uuid,'manager','insert into messages(company_id,lead_id,channel) values ('||quote_literal(:B)||','||quote_literal(:BL)||',''sms'')'), true, 'messages: A manager cross-tenant INSERT (company_id=B) blocked');

-- =====================================================================
-- 4. COMPANIES SPECIAL-CASE (predicate keys on id, not company_id)
-- =====================================================================
select is(t_rowcount('authenticated', :A::uuid,'admin','update companies set name=''A2'' where id='||quote_literal(:A)),  1::bigint, 'companies: A admin can update its OWN company');
select is(t_blocked ('authenticated', :A::uuid,'manager','update companies set name=''nope'' where id='||quote_literal(:A)), true, 'companies: A manager UPDATE own company blocked (WITH CHECK role=admin)');
select is(t_blocked ('authenticated', :A::uuid,'admin','insert into companies(id,name,slug) values (gen_random_uuid(),''rogue'',''rogue'')'), true, 'companies: authenticated INSERT blocked (service_role only)');
select is(t_rowcount('authenticated', :A::uuid,'admin','update companies set name=''hijack'' where id='||quote_literal(:B)), 0::bigint, 'companies: A admin cross-tenant UPDATE of B company affects 0 rows');

-- =====================================================================
-- 5. ROLE-GATED WRITE DENY (positive control: role floor holds within tenant)
-- =====================================================================
select is(t_blocked('authenticated', :A::uuid,'viewer','insert into leads(company_id,phone,source) values ('||quote_literal(:A)||',''+919000008888'',''manual'')'), true, 'leads: viewer denied INSERT even in own tenant (manager+ required)');
select is(t_blocked('authenticated', :A::uuid,'agent','insert into documents(company_id,knowledge_base_id,title) values ('||quote_literal(:A)||','||quote_literal(:AK)||',''X'')'), true, 'documents: agent denied INSERT in own tenant (admin required)');

-- =====================================================================
-- 6. UNAUTHENTICATED / NO-TENANT-CLAIM DENIAL (no accidental wildcard)
-- =====================================================================
select is(t_count('anon', :A::uuid,'admin','select count(*) from leads'),     0::bigint, 'anon sees 0 leads even with a tenant claim (no anon policy)');
select is(t_count('authenticated', NULL::uuid,'admin','select count(*) from leads'),     0::bigint, 'authenticated with NULL company_id claim sees 0 leads (NULL never matches)');
select is(t_count('authenticated', NULL::uuid,'admin','select count(*) from companies'), 0::bigint, 'authenticated with NULL company_id claim sees 0 companies');

-- =====================================================================
-- 7. service_role BYPASS — intentional backend path (scoped to fixtures
--    so the assertion is independent of any loaded dev seed).
-- =====================================================================
select is(t_count('service_role', :A::uuid,'admin','select count(*) from leads where company_id in ('||quote_literal(:A)||','||quote_literal(:B)||')'),           2::bigint, 'service_role bypasses RLS: sees BOTH tenants'' fixture leads');
select is(t_count('service_role', :A::uuid,'admin','select count(*) from document_chunks where company_id in ('||quote_literal(:A)||','||quote_literal(:B)||')'),  2::bigint, 'service_role bypasses RLS: sees BOTH tenants'' fixture chunks');

-- =====================================================================
-- 8. APPEND-ONLY ENFORCEMENT (clients cannot mutate audit/usage trails)
-- =====================================================================
select is(t_rowcount('authenticated', :A::uuid,'admin','update usage_logs set operation=''x'' where company_id='||quote_literal(:A)), 0::bigint, 'usage_logs: own UPDATE blocked (append-only, no client update policy)');
select is(t_rowcount('authenticated', :A::uuid,'admin','delete from usage_logs where company_id='||quote_literal(:A)),                 0::bigint, 'usage_logs: own DELETE blocked (append-only)');
select is(t_rowcount('authenticated', :A::uuid,'admin','update audit_logs set action=''x'' where company_id='||quote_literal(:A)),     0::bigint, 'audit_logs: own UPDATE blocked (append-only)');
select is(t_rowcount('authenticated', :A::uuid,'admin','delete from audit_logs where company_id='||quote_literal(:A)),                 0::bigint, 'audit_logs: own DELETE blocked (append-only)');

-- =====================================================================
-- 9. STORAGE OBJECT ISOLATION (folder prefix = company_id)
-- =====================================================================
select is(t_count('authenticated', :A::uuid,'admin','select count(*) from storage.objects where bucket_id=''documents'''), 1::bigint, 'storage/documents: A sees only its own object');
select is(t_count('authenticated', :A::uuid,'admin','select count(*) from storage.objects where bucket_id=''documents'' and (storage.foldername(name))[1]='||quote_literal(:B)), 0::bigint, 'storage/documents: A cannot see B''s object');
select is(t_count('authenticated', :A::uuid,'agent','select count(*) from storage.objects where bucket_id=''recordings'''), 1::bigint, 'storage/recordings: A sees only its own object');
select is(t_count('service_role', :A::uuid,'admin','select count(*) from storage.objects where bucket_id=''documents'' and (storage.foldername(name))[1] in ('||quote_literal(:A)||','||quote_literal(:B)||')'), 2::bigint, 'storage/documents: service_role sees both tenants'' fixture objects (bypass)');

select * from finish();
rollback;
