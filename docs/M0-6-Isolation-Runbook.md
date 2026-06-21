# M0-6 — DB Tenant-Isolation Suite · Runbook

**Project:** RYtaine LeadAI · **Milestone:** M0-6
**Depends on:** M0-4 (`0014–0016` applied) · M0-3 (`0001–0013` schema) · **Blocks:** M0-7, M1.x
**Engine:** PostgreSQL 16.14 + pgvector 0.6.0 + pgTAP 1.3.2 (validated)
**Status:** ✅ 67/67 pgTAP green; repeatable; seed-independent; zero fixture residue.

---

## 1. What this milestone delivers

- **`tests/m0_6_isolation.test.sql`** — 67-assertion pgTAP suite proving DB-enforced
  multi-tenant isolation (RLS + helpers + storage policies) with **no application layer**.
- **`.github/workflows/m0-6-isolation.yml`** — CI gate running the suite against a real
  Supabase local stack (`supabase db start`) via `pg_prove`.
- **`docs/M0-6-VALIDATION-REPORT.md`** — full run evidence (env, TAP, seed-independence).
- **Makefile targets** (additive): `db-test-isolation`, `db-isolation-prove`.

`0001–0016` are **not touched**. No rollback scripts change. This milestone is
**DB-isolation-only**; the app-layer claims-injection plumbing is **M0-7**.

---

## 2. Enforcement model (the load-bearing contract)

RLS does not engage on our path automatically: the FastAPI app reaches Postgres through the
Supavisor **transaction** pooler (not PostgREST), so identity must be injected per transaction.
The suite reproduces this exactly — once per check it runs:

```sql
SET LOCAL ROLE authenticated;                 -- non-BYPASSRLS role => RLS applies
SET LOCAL request.jwt.claims =
  '{"app_metadata":{"company_id":"<uuid>","role":"<role>"}}';
```

- `authenticated` ⇒ RLS evaluated under the injected `company_id` / `role` claims.
- `anon` ⇒ no policies ⇒ denied everywhere (assertions 4, 55).
- `service_role` ⇒ `BYPASSRLS` ⇒ crosses the tenant boundary by design (assertions 58–59, 67).

The actual per-request `SET LOCAL` wiring in FastAPI is an **app-layer task (M0-7)**, not part of
this suite. The suite asserts the database half of that contract holds.

---

## 3. Policy model under test

Tenant predicate: `companies` keys on `id = current_company_id()`; the other 15 tables on
`company_id = current_company_id()`. Role gating (`admin > manager > agent > viewer`, compared
as a **text** claim):

| Group | Tables | Write rule | Assertions |
|---|---|---|---|
| Admin-managed | users, prompts, knowledge_bases, agent_configs, documents | admin (or service) | 40–44, 47, 54 |
| Operational | leads, call_schedules, messages | manager+ (or service) | 37–39, 45, 48, 53 |
| Notes | lead_notes | agent+ insert | 46 |
| Service-written, tenant read-only | calls, transcripts, recordings, document_chunks | service only | 13–15, 18, 29–31, 34 |
| Append-only, admin-read | usage_logs, audit_logs | admin read; service insert; no update/delete | 19–20, 35–36, 60–63 |
| Storage | `storage.objects` (documents, recordings buckets) | folder-1 = `company_id` | 64–67 |

---

## 4. Fixtures (seed-independent by construction)

Two dedicated tenants, with UUIDs chosen to never collide with the dev seed (`1111…`) or the
M0-4 suite (`1111…` / `2222…`):

- **Tenant A** = `6a000000-0000-0000-0000-0000000000aa`
- **Tenant B** = `6b000000-0000-0000-0000-0000000000bb`
- Child rows (KB, document, lead, call, user, storage object) under `6a…a1xx` / `6b…b1xx`.

The whole suite runs inside `BEGIN … ROLLBACK`, so **nothing persists** and it can be run
repeatedly against the same database. Pre-existing data from other tenants (including the dev
seed) is invisible to the assertions because every count/leak/bypass check is scoped to the
fixture UUID set.

---

## 5. How to run

### A. Local — against any DB reachable by `$DIRECT_URL`

`$DIRECT_URL` is the **session-pooler / direct** connection string (port 5432), the same one the
other `db-*` targets use. Requires the migrations `0001–0016` already applied.

```bash
# pass/fail exit code (CI-grade) — use this in gates:
make db-isolation-prove

# raw TAP stream via psql (human-readable, same content):
make db-test-isolation
```

`db-isolation-prove` needs `pg_prove` on PATH
(`apt-get install libtap-parser-sourcehandler-pgtap-perl`). `db-test-isolation` needs only
`psql`. Neither touches the existing `db-test` target.

### B. Local — full reset against the Supabase stack

```bash
supabase db start           # or: supabase start && supabase db reset
make db-isolation-prove      # DIRECT_URL pointed at the local stack
```

`db reset` applies `0001–0016` and loads `supabase/seed.sql`; the suite is seed-independent so
the seed neither helps nor hurts.

### C. CI

Push or open a PR touching `supabase/**`, `tests/m0_6_isolation.test.sql`, or the workflow file.
`m0-6-isolation` stands up a real Supabase local stack, asserts the prerequisites
(2 helpers + 16/16 RLS+FORCE), then runs `pg_prove`. Any failed assertion fails the job.

---

## 6. Interpreting output

- `1..67` then `ok N - …` for each assertion; final `Result: PASS` from `pg_prove`.
- A `not ok N - …` line names the exact isolation property that regressed (e.g.
  `not ok 26 - leads: A cannot see B's leads (PII)` ⇒ a leads SELECT policy leaks across tenants).
- `Parse errors: No plan found` usually means the script aborted before `plan()` — check the
  first `psql` ERROR above it (most often a missing helper ⇒ `0014` not applied, or a connection
  pointed at the wrong DB).

---

## 7. Known discrepancies (named; not fixed in M0-6)

- **D-1** — the committed M0-4 suite (`tests/m0_4_rls.test.sql`) references columns/enum values
  that are not in the committed `0001–0013` schema (`leads.source='website'`,
  `usage_logs.provider`, `leads.status`). It was validated against a reconstructed schema. The
  M0-6 suite uses only real committed columns, so it is unaffected. Triage M0-4 separately;
  recommendation is to let M0-6 supersede it for isolation coverage.
- **D-2** — `viewer` is not a `user_role` enum value, but RLS compares the role claim as text, so
  a `viewer` claim is a correct deny-by-default. Benign; used only on the deny path (assertion 53).

See `docs/M0-6-VALIDATION-REPORT.md` §7 for the full write-up.

---

## 8. Carry-forwards (unchanged)

1. **App-layer `SET LOCAL` claims injection** (FastAPI DB-session dependency) — **M0-7**.
2. **`lead_notes` edit policy** stays admin-scoped pending a `current_user_id()` helper decision.

---

## 9. Guarantees this milestone does and does not give

**Does:** proves that *if* the correct claims are injected, the database isolates every tenant
across all 16 tables + storage, for read and write, including append-only and `service_role`
bypass semantics.

**Does not:** prove the application injects those claims correctly — that is M0-7, and until it
lands there is no externally reachable tenant traffic path. This suite is the DB-side guarantee
that M0-7 builds on top of.
