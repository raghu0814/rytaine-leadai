# RYtaine LeadAI — Consolidated M0 Package

Multi-tenant SaaS for Indian real estate with an AI voice agent. This package
is the complete **M0 foundation** — the runnable API skeleton, environment &
Supabase provisioning, and the database migration layer — across three approved
milestones:

- **M0-1** — FastAPI scaffold: config, JWT security, async DB session factory, health endpoints, tests, Dockerfile.
- **M0-2** — Supabase config, environment templates, Railway integration, CI smoke gate, setup docs.
- **M0-3** — Migrations `0001`–`0013`, rollback scripts, verification script, pgTAP suite, runbook.

> Scope: M0 only. No M0-4 (RLS/storage policies), M0-5 (seed), M0-6 (isolation suite), or M0-7. RLS helper functions (`current_company_id()` / `current_user_role()`) are **not** here — they belong to M0-4.

---

## Repository tree

```
rytaine-leadai/
├── README.md                              # this file
├── Makefile                               # dev workflow helpers (M0-2)
├── railway.json                           # Railway nixpacks build + uvicorn start (M0-2)
├── .gitignore                             # (M0-2)
├── .env.example                           # full project env inventory (M0-2)
├── .github/
│   └── workflows/
│       └── m0-2-supabase-smoke.yml        # CI acceptance gate (M0-2)
├── docs/
│   ├── M0-2-Environment-Setup-Guide.md    # provisioning + connection architecture
│   └── M0-3-Migrations-Runbook.md         # migration/rollback/verify/test runbook
├── scripts/
│   ├── check_env.py                       # env-shape validator (M0-2)
│   └── verify_m0_3.sql                    # schema verification, hard-asserts (M0-3)
├── supabase/
│   ├── config.toml                        # Supabase project config, major_version 17 (M0-2)
│   ├── migrations/                        # M0-3 — apply in order
│   │   ├── 0001_extensions.sql
│   │   ├── 0002_enums.sql
│   │   ├── 0003_tenant_core.sql
│   │   ├── 0004_agent_layer.sql
│   │   ├── 0005_leads.sql
│   │   ├── 0006_lead_notes.sql
│   │   ├── 0007_calls_scheduling.sql
│   │   ├── 0008_messaging.sql
│   │   ├── 0009_rag.sql
│   │   ├── 0010_usage_logs.sql
│   │   ├── 0011_audit_logs.sql
│   │   ├── 0012_functions_updated_at.sql
│   │   └── 0013_dedup_trigger.sql
│   ├── rollback/                          # M0-3 — paired down-scripts (staging/local only)
│   │   ├── 0001_extensions.down.sql … 0013_dedup_trigger.down.sql
│   └── tests/
│       └── m0_3_schema.test.sql           # pgTAP structural suite, plan(48)
└── services/
    └── api/                               # M0-1 FastAPI service
        ├── README.md
        ├── Dockerfile
        ├── pyproject.toml
        ├── .env.example
        ├── app/
        │   ├── __init__.py                # __version__
        │   ├── main.py                    # app factory · lifespan · middleware · error envelope
        │   ├── core/
        │   │   ├── config.py              # pydantic-settings (cached singleton)
        │   │   ├── logging.py             # structlog
        │   │   └── security.py            # JWT verify → Principal
        │   ├── db/
        │   │   ├── base.py                # DeclarativeBase
        │   │   └── session.py             # async engine + sessionmaker + get_db + check_database
        │   ├── api/
        │   │   ├── deps.py                # get_current_principal · require_roles
        │   │   └── v1/
        │   │       ├── router.py
        │   │       └── routes/
        │   │           └── health.py
        │   └── schemas/
        │       ├── auth.py                # Principal · UserRole
        │       └── common.py              # error envelope · health models
        └── tests/
            ├── conftest.py
            ├── test_config.py
            ├── test_security.py
            └── test_health.py
```

---

## File inventory

| Milestone | Path | Purpose |
|-----------|------|---------|
| M0-1 | `services/api/app/main.py` | App factory, lifespan (DB pool), request-id middleware, error envelope |
| M0-1 | `services/api/app/core/config.py` | `pydantic-settings` config; normalises Postgres URL to asyncpg; CSV CORS |
| M0-1 | `services/api/app/core/security.py` | Verify Supabase HS256 JWT → `Principal` (claims from `app_metadata`) |
| M0-1 | `services/api/app/core/logging.py` | structlog (console locally / JSON in prod) |
| M0-1 | `services/api/app/db/session.py` | Async engine + sessionmaker, `get_db`, `check_database` |
| M0-1 | `services/api/app/db/base.py` | Declarative base for M1+ models |
| M0-1 | `services/api/app/api/deps.py` | `get_current_principal`, `require_roles` |
| M0-1 | `services/api/app/api/v1/router.py` + `routes/health.py` | v1 router; `/health` + `/health/ready` |
| M0-1 | `services/api/app/schemas/{auth,common}.py` | `Principal`/`UserRole`; error & health models |
| M0-1 | `services/api/tests/*` | Offline suite (config, JWT, health, role guard) |
| M0-1 | `services/api/{Dockerfile,pyproject.toml,.env.example}` | Image, packaging, service env template |
| M0-2 | `supabase/config.toml` | Reproducible Supabase config (`major_version = 17`) |
| M0-2 | `.env.example` | Project env inventory (M0-active + reserved blocks) |
| M0-2 | `railway.json` | Nixpacks build + uvicorn start + healthcheck |
| M0-2 | `.github/workflows/m0-2-supabase-smoke.yml` | Connectivity + migration dry-run gate |
| M0-2 | `Makefile` | install / dev / test / lint / db-migrate / db-verify / db-test |
| M0-2 | `scripts/check_env.py` | Validates the required env block; exits non-zero on gaps |
| M0-2 | `.gitignore` | Prevents committing secrets / build artifacts |
| M0-2 | `docs/M0-2-Environment-Setup-Guide.md` | Provisioning + connection architecture runbook |
| M0-3 | `supabase/migrations/0001…0013` | Extensions → enums → tables → indexes → functions → triggers |
| M0-3 | `supabase/rollback/*.down.sql` | Reverse-order down-scripts (staging/local only) |
| M0-3 | `scripts/verify_m0_3.sql` | Report + hard asserts (16 tables, 26 enums, triggers, HNSW, dedup) |
| M0-3 | `supabase/tests/m0_3_schema.test.sql` | pgTAP structural suite, `plan(48)` |
| M0-3 | `docs/M0-3-Migrations-Runbook.md` | Full migration/rollback/verification/testing runbook |

---

## Setup instructions

Prerequisites: Python 3.11+, the Supabase CLI, and PostgreSQL client tools (`psql`).

```bash
# 1. Environment
cp .env.example .env
#    Fill the M0-active block. DATABASE_URL -> 6543 (transaction pooler),
#    DIRECT_URL -> 5432 (session pooler). Keep DB_STATEMENT_CACHE_SIZE=0.
python scripts/check_env.py .env          # validate before proceeding

# 2. Local Supabase stack (provides the auth schema the migrations depend on)
supabase start

# 3. Database schema (M0-3)
make db-migrate                           # applies supabase/migrations/0001..0013 over $DIRECT_URL
make db-verify                            # structural verification (hard asserts)
make db-test                              # pgTAP structural suite
```

See `docs/M0-2-Environment-Setup-Guide.md` for the connection architecture and
the CI secrets, and `docs/M0-3-Migrations-Runbook.md` for rollback/PITR details.

---

## Local development instructions

```bash
# API service
cd services/api
python -m venv .venv && source .venv/bin/activate
pip install --upgrade pip && pip install -e ".[dev]"
cp .env.example .env                      # paste SUPABASE_JWT_SECRET + DATABASE_URL
uvicorn app.main:app --reload --port 8000
```

- Interactive docs: <http://localhost:8000/docs>
- Liveness: `GET /api/v1/health`
- Readiness: `GET /api/v1/health/ready` (returns `degraded` at HTTP 200 if the DB pool is down)

From the repo root, `make dev` / `make lint` / `make typecheck` wrap the above.

---

## Test execution instructions

**API unit tests (M0-1)** — fully offline, the DB probe is patched:
```bash
cd services/api && source .venv/bin/activate
pytest                # or: make test   (from repo root)
```

**Database structural tests (M0-3)** — against a database with `0001`–`0013` applied:
```bash
# pgTAP (raw TAP via psql; expect 1..48 then ok 1..ok 48)
psql "$DIRECT_URL" -X -q -t -A -f supabase/tests/m0_3_schema.test.sql
# or with pg_prove:
pg_prove -d <dbname> supabase/tests/m0_3_schema.test.sql

# Verification (report + hard asserts)
psql "$DIRECT_URL" -v ON_ERROR_STOP=1 -f scripts/verify_m0_3.sql
```

**CI** — `.github/workflows/m0-2-supabase-smoke.yml` runs the connectivity check
and a migration dry-run on every change under `supabase/`.
