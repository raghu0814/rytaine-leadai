-- =====================================================================
-- Migration : 0007_calls_scheduling
-- Milestone : M0-3 (schema)
-- Concern   : Scheduling intent + call outcomes + artifacts
--             (tables 8-11 of 16: call_schedules, calls, transcripts, recordings)
-- Depends on: 0005_leads, 0004_agent_layer, 0003_tenant_core
-- Order     : call_schedules -> calls -> (deferred FK back to calls)
--             -> transcripts -> recordings
--             call_schedules.call_id FK is added AFTER calls exists
--             (circular reference broken with ALTER TABLE).
-- Forward-only. Immutable once merged.
-- =====================================================================

-- call_schedules — planned/queued attempts (intent). The scheduler polls this.
create table call_schedules (
  id               uuid primary key default gen_random_uuid(),
  company_id       uuid not null references companies(id) on delete cascade,
  lead_id          uuid not null references leads(id) on delete cascade,
  agent_config_id  uuid references agent_configs(id) on delete set null,
  scheduled_at     timestamptz not null,
  attempt_number   int not null default 1,
  reason           schedule_reason not null default 'initial',
  status           schedule_status not null default 'pending',
  call_id          uuid,                            -- FK added after calls (see below)
  created_by       uuid references users(id) on delete set null,
  notes            text,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);
-- scheduler hot path: only pending & due rows
create index idx_call_schedules_due  on call_schedules(status, scheduled_at)
  where status = 'pending';
create index idx_call_schedules_lead on call_schedules(company_id, lead_id);

-- calls — one row per dial attempt (outcome / record).
create table calls (
  id                  uuid primary key default gen_random_uuid(),
  company_id          uuid not null references companies(id) on delete cascade,
  lead_id             uuid not null references leads(id) on delete cascade,
  call_schedule_id    uuid references call_schedules(id) on delete set null,
  agent_config_id     uuid references agent_configs(id) on delete set null,
  provider            telephony_provider not null default 'twilio',
  call_sid            text unique,                 -- provider call id
  direction           call_direction not null default 'outbound',
  attempt_number      int not null default 1,
  call_status         call_status not null default 'queued',
  started_at          timestamptz,
  ended_at            timestamptz,
  duration_seconds    int,
  sentiment           call_sentiment,
  qualification_score int,
  summary             text,
  error_code          text,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now()
);
create index idx_calls_company_lead   on calls(company_id, lead_id);
create index idx_calls_company_status on calls(company_id, call_status);

-- back-reference now that calls exists
alter table call_schedules
  add constraint fk_call_schedules_call
  foreign key (call_id) references calls(id) on delete set null;

-- transcripts — 1:1 with a call (service-role written, read-only to clients).
create table transcripts (
  id          uuid primary key default gen_random_uuid(),
  company_id  uuid not null references companies(id) on delete cascade,
  call_id     uuid not null references calls(id) on delete cascade,
  language    text not null default 'te',
  full_text   text,
  segments    jsonb not null default '[]'::jsonb,  -- [{speaker,start_ms,end_ms,text,confidence}]
  provider    stt_provider not null default 'deepgram',
  created_at  timestamptz not null default now(),
  unique (call_id)
);

-- recordings — audio file references (never raw bytes in DB).
create table recordings (
  id               uuid primary key default gen_random_uuid(),
  company_id       uuid not null references companies(id) on delete cascade,
  call_id          uuid not null references calls(id) on delete cascade,
  storage_path     text not null,                  -- private bucket key; signed URL on read
  duration_seconds int,
  format           text,
  size_bytes       bigint,
  channels         int,
  is_encrypted     boolean not null default true,
  created_at       timestamptz not null default now()
);
create index idx_recordings_call on recordings(call_id);
