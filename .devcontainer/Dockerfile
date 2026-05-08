# Docker Hub instead of mcr.microsoft.com to avoid the occasional AFD 403
# blocks that hit Codespaces. The official Python image is Debian-based,
# so the apt steps below are unchanged.
FROM python:3.12-bookworm

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        git \
        postgresql-client \
        curl \
        ca-certificates \
    && rm -rf /var/lib/apt/lists/*

RUN curl -LsSf https://astral.sh/uv/install.sh | env UV_INSTALL_DIR=/usr/local/bin sh

# Used by dbt's profiles.yml env_var lookups (host/port/user/password are
# shared across all Postgres targets; dbname is hardcoded per target).
ENV POSTGRES_HOST=postgres \
    POSTGRES_PORT=5432 \
    POSTGRES_USER=postgres \
    POSTGRES_PASSWORD=postgres

# Convenience vars so `psql` with no args drops into the playground DB.
ENV PGHOST=postgres \
    PGPORT=5432 \
    PGUSER=postgres \
    PGPASSWORD=postgres \
    PGDATABASE=playground
