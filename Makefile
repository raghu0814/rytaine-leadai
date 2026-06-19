# RYtaine LeadAI — developer workflow helpers (M0).
# Uses '>' as the recipe prefix to avoid tab/space ambiguity.
.RECIPEPREFIX = >
.DEFAULT_GOAL := help
SHELL := /bin/bash

API_DIR := services/api
PSQL := psql "$$DIRECT_URL" -v ON_ERROR_STOP=1

.PHONY: help install dev test lint typecheck check-env \
        supabase-start db-migrate db-verify db-test db-rollback-last

help:                ## Show this help
> @grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
>   awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'

install:             ## Install the API service with dev tooling
> cd $(API_DIR) && python -m venv .venv && . .venv/bin/activate && \
>   pip install --upgrade pip && pip install -e ".[dev]"

dev:                 ## Run the API locally with autoreload
> cd $(API_DIR) && . .venv/bin/activate && \
>   uvicorn app.main:app --reload --port 8000

test:                ## Run the API unit tests (offline)
> cd $(API_DIR) && . .venv/bin/activate && pytest

lint:                ## Ruff lint
> cd $(API_DIR) && . .venv/bin/activate && ruff check .

typecheck:           ## mypy type check
> cd $(API_DIR) && . .venv/bin/activate && mypy app

check-env:           ## Validate the M0-active environment block
> python scripts/check_env.py .env

supabase-start:      ## Start the local Supabase stack
> supabase start

db-migrate:          ## Apply migrations 0001-0013 in order ($$DIRECT_URL)
> for f in supabase/migrations/0*.sql; do echo ">> $$f"; $(PSQL) -f "$$f"; done

db-verify:           ## Run the M0-3 verification script
> $(PSQL) -f scripts/verify_m0_3.sql

db-test:             ## Run the pgTAP structural suite
> $(PSQL) -f supabase/tests/m0_3_schema.test.sql

db-rollback-last:    ## Roll back the most recent migration (staging/local only)
> $(PSQL) -f supabase/rollback/0013_dedup_trigger.down.sql
