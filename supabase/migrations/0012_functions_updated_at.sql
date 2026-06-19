-- =====================================================================
-- Migration : 0012_functions_updated_at
-- Milestone : M0-3 (schema)
-- Concern   : Generic updated_at maintenance (function + triggers)
-- Depends on: all table migrations (0003-0011)
-- Scope     : Schema functions/triggers ONLY. RLS helper functions
--             (current_company_id / current_user_role) are M0-4 — NOT here.
-- Targets   : the 10 tables that carry `updated_at`:
--             companies, users, prompts, knowledge_bases, agent_configs,
--             leads, call_schedules, calls, messages, documents.
--             (lead_notes, transcripts, recordings, document_chunks,
--              usage_logs, audit_logs are created-once — no updated_at.)
-- Forward-only. Immutable once merged.
-- =====================================================================

create or replace function set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger trg_companies_updated       before update on companies
  for each row execute function set_updated_at();
create trigger trg_users_updated           before update on users
  for each row execute function set_updated_at();
create trigger trg_prompts_updated         before update on prompts
  for each row execute function set_updated_at();
create trigger trg_knowledge_bases_updated before update on knowledge_bases
  for each row execute function set_updated_at();
create trigger trg_agent_configs_updated   before update on agent_configs
  for each row execute function set_updated_at();
create trigger trg_leads_updated           before update on leads
  for each row execute function set_updated_at();
create trigger trg_call_schedules_updated  before update on call_schedules
  for each row execute function set_updated_at();
create trigger trg_calls_updated           before update on calls
  for each row execute function set_updated_at();
create trigger trg_messages_updated        before update on messages
  for each row execute function set_updated_at();
create trigger trg_documents_updated       before update on documents
  for each row execute function set_updated_at();
