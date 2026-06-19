-- =====================================================================
-- Migration : 0009_rag
-- Milestone : M0-3 (schema)
-- Concern   : RAG store — documents + chunks (tables 13-14 of 16)
-- Depends on: 0004_agent_layer (knowledge_bases), 0003_tenant_core
-- Embeddings: vector(1536), text-embedding-3-small.
-- Retrieval : ALWAYS pre-filter by (company_id, knowledge_base_id), then
--             cosine ANN — tenant isolation holds inside vector search.
-- Index     : HNSW (vector_cosine_ops). Safe to create up-front on empty
--             tables. For large historical back-loads, prefer creating the
--             HNSW index AFTER bulk insert (separate forward migration).
-- Forward-only. Immutable once merged.
-- =====================================================================

create table documents (
  id                uuid primary key default gen_random_uuid(),
  company_id        uuid not null references companies(id) on delete cascade,
  knowledge_base_id uuid not null references knowledge_bases(id) on delete cascade,
  title             text not null,
  source_type       document_source not null default 'upload',
  storage_path      text,                           -- for uploads (private bucket)
  source_url        text,                           -- for url ingestion
  file_type         text,
  size_bytes        bigint,
  status            document_status not null default 'pending',
  error_message     text,
  chunk_count       int not null default 0,
  metadata          jsonb not null default '{}'::jsonb,  -- {project, tower, price_band, ...}
  created_by        uuid references users(id) on delete set null,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);
create index idx_documents_kb     on documents(company_id, knowledge_base_id);
create index idx_documents_status on documents(status);

create table document_chunks (
  id                uuid primary key default gen_random_uuid(),
  company_id        uuid not null references companies(id) on delete cascade,
  document_id       uuid not null references documents(id) on delete cascade,
  knowledge_base_id uuid not null references knowledge_bases(id) on delete cascade,  -- denormalized for filtered vector search
  chunk_index       int not null,
  content           text not null,
  token_count       int,
  embedding         vector(1536),                   -- text-embedding-3-small
  metadata          jsonb not null default '{}'::jsonb,
  created_at        timestamptz not null default now()
);
create index idx_chunks_document on document_chunks(document_id);
create index idx_chunks_kb       on document_chunks(company_id, knowledge_base_id);
-- vector ANN index (cosine)
create index idx_chunks_embedding on document_chunks
  using hnsw (embedding vector_cosine_ops);
