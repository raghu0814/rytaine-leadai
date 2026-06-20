-- =====================================================================
-- Migration : 0014_rls_helpers
-- Milestone : M0-4 (RLS, storage policies & helper functions)
-- Concern   : JWT-claim reader functions used by every RLS policy.
-- Depends on: 0001-0013 (schema). Precedes 0015_rls_policies.
-- Forward-only. Immutable once merged.
-- ---------------------------------------------------------------------
-- These functions read the *verified* JWT payload that the request layer
-- injects into the transaction-local GUC `request.jwt.claims`. Identity
-- claims live under `app_metadata` (server-controlled, untamperable).
--
-- Runtime contract (enforced by the FastAPI DB-session dependency, NOT here):
--   SET LOCAL ROLE authenticated;
--   SET LOCAL request.jwt.claims =
--     '{"app_metadata":{"company_id":"<uuid>","role":"<role>"}}';
-- Must run inside an explicit transaction (Supavisor transaction pooler:
-- session-level SET would leak across pooled clients).
--
-- `current_setting(..., true)` is the same source Supabase's auth.jwt()
-- reads; using it directly keeps these portable to the bare-Postgres
-- pgTAP rig. The `true` (missing_ok) arg yields NULL when the GUC is unset.
-- =====================================================================

create or replace function public.current_company_id()
returns uuid
language sql
stable
set search_path = ''
as $$
  select nullif(
    current_setting('request.jwt.claims', true)::jsonb -> 'app_metadata' ->> 'company_id',
    ''
  )::uuid
$$;

comment on function public.current_company_id() is
  'Tenant UUID from the verified JWT app_metadata.company_id claim; NULL if unset.';

create or replace function public.current_user_role()
returns text
language sql
stable
set search_path = ''
as $$
  select current_setting('request.jwt.claims', true)::jsonb -> 'app_metadata' ->> 'role'
$$;

comment on function public.current_user_role() is
  'Authorization role from the verified JWT app_metadata.role claim; NULL if unset.';

-- Policies are evaluated as the calling role; ensure it can execute helpers.
grant execute on function public.current_company_id() to anon, authenticated, service_role;
grant execute on function public.current_user_role() to anon, authenticated, service_role;
