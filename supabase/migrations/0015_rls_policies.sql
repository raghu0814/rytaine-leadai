-- =====================================================================
-- Migration : 0015_rls_policies
-- Milestone : M0-4
-- Concern   : Enable + FORCE row-level security on every tenant table,
--             then apply per-table tenant/role policies.
-- Depends on: 0014_rls_helpers.
-- Forward-only. Immutable once merged.
-- ---------------------------------------------------------------------
-- Model:
--  * Tenant predicate: companies uses `id = current_company_id()`;
--    all other 15 tables use `company_id = current_company_id()`.
--  * Roles (user_role): admin, manager, agent, viewer. "manager+" = {manager,admin}.
--  * service_role carries BYPASSRLS by design -> backend workers write freely;
--    append-only / service-written tables therefore omit authenticated write
--    policies (clients cannot write; service can).
--  * Policies target `to authenticated`; anon has no policy => denied.
--  * FORCE makes policies apply even to the table owner (defense in depth).
-- =====================================================================

-- ---- 1. Enable + FORCE RLS on EVERY public table (no table left open) ----
do $$
declare r record;
begin
  for r in select tablename from pg_tables where schemaname = 'public' loop
    execute format('alter table public.%I enable row level security', r.tablename);
    execute format('alter table public.%I force  row level security', r.tablename);
  end loop;
end $$;

-- =====================================================================
-- 2. Per-table policies
-- =====================================================================

-- ---------- companies (tenant key = id) ----------
create policy companies_select on companies for select to authenticated
  using (id = public.current_company_id());
create policy companies_update_admin on companies for update to authenticated
  using (id = public.current_company_id())
  with check (id = public.current_company_id() and public.current_user_role() = 'admin');
-- insert/delete: service_role only (no authenticated policy)

-- ---------- users (admin-managed) ----------
create policy users_select on users for select to authenticated
  using (company_id = public.current_company_id());
create policy users_insert_admin on users for insert to authenticated
  with check (company_id = public.current_company_id() and public.current_user_role() = 'admin');
create policy users_update_admin on users for update to authenticated
  using (company_id = public.current_company_id() and public.current_user_role() = 'admin')
  with check (company_id = public.current_company_id() and public.current_user_role() = 'admin');
create policy users_delete_admin on users for delete to authenticated
  using (company_id = public.current_company_id() and public.current_user_role() = 'admin');

-- ---------- prompts (admin-managed) ----------
create policy prompts_select on prompts for select to authenticated
  using (company_id = public.current_company_id());
create policy prompts_insert_admin on prompts for insert to authenticated
  with check (company_id = public.current_company_id() and public.current_user_role() = 'admin');
create policy prompts_update_admin on prompts for update to authenticated
  using (company_id = public.current_company_id() and public.current_user_role() = 'admin')
  with check (company_id = public.current_company_id() and public.current_user_role() = 'admin');
create policy prompts_delete_admin on prompts for delete to authenticated
  using (company_id = public.current_company_id() and public.current_user_role() = 'admin');

-- ---------- knowledge_bases (admin-managed) ----------
create policy kb_select on knowledge_bases for select to authenticated
  using (company_id = public.current_company_id());
create policy kb_insert_admin on knowledge_bases for insert to authenticated
  with check (company_id = public.current_company_id() and public.current_user_role() = 'admin');
create policy kb_update_admin on knowledge_bases for update to authenticated
  using (company_id = public.current_company_id() and public.current_user_role() = 'admin')
  with check (company_id = public.current_company_id() and public.current_user_role() = 'admin');
create policy kb_delete_admin on knowledge_bases for delete to authenticated
  using (company_id = public.current_company_id() and public.current_user_role() = 'admin');

-- ---------- agent_configs (admin-managed) ----------
create policy agent_configs_select on agent_configs for select to authenticated
  using (company_id = public.current_company_id());
create policy agent_configs_insert_admin on agent_configs for insert to authenticated
  with check (company_id = public.current_company_id() and public.current_user_role() = 'admin');
create policy agent_configs_update_admin on agent_configs for update to authenticated
  using (company_id = public.current_company_id() and public.current_user_role() = 'admin')
  with check (company_id = public.current_company_id() and public.current_user_role() = 'admin');
create policy agent_configs_delete_admin on agent_configs for delete to authenticated
  using (company_id = public.current_company_id() and public.current_user_role() = 'admin');

-- ---------- leads (manager+ write) ----------
create policy leads_select on leads for select to authenticated
  using (company_id = public.current_company_id());
create policy leads_insert_mgr on leads for insert to authenticated
  with check (company_id = public.current_company_id() and public.current_user_role() in ('manager','admin'));
create policy leads_update_mgr on leads for update to authenticated
  using (company_id = public.current_company_id() and public.current_user_role() in ('manager','admin'))
  with check (company_id = public.current_company_id() and public.current_user_role() in ('manager','admin'));
create policy leads_delete_mgr on leads for delete to authenticated
  using (company_id = public.current_company_id() and public.current_user_role() in ('manager','admin'));

-- ---------- lead_notes (agent+ insert; admin manage) ----------
-- NOTE: author-scoped edit (user_id = caller) needs a current_user_id()/auth.uid()
-- helper that is OUTSIDE the approved M0-4 helper set; update/delete are
-- admin-scoped here. See discrepancy D-2 in the runbook.
create policy lead_notes_select on lead_notes for select to authenticated
  using (company_id = public.current_company_id());
create policy lead_notes_insert on lead_notes for insert to authenticated
  with check (company_id = public.current_company_id() and public.current_user_role() in ('agent','manager','admin'));
create policy lead_notes_update_admin on lead_notes for update to authenticated
  using (company_id = public.current_company_id() and public.current_user_role() = 'admin')
  with check (company_id = public.current_company_id() and public.current_user_role() = 'admin');
create policy lead_notes_delete_admin on lead_notes for delete to authenticated
  using (company_id = public.current_company_id() and public.current_user_role() = 'admin');

-- ---------- call_schedules (manager+ write) ----------
create policy call_schedules_select on call_schedules for select to authenticated
  using (company_id = public.current_company_id());
create policy call_schedules_insert_mgr on call_schedules for insert to authenticated
  with check (company_id = public.current_company_id() and public.current_user_role() in ('manager','admin'));
create policy call_schedules_update_mgr on call_schedules for update to authenticated
  using (company_id = public.current_company_id() and public.current_user_role() in ('manager','admin'))
  with check (company_id = public.current_company_id() and public.current_user_role() in ('manager','admin'));
create policy call_schedules_delete_mgr on call_schedules for delete to authenticated
  using (company_id = public.current_company_id() and public.current_user_role() in ('manager','admin'));

-- ---------- calls (service-written; tenant read-only) ----------
create policy calls_select on calls for select to authenticated
  using (company_id = public.current_company_id());
-- insert/update/delete: service_role only

-- ---------- transcripts (service-written; tenant read-only) ----------
create policy transcripts_select on transcripts for select to authenticated
  using (company_id = public.current_company_id());

-- ---------- recordings (service-written; tenant read-only) ----------
create policy recordings_select on recordings for select to authenticated
  using (company_id = public.current_company_id());

-- ---------- messages (manager+ insert; service updates) ----------
create policy messages_select on messages for select to authenticated
  using (company_id = public.current_company_id());
create policy messages_insert_mgr on messages for insert to authenticated
  with check (company_id = public.current_company_id() and public.current_user_role() in ('manager','admin'));
-- update: service_role only; delete: none

-- ---------- documents (admin write) ----------
create policy documents_select on documents for select to authenticated
  using (company_id = public.current_company_id());
create policy documents_insert_admin on documents for insert to authenticated
  with check (company_id = public.current_company_id() and public.current_user_role() = 'admin');
create policy documents_update_admin on documents for update to authenticated
  using (company_id = public.current_company_id() and public.current_user_role() = 'admin')
  with check (company_id = public.current_company_id() and public.current_user_role() = 'admin');
create policy documents_delete_admin on documents for delete to authenticated
  using (company_id = public.current_company_id() and public.current_user_role() = 'admin');

-- ---------- document_chunks (service-written; tenant read-only) ----------
create policy document_chunks_select on document_chunks for select to authenticated
  using (company_id = public.current_company_id());

-- ---------- usage_logs (admin read; append-only, service writes) ----------
create policy usage_logs_select_admin on usage_logs for select to authenticated
  using (company_id = public.current_company_id() and public.current_user_role() = 'admin');
-- insert: service_role only; no update/delete => append-only for clients

-- ---------- audit_logs (admin read; append-only, service writes) ----------
create policy audit_logs_select_admin on audit_logs for select to authenticated
  using (company_id = public.current_company_id() and public.current_user_role() = 'admin');
-- insert: service_role only; no update/delete => append-only for clients
