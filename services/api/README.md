# RYtaine LeadAI — API Service (`services/api`)

M0-1 scaffold: a runnable FastAPI skeleton with configuration management, an
async database session factory, a Supabase JWT dependency, and health probes.
No business logic, lead ingestion, adapters, validation, voice, or telephony —
those arrive in later milestones.

## Layout

```
services/api/
├── app/
│   ├── __init__.py            # package version
│   ├── main.py                # app factory, lifespan, middleware, handlers
│   ├── core/
│   │   ├── config.py          # pydantic-settings configuration
│   │   ├── logging.py         # structlog setup
│   │   └── security.py        # JWT verify -> Principal (framework-agnostic)
│   ├── db/
│   │   ├── base.py            # DeclarativeBase (models land here in M1+)
│   │   └── session.py         # async engine + sessionmaker + get_db + check_database
│   ├── api/
│   │   ├── deps.py            # get_current_principal, require_roles
│   │   └── v1/
│   │       ├── router.py      # v1 aggregator
│   │       └── routes/health.py
│   └── schemas/
│       ├── auth.py            # Principal, UserRole
│       └── common.py          # error envelope, health models
├── tests/
│   ├── conftest.py            # settings, JWT factory, ASGI client
│   ├── test_config.py
│   ├── test_security.py
│   └── test_health.py
├── .env.example
├── Dockerfile
├── pyproject.toml
└── README.md
```

## Local setup

Requires Python 3.11+.

```bash
cd services/api

# 1. Create and activate a virtual environment
python -m venv .venv
source .venv/bin/activate          # Windows: .venv\Scripts\activate

# 2. Install the service with dev tooling
pip install --upgrade pip
pip install -e ".[dev]"

# 3. Configure environment
cp .env.example .env
#   - paste your Supabase JWT secret into SUPABASE_JWT_SECRET
#   - paste your Supabase Postgres URL into DATABASE_URL
#   - if using the transaction pooler (port 6543), set DB_STATEMENT_CACHE_SIZE=0

# 4. Run the API
uvicorn app.main:app --reload --port 8000
```

Open the interactive docs at <http://localhost:8000/docs>.

Health probes:
- `GET /api/v1/health` — liveness (no DB).
- `GET /api/v1/health/ready` — readiness (`SELECT 1`); returns `degraded` at HTTP 200 if the pool is down.

## Tests

```bash
pip install -e ".[dev]"
pytest            # fully offline; the DB probe is patched
```
