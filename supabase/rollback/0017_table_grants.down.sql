-- Rollback : 0017_table_grants  (local/staging only)
-- Reverses 0017 by revoking the table DML grants from authenticated and
-- service_role, returning the schema to its pre-0017 state (no table grants).
-- REVOKE is idempotent. The pre-0017 state provably held zero table grants
-- for these roles, so REVOKE ALL is an exact reversal.
--
-- NOTE: schema USAGE on public is intentionally NOT revoked. It is the
-- Supabase default and other objects depend on schema visibility; revoking
-- it would break all access, not just 0017's additions.

revoke all privileges on table
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
from authenticated, service_role;
