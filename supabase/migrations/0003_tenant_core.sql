-- =====================================================================
-- Migration : 0003_tenant_core
-- Milestone : M0-3 (schema)
-- Concern   : Tenant root + app users (tables 1-2 of 16)
-- Depends on: 0002_enums
-- Note      : `users` references auth.users(id) — requires the Supabase
--             `auth` schema (present in `supabase start` / a Supabase
--             project). This will NOT apply against bare PostgreSQL.
-- Forward-only. Immutable once merged.
-- =====================================================================

-- companies — tenant root; every business row hangs off this.
create table companies (
  id          uuid primary key default gen_random_uuid(),
  name        text not null,
  slug        text not null unique,
  status      company_status not null default 'trial',
  plan        text not null default 'starter',
  timezone    text not null default 'Asia/Kolkata',
  settings    jsonb not null default '{}'::jsonb,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

-- users — application profile, 1:1 with auth.users.
create table users (
  id            uuid primary key references auth.users(id) on delete cascade,
  company_id    uuid not null references companies(id) on delete cascade,
  email         text not null,
  full_name     text,
  role          user_role not null default 'agent',
  status        user_status not null default 'invited',
  last_login_at timestamptz,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  unique (email)
);
create index idx_users_company on users(company_id);
