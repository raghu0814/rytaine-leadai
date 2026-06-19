-- DOWN for 0008_messaging. Local/staging only; prod uses PITR.
drop table if exists messages cascade;
