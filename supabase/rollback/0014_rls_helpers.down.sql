-- Rollback : 0014_rls_helpers  (local/staging only)
-- Drops the helper functions. Run only AFTER 0015 rollback, since policies
-- depend on these functions.

drop function if exists public.current_user_role();
drop function if exists public.current_company_id();
