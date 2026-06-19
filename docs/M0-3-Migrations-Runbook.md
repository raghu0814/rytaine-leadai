# M0-3 — Database Migrations Runbook

**Milestone:** M0-3 — *PostgreSQL extensions, enums, tables, indexes, triggers, functions*
**Project:** RYtaine LeadAI (multi-tenant Indian real-estate SaaS, Telugu AI voice agent)
**Stack target:** Supabase / PostgreSQL 17 (validated on 16.14) · pgvector · Supabase CLI
**Status:** Complete. All 13 migrations live-applied to a fresh PostgreSQL cluster, verified, pgTAP-green, and behaviorally tested.

---

## 1. Scope

This milestone delivers the **physical schema only**: extensions, enum types, all 16 tables, their indexes, the `updated_at` maintenance triggers, and the soft-dedup trigger.

**In scope (this milestone):**
- `0001`–`0013` migrations: extensions → enums → tables → indexes → functions → triggers.
- Paired rollback scripts (local/staging only).
- A verification script and a structural pgTAP test suite.

**Explicitly out of scope (deferred):**
- **RLS policies, storage policies, and the RLS helper functions** `current_company_id()` / `current_user_role()` → **M0-4**.
- Seed data → M0-5.
- CI/CD and application code → later milestones.

> ### Decision callout — why these are renumbered `0001`–`0013`
> The earlier v0.2 draft plan reserved `0012` for RLS and `0013` for storage. M0-3's scope **excludes both** (they are M0-4 work), and the six final schema decisions **added** a 16th table (`lead_notes`) plus the soft-dedup columns/trigger. The schema-only migrations were therefore **renumbered to fill `0001`–`0013` contiguously**, with RLS / storage / helper functions pushed to M0-4. This keeps the migration sequence gap-free and the file ordering aligned with the dependency DAG.

---

## 2. Prerequisites

1. **Supabase `auth` schema must exist.** `users.id` references `auth.users(id)`. On Supabase this is present by default. On a bare PostgreSQL instance (local test rig, CI) you must stub `auth.users` *before* applying `0003`, otherwise the FK fails.
2. **PostgreSQL 17** in production (Supabase). Validated locally on **16.14** — no 17-only syntax is used.
3. **Superuser (or equivalent) at first apply** so `0001` can `create extension`. On Supabase the migration runner already has this.
4. Apply via the **direct connection string** (`$DIRECT_URL`), not the pooled (pgBouncer) one — extension creation and DDL want a real session.

---

## 3. Deliverable 1 — Migration execution order

Order is dictated by the foreign-key dependency graph. Each file is a single concern.

| # | File | Creates | Depends on |
|---|------|---------|------------|
| 0001 | `0001_extensions.sql` | `pgcrypto`, `vector` | — |
| 0002 | `0002_enums.sql` | 26 enum types | — |
| 0003 | `0003_tenant_core.sql` | `companies`, `users` | 0001, 0002, `auth.users` |
| 0004 | `0004_agent_layer.sql` | `prompts`, `knowledge_bases`, `agent_configs` | 0003 |
| 0005 | `0005_leads.sql` | `leads` (+ soft-dedup columns, `idx_leads_phone`, hard-dedup unique) | 0003, 0004 |
| 0006 | `0006_lead_notes.sql` | `lead_notes` | 0005 |
| 0007 | `0007_calls_scheduling.sql` | `call_schedules`, `calls`, `transcripts`, `recordings` (+ deferred FK `fk_call_schedules_call`) | 0005 |
| 0008 | `0008_messaging.sql` | `messages` | 0005, 0007 |
| 0009 | `0009_rag.sql` | `documents`, `document_chunks` (+ HNSW `idx_chunks_embedding`) | 0004 |
| 0010 | `0010_usage_logs.sql` | `usage_logs` | 0003 |
| 0011 | `0011_audit_logs.sql` | `audit_logs` | 0003 |
| 0012 | `0012_functions_updated_at.sql` | `set_updated_at()` + 10 triggers | 0003–0011 |
| 0013 | `0013_dedup_trigger.sql` | `flag_potential_duplicate_lead()` + `trg_leads_flag_duplicate` | 0005, 0012 |

**Cyclic FK note (`0007`):** `call_schedules` and `calls` reference each other. The mutual link `fk_call_schedules_call` is added as a **deferred ALTER** at the end of `0007`, after both tables exist, to break the cycle.

**Why `0012` and `0013` are separate:** one concern per file. `0012` is generic timestamp maintenance; `0013` is lead business logic. Keeping them apart keeps each migration independently reviewable and reversible.

---

## 4. Deliverable 2 — Migration files & how to apply

Files live in `supabase/migrations/`, named `NNNN_name.sql` (sequential prefix, sorts lexicographically for the Supabase CLI).

**Apply with the Supabase CLI (recommended):**
```bash
supabase db push            # applies pending migrations in filename order
```

**Or apply directly with psql (CI / local rig):**
```bash
for f in supabase/migrations/0*.sql; do
  echo ">> $f"
  psql "$DIRECT_URL" -v ON_ERROR_STOP=1 -f "$f"
done
```

`ON_ERROR_STOP=1` is mandatory — a failed statement must abort the run, not limp forward.

> **CLI naming note:** Supabase's own `supabase migration new` command generates **timestamp-prefixed** filenames. This project uses **sequential** `0001…` prefixes deliberately (matches every prior project doc and the M0 build plan, and is unambiguous to review). Both sort correctly; do not mix the two schemes within `migrations/`. If you later adopt `supabase migration new`, rename its output to continue the sequence.

**Conventions baked into the DDL (locked):**
- UUID PKs via `gen_random_uuid()`.
- `created_at timestamptz` on every table; `updated_at` only on the 10 mutable tables (trigger-maintained).
- Money = `numeric(14,2)` (INR). Phones = E.164 text. Embeddings = `vector(1536)` (text-embedding-3-small).
- **Hard dedup:** `unique (company_id, source, external_lead_id)` on `leads`.
- **Soft dedup:** `BEFORE INSERT` trigger flags (never rejects) a same-company / same-phone lead created within 30 days.

---

## 5. Deliverable 3 — Rollback strategy

**Philosophy: forward-only / fix-forward.** Once a migration is merged it is **immutable** — never edit an applied migration. A mistake is corrected by a *new* migration.

| Environment | Recovery mechanism |
|---|---|
| **Production** | **Supabase PITR** (point-in-time recovery). Do **not** run down-scripts against prod. |
| **Staging / local** | Paired down-scripts in `supabase/rollback/`, applied manually when safe. |

- Down-scripts are in `supabase/rollback/NNNN_name.down.sql`, **outside** `migrations/` so the CLI never auto-applies them.
- They run in **reverse dependency order** and use `drop … cascade`.
- `0001_extensions.down.sql` is **commented out by default** — dropping `pgcrypto` / `vector` is destructive and is teardown-only. Uncomment deliberately.

**Manual rollback (staging) example — undo the last migration:**
```bash
psql "$DIRECT_URL" -v ON_ERROR_STOP=1 -f supabase/rollback/0013_dedup_trigger.down.sql
```

---

## 6. Deliverable 4 — Verification checklist

Run **after** applying `0001`–`0013` against a fresh DB:
```bash
psql "$DIRECT_URL" -v ON_ERROR_STOP=1 -f scripts/verify_m0_3.sql
```

The script prints a readable report **and hard-asserts** the load-bearing invariants (it raises and aborts on any mismatch):

- [ ] Extensions `pgcrypto` and `vector` present.
- [ ] **16** base tables in `public`.
- [ ] **26** enum types in `public`.
- [ ] Hard-dedup unique constraint on `leads (company_id, source, external_lead_id)`.
- [ ] Soft-dedup columns `is_potential_duplicate`, `duplicate_of_lead_id` on `leads`.
- [ ] **10** `updated_at` triggers (companies, users, prompts, knowledge_bases, agent_configs, leads, call_schedules, calls, messages, documents).
- [ ] Soft-dedup trigger `trg_leads_flag_duplicate` present.
- [ ] HNSW index `idx_chunks_embedding` on `document_chunks`.

A green run is the M0-3 acceptance signal for schema shape. Cross-tenant / RLS behavior is **not** checked here — that is M0-4 / M0-6.

---

## 7. Deliverable 5 — Migration testing strategy

Five components:

1. **Fresh-DB forward apply.** Spin up an empty PostgreSQL, stub `auth.users`, apply `0001`→`0013` with `ON_ERROR_STOP=1`. Must complete with zero errors. *(This is the primary CI gate.)*
2. **Schema snapshot diff.** `pg_dump --schema-only` of the migrated DB, diffed against a committed baseline. A non-empty diff fails the build — this is what enforces "the migrations reproduce exactly the approved schema."
3. **Structural pgTAP suite** — `supabase/tests/m0_3_schema.test.sql`, **48 assertions**, fixture-free. Asserts table presence (16), enum presence (26), key columns/types, the dedup constraint, and the trigger inventory.
   ```bash
   pg_prove --ext .sql -d "$DIRECT_URL" supabase/tests/m0_3_schema.test.sql
   # or wrapped in a transaction: begin; create extension pgtap; \i …; rollback;
   ```
4. **Reproducibility.** Apply twice on two fresh DBs; snapshots must be byte-identical.
5. **Rollback rehearsal (staging).** Apply up, then the paired down-scripts; confirm a clean teardown with no orphaned objects.

**Scope of testing:** schema correctness only. Tenant-isolation behavior is deferred to the **M0-6** isolation suite (it depends on the RLS policies that land in **M0-4**).

---

## 8. Validation results (this milestone)

Performed against a real PostgreSQL **16.14** cluster (pgvector 0.6.0, pgTAP installed), `auth` schema stubbed:

- **Static parse:** all 28 SQL files parse cleanly against the real PostgreSQL grammar (via `pglast`). Statement counts confirmed (`0002` = 26 types, `0007` = 10 statements, `0012` = 11).
- **Forward apply:** `0001`→`0013` applied sequentially with `ON_ERROR_STOP=1` — **all 13 applied cleanly.**
- **Verification script:** full pass (16 tables, 26 enums, 10 `updated_at` triggers, dedup trigger, HNSW index, hard-dedup unique).
- **pgTAP:** all **48** assertions ok, zero failures.
- **Behavioral — soft dedup:** a second lead with the same company + phone was flagged `is_potential_duplicate = true` pointing at the first lead; the first lead stayed unflagged; a same-phone lead in a *different* company was **not** flagged. Correct.
- **Behavioral — `updated_at`:** timestamp advanced on `UPDATE`. Correct.

---

## 9. Forward notes for M0-4

- **Migration number collision:** M1.0 already claims `0014` for `lead_events`. To avoid a clash, land M0-4 RLS as **idempotent files under `supabase/policies/`** (that folder already exists in the repo) rather than as a numbered `0014` migration.
- **Helper functions** `current_company_id()` and `current_user_role()` are **not** created in M0-3 — they are part of the M0-4 RLS work and must precede the policies that call them.
- Storage bucket policies are likewise M0-4.

---

*End of M0-3 runbook.*
