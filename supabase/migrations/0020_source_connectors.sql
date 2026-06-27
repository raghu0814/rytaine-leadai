-- =====================================================================
-- Migration : 0020_source_connectors
-- Milestone : M1.1 (Source Adapters — provider->company routing & config)
-- Concern   : source_connectors — per-tenant connector configuration that
--             maps an inbound provider identity (Meta page/form, Google Lead
--             Form) to a company_id, carries the per-form field map, and holds
--             per-connector SECRETS (Meta page access token, Google google_key)
--             that the service_role webhook path reads to verify & fetch.
--             (table 18; second table added after the M0 set, after 0018.)
-- Depends on: 0003_tenant_core (companies), 0002_enums (lead_source),
--             0012_functions_updated_at (shared set_updated_at()),
--             0014_rls_helpers (current_company_id / current_user_role).
--
-- Model (locked — M1.1 design review; D-CONN, D-CONN-SEC = Option A):
--   * Mutable tenant CONFIG (not a ledger): FK ON DELETE CASCADE — deleting a
--     company removes its connectors (contrast lead_events, which RESTRICTs).
--   * SECRET HIDING (D-CONN-SEC Option A): secrets live in secret jsonb. The
--     authenticated role is granted COLUMN-level SELECT on the non-secret
--     columns ONLY; it can NEVER read (or write) secret. service_role
--     (BYPASSRLS) reads/writes everything; anon gets nothing.
--   * REVOKE-FIRST: Supabase platform default privileges auto-GRANT ALL on every
--     column to anon/authenticated/service_role at CREATE TABLE time; GRANT is
--     additive and does NOT undo them. We REVOKE ALL first (which also clears
--     the table-wide column SELECT that would otherwise expose secret), then
--     re-grant the exact least-privilege surface. Without the REVOKE, the
--     platform default would leave authenticated able to read secret.
--   * authenticated is SELECT-only on the non-secret surface in M1.1 (no client
--     write path to connectors yet; provisioning is service_role). [NARROWED
--     from the plan's "admin INSERT/UPDATE" — see Phase 1 self-audit.]
--   * Source domain is constrained to the providers M1.1 actually adapts
--     (meta, google); manual needs no connector (company comes from the JWT),
--     api is out of scope. Relaxing this is a future forward migration.
--   * Routing identifiers are GLOBALLY unique (partial unique indexes) so a
--     webhook resolves to exactly one connector before the company is known.
--   * Created AFTER the 0015 global enable/force loop, so it enables + forces
--     RLS on itself (same as 0018).
-- Forward-only. Immutable once merged.
-- =====================================================================

create table source_connectors (
  id              uuid primary key default gen_random_uuid(),
  company_id      uuid not null references companies(id) on delete cascade,
  source          lead_source not null,
  display_name    text,
  meta_page_id    text,                                  -- Meta routing key
  meta_form_id    text,                                  -- optional finer Meta routing
  google_form_id  text,                                  -- Google Lead Form routing key
  field_map       jsonb not null default '{}'::jsonb,    -- provider-question -> canonical-field
  secret          jsonb not null default '{}'::jsonb,    -- per-connector secrets (service_role only)
  is_active       boolean not null default true,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  -- M1.1 only adapts meta + google; manual/api take no connector.
  constraint source_connectors_source_supported_ck
    check (source in ('meta','google')),
  -- the routing key required by the source must be present.
  constraint source_connectors_routing_present_ck
    check (
      (source = 'meta'   and meta_page_id   is not null) or
      (source = 'google' and google_form_id is not null)
    ),
  constraint source_connectors_field_map_object check (jsonb_typeof(field_map) = 'object'),
  constraint source_connectors_secret_object    check (jsonb_typeof(secret)    = 'object')
);

-- Tenant config lookup (admin views).
create index idx_source_connectors_company
  on source_connectors (company_id);

-- Global routing uniqueness: a provider identifier maps to ONE connector.
create unique index uq_source_connectors_meta_page
  on source_connectors (meta_page_id)
  where meta_page_id is not null;
create unique index uq_source_connectors_google_form
  on source_connectors (google_form_id)
  where google_form_id is not null;

-- Mutable config -> maintain updated_at via the shared 0012 function.
create trigger trg_source_connectors_updated
  before update on source_connectors
  for each row execute function set_updated_at();

-- ---- RLS (created after the 0015 loop -> enable + force here) -------------
alter table source_connectors enable row level security;
alter table source_connectors force  row level security;

-- Admin-only tenant read (mirrors lead_events / usage_logs / audit_logs). No
-- authenticated write policy => clients cannot write; service_role bypasses RLS
-- and is the sole write path.
create policy source_connectors_select_admin on source_connectors for select to authenticated
  using (company_id = public.current_company_id()
         and public.current_user_role() = 'admin');

-- ---- Grants (REVOKE-FIRST; least privilege; D-CONN-SEC Option A) ----------
-- REVOKE ALL clears both the platform default ALL grant AND the table-wide
-- column SELECT, so secret is not readable until we re-grant column SELECT on
-- the non-secret columns only.
revoke all on table public.source_connectors from public, anon, authenticated, service_role;

-- service_role (BYPASSRLS): full DML, including secret read/write.
grant select, insert, update, delete on table public.source_connectors to service_role;

-- authenticated: COLUMN-level SELECT on the non-secret columns ONLY.
-- secret is deliberately omitted -> authenticated can never read it.
grant select (
  id, company_id, source, display_name,
  meta_page_id, meta_form_id, google_form_id,
  field_map, is_active, created_at, updated_at
) on table public.source_connectors to authenticated;

-- anon: no grant, no policy => denied.
