# M0-2 — Environment & Supabase Provisioning Guide

This runbook covers provisioning Supabase, the environment templates, the
connection architecture, Railway deployment, and the CI smoke gate.

## 1. Connection architecture (the important decision)

Railway is **IPv4-only**, and Supabase's direct `db.<ref>.supabase.co` endpoint
is IPv6. All connections therefore go through the **Supavisor pooler host**
`aws-0-<region>.pooler.supabase.com`:

| Purpose | Pooler mode | Port | Env var |
|---------|-------------|------|---------|
| App runtime (FastAPI on Railway) | transaction | **6543** | `DATABASE_URL` |
| Migrations & CI | session | **5432** | `DIRECT_URL` |

Consequences carried forward to the API service (M0-1):
- The transaction pooler does **not** support prepared statements, so asyncpg
  must run with `statement_cache_size=0` (exposed as `DB_STATEMENT_CACHE_SIZE=0`).
- RLS JWT claims must be applied per-request with `SET LOCAL` **inside the
  request transaction** (transaction-scoped), not `SET` (session-scoped).

## 2. Provision the Supabase project

1. Create a project in the Supabase dashboard; note the **project ref** and
   **database password**.
2. Collect from *Project Settings → API*: `SUPABASE_URL`, the **anon** key, and
   the **service-role** key (backend only — it bypasses RLS and must never reach
   the browser).
3. Collect the **JWT secret** (*Project Settings → API → JWT Settings*) for
   token verification in the API service.
4. Build `DATABASE_URL` (6543) and `DIRECT_URL` (5432) from the pooler host.

## 3. `supabase/config.toml`

Reproducible project config committed to the repo. `db.major_version = 17`
matches production. Reconcile it with your installed CLI before committing:

```bash
supabase --version
supabase init      # if not already initialised
supabase start     # local stack (Postgres, Studio, Auth, Storage)
```

## 4. Environment templates

- **Root `.env.example`** — the full project inventory. The M0-active block is
  required now; a clearly fenced *reserved* block (Redis, OpenAI, ElevenLabs,
  Twilio, Sarvam) stays blank until the milestone that needs it.
- **`services/api/.env.example`** — the API service runtime subset.

Validate your `.env` before running anything:

```bash
python scripts/check_env.py .env     # exits non-zero if a required var is missing
```

## 5. Railway integration (`railway.json`)

- Builder: **Nixpacks**. Build installs the API package (`pip install -e services/api`).
- Start: `uvicorn app.main:app --app-dir services/api --host 0.0.0.0 --port $PORT`.
- Healthcheck path: `/api/v1/health` (the liveness probe).
- Set the following Railway service variables: everything in the M0-active block,
  with `DATABASE_URL` pointing at the **6543** transaction pooler.

## 6. CI smoke gate (`.github/workflows/m0-2-supabase-smoke.yml`)

The acceptance gate for M0-2. It (a) proves connectivity with `SELECT 1` over the
session pooler and (b) runs a **migration dry-run** that applies nothing.

Required GitHub repository secrets:

| Secret | Purpose |
|--------|---------|
| `DEV_DIRECT_URL` | session-pooler URL of the dev project (connectivity + dry-run) |
| `DEV_PROJECT_REF` | dev project ref (for `supabase link`) |
| `DEV_DB_PASSWORD` | dev database password (for `supabase link`) |
| `SUPABASE_ACCESS_TOKEN` | personal access token for the Supabase CLI |

## 7. Local quickstart

```bash
cp .env.example .env          # fill the M0-active block
python scripts/check_env.py .env
supabase start                # provides the local auth schema + Postgres
make db-migrate               # apply 0001-0013 over $DIRECT_URL
make db-verify                # structural verification
cd services/api && make -C ../../ test
```
