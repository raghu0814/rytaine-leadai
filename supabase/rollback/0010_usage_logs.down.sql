-- DOWN for 0010_usage_logs. Local/staging only; prod uses PITR.
drop table if exists usage_logs cascade;
