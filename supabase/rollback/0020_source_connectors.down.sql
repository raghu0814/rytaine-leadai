-- =====================================================================
-- Rollback : 0020_source_connectors.down  (local/staging only; prod is forward-only)
-- Reverses : 0020_source_connectors
-- ---------------------------------------------------------------------
-- DROP TABLE ... CASCADE atomically removes the dependent policy
-- (source_connectors_select_admin), the grants (table + column), all three
-- indexes (company + the two partial-unique routing indexes), the four CHECK
-- constraints, the FK, the RLS flags, and the trg_source_connectors_updated
-- trigger.
--
-- set_updated_at() is the SHARED function created in 0012 and used by ten M0
-- tables — it is intentionally NOT dropped here.
--
-- IF EXISTS + CASCADE make this idempotent and safe to re-run.
-- =====================================================================

drop table if exists public.source_connectors cascade;
