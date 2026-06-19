-- =====================================================================
-- Migration : 0010_usage_logs
-- Milestone : M0-3 (schema)
-- Concern   : Per-provider cost tracking (table 15 of 16)
-- Depends on: 0008_messaging (messages), 0007_calls_scheduling (calls),
--             0005_leads, 0003_tenant_core
-- Notes     : High-volume, append-only. Candidate for monthly range
--             partitioning post-launch (not done here). Cost rows attach to
--             whichever of lead/call/message is relevant (all nullable).
-- Forward-only. Immutable once merged.
-- =====================================================================

create table usage_logs (
  id                 uuid primary key default gen_random_uuid(),
  company_id         uuid not null references companies(id) on delete cascade,
  lead_id            uuid references leads(id) on delete set null,
  call_id            uuid references calls(id) on delete set null,
  message_id         uuid references messages(id) on delete set null,
  service            usage_service not null,
  operation          text not null,                 -- chat_completion | embedding | stt_stream | tts | call_minutes | whatsapp | sms ...
  provider_reference text,                           -- upstream request id
  quantity           numeric(16,4) not null default 0,
  unit               usage_unit not null,
  unit_cost          numeric(16,8),                  -- cost per unit
  cost               numeric(14,6) not null default 0,
  currency           text not null default 'USD',    -- telephony often INR; reporting normalizes
  metadata           jsonb not null default '{}'::jsonb,
  occurred_at        timestamptz not null default now(),
  created_at         timestamptz not null default now()
);
create index idx_usage_company_time    on usage_logs(company_id, occurred_at desc);
create index idx_usage_company_service on usage_logs(company_id, service, occurred_at desc);
create index idx_usage_call            on usage_logs(call_id);
create index idx_usage_lead            on usage_logs(lead_id);
