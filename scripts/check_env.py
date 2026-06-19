#!/usr/bin/env python3
"""Validate that the M0-active environment variables are present and shaped.

Exits 0 when every required variable is set to a non-placeholder value,
and 1 otherwise. Reserved (later-milestone) variables are reported but never
cause failure. Reads the process environment; optionally loads a .env file
passed as the first argument.

Usage:
    python scripts/check_env.py            # checks os.environ
    python scripts/check_env.py .env       # also loads values from .env
"""

from __future__ import annotations

import os
import sys

# Required for M0 (app boot + DB + auth).
REQUIRED: tuple[str, ...] = (
    "APP_ENV",
    "API_V1_PREFIX",
    "SUPABASE_JWT_SECRET",
    "SUPABASE_JWT_AUDIENCE",
    "DATABASE_URL",
    "DIRECT_URL",
    "DB_STATEMENT_CACHE_SIZE",
)

# Reserved for later milestones — reported, never fatal.
RESERVED: tuple[str, ...] = (
    "REDIS_URL",
    "OPENAI_API_KEY",
    "ELEVENLABS_API_KEY",
    "TWILIO_ACCOUNT_SID",
    "TWILIO_AUTH_TOKEN",
    "SARVAM_API_KEY",
)

PLACEHOLDER_MARKERS = ("<", ">", "change-me")


def _load_env_file(path: str) -> None:
    if not os.path.exists(path):
        print(f"  (env file '{path}' not found; checking process environment only)")
        return
    with open(path, encoding="utf-8") as fh:
        for line in fh:
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, _, value = line.partition("=")
            os.environ.setdefault(key.strip(), value.strip())


def _is_placeholder(value: str) -> bool:
    return (not value) or any(marker in value for marker in PLACEHOLDER_MARKERS)


def main(argv: list[str]) -> int:
    if len(argv) > 1:
        _load_env_file(argv[1])

    missing: list[str] = []
    placeholders: list[str] = []

    print("Required (M0-active):")
    for key in REQUIRED:
        value = os.environ.get(key)
        if value is None:
            missing.append(key)
            print(f"  [MISSING]     {key}")
        elif _is_placeholder(value):
            placeholders.append(key)
            print(f"  [PLACEHOLDER] {key}")
        else:
            print(f"  [ok]          {key}")

    print("\nReserved (later milestones — informational):")
    for key in RESERVED:
        state = "set" if os.environ.get(key) else "unset"
        print(f"  [{state}] {key}")

    if missing or placeholders:
        print(
            f"\nFAIL: {len(missing)} missing, {len(placeholders)} placeholder "
            f"value(s) in the required block."
        )
        return 1

    print("\nOK: all required M0 variables are set.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
