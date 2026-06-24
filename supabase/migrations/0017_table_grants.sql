-- =====================================================================
-- Migration : 0017_table_grants
-- Milestone : M0-4-R (RLS table-grants remediation)
-- Concern   : Grant the base table privileges that every M0-4 RLS policy
--             sits on top of. RLS filters rows; it never grants access.
--             0014-0016 enabled+forced RLS and wrote policies but granted
--             no table DML, so `authenticated`/`service_role` hit
--             "permission denied for table ..." before RLS is ever reached.
-- Depends on: 0015_rls_policies (policies), 0001-0013 (tables).
-- Forward-only. Additive. Modifies no prior migration. Immutable once merged.
-- ---------------------------------------------------------------------
-- Design (approved):
--  * authenticated  -> grants MIRROR the 0015 policy surface exactly
--    (least privilege): a privilege is granted only where a matching policy
--    exists. RLS + FORCE then enforce tenant/role isolation per row.
--  * service_role    -> carries BYPASSRLS, so grants are its ONLY DB-level
--    guard. Full DML on the 14 operational tables; INSERT + SELECT ONLY on
--    the two immutable tables (usage_logs, audit_logs) so append-only holds
--    for backend workers today (no UPDATE/DELETE path), independent of any
--    future guard trigger.
--  * anon            -> NOTHING (no anon policy exists; anon stays denied).
--  * GRANT is idempotent, so re-apply is a no-op.
--
-- Why not ALTER DEFAULT PRIVILEGES: it is role/context-specific and would
-- behave differently across CI vs Railway runners (the same environment
-- coupling that produced this defect). Every future CREATE TABLE migration
-- must instead ship its own grants alongside its RLS policies.
-- =====================================================================

-- ---- 0. Schema usage (defensive + idempotent) -----------------------
-- Supabase already grants this; restating makes the migration self-contained
-- and not reliant on ambient platform state. The rollback intentionally does
-- NOT revoke this (other objects depend on schema visibility).
grant usage on schema public to authenticated, service_role;

-- =====================================================================
-- 1. service_role  (BYPASSRLS) — backend worker write path
-- =====================================================================

-- Operational tables: full DML.
grant select, insert, update, delete on table
  public.companies,
  public.users,
  public.prompts,
  public.knowledge_bases,
  public.agent_configs,
  public.leads,
  public.lead_notes,
  public.call_schedules,
  public.calls,
  public.transcripts,
  public.recordings,
  public.messages,
  public.documents,
  public.document_chunks
to service_role;

-- Immutable tables: INSERT + SELECT only (append-only preserved for service_role).
grant select, insert on table
  public.usage_logs,
  public.audit_logs
to service_role;

-- =====================================================================
-- 2. authenticated — grants mirror the 0015 policy surface (least privilege)
-- =====================================================================

-- Full DML (tables whose policy set covers select+insert+update+delete).
grant select, insert, update, delete on table
  public.users,
  public.prompts,
  public.knowledge_bases,
  public.agent_configs,
  public.leads,
  public.lead_notes,
  public.call_schedules,
  public.documents
to authenticated;

-- companies: select + update only (no authenticated insert/delete policy).
grant select, update on table public.companies to authenticated;

-- messages: select + insert only (update is service_role; no delete policy).
grant select, insert on table public.messages to authenticated;

-- Read-only / service-written tables: select only.
grant select on table
  public.calls,
  public.transcripts,
  public.recordings,
  public.document_chunks,
  public.usage_logs,
  public.audit_logs
to authenticated;
