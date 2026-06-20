-- Rollback : 0015_rls_policies  (local/staging only)
-- Drops every policy created in 0015, then unforces + disables RLS on all
-- public tables (returns the schema to its post-0013 state).

-- ---- drop policies (idempotent) ----
drop policy if exists companies_select            on companies;
drop policy if exists companies_update_admin      on companies;

drop policy if exists users_select                on users;
drop policy if exists users_insert_admin          on users;
drop policy if exists users_update_admin          on users;
drop policy if exists users_delete_admin          on users;

drop policy if exists prompts_select              on prompts;
drop policy if exists prompts_insert_admin        on prompts;
drop policy if exists prompts_update_admin        on prompts;
drop policy if exists prompts_delete_admin        on prompts;

drop policy if exists kb_select                   on knowledge_bases;
drop policy if exists kb_insert_admin             on knowledge_bases;
drop policy if exists kb_update_admin             on knowledge_bases;
drop policy if exists kb_delete_admin             on knowledge_bases;

drop policy if exists agent_configs_select        on agent_configs;
drop policy if exists agent_configs_insert_admin  on agent_configs;
drop policy if exists agent_configs_update_admin  on agent_configs;
drop policy if exists agent_configs_delete_admin  on agent_configs;

drop policy if exists leads_select                on leads;
drop policy if exists leads_insert_mgr            on leads;
drop policy if exists leads_update_mgr            on leads;
drop policy if exists leads_delete_mgr            on leads;

drop policy if exists lead_notes_select           on lead_notes;
drop policy if exists lead_notes_insert           on lead_notes;
drop policy if exists lead_notes_update_admin     on lead_notes;
drop policy if exists lead_notes_delete_admin     on lead_notes;

drop policy if exists call_schedules_select       on call_schedules;
drop policy if exists call_schedules_insert_mgr   on call_schedules;
drop policy if exists call_schedules_update_mgr   on call_schedules;
drop policy if exists call_schedules_delete_mgr   on call_schedules;

drop policy if exists calls_select                on calls;
drop policy if exists transcripts_select          on transcripts;
drop policy if exists recordings_select           on recordings;

drop policy if exists messages_select             on messages;
drop policy if exists messages_insert_mgr         on messages;

drop policy if exists documents_select            on documents;
drop policy if exists documents_insert_admin      on documents;
drop policy if exists documents_update_admin      on documents;
drop policy if exists documents_delete_admin      on documents;

drop policy if exists document_chunks_select      on document_chunks;

drop policy if exists usage_logs_select_admin     on usage_logs;
drop policy if exists audit_logs_select_admin     on audit_logs;

-- ---- unforce + disable RLS on all public tables ----
do $$
declare r record;
begin
  for r in select tablename from pg_tables where schemaname = 'public' loop
    execute format('alter table public.%I no force row level security', r.tablename);
    execute format('alter table public.%I disable row level security', r.tablename);
  end loop;
end $$;
