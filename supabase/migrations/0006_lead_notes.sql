-- =====================================================================
-- Migration : 0006_lead_notes
-- Milestone : M0-3 (schema)
-- Concern   : Free-text notes attached to a lead (table 7 of 16)
-- Depends on: 0005_leads (leads), 0003_tenant_core (companies, users)
-- Notes     : Append-style in practice (created_at only, no updated_at, so
--             no set_updated_at trigger). user_id is the author; nullable +
--             ON DELETE SET NULL so a note survives author removal, matching
--             the schema-wide convention for `created_by`-style references.
-- Forward-only. Immutable once merged.
-- =====================================================================

create table lead_notes (
  id          uuid primary key default gen_random_uuid(),
  company_id  uuid not null references companies(id) on delete cascade,
  lead_id     uuid not null references leads(id) on delete cascade,
  user_id     uuid references users(id) on delete set null,
  note        text not null,
  created_at  timestamptz not null default now()
);

create index idx_lead_notes_lead on lead_notes(company_id, lead_id);
