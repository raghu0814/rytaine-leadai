-- =====================================================================
-- tests/m1_1_source_connectors.test.sql  —  M1.1 pgTAP suite (DB-ONLY)
-- ---------------------------------------------------------------------
-- Milestone : M1.1 (source_connectors connector config, migration 0020).
-- Proves the locked design contract at the database layer:
--   structure / types / nullability / defaults, PK, FK ON DELETE CASCADE,
--   four CHECKs (source-supported, routing-present, two jsonb-object),
--   the company index + the two PARTIAL-UNIQUE routing indexes,
--   RLS enabled+forced, admin-only SELECT policy, exactly one (updated_at)
--   trigger, the exact table grant surface AND the COLUMN-level secret hiding
--   (D-CONN-SEC Option A), and the behavioural guarantees:
--   admin-only tenant read, authenticated CANNOT read secret (column denial),
--   service_role CAN read/write secret, anon denied, routing uniqueness,
--   CHECK enforcement, and FK CASCADE on company delete.
--
-- Enforcement path mirrors production: behavioural checks run as
-- authenticated / anon / service_role with verified JWT claims injected into
-- request.jwt.claims exactly as the FastAPI DB-session dependency injects them.
--
-- Run model: BEGIN/ROLLBACK — fixtures + harness never persist. Seed-independent:
-- fixtures use dedicated tenant UUIDs (aaaa…/bbbb…/cccc…) that cannot collide
-- with the dev seed or other suites.
--
-- Requires: pgtap; migrations 0001-0020 applied; Supabase-provided roles
--           (anon, authenticated, service_role) — supplied by the local stack /
--           hosted project, emulated by the bare-PG rig (whose bootstrap must
--           carry the Supabase ALTER DEFAULT PRIVILEGES so REVOKE-first is real).
-- =====================================================================
begin;
create extension if not exists pgtap;
select plan(73);

-- ---------------------------------------------------------------------
-- Harness: impersonate a DB role under injected JWT claims (dropped on
-- rollback). Mirrors the M1.0 / M0-6 isolation harness.
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

-- =====================================================================
-- 1. Structure
-- =====================================================================
select has_table('public', 'source_connectors', 'source_connectors table exists');

select has_column('public','source_connectors','id',             'has id');
select has_column('public','source_connectors','company_id',     'has company_id');
select has_column('public','source_connectors','source',         'has source');
select has_column('public','source_connectors','display_name',   'has display_name');
select has_column('public','source_connectors','meta_page_id',   'has meta_page_id');
select has_column('public','source_connectors','meta_form_id',   'has meta_form_id');
select has_column('public','source_connectors','google_form_id', 'has google_form_id');
select has_column('public','source_connectors','field_map',      'has field_map');
select has_column('public','source_connectors','secret',         'has secret');
select has_column('public','source_connectors','is_active',      'has is_active');
select has_column('public','source_connectors','created_at',     'has created_at');
select has_column('public','source_connectors','updated_at',     'has updated_at');

select col_type_is('public','source_connectors','id',             'uuid',                     'id uuid');
select col_type_is('public','source_connectors','company_id',     'uuid',                     'company_id uuid');
select col_type_is('public','source_connectors','source',         'lead_source',              'source lead_source');
select col_type_is('public','source_connectors','display_name',   'text',                     'display_name text');
select col_type_is('public','source_connectors','meta_page_id',   'text',                     'meta_page_id text');
select col_type_is('public','source_connectors','meta_form_id',   'text',                     'meta_form_id text');
select col_type_is('public','source_connectors','google_form_id', 'text',                     'google_form_id text');
select col_type_is('public','source_connectors','field_map',      'jsonb',                    'field_map jsonb');
select col_type_is('public','source_connectors','secret',         'jsonb',                    'secret jsonb');
select col_type_is('public','source_connectors','is_active',      'boolean',                  'is_active boolean');
select col_type_is('public','source_connectors','created_at',     'timestamp with time zone', 'created_at timestamptz');
select col_type_is('public','source_connectors','updated_at',     'timestamp with time zone', 'updated_at timestamptz');

select col_not_null('public','source_connectors','id',          'id NOT NULL');
select col_not_null('public','source_connectors','company_id',  'company_id NOT NULL');
select col_not_null('public','source_connectors','source',      'source NOT NULL');
select col_not_null('public','source_connectors','field_map',   'field_map NOT NULL');
select col_not_null('public','source_connectors','secret',      'secret NOT NULL');
select col_not_null('public','source_connectors','is_active',   'is_active NOT NULL');
select col_not_null('public','source_connectors','created_at',  'created_at NOT NULL');
select col_not_null('public','source_connectors','updated_at',  'updated_at NOT NULL');
select col_is_null('public','source_connectors','display_name',   'display_name nullable');
select col_is_null('public','source_connectors','meta_page_id',   'meta_page_id nullable');
select col_is_null('public','source_connectors','meta_form_id',   'meta_form_id nullable');
select col_is_null('public','source_connectors','google_form_id', 'google_form_id nullable');

-- =====================================================================
-- 2. Keys / constraints
-- =====================================================================
select col_is_pk('public','source_connectors','id', 'id is the PK');
select fk_ok('public','source_connectors','company_id','public','companies','id',
             'company_id FK -> companies.id');
select is((select confdeltype::text from pg_constraint
            where conrelid='public.source_connectors'::regclass and contype='f'),
          'c', 'FK company_id is ON DELETE CASCADE');

select is((select count(*)::int from pg_constraint
            where conrelid='public.source_connectors'::regclass and contype='c'),
          4, 'exactly four CHECK constraints');
select ok(exists(select 1 from pg_constraint
            where conname='source_connectors_source_supported_ck'
              and conrelid='public.source_connectors'::regclass),
          'source-supported CHECK present');
select ok(exists(select 1 from pg_constraint
            where conname='source_connectors_routing_present_ck'
              and conrelid='public.source_connectors'::regclass),
          'routing-present CHECK present');
select ok(exists(select 1 from pg_constraint
            where conname='source_connectors_field_map_object'
              and conrelid='public.source_connectors'::regclass),
          'field_map jsonb-object CHECK present');
select ok(exists(select 1 from pg_constraint
            where conname='source_connectors_secret_object'
              and conrelid='public.source_connectors'::regclass),
          'secret jsonb-object CHECK present');

-- =====================================================================
-- 3. Indexes
-- =====================================================================
select has_index('public','source_connectors','idx_source_connectors_company',
                 ARRAY['company_id'], 'company index');
select has_index('public','source_connectors','uq_source_connectors_meta_page',
                 ARRAY['meta_page_id'], 'meta_page routing index');
select ok((select indexdef from pg_indexes where indexname='uq_source_connectors_meta_page')
          like '%UNIQUE%' and
          (select indexdef from pg_indexes where indexname='uq_source_connectors_meta_page')
          like '%WHERE (meta_page_id IS NOT NULL)%',
          'meta_page index is partial-UNIQUE WHERE meta_page_id IS NOT NULL');
select has_index('public','source_connectors','uq_source_connectors_google_form',
                 ARRAY['google_form_id'], 'google_form routing index');
select ok((select indexdef from pg_indexes where indexname='uq_source_connectors_google_form')
          like '%UNIQUE%' and
          (select indexdef from pg_indexes where indexname='uq_source_connectors_google_form')
          like '%WHERE (google_form_id IS NOT NULL)%',
          'google_form index is partial-UNIQUE WHERE google_form_id IS NOT NULL');

-- =====================================================================
-- 4. RLS / policy / trigger
-- =====================================================================
select is((select relrowsecurity      from pg_class where oid='public.source_connectors'::regclass),
          true, 'RLS enabled');
select is((select relforcerowsecurity from pg_class where oid='public.source_connectors'::regclass),
          true, 'RLS forced');
select policies_are('public','source_connectors', ARRAY['source_connectors_select_admin'],
                    'only the admin SELECT policy exists (no client write policy)');
select is((select count(*)::int from pg_trigger t join pg_class c on c.oid=t.tgrelid
            where c.relname='source_connectors' and not t.tgisinternal),
          1, 'exactly one user trigger (updated_at maintenance)');

-- =====================================================================
-- 5. Grant surface (least privilege) + COLUMN-level secret hiding
-- =====================================================================
select table_privs_are('public','source_connectors','service_role',
                       ARRAY['SELECT','INSERT','UPDATE','DELETE'],
                       'service_role: full DML');
select table_privs_are('public','source_connectors','authenticated', ARRAY[]::text[],
                       'authenticated: NO table-level privileges (column-level SELECT only)');
select table_privs_are('public','source_connectors','anon', ARRAY[]::text[],
                       'anon: no privileges');
select column_privs_are('public','source_connectors','secret','authenticated',
                        ARRAY[]::text[], 'authenticated CANNOT read secret column');
select column_privs_are('public','source_connectors','field_map','authenticated',
                        ARRAY['SELECT'], 'authenticated CAN read field_map column');
select column_privs_are('public','source_connectors','secret','service_role',
                        ARRAY['SELECT','INSERT','UPDATE'], 'service_role can read/write secret column');

-- =====================================================================
-- 6. Fixtures (inserted as superuser; bypasses RLS + column grants)
-- =====================================================================
insert into companies (id, name, slug) values
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','SC Tenant A','sc-tenant-a'),
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb','SC Tenant B','sc-tenant-b'),
  ('cccccccc-cccc-cccc-cccc-cccccccccccc','SC Tenant C','sc-tenant-c');
insert into source_connectors (company_id, source, meta_page_id, google_form_id, secret) values
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','meta',  'pg-A', null, '{"page_token":"tok-A"}'),
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','google', null, 'gf-A', '{"google_key":"key-A"}'),
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb','meta',  'pg-B', null, '{"page_token":"tok-B"}'),
  ('cccccccc-cccc-cccc-cccc-cccccccccccc','meta',  'pg-C', null, '{"page_token":"tok-C"}');

-- =====================================================================
-- 7. Behavioural
-- =====================================================================
-- 7a. admin-only tenant read
select is(_count('authenticated','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','admin',
                 'select count(*) from source_connectors'),
          2::bigint, 'admin of A sees exactly A''s 2 connectors');
select is(_count('authenticated','bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb','admin',
                 'select count(*) from source_connectors'),
          1::bigint, 'admin of B sees exactly B''s 1 connector (no cross-tenant leak)');
select is(_count('authenticated','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','agent',
                 'select count(*) from source_connectors'),
          0::bigint, 'non-admin (agent) of A sees nothing (admin-gated policy)');

-- 7b. secret hiding (column-level denial) — even an admin cannot read secret
select ok(_blocked('authenticated','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','admin',
            'select secret from source_connectors'),
          'authenticated admin SELECT of secret column is denied (column privilege)');
select ok(not _blocked('authenticated','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','admin',
            $ns$select id, company_id, source, display_name, meta_page_id,
                       meta_form_id, google_form_id, field_map, is_active,
                       created_at, updated_at from source_connectors$ns$),
          'authenticated admin SELECT of non-secret columns succeeds');

-- 7c. anon fully denied
select ok(_blocked('anon', null, null, 'select count(*) from source_connectors'),
          'anon is denied (no grant, no policy)');

-- 7d. service_role can read secret and insert
select ok(not _blocked('service_role', null, null, 'select secret from source_connectors'),
          'service_role can read the secret column');
select ok(not _blocked('service_role', null, null,
            $si$insert into source_connectors (company_id, source, google_form_id, secret)
                values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','google','gf-svc','{"google_key":"key-svc"}')$si$),
          'service_role INSERT (with secret) succeeds');

-- 7e. routing uniqueness (global, partial)
select ok(_blocked('service_role', null, null,
            $dm$insert into source_connectors (company_id, source, meta_page_id)
                values ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb','meta','pg-A')$dm$),
          'duplicate meta_page_id raises unique_violation');
select ok(_blocked('service_role', null, null,
            $dg$insert into source_connectors (company_id, source, google_form_id)
                values ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb','google','gf-A')$dg$),
          'duplicate google_form_id raises unique_violation');

-- 7f. CHECK enforcement
select ok(_blocked('service_role', null, null,
            $ms$insert into source_connectors (company_id, source, meta_page_id)
                values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','manual','pg-manual')$ms$),
          'unsupported source (manual) rejected by source-supported CHECK');
select ok(_blocked('service_role', null, null,
            $nr$insert into source_connectors (company_id, source, meta_page_id)
                values ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa','meta', null)$nr$),
          'meta connector without meta_page_id rejected by routing-present CHECK');

-- 7g. FK CASCADE: deleting a company removes its connectors (contrast lead_events RESTRICT)
delete from companies where id = 'cccccccc-cccc-cccc-cccc-cccccccccccc';
select is((select count(*) from source_connectors
            where company_id = 'cccccccc-cccc-cccc-cccc-cccccccccccc'),
          0::bigint, 'company delete cascades to its connectors (ON DELETE CASCADE)');

select * from finish();
rollback;
