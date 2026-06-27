-- =====================================================================
-- Migration : 0019_privilege_floor_remediation
-- Milestone : M0-9 (full-schema privilege-floor remediation)  [PROPOSED label]
-- Concern   : Supabase platform default privileges
--               ALTER DEFAULT PRIVILEGES IN SCHEMA public
--               GRANT ALL ON TABLES TO anon, authenticated, service_role
--             auto-grant the FULL privilege set to all three roles on every
--             table at CREATE TABLE time. GRANT is additive; 0017 granted the
--             intended surface ON TOP of these defaults and never revoked them.
--             Net effect on the live Supabase stack:
--               * anon + authenticated hold TRUNCATE on every M0 table, and
--                 TRUNCATE is NOT subject to RLS -> an RLS-immune full-table wipe
--                 by untrusted roles.
--               * service_role (BYPASSRLS) holds UPDATE/DELETE/TRUNCATE on the
--                 append-only tables (usage_logs, audit_logs) -> append-only is
--                 unenforced.
--             This migration REVOKE-FIRSTs every M0 table (PUBLIC + the three
--             roles) and re-asserts EXACTLY the 0017 intended least-privilege
--             surface, so no role retains TRUNCATE / REFERENCES / TRIGGER or any
--             privilege beyond design.
-- Depends on: 0017_table_grants (authoritative intended surface), 0001-0016.
-- Scope     : the 16 M0 tables. lead_events (0018) self-remediates REVOKE-first
--             and is re-verified by the proof suite, not re-granted here.
-- Note      : forward-only. Modifies no prior (frozen) migration. GRANT/REVOKE
--             are idempotent, so re-apply is a no-op. Immutable once merged.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Strip ALL privileges from PUBLIC and the three roles on every M0 table.
--    This neutralises the platform default-privilege grants AND the 0017
--    grants in one deterministic step; section 2 re-establishes intent.
-- ---------------------------------------------------------------------
revoke all on table
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
  public.document_chunks,
  public.usage_logs,
  public.audit_logs
from public, anon, authenticated, service_role;

-- ---------------------------------------------------------------------
-- 2. Re-assert the EXACT 0017 intended least-privilege surface.
--    (verbatim re-statement of 0017 sections 1 and 2; no TRUNCATE anywhere)
-- ---------------------------------------------------------------------

-- 2a. service_role (BYPASSRLS) — backend worker write path.
--     Operational tables: full DML. Immutable tables: SELECT + INSERT only.
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

grant select, insert on table
  public.usage_logs,
  public.audit_logs
to service_role;

-- 2b. authenticated — grants mirror the 0015 policy surface (least privilege).
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

grant select, update on table public.companies to authenticated;

grant select, insert on table public.messages to authenticated;

grant select on table
  public.calls,
  public.transcripts,
  public.recordings,
  public.document_chunks,
  public.usage_logs,
  public.audit_logs
to authenticated;

-- 2c. anon — NOTHING. No anon policy exists; anon stays denied. (no grants)
