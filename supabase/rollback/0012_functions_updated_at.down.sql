-- DOWN for 0012_functions_updated_at. Local/staging only; prod uses PITR.
drop trigger if exists trg_documents_updated       on documents;
drop trigger if exists trg_messages_updated        on messages;
drop trigger if exists trg_calls_updated           on calls;
drop trigger if exists trg_call_schedules_updated  on call_schedules;
drop trigger if exists trg_leads_updated           on leads;
drop trigger if exists trg_agent_configs_updated   on agent_configs;
drop trigger if exists trg_knowledge_bases_updated on knowledge_bases;
drop trigger if exists trg_prompts_updated         on prompts;
drop trigger if exists trg_users_updated           on users;
drop trigger if exists trg_companies_updated       on companies;
drop function if exists set_updated_at();
