-- DOWN for 0011_audit_logs. Local/staging only; prod uses PITR.
drop table if exists audit_logs cascade;
