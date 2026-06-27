-- =====================================================================
-- Migration : 0018_lead_events
-- Milestone : M1.0 (lead ingestion — append-only delivery ledger)
-- Concern   : lead_events — immutable inbound-delivery ledger, upstream of
--             leads (table 17; first table added after the M0 set).
-- Depends on: 0003_tenant_core (companies), 0002_enums (lead_source),
--             0014_rls_helpers (current_company_id / current_user_role).
--
-- Model (locked — M1.0 design review, ratified register):
--   * One row per ACCEPTED inbound lead delivery. Append-only.
--   * Write path = service_role (BYPASSRLS).                        [A1-1]
--   * Append-only enforced at the GRANT layer, REVOKE-FIRST: Supabase platform
--     default privileges auto-GRANT ALL (incl. UPDATE/DELETE/TRUNCATE) to anon/
--     authenticated/service_role at CREATE TABLE time; GRANT is additive and does
--     not undo them, so we REVOKE ALL first, then GRANT service_role select+insert
--     only. No guard triggers in M1.0.                              [A1-2]
--   * FK ON DELETE RESTRICT: a company hard-delete must not cascade-erase
--     the ledger (cascade actions bypass table grants).             [A1-3]
--   * RLS: admin-only tenant read, mirroring usage_logs / audit_logs.[A1-4]
--   * leads.origin_event_id is deferred to M1.3 — NOT added here.    [A1-5]
--   * source reuses the existing lead_source enum.                   [A1-6]
--   * Primary key is uuid (house convention).                        [A1-7]
--   * Idempotency gate = UNIQUE (company_id, idempotency_key); the key is
--     NOT NULL and adapter-derived in M1.1 (delivery dedup boundary).
--   * This table is created AFTER the 0015 global enable/force loop, so it
--     enables + forces RLS on itself.
-- Forward-only. Immutable once merged.
-- =====================================================================

create table lead_events (
  id               uuid primary key default gen_random_uuid(),
  company_id       uuid not null references companies(id) on delete restrict,
  source           lead_source not null,
  external_lead_id text,                                   -- provider-native id; NULL for manual
  idempotency_key  text not null,                          -- delivery dedup gate (adapter-derived, M1.1)
  payload          jsonb not null default '{}'::jsonb,     -- adapter-normalized inbound event
  raw_payload      jsonb not null default '{}'::jsonb,     -- verbatim source payload (replay / audit)
  provenance       jsonb not null default '{}'::jsonb,     -- signature / headers / adapter id+version / correlation id
  occurred_at      timestamptz,                            -- source-reported event time (nullable)
  received_at      timestamptz not null default now(),     -- immutable write time; no updated_at (append-only)
  constraint lead_events_company_idem_key  unique (company_id, idempotency_key),
  constraint lead_events_payload_object     check (jsonb_typeof(payload)     = 'object'),
  constraint lead_events_raw_payload_object check (jsonb_typeof(raw_payload) = 'object'),
  constraint lead_events_provenance_object  check (jsonb_typeof(provenance)  = 'object')
);

-- Tenant timeline (admin views).
create index idx_lead_events_company_time
  on lead_events (company_id, received_at desc);

-- Provider lookup + the M1.3 join path to leads. Partial: external_lead_id is
-- NULL for manual deliveries (the idempotency_key constraint is the dedup gate).
create index idx_lead_events_company_source_ext
  on lead_events (company_id, source, external_lead_id)
  where external_lead_id is not null;
-- (the UNIQUE constraint above supplies the (company_id, idempotency_key) index)

-- ---- RLS (created after the 0015 loop -> enable + force here) -------------
alter table lead_events enable row level security;
alter table lead_events force  row level security;

-- Admin-only tenant read (mirrors usage_logs / audit_logs). No authenticated
-- insert/update/delete policy => clients cannot write; service_role bypasses
-- RLS and is the sole write path.
create policy lead_events_select_admin on lead_events for select to authenticated
  using (company_id = public.current_company_id()
         and public.current_user_role() = 'admin');

-- ---- Grants (REVOKE-FIRST; least privilege) ------------------------------
-- Supabase platform default privileges (ALTER DEFAULT PRIVILEGES IN SCHEMA public
-- GRANT ALL ON TABLES TO anon, authenticated, service_role) auto-grant the FULL
-- privilege set to all three roles when this table is created. GRANT is additive
-- and does NOT undo them, so we must REVOKE first. Without this, anon/authenticated
-- would hold TRUNCATE (which is NOT subject to RLS) and service_role (BYPASSRLS)
-- would hold UPDATE/DELETE — silently breaking append-only.
revoke all on table public.lead_events from public, anon, authenticated, service_role;

grant select, insert on table public.lead_events to service_role;
grant select          on table public.lead_events to authenticated;
-- anon: no grant, no policy => denied.
