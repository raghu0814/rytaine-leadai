"""DB-backed API integration tests (M0-7).

These require a real Postgres with migrations 0001-0016 + the Supabase roles
applied, addressed by ``INTEGRATION_DATABASE_URL``. They are skipped when that
variable is unset, so the offline unit suite (``make test``) is unaffected.
"""