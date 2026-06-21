# M0-6 Validation Report

**Milestone:** M0-6 — DB Tenant-Isolation Suite (DB-isolation-only)
**Environment:** PostgreSQL 16.14 · pgvector 0.6.0 · pgTAP 1.3.2 · pg_prove (TAP::Parser::SourceHandler::pgTAP)
**Schema basis:** migrations `0001–0016` applied in order (live-equivalent rig; see note)
**Suite:** `tests/m0_6_isolation.test.sql` — 67 assertions, `BEGIN/ROLLBACK`-wrapped, seed-independent
**Date of run:** 2026-06-21 UTC
**Status:** ✅ 67/67 green · repeatable · seed-independent · zero fixture residue

---

## 1. What this milestone proves

That multi-tenant data isolation is enforced by the **database alone** — RLS policies, the
`current_company_id()` / `current_user_role()` helpers, and the `storage.objects` policies
delivered in migrations `0014–0016`, sitting on the `0001–0013` schema. No application layer
is involved: the suite injects the verified JWT payload into `request.jwt.claims` and drops to
`authenticated` / `anon` / `service_role` exactly as the M0-7 FastAPI DB-session dependency
will, then asserts what each principal can read and write across a two-tenant fixture set.

M0-6 is **DB-isolation-only** by approved decision. The app-layer `SET LOCAL` claims-injection
plumbing is **out of scope** and deferred to **M0-7**.

## 2. Environment note (live-equivalent rig)

Docker / the Supabase CLI are unavailable in the validation sandbox, so the suite was executed
against a **bare-PostgreSQL 16.14 rig** that reproduces what the Supabase local stack supplies:
the `anon`, `authenticated`, and `service_role` roles (with `service_role` `BYPASSRLS`), the
`storage` schema (`buckets`, `objects`, `storage.foldername()`), and `pgvector`. This is the
same methodology used for the committed M0-4 validation report. The **CI workflow**
(`.github/workflows/m0-6-isolation.yml`) runs the identical suite against a **real** Supabase
local stack via `supabase db start`, so the production enforcement path is exercised on every
push/PR touching `supabase/**` or the suite.

## 3. Lifecycle results

| Phase | Result |
|---|---|
| Apply `0001–0013` → `0014` → `0015` → `0016` on fresh instance | clean, no errors |
| Prereq gate: 2 helpers present · 16/16 public tables RLS+FORCE | PASS |
| `tests/m0_6_isolation.test.sql` (pgTAP, via `pg_prove`) | **67 passed / 0 failed** |
| Re-run on same DB (no reset) | 67/67 — repeatable |
| Fixture residue after run (BEGIN/ROLLBACK) | 0 rows — nothing persists |
| Run with non-fixture tenant data present (seed-shaped) | 67/67 — seed-independent |

## 4. Coverage map (67 assertions)

| Group | Count | What it locks |
|---|---|---|
| Structural | 4 | both helpers exist; all 16 public tables RLS **and** FORCE; no policy targets `anon` |
| SELECT isolation (own) | 16 | each of the 16 tables returns only the caller-tenant rows |
| Cross-tenant SELECT leakage | 16 | each of the 16 tables returns **0** of the other tenant's rows |
| Cross-tenant WRITE isolation | 12 | UPDATE/DELETE affect 0 rows; cross-tenant INSERT raises `42501` |
| `companies` special-case | 4 | `id = current_company_id()` predicate; admin-only `WITH CHECK`; INSERT service-only |
| Role-gated deny | 2 | viewer denied lead INSERT; agent denied document INSERT (own tenant) |
| Unauth / no-claim denial | 3 | `anon` and NULL-company claims see nothing |
| `service_role` bypass (scoped) | 2 | backend sees both fixture tenants by design |
| Append-only | 4 | `usage_logs` / `audit_logs` client UPDATE+DELETE blocked |
| Storage isolation | 4 | `documents` / `recordings` objects isolated by `company_id` folder; service bypass |

The `companies` table is deliberately tested on its structurally-different predicate
(`id = current_company_id()`, not `company_id = …`).

## 5. Full pgTAP output

```
1..67
ok 1 - helper current_company_id() exists
ok 2 - helper current_user_role() exists
ok 3 - all 16 public tables have RLS + FORCE (no table left open)
ok 4 - no public RLS policy targets anon => anon denied by default
ok 5 - companies: A sees only its own company row
ok 6 - users: A sees only its own user
ok 7 - prompts: A sees only its own
ok 8 - knowledge_bases: A sees only its own
ok 9 - agent_configs: A sees only its own
ok 10 - leads: A sees only its own
ok 11 - lead_notes: A sees only its own
ok 12 - call_schedules: A sees only its own
ok 13 - calls: A sees only its own
ok 14 - transcripts: A sees only its own
ok 15 - recordings: A sees only its own
ok 16 - messages: A sees only its own
ok 17 - documents: A sees only its own
ok 18 - document_chunks: A sees only its own (RAG tenant floor)
ok 19 - usage_logs: A admin sees only its own
ok 20 - audit_logs: A admin sees only its own
ok 21 - companies: A cannot see B's company
ok 22 - users: A cannot see B's users
ok 23 - prompts: A cannot see B's prompts
ok 24 - knowledge_bases: A cannot see B's KBs
ok 25 - agent_configs: A cannot see B's configs
ok 26 - leads: A cannot see B's leads (PII)
ok 27 - lead_notes: A cannot see B's notes
ok 28 - call_schedules: A cannot see B's schedules
ok 29 - calls: A cannot see B's calls
ok 30 - transcripts: A cannot see B's transcripts (content)
ok 31 - recordings: A cannot see B's recordings (content)
ok 32 - messages: A cannot see B's messages
ok 33 - documents: A cannot see B's documents
ok 34 - document_chunks: A cannot see B's chunks (RAG leak floor)
ok 35 - usage_logs: A cannot see B's usage
ok 36 - audit_logs: A cannot see B's audit trail
ok 37 - leads: A manager cross-tenant UPDATE of B affects 0 rows
ok 38 - leads: A manager cross-tenant DELETE of B affects 0 rows
ok 39 - leads: A manager cross-tenant INSERT (company_id=B) raises 42501
ok 40 - documents: A admin cross-tenant UPDATE of B affects 0 rows
ok 41 - documents: A admin cross-tenant INSERT (company_id=B) blocked
ok 42 - prompts: A admin cross-tenant UPDATE of B affects 0 rows
ok 43 - knowledge_bases: A admin cross-tenant INSERT (company_id=B) blocked
ok 44 - agent_configs: A admin cross-tenant UPDATE of B affects 0 rows
ok 45 - call_schedules: A manager cross-tenant INSERT (company_id=B) blocked
ok 46 - lead_notes: A agent cross-tenant INSERT (company_id=B) blocked
ok 47 - users: A admin cross-tenant UPDATE of B affects 0 rows
ok 48 - messages: A manager cross-tenant INSERT (company_id=B) blocked
ok 49 - companies: A admin can update its OWN company
ok 50 - companies: A manager UPDATE own company blocked (WITH CHECK role=admin)
ok 51 - companies: authenticated INSERT blocked (service_role only)
ok 52 - companies: A admin cross-tenant UPDATE of B company affects 0 rows
ok 53 - leads: viewer denied INSERT even in own tenant (manager+ required)
ok 54 - documents: agent denied INSERT in own tenant (admin required)
ok 55 - anon sees 0 leads even with a tenant claim (no anon policy)
ok 56 - authenticated with NULL company_id claim sees 0 leads (NULL never matches)
ok 57 - authenticated with NULL company_id claim sees 0 companies
ok 58 - service_role bypasses RLS: sees BOTH tenants' fixture leads
ok 59 - service_role bypasses RLS: sees BOTH tenants' fixture chunks
ok 60 - usage_logs: own UPDATE blocked (append-only, no client update policy)
ok 61 - usage_logs: own DELETE blocked (append-only)
ok 62 - audit_logs: own UPDATE blocked (append-only)
ok 63 - audit_logs: own DELETE blocked (append-only)
ok 64 - storage/documents: A sees only its own object
ok 65 - storage/documents: A cannot see B's object
ok 66 - storage/recordings: A sees only its own object
ok 67 - storage/documents: service_role sees both tenants' fixture objects (bypass)
```

## 6. Seed-independence

The suite is correct whether or not `supabase/seed.sql` has been loaded (e.g. after
`supabase db reset`). Two properties guarantee it:

1. **Dedicated fixture UUIDs** — tenants `A = 6a000000-…-aa` and `B = 6b000000-…-bb` (and their
   child rows `6a…a1xx` / `6b…b1xx`) cannot collide with the dev seed (`1111…`) or the M0-4
   suite (`1111…` / `2222…`). Every cross-tenant, bypass, and count assertion is scoped to the
   fixture set, so other tenants' rows are invisible to the assertions.
2. **`BEGIN/ROLLBACK` wrapper** — fixtures and harness functions never commit.

Verified empirically: with a non-fixture tenant (`1111…`) holding 1 company + 5 leads present
in the database, the suite still returned **67/67**; and after any run, **0** fixture rows
remain (`select count(*) from companies where id in ('6a…aa','6b…bb')` → `0`).

## 7. Discrepancies surfaced (named, for Raghu — not fixed here)

Both are **out of scope** for M0-6 (migrations `0001–0016` and the M0-4 suite are frozen). They
are recorded so they can be triaged deliberately.

- **D-1 — committed M0-4 suite drifted from committed schema.**
  `tests/m0_4_rls.test.sql` (committed) inserts `leads.source = 'website'`, references
  `usage_logs.provider`, and `update leads set status = …`. Against the **committed** migrations
  these do not exist: `lead_source` enum is `('meta','google','manual','api')` (no `'website'`);
  `usage_logs` columns are `service / operation / unit` (no `provider`); the leads status column
  is `lead_status` (no `status`). The committed M0-4 suite was validated against a *reconstructed*
  schema that differed from what landed in `0001–0013`. The **M0-6 suite uses only real
  committed columns/enums**, so it is unaffected. Options for M0-4: (A) leave frozen and rely on
  M0-6 for isolation coverage; (B) open a follow-up to realign `m0_4_rls.test.sql` with the
  committed schema. Recommendation: **(A)** for now — M0-6 supersedes it for isolation.

- **D-2 — `viewer` is not a `user_role` enum value (benign).**
  RLS compares the JWT `role` claim as **text**, so a `'viewer'` claim is simply a value that
  matches no write policy ⇒ correct deny-by-default. The M0-6 suite uses `'viewer'` only as a
  deny-path claim (assertion 53). No change required.

## 8. Carry-forwards (unchanged, not addressed by M0-6)

1. **App-layer `SET LOCAL` claims injection** — the FastAPI DB-session dependency that injects
   `request.jwt.claims` per transaction is **M0-7**.
2. **`lead_notes` edit policy** remains admin-scoped pending a future `current_user_id()` helper
   decision (originally noted in M0-4).

## 9. How to reproduce

Local (against a running DB reachable by `$DIRECT_URL`):

```bash
make db-isolation-prove     # pg_prove — pass/fail exit code (CI-grade)
make db-test-isolation      # raw TAP via psql
```

CI: push/PR touching `supabase/**` or `tests/m0_6_isolation.test.sql` triggers
`m0-6-isolation`, which stands up a real Supabase local stack and runs the same suite.
