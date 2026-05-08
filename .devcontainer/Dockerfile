# Docker Hub statt mcr.microsoft.com, um sporadische AFD-403-Blocks in
# Codespaces zu vermeiden. Das offizielle Python-Image ist Debian-basiert,
# daher funktionieren die apt-Schritte unverändert.
FROM python:3.12-bookworm

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        git \
        postgresql-client \
        curl \
        ca-certificates \
    && rm -rf /var/lib/apt/lists/*

RUN curl -LsSf https://astral.sh/uv/install.sh | env UV_INSTALL_DIR=/usr/local/bin sh

ENV POSTGRES_HOST=postgres \
    POSTGRES_PORT=5432 \
    POSTGRES_USER=postgres \
    POSTGRES_PASSWORD=postgres \
    POSTGRES_DB=analytics \
    DBT_PROFILES_DIR=/workspaces/dbt_codespace_demo/dbt
