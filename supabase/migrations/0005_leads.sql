-- =====================================================================
-- Migration : 0005_leads
-- Milestone : M0-3 (schema)
-- Concern   : Leads — the central business object (table 6 of 16)
-- Depends on: 0004_agent_layer (users for assignee; companies)
-- Dedup model (locked):
--   * HARD : UNIQUE (company_id, source, external_lead_id).
--            external_lead_id is NULL for manual leads, and PostgreSQL
--            treats NULLs as distinct, so manual rows are never hard-blocked.
--   * SOFT : is_potential_duplicate / duplicate_of_lead_id are SET (never
--            rejected) by the BEFORE INSERT trigger in 0013_dedup_trigger.
--            The columns live here; the trigger that populates them ships
--            after the function layer.
-- Forward-only. Immutable once merged.
-- =====================================================================

create table leads (
  id                    uuid primary key default gen_random_uuid(),
  company_id            uuid not null references companies(id) on delete cascade,
  external_lead_id      text,                       -- provider id (idempotency)
  name                  text,
  phone                 text not null,              -- E.164 (+91...)
  email                 text,
  city                  text,
  source                lead_source not null default 'manual',
  campaign_name         text,
  lead_status           lead_status not null default 'new',
  lead_score            int not null default 0,
  lead_category         lead_category,
  purpose               lead_purpose not null default 'unknown',
  budget_min            numeric(14,2),
  budget_max            numeric(14,2),
  location_preference   text,
  purchase_timeline     purchase_timeline,
  site_visit_required   boolean not null default false,
  assigned_user_id      uuid references users(id) on delete set null,
  -- soft-dedup flags (populated by trigger in 0013; defaults keep inserts clean)
  is_potential_duplicate boolean not null default false,
  duplicate_of_lead_id   uuid references leads(id) on delete set null,
  raw_payload           jsonb not null default '{}'::jsonb,
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now(),
  unique (company_id, source, external_lead_id)     -- hard dedupe; NULLs allowed for manual
);

create index idx_leads_company_status  on leads(company_id, lead_status);
create index idx_leads_company_score    on leads(company_id, lead_score desc);
create index idx_leads_company_created  on leads(company_id, created_at desc);
-- supports the soft-dedup phone lookup in 0013 (company + phone)
create index idx_leads_phone            on leads(company_id, phone);
