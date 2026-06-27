-- =====================================================================
-- Rollback  : 0019_privilege_floor_remediation
-- =====================================================================
-- This is a forward-only SECURITY remediation. Its rollback re-asserts the
-- 0017 intended least-privilege surface and INTENTIONALLY does NOT restore the
-- Supabase platform default-privilege ALL grants that 0019 removed — doing so
-- would re-introduce the RLS-immune TRUNCATE exposure (anon/authenticated) and
-- the append-only break (service_role) on every M0 table.
--
-- Therefore "rolling back" 0019 returns the schema to the secure 0017 floor,
-- which is the correct prior *intent*. The grants below are idempotent.
-- =====================================================================

-- service_role (BYPASSRLS) — backend worker write path.
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

-- authenticated — grants mirror the 0015 policy surface (least privilege).
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

-- anon — remains with no grants.
