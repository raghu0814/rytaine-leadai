from app.core.config import Settings, get_settings


def test_postgresql_scheme_coerced_to_asyncpg():
    s = Settings(database_url="postgresql://u:p@h:5432/db", supabase_jwt_secret="x")
    assert str(s.database_url).startswith("postgresql+asyncpg://")


def test_plain_postgres_scheme_coerced_to_asyncpg():
    s = Settings(database_url="postgres://u:p@h:5432/db", supabase_jwt_secret="x")
    assert str(s.database_url).startswith("postgresql+asyncpg://")


def test_cors_origins_split_from_csv():
    s = Settings(cors_origins="https://a.com, http://localhost:3000", supabase_jwt_secret="x")
    assert s.cors_origins == ["https://a.com", "http://localhost:3000"]


def test_get_settings_is_cached_singleton():
    assert get_settings() is get_settings()
