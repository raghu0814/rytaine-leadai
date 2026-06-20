-- =====================================================================
-- Migration : 0016_storage_policies
-- Milestone : M0-4
-- Concern   : Private storage buckets (documents, recordings) + tenant
--             isolation policies on storage.objects.
-- Depends on: 0014_rls_helpers.
-- Forward-only. Immutable once merged.
-- ---------------------------------------------------------------------
-- Path convention: the first folder segment of an object name is the
-- tenant -> objects live at '<company_id>/<...>'. The backend authorizes
-- and mints short-lived signed URLs via service_role; these policies are
-- the isolation backstop for any direct `authenticated` access.
--
-- RLS on storage.objects is ENABLED (Supabase enables it already; the
-- statement is idempotent) but NOT forced: storage.objects is owned by the
-- storage admin role, and forcing would break the internal storage service.
-- service_role bypasses RLS, so backend object writes are unaffected.
-- =====================================================================

-- ---- buckets (private; idempotent) ----
insert into storage.buckets (id, name, public)
values ('documents','documents',false),
       ('recordings','recordings',false)
on conflict (id) do nothing;

-- ---- ensure RLS is active on storage.objects ----
-- alter table storage.objects enable row level security;

-- ---- documents: tenant read; admin write (service bypasses) ----
create policy documents_tenant_select on storage.objects for select to authenticated
  using (
    bucket_id = 'documents'
    and (storage.foldername(name))[1] = public.current_company_id()::text
  );
create policy documents_admin_insert on storage.objects for insert to authenticated
  with check (
    bucket_id = 'documents'
    and (storage.foldername(name))[1] = public.current_company_id()::text
    and public.current_user_role() = 'admin'
  );
create policy documents_admin_update on storage.objects for update to authenticated
  using (
    bucket_id = 'documents'
    and (storage.foldername(name))[1] = public.current_company_id()::text
    and public.current_user_role() = 'admin'
  )
  with check (
    bucket_id = 'documents'
    and (storage.foldername(name))[1] = public.current_company_id()::text
    and public.current_user_role() = 'admin'
  );
create policy documents_admin_delete on storage.objects for delete to authenticated
  using (
    bucket_id = 'documents'
    and (storage.foldername(name))[1] = public.current_company_id()::text
    and public.current_user_role() = 'admin'
  );

-- ---- recordings: tenant read only; writes via service_role only ----
create policy recordings_tenant_select on storage.objects for select to authenticated
  using (
    bucket_id = 'recordings'
    and (storage.foldername(name))[1] = public.current_company_id()::text
  );
