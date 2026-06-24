# M0-4-R Validation Report — RLS Table-Grants Remediation

**Environment:** PostgreSQL 16.14 · pgvector 0.6.0 · pgTAP 1.3.2 (fresh instance)
**Schema basis:** committed migrations `0001`–`0016` applied **verbatim** (not reconstructed) on a Supabase-equivalent rig — `anon`/`authenticated`/`service_role` roles, `auth.users`, and `storage.*` primitives, with Supabase's storage-object grants but **no blanket public-table grants**.
**Milestone:** M0-4-R · forward migration `0017_table_grants.sql`
**Date of run:** 2026-06-23 17:41 UTC
**Result:** PASS — defect reproduced and fixed; RLS not weakened; append-only preserved; rollback + re-apply clean.

---

## 1. Defect

Observed in M0-7 validation against the real Supabase local stack:

```
permission denied for table leads
```

**Root cause.** `0014`–`0016` enable + **force** RLS on all 16 public tables and write per-table policies, but no migration in `0001`–`0016` grants any table-level DML. RLS is a row *filter* layered on top of base table privileges; it never grants access. A role with no base grant is rejected with `permission denied for table …` **before** RLS is evaluated. The only grants present are two `EXECUTE` grants on the helper functions (`0014`).

**Why it escaped earlier.** The M0-4 pgTAP run used a bare-Postgres rig whose harness held blanket table grants, masking the gap. The real Supabase stack uses the actual `authenticated`/`service_role` roles, whose default privileges do not cover the migration-created tables — so every public table denies. Confirmed in this rig: the defect reproduces for `authenticated` **and** for `service_role` (BYPASSRLS does not substitute for a base grant), while `storage.objects` works because Supabase grants those directly.

```
DEFECT REPRO — authenticated SELECT leads     -> ERROR: permission denied for table leads
DEFECT REPRO — authenticated SELECT companies -> ERROR: permission denied for table companies
DEFECT REPRO — service_role  SELECT leads     -> ERROR: permission denied for table leads
CONTROL      — authenticated SELECT storage.objects -> 1 row (Supabase-granted; works)
```

---

## 2. Fix

Forward-only, additive migration `0017_table_grants.sql` (+ rollback). No prior migration, rollback, or M0-6 artifact modified.

- **`authenticated`** — grants mirror the `0015` policy surface exactly (least privilege). A privilege is granted only where a matching policy exists; RLS + FORCE then enforce per-row tenant/role isolation.
- **`service_role`** (BYPASSRLS) — full DML on the 14 operational tables; **INSERT + SELECT only** on the two immutable tables (`usage_logs`, `audit_logs`), so append-only holds for backend workers at the grant layer today, independent of any future guard trigger.
- **`anon`** — nothing (no anon policy; stays denied).
- **Schema `USAGE`** restated idempotently so the migration is self-contained; rollback does **not** revoke it.
- `ALTER DEFAULT PRIVILEGES` deliberately avoided (role/context fragility — the same coupling that caused this defect). Forward rule: every future `CREATE TABLE` migration ships its grants alongside its RLS policies.

### Grant matrix — `authenticated`

| Table | SEL | INS | UPD | DEL | Table | SEL | INS | UPD | DEL |
|---|:--:|:--:|:--:|:--:|---|:--:|:--:|:--:|:--:|
| companies | ✓ | | ✓ | | calls | ✓ | | | |
| users | ✓ | ✓ | ✓ | ✓ | transcripts | ✓ | | | |
| prompts | ✓ | ✓ | ✓ | ✓ | recordings | ✓ | | | |
| knowledge_bases | ✓ | ✓ | ✓ | ✓ | messages | ✓ | ✓ | | |
| agent_configs | ✓ | ✓ | ✓ | ✓ | documents | ✓ | ✓ | ✓ | ✓ |
| leads | ✓ | ✓ | ✓ | ✓ | document_chunks | ✓ | | | |
| lead_notes | ✓ | ✓ | ✓ | ✓ | usage_logs | ✓ | | | |
| call_schedules | ✓ | ✓ | ✓ | ✓ | audit_logs | ✓ | | | |

### Grant matrix — `service_role`

| Tables | SEL | INS | UPD | DEL |
|---|:--:|:--:|:--:|:--:|
| companies, users, prompts, knowledge_bases, agent_configs, leads, lead_notes, call_schedules, calls, transcripts, recordings, messages, documents, document_chunks | ✓ | ✓ | ✓ | ✓ |
| usage_logs, audit_logs | ✓ | ✓ | — | — |

---

## 3. Lifecycle results

| Phase | Result |
|---|---|
| Apply `0001`–`0016` verbatim on fresh Supabase-equivalent rig | clean, no errors (16 tables) |
| Reproduce defect (authenticated + service_role) | `permission denied` confirmed |
| Apply `0017` | clean |
| Fix confirmed — authenticated SELECT leads (RLS filters) | no error |
| Fix confirmed — service_role full DML | no error |
| `verify_m0_4_grants.sql` | PASS |
| `verify_m0_4.sql` (RLS/FORCE/policies/storage unchanged) | PASS |
| Behavioral isolation (real schema, 10 checks) | PASS |
| Append-only — service_role UPDATE/DELETE on immutable tables | `permission denied` (blocked) |
| Rollback `0017` | defect returns; schema `USAGE` retained |
| Re-apply `0017` ×2 | clean (GRANT idempotent) |

---

## 4. `verify_m0_4_grants.sql` output (abridged)

```
--- effective DML grants: authenticated & service_role ---   (32 rows)
 authenticated | companies       | SELECT, UPDATE
 authenticated | leads           | SELECT, INSERT, UPDATE, DELETE
 authenticated | messages        | SELECT, INSERT
 authenticated | usage_logs      | SELECT
 ...
 service_role  | leads           | SELECT, INSERT, UPDATE, DELETE
 service_role  | usage_logs      | SELECT, INSERT
 service_role  | audit_logs      | SELECT, INSERT
--- append-only check: usage_logs / audit_logs UPDATE+DELETE must be f for both roles ---
 authenticated | audit_logs | f | f
 authenticated | usage_logs | f | f
 service_role  | audit_logs | f | f
 service_role  | usage_logs | f | f
--- RLS / FORCE per public table --- all 16 = t / t
NOTICE:  PASS: M0-4-R grants — all required grants present, 0 extra (append-only preserved),
         RLS+FORCE intact on 16 tables, schema USAGE present.
```

## 5. Behavioral isolation (against the actual committed schema)

```
 a_agent_leads | b_agent_leads | svc_all_leads | a_mgr_own_upd | a_mgr_cross_upd | viewer_blocked | mgr_blocked | admin_usage | agent_usage | svc_del_blocked | result
       2       |       3       |       5       |       2       |        0        |       1        |      0      |      1      |      0      |       1         |  PASS
```

Tenant read scoping, cross-tenant writes = 0, role gates (viewer denied / manager allowed), admin-only `usage_logs`, and service-role append-only all hold under `0017` grants + M0-4 RLS.

---

## 6. Discrepancy raised (pre-existing; OUT OF M0-4-R SCOPE) — **D-3**

While grounding, the committed pgTAP suite `tests/m0_4_rls.test.sql` was found to **not run against the committed schema**. It references objects that do not exist in `0001`–`0016`:

- `usage_logs(company_id, provider)` — `usage_logs` has no `provider` column (it has `service`, `operation`, `unit`, all `NOT NULL`).
- `leads.source` values `'website'` / `'web'` — invalid for enum `lead_source` (valid: `meta, google, manual, api`).
- `update leads set status = …` — `leads` has no `status` column (it is `lead_status`).

The M0-4 report's 24/24 ran against a *reconstructed* schema that drifted from the committed migrations (12 marker occurrences in this one file; `tests/m0_6_isolation.test.sql` has none). This is independent of the grants defect and is **not** modified here. Grants were instead validated end-to-end with a schema-faithful behavioral harness (§5). **Recommendation:** open a separate remediation to reconcile `m0_4_rls.test.sql` with the committed schema (or regenerate it), so CI exercises the real migrations.

## 7. Forward recommendation

Adopt a standing rule: **every future `CREATE TABLE` migration ships its DML grants in the same migration as (or immediately paired with) its RLS policies.** This prevents recurrence of the M0-4 grant/policy mismatch for new tables (e.g., M1.0 `lead_events`) without relying on ambient platform default privileges.

---

## 8. Artifacts delivered (M0-4-R)

| File | Location |
|---|---|
| Forward migration | `supabase/migrations/0017_table_grants.sql` |
| Rollback | `supabase/rollback/0017_table_grants.down.sql` |
| Grants verification | `verification/verify_m0_4_grants.sql` |
| Validation report | `docs/M0-4-GRANTS-VALIDATION-REPORT.md` |

Sequencing note: `0017` consumes the next migration slot; the next M1.0 migration (`lead_events`) becomes `0018`.
