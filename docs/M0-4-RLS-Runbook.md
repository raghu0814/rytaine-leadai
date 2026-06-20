# M0-4 — RLS, Storage Policies & Helper Functions · Runbook

**Project:** RYtaine LeadAI · **Milestone:** M0-4
**Depends on:** M0-3 (schema `0001–0013`, applied) · **Blocks:** M0-5, M0-6, M1.x
**Engine:** PostgreSQL 16.14 + pgvector 0.6.0 + pgTAP 1.3.2 (validated)
**Status:** ✅ Generated and validated on a fresh instance. 24/24 pgTAP green; verify PASS; rollback + re-apply clean.

---

## 1. What this milestone deploys

- **`0014_rls_helpers.sql`** — `current_company_id()` and `current_user_role()`, `STABLE`, `search_path=''`, reading the verified JWT payload from the `request.jwt.claims` GUC under `app_metadata`.
- **`0015_rls_policies.sql`** — `ENABLE` + `FORCE ROW LEVEL SECURITY` on every `public` table (via a loop, so no table can be missed), then explicit per-table tenant/role policies.
- **`0016_storage_policies.sql`** — private `documents` and `recordings` buckets + tenant-isolation policies on `storage.objects` (folder-1 = `company_id`).
- Paired rollbacks, `verify_m0_4.sql`, and the `m0_4_rls.test.sql` pgTAP suite.

`0001–0013` are **not touched**. The M1.0 `lead_events` reservation moves to **`0017`** (Option A).

---

## 2. Enforcement model (the load-bearing contract)

RLS does **not** engage automatically on our path: the FastAPI app reaches Postgres through the Supavisor **transaction** pooler (not PostgREST), so the request layer must inject identity per transaction:

```sql
-- once per request transaction, BEFORE any tenant query
SET LOCAL ROLE authenticated;                 -- non-BYPASSRLS role => RLS applies
SET LOCAL request.jwt.claims =
  '{"app_metadata":{"company_id":"<uuid>","role":"<role>"}}';
```

- Transaction pooler ⇒ **`SET LOCAL` only** (session `SET` leaks across pooled clients); every tenant query path runs inside an explicit transaction.
- `service_role` carries `BYPASSRLS` ⇒ backend workers (call pipeline, embeddings, recovery worker) read/write across the tenant boundary by design; service-written tables therefore omit `authenticated` write policies.
- `anon` has no policies ⇒ denied everywhere.

This `SET LOCAL` wiring is an **app-layer task** (a DB-session dependency), not part of these migrations. The migrations + the contract together are what enforce isolation.

## 3. Policy model

Tenant predicate: `companies` uses `id = current_company_id()`; the other 15 use `company_id = current_company_id()`. Role gating (`user_role`: admin > manager > agent > viewer):

| Group | Tables | Write rule |
|---|---|---|
| Admin-managed | users, prompts, knowledge_bases, agent_configs, documents | admin (or service) writes |
| Operational | leads, call_schedules, messages | manager+ (or service) writes |
| Notes | lead_notes | agent+ insert; admin update/delete (see D-2) |
| Service-written, tenant read-only | calls, transcripts, recordings, document_chunks | writes via service_role only |
| Append-only, admin-read | usage_logs, audit_logs | admin read; insert via service; no update/delete |

`FORCE` is applied to all 16 `public` tables. `storage.objects` uses `ENABLE` only (not `FORCE`) — it is owned by the storage admin role and forcing would break the internal storage service; `service_role` bypass already covers backend object writes.

---

## 4. Validation results (fresh PostgreSQL 16.14)

**Apply chain:** `0001–0013` → `0014` → `0015` → `0016` applied clean, no errors.

**`verify_m0_4.sql`:** PASS —
`2 helpers (both STABLE) · all 16 public tables RLS+FORCE+at-least-one-policy · 2 private buckets · 5 storage.objects policies`.

**`m0_4_rls.test.sql` (pgTAP): `1..24`, 24 passed, 0 failed.** Coverage:

- Structural: helpers exist; 16 tables RLS+FORCE; buckets private.
- Read isolation: A sees only A's rows (leads, companies); B sees only B's; `service_role` sees all (bypass).
- Write/role isolation: cross-tenant UPDATE/DELETE → 0 rows; cross-tenant INSERT → `42501`; viewer INSERT denied; manager INSERT allowed; manager updates own rows.
- Append-only: `usage_logs` admin-read only; non-admin read → 0 rows; UPDATE/DELETE → 0 rows.
- RAG isolation: `document_chunks` scoped per tenant (the DB floor under the app's `company_id`+`knowledge_base_id` pre-filter).
- Storage isolation: object visibility scoped to the `company_id` folder; `service_role` sees all.

**Rollback:** `0016→0015→0014` down-scripts restore the exact pre-M0-4 state (0 helpers, 0 forced tables, 0 policies). Full re-apply on a fresh DB reproduces the green state.

> Validation ran against a faithful reconstruction of the M0-3 schema (the live Supabase DB is not reachable from the build environment). Table names are high-confidence; confirm against live before `db push` — see §6.

---

## 5. Deploy order

1. `supabase db push` applies `0014`, `0015`, `0016` (session pooler / `DIRECT_URL`).
2. Run `verification/verify_m0_4.sql` against the target — must print the PASS notice.
3. Run `tests/m0_4_rls.test.sql` (wrapped in BEGIN/ROLLBACK; requires `pgtap`) — must report `1..24` all green.
4. Ship the app-layer `SET LOCAL ROLE authenticated` + claims-injection DB-session dependency (separate task) before any tenant traffic.
5. Re-point the M1.0 `lead_events` migration to `0017`.

---

## 6. Confirm the live inventory matches (run before db push)

```sql
select tablename from pg_tables where schemaname='public' order by 1;
-- expect exactly these 16:
-- agent_configs, audit_logs, call_schedules, calls, companies, document_chunks,
-- documents, knowledge_bases, lead_notes, leads, messages, prompts,
-- recordings, transcripts, usage_logs, users
```

If the live list differs, tell me the delta and I'll adjust `0015` before push. Note: even if an unexpected extra `public` table exists, the `ENABLE/FORCE` loop locks it down (deny-by-default) rather than leaking it — safe failure mode.

---

## 7. Schema discrepancies & open items discovered

- **D-1 (handled): `companies` has no `company_id` column.** Its tenant key is `id`; the generic `company_id = current_company_id()` predicate does not literally apply. Resolved by keying `companies` policies on `id`.
- **D-2 (decision, non-blocking): author-scoped `lead_notes` editing.** Letting only a note's author edit it needs a `current_user_id()` / `auth.uid()` helper reading the JWT `sub` claim — **outside the approved M0-4 helper set** (only `company_id` + `role` were approved). Implemented as **admin-scoped** update/delete for now. Options: (a) add a `current_user_id()` helper in a small follow-up to enable author editing; (b) keep admin-scoped. Your call.
- **D-3 (reconciled): draft-era RLS matrix predated the M0-3 renumbering** (and listed tables under old migration numbers). Policies here are generated from the **actual** 16-table inventory read from `pg_tables`, not the draft.
- **Carry-forward:** the `actor_id` FK target for `lead_events` and the app-layer claims-injection dependency remain owned by M1.0 / the app task respectively.
```
