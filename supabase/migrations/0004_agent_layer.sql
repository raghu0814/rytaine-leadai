-- =====================================================================
-- Migration : 0004_agent_layer
-- Milestone : M0-3 (schema)
-- Concern   : Agent configuration (tables 3-5 of 16)
-- Depends on: 0003_tenant_core
-- Order     : prompts -> knowledge_bases -> agent_configs
--             (agent_configs FKs both prompts and knowledge_bases)
-- Forward-only. Immutable once merged.
-- =====================================================================

-- prompts — versioned Telugu agent scripts.
create table prompts (
  id            uuid primary key default gen_random_uuid(),
  company_id    uuid not null references companies(id) on delete cascade,
  name          text not null,
  version       int  not null default 1,
  language      text not null default 'te',
  system_prompt text not null,
  opening_line  text,
  variables     jsonb not null default '{}'::jsonb,
  is_active     boolean not null default false,
  created_by    uuid references users(id) on delete set null,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  unique (company_id, name, version)
);
create index idx_prompts_company_active on prompts(company_id, is_active);

-- knowledge_bases — RAG store root; referenced by agent_configs.
create table knowledge_bases (
  id          uuid primary key default gen_random_uuid(),
  company_id  uuid not null references companies(id) on delete cascade,
  name        text not null,
  description text,
  status      kb_status not null default 'active',
  is_default  boolean not null default false,
  created_by  uuid references users(id) on delete set null,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create index idx_kb_company on knowledge_bases(company_id);
-- At most one default KB per company.
create unique index idx_kb_one_default on knowledge_bases(company_id) where is_default;

-- agent_configs — per-tenant agent behaviour (model/voice/telephony/retry).
create table agent_configs (
  id                 uuid primary key default gen_random_uuid(),
  company_id         uuid not null references companies(id) on delete cascade,
  name               text not null,
  prompt_id          uuid references prompts(id) on delete set null,
  knowledge_base_id  uuid references knowledge_bases(id) on delete set null,
  llm_provider       llm_provider not null default 'openai',
  llm_model          text not null default 'gpt-4o',
  stt_provider       stt_provider not null default 'deepgram',
  stt_model          text not null default 'nova-3',
  tts_provider       tts_provider not null default 'elevenlabs',
  voice_id           text,
  telephony_provider telephony_provider not null default 'twilio',
  max_attempts       int  not null default 3,
  retry_intervals    jsonb not null default '[0, 3600, 86400]'::jsonb,  -- seconds
  qualification_fields jsonb not null default '[]'::jsonb,
  scoring_rules      jsonb not null default '{}'::jsonb,
  is_active          boolean not null default false,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now()
);
create index idx_agent_configs_company_active on agent_configs(company_id, is_active);
