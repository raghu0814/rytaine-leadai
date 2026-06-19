-- =====================================================================
-- Migration : 0008_messaging
-- Milestone : M0-3 (schema)
-- Concern   : Outbound/inbound WhatsApp / SMS / email (table 12 of 16)
-- Depends on: 0007_calls_scheduling (calls), 0005_leads, 0003_tenant_core
-- Forward-only. Immutable once merged.
-- =====================================================================

create table messages (
  id                  uuid primary key default gen_random_uuid(),
  company_id          uuid not null references companies(id) on delete cascade,
  lead_id             uuid not null references leads(id) on delete cascade,
  call_id             uuid references calls(id) on delete set null,
  channel             message_channel not null,
  direction           message_direction not null default 'outbound',
  provider            message_provider not null default 'twilio',
  provider_message_id text,
  template_name       text,                         -- WA template id
  body                text,
  media_url           text,
  status              message_status not null default 'queued',
  error_code          text,
  status_updated_at   timestamptz,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  unique (provider, provider_message_id)
);

create index idx_messages_company_lead    on messages(company_id, lead_id);
create index idx_messages_company_channel  on messages(company_id, channel, status);
