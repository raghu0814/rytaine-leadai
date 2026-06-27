-- =====================================================================
-- tests/m1_0_lead_events.test.sql  —  M1.0 pgTAP suite (DB-ONLY)
-- ---------------------------------------------------------------------
-- Milestone : M1.0 (lead_events append-only delivery ledger, migration 0018).
-- Proves the locked design contract at the database layer:
--   structure / types / nullability / defaults, PK, UNIQUE idempotency gate,
--   FK ON DELETE RESTRICT, jsonb-object CHECKs, indexes (incl. the partial),
--   RLS enabled+forced, admin-only SELECT policy, NO triggers (append-only is
--   grant-based), the exact grant surface, and the behavioural guarantees:
--   service_role append-only (UPDATE/DELETE/TRUNCATE denied by privilege),
--   idempotency dedup, and admin-only tenant isolation.
--
-- Enforcement path mirrors production: behavioural checks run as
-- authenticated / anon / service_role with verified JWT claims injected into
-- request.jwt.claims exactly as the FastAPI DB-session dependency injects them.
--
-- Run model: BEGIN/ROLLBACK — fixtures + harness never persist. Seed-independent:
-- fixtures use dedicated tenant UUIDs (aaaa…/bbbb…) that cannot collide with the
-- dev seed or other suites.
--
-- Requires: pgtap; migrations 0001-0018 applied; Supabase-provided roles
--           (anon, authenticated, service_role) — supplied by the local stack /
--           hosted project, emulated by the bare-PG rig.
-- =====================================================================
begin;
create extension if not exists pgtap;
select plan(62);

-- ---------------------------------------------------------------------
-- Harness: impersonate a DB role under injected JWT claims (SECURITY INVOKER;
-- dropped on rollback). Mirrors the M0-6 isolation harness.
-- ---------------------------------------------------------------------
create function _claims(company uuid, claim_role text) returns void
language plpgsql as $$
begin
  perform set_config('request.jwt.claims',
    json_build_object('app_metadata',
      json_build_object('company_id', company, 'role', claim_role))::text, true);
end $$;

create function _count(db_role name, company uuid, claim_role text, q text)
returns bigint language plpgsql as $$
declare res bigint;
begin
  perform _claims(company, claim_role);
  execute format('set local role %I', db_role);
  execute q into res;
  reset role;
  return res;
end $$;

create function _blocked(db_role name, company uuid, claim_role text, sql text)
returns boolean language plpgsql as $$
begin
  perform _claims(company, claim_role);
  execute format('set local role %I', db_role);
  execute sql;
  reset role;
  return false;                          -- statement succeeded => NOT blocked
exception when others then
  reset role;
  return true;                           -- any error (privilege / constraint) => blocked
end $$;

create function _rows(db_role name, company uuid, claim_role text, sql text)
returns bigint language plpgsql as $$
declare n bigint;
begin
  perform _claims(company, claim_role);
  execute format('set local role %I', db_role);
  execute sql;
  get diagnostics n = row_count;
  reset role;
  return n;
end $$;

-- =====================================================================
-- 1. Structure
-- =====================================================================
select has_table('public', 'lead_events', 'lead_events table exists');

select has_column('public','lead_events','id',               'has id');
select has_column('public','lead_events','company_id',       'has company_id');
select has_column('public','lead_events','source',           'has source');
select has_column('public','lead_events','external_lead_id', 'has external_lead_id');
select has_column('public','lead_events','idempotency_key',  'has idempotency_key');
select has_column('public','lead_events','payload',          'has payload');
select has_column('public','lead_events','raw_payload',      'has raw_payload');
select has_column('public','lead_events','provenance',       'has provenance');
select has_column('public','lead_events','occurred_at',      'has occurred_at');
select has_column('public','lead_events','received_at',      'has received_at');

select col_type_is('public','lead_events','id',               'uuid',                      'id uuid');
select col_type_is('public','lead_events','company_id',       'uuid',                      'company_id uuid');
select col_type_is('public','lead_events','source',           'lead_source',               'source lead_source');
select col_type_is('public','lead_events','external_lead_id', 'text',                      'external_lead_id text');
select col_type_is('public','lead_events','idempotency_key',  'text',                      'idempotency_key text');
select col_type_is('public','lead_events','payload',          'jsonb',                     'payload jsonb');
select col_type_is('public','lead_events','raw_payload',      'jsonb',                     'raw_payload jsonb');
select col_type_is('public','lead_events','provenance',       'jsonb',                     'provenance jsonb');
select col_type_is('public','lead_events','occurred_at',      'timestamp with time zone',  'occurred_at timestamptz');
select col_type_is('public','lead_events','received_at',      'timestamp with time zone',  'received_at timestamptz');

select col_not_null('public','lead_events','id',              'id NOT NULL');
select col_not_null('public','lead_events','company_id',      'company_id NOT NULL');
select col_not_null('public','lead_events','source',          'source NOT NULL');
select col_not_null('public','lead_events','idempotency_key', 'idempotency_key NOT NULL');
select col_not_null('public','lead_events','payload',         'payload NOT NULL');
select col_not_null('public','lead_events','raw_payload',     'raw_payload NOT NULL');
select col_not_null('public','lead_events','provenance',      'provenance NOT NULL');
select col_not_null('public','lead_events','received_at',     'received_at NOT NULL');
select col_is_null('public','lead_events','external_lead_id', 'external_lead_id nullable');
select col_is_null('public','lead_events','occurred_at',      'occurred_at nullable');

-- =====================================================================
-- 2. Keys / constraints
-- =====================================================================
select col_is_pk('public','lead_events','id', 'id is the PK');
select col_is_unique('public','lead_events', ARRAY['company_id','idempotency_key'],
                     'UNIQUE(company_id, idempotency_key) idempotency gate');
select fk_ok('public','lead_events','company_id','public','companies','id',
             'company_id FK -> companies.id');
select is((select confdeltype::text from pg_constraint
            where conrelid='public.lead_events'::regclass and contype='f'),
          'r', 'FK company_id is ON DELETE RESTRICT');

select is((select count(*)::int from pg_constraint
            where conrelid='public.lead_events'::regclass and contype='c'),
          3, 'exactly three CHECK constraints');
select ok(exists(select 1 from pg_constraint
            where conname='lead_events_payload_object'    and conrelid='public.lead_events'::regclass),
          'payload jsonb-object CHECK present');
select ok(exists(select 1 from pg_constraint
            where conname='lead_events_raw_payload_object' and conrelid='public.lead_events'::regclass),
          'raw_payload jsonb-object CHECK present');
select ok(exists(select 1 from pg_constraint
            where conname='lead_events_provenance_object'  and conrelid='public.lead_events'::regclass),
          'provenance jsonb-object CHECK present');

-- =====================================================================
-- 3. Indexes
-- =====================================================================
select has_index('public','lead_events','idx_lead_events_company_time',
                 ARRAY['company_id','received_at'], 'company/time index');
select has_index('public','lead_events','idx_lead_events_company_source_ext',
                 ARRAY['company_id','source','external_lead_id'], 'company/source/ext index');
select ok((select indexdef from pg_indexes where indexname='idx_lead_events_company_source_ext')
          like '%WHERE (external_lead_id IS NOT NULL)%',
          'source/ext index is partial WHERE external_lead_id IS NOT NULL');

-- =====================================================================
-- 4. RLS / policy / triggers
-- =====================================================================
select is((select relrowsecurity      from pg_class where oid='public.lead_events'::regclass),
          true, 'RLS enabled');
select is((select relforcerowsecurity from pg_class where oid='public.lead_events'::regclass),
          true, 'RLS forced');
select policies_are('public','lead_events', ARRAY['lead_events_select_admin'],
                    'only the admin SELECT policy exists (no client write policy)');
select is((select count(*)::int from pg_trigger t join pg_class c on c.oid=t.tgrelid
            where c.relname='lead_events' and not t.tgisinternal),
          0, 'no user triggers — append-only is grant-based (A1-2)');

-- =====================================================================
-- 5. Grant surface (least privilege)
-- =====================================================================
select table_privs_are('public','lead_events','service_role',  ARRAY['SELECT','INSERT'],
                       'service_role: SELECT + INSERT only (append-only)');
select table_privs_are('public','lead_events','authenticated', ARRAY['SELECT'],
                       'authenticated: SELECT only');
select table_privs_are('public','lead_events','anon',          ARRAY[]::text[],
                       'anon: no privileges');

-- =====================================================================
-- 6. Fixtures (inserted as superuser; bypasses RLS)
-- =====================================================================
insert into companies (id, name, slug) values
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','Tenant A','tenant-a'),
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb','Tenant B','tenant-b');
insert into lead_events (company_id, source, external_lead_id, idempotency_key, payload) values
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','meta','fb-1','meta:fb-1','{"name":"A1"}'),
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','google','g-1','google:g-1','{"name":"A2"}'),
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb','meta','fb-1','meta:fb-1','{"name":"B1"}');

-- =====================================================================
-- 7. Tenant isolation (admin-only read; A1-4)
-- =====================================================================
select is(_count('authenticated','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','admin',
                 'select count(*) from lead_events'),
          2::bigint, 'admin of A sees exactly A''s 2 events');
select is(_count('authenticated','bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb','admin',
                 'select count(*) from lead_events'),
          1::bigint, 'admin of B sees exactly B''s 1 event (no cross-tenant leakage)');
select is(_count('authenticated','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','agent',
                 'select count(*) from lead_events'),
          0::bigint, 'non-admin (agent) of A sees nothing (admin-gated policy)');
select ok(_blocked('anon', null, null, 'select count(*) from lead_events'),
          'anon is denied (no grant, no policy)');

-- =====================================================================
-- 8. Append-only via privilege (service_role; A1-2)
-- =====================================================================
select ok(not _blocked('service_role', null, null,
            $i$insert into lead_events (company_id, source, idempotency_key)
               values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','manual','svc-ins-1')$i$),
          'service_role INSERT succeeds');
select ok(_blocked('service_role', null, null,
            $u$update lead_events set payload = '{"x":1}' where true$u$),
          'service_role UPDATE denied by privilege');
select ok(_blocked('service_role', null, null,
            'delete from lead_events where true'),
          'service_role DELETE denied by privilege');
select ok(_blocked('service_role', null, null,
            'truncate lead_events'),
          'service_role TRUNCATE denied by privilege');

-- =====================================================================
-- 9. Idempotency gate
-- =====================================================================
select ok(_blocked('service_role', null, null,
            $d$insert into lead_events (company_id, source, idempotency_key)
               values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','meta','meta:fb-1')$d$),
          'duplicate (company_id, idempotency_key) raises unique_violation');
select is(_rows('service_role', null, null,
            $c$insert into lead_events (company_id, source, idempotency_key)
               values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','meta','meta:fb-1')
               on conflict (company_id, idempotency_key) do nothing$c$),
          0::bigint, 'ON CONFLICT DO NOTHING on a duplicate inserts 0 rows');
select is((select count(*) from lead_events where idempotency_key = 'cross:key'),
          0::bigint, 'precondition: cross-tenant key unused');
select is(_rows('service_role', null, null,
            $x$insert into lead_events (company_id, source, idempotency_key) values
               ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','api','cross:key'),
               ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb','api','cross:key')$x$),
          2::bigint, 'same idempotency_key under two companies: both insert (tenant-scoped gate)');

-- =====================================================================
-- 10. FK ON DELETE RESTRICT protects the ledger (A1-3)
-- =====================================================================
select ok(_blocked('service_role', null, null,
            $f$delete from companies where id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'$f$),
          'deleting a company with events is blocked (ON DELETE RESTRICT)');

select * from finish();
rollback;
