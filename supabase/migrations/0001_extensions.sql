-- =====================================================================
-- Migration : 0001_extensions
-- Milestone : M0-3 (schema)
-- Concern   : PostgreSQL extensions
-- Depends on: — (first migration)
-- Forward-only. Immutable once merged. Do not edit; fix forward.
-- =====================================================================
-- pgcrypto  -> gen_random_uuid() for UUID primary keys
-- vector    -> pgvector, RAG embeddings (vector(1536))
-- Both are idempotent (IF NOT EXISTS) so a re-run on a primed DB is safe.

create extension if not exists pgcrypto;
create extension if not exists vector;
