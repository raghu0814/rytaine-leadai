-- =====================================================================
-- Migration : 0011_audit_logs
-- Milestone : M0-3 (schema)
-- Concern   : Append-only audit trail (table 16 of 16)
-- Depends on: 0003_tenant_core (companies, users)
-- Notes     : company_id is nullable (system events have no tenant).
--             Append-only intent is ENFORCED by RLS policy in M0-4
--             (INSERT + SELECT only). M0-3 lands structure only.
-- Forward-only. Immutable once merged.
-- =====================================================================

create table audit_logs (
  id            uuid primary key default gen_random_uuid(),
  company_id    uuid references companies(id) on delete set null,  -- null for system events
  actor_user_id uuid references users(id) on delete set null,
  action        text not null,
  entity_type   text not null,
  entity_id     uuid,
  ip_address    inet,
  user_agent    text,
  metadata      jsonb not null default '{}'::jsonb,
  created_at    timestamptz not null default now()
);
create index idx_audit_company_time on audit_logs(company_id, created_at desc);
create index idx_audit_entity       on audit_logs(entity_type, entity_id);
