-- DOWN for 0009_rag. Local/staging only; prod uses PITR.
drop table if exists document_chunks cascade;
drop table if exists documents cascade;
