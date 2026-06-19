-- DOWN for 0005_leads. Local/staging only; prod uses PITR.
-- Self-FK (duplicate_of_lead_id) is dropped with the table.
drop table if exists leads cascade;
