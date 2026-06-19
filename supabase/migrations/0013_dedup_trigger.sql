-- =====================================================================
-- Migration : 0013_dedup_trigger
-- Milestone : M0-3 (schema)
-- Concern   : Soft deduplication — FLAG (never reject) same-phone leads
-- Depends on: 0005_leads (columns is_potential_duplicate, duplicate_of_lead_id;
--             index idx_leads_phone), 0012 (kept separate: business logic vs
--             generic updated_at maintenance — one concern per file).
--
-- Behaviour (locked): On INSERT, if another lead in the SAME company has the
-- SAME phone and was created within the last 30 days, set:
--     NEW.is_potential_duplicate = true
--     NEW.duplicate_of_lead_id   = <id of the most recent such lead>
-- The row is ALWAYS inserted. This complements the HARD unique constraint
-- (company_id, source, external_lead_id), which does not catch manual/cross-
-- source re-entry of the same phone.
--
-- Forward-only. Immutable once merged.
-- =====================================================================

create or replace function flag_potential_duplicate_lead()
returns trigger
language plpgsql
as $$
declare
  v_existing_id uuid;
begin
  select l.id
    into v_existing_id
    from leads l
   where l.company_id = new.company_id
     and l.phone      = new.phone
     and l.created_at >= (now() - interval '30 days')
   order by l.created_at desc
   limit 1;

  if v_existing_id is not null then
    new.is_potential_duplicate := true;
    new.duplicate_of_lead_id   := v_existing_id;
  end if;

  return new;
end;
$$;

create trigger trg_leads_flag_duplicate
  before insert on leads
  for each row execute function flag_potential_duplicate_lead();
