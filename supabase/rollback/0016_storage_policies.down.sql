-- Rollback : 0016_storage_policies  (local/staging only)
-- Reverses 0016. Buckets are dropped only if empty; object data is not deleted here.

drop policy if exists recordings_tenant_select on storage.objects;
drop policy if exists documents_admin_delete   on storage.objects;
drop policy if exists documents_admin_update   on storage.objects;
drop policy if exists documents_admin_insert   on storage.objects;
drop policy if exists documents_tenant_select  on storage.objects;

-- Remove buckets only when they hold no objects (safety).
delete from storage.buckets b
 where b.id in ('documents','recordings')
   and not exists (select 1 from storage.objects o where o.bucket_id = b.id);

-- Note: RLS on storage.objects is left ENABLED (it is the Supabase default
-- and other policies may depend on it). Do not disable it on rollback.
