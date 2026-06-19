-- DOWN for 0003_tenant_core. Local/staging only; prod uses PITR.
drop table if exists users cascade;
drop table if exists companies cascade;
