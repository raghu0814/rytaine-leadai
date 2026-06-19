-- DOWN for 0013_dedup_trigger. Local/staging only; prod uses PITR.
drop trigger if exists trg_leads_flag_duplicate on leads;
drop function if exists flag_potential_duplicate_lead();
