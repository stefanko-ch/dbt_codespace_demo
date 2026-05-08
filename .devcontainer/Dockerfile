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
        unzip \
    && rm -rf /var/lib/apt/lists/*

RUN curl -LsSf https://astral.sh/uv/install.sh | env UV_INSTALL_DIR=/usr/local/bin sh

# DuckDB CLI -- used by the DuckDB/ tutorial. Architecture-aware so it works
# on both Codespaces (amd64) and Apple Silicon devcontainers (arm64).
RUN ARCH="$(uname -m)" \
    && case "$ARCH" in \
         x86_64)           CLI_URL="https://github.com/duckdb/duckdb/releases/latest/download/duckdb_cli-linux-amd64.zip" ;; \
         aarch64|arm64)    CLI_URL="https://github.com/duckdb/duckdb/releases/latest/download/duckdb_cli-linux-aarch64.zip" ;; \
         *)                echo "Unsupported arch $ARCH for DuckDB CLI" && exit 1 ;; \
       esac \
    && curl -sL "$CLI_URL" -o /tmp/duckdb.zip \
    && unzip -o /tmp/duckdb.zip -d /usr/local/bin \
    && rm /tmp/duckdb.zip \
    && chmod +x /usr/local/bin/duckdb \
    && duckdb --version

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
