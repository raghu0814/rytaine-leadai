-- =====================================================================
-- Rollback : 0018_lead_events.down   (local/staging only; prod is forward-only)
-- Reverses : 0018_lead_events
-- ---------------------------------------------------------------------
-- DROP TABLE atomically removes the dependent policy (lead_events_select_admin),
-- the grants, both indexes, the UNIQUE + CHECK constraints, and the RLS flags.
-- No triggers or functions were introduced (A1-2), so none are dropped here.
-- IF EXISTS + CASCADE make this idempotent and safe to re-run.
-- =====================================================================

drop table if exists public.lead_events cascade;
