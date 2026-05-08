#!/usr/bin/env bash
set -euo pipefail

# Backing-store DBs and the dbt warm-up DB. The `analytics` DB is created by
# the postgres image itself via POSTGRES_DB, and is reserved for the
# AdventureWorks ingest from n8n.
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" <<-EOSQL
    CREATE DATABASE kestra;
    CREATE DATABASE metabase;
    CREATE DATABASE playground;
EOSQL

# Standard layered schemas in the two warehouse DBs students will work with.
for db in analytics playground; do
    psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$db" <<-EOSQL
        CREATE SCHEMA IF NOT EXISTS raw;
        CREATE SCHEMA IF NOT EXISTS staging;
        CREATE SCHEMA IF NOT EXISTS marts;
EOSQL
done
