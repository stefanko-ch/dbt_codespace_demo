# dbt + n8n + Postgres Codespace Demo

Codespace environment for the workshop.

## What we're doing

We build a small end-to-end data pipeline:

```
 Azure SQL (AdventureWorks) ──► n8n ──► Postgres (raw) ──► dbt ──► Postgres (staging → marts) ──► Metabase
       source system         ingest    landing zone   transform        analytics models           BI / dashboards
```

- **Source:** the full **AdventureWorks** sample database hosted on Azure SQL (not AdventureWorksLT — we use the complete schema with `Sales`, `Production`, `Person`, `HumanResources`, etc.).
- **Ingest with n8n:** workflows in n8n connect to Azure SQL using credentials read from Codespace secrets, pull selected tables, and load them into the `raw` schema of the local Postgres.
- **Transform with dbt:** a dbt project on top of Postgres turns the raw tables into clean staging views and curated marts. DuckDB is wired up as an alternative target for offline experiments.
- **Visualize with Metabase:** Metabase connects to the same Postgres warehouse to explore the marts and build dashboards.
- **Everything runs in a Codespace:** Postgres, n8n, dbt, and Metabase are containers in one `docker-compose` stack. Students fork the repo, open it in a Codespace, and have the full environment in a few minutes.

## Stack

- **Postgres 16** as the warehouse
- **n8n** for workflow automation (uses Postgres as its backing store)
- **dbt** (Postgres + DuckDB adapters) as a uv-managed Python project
- **Metabase** for BI and dashboards (uses Postgres as its backing store)
- VS Code extensions for dbt and SQL, with pre-configured Postgres connections

## Quickstart

1. Fork the repository on GitHub.
2. Add the Azure SQL Codespace secrets — see [Azure SQL secrets for n8n](#azure-sql-secrets-for-n8n) below. Without these, n8n cannot reach AdventureWorks.
3. In your fork: **Code → Codespaces → Create codespace on main**.
4. On first start, Codespaces builds the image and runs `uv sync` (~2–3 min).
5. Once the codespace is ready, these ports are forwarded automatically:
   - **5678** → n8n UI (opens automatically in the preview pane)
   - **3000** → Metabase UI
   - **5432** → Postgres

## Using dbt

The venv is activated automatically (via `~/.bashrc`). In a new terminal:

```bash
cd dbt
dbt debug          # checks the Postgres connection
dbt seed           # loads the example CSVs into raw.*
dbt run            # builds staging views and marts tables
dbt test           # runs the tests
```

### Switching targets (Postgres ↔ DuckDB)

Default is `postgres`. For local DuckDB experiments:

```bash
dbt run --target duckdb
```

The DuckDB file lands at `dbt/analytics.duckdb` (gitignored).

## Querying Postgres directly

From the terminal:

```bash
psql -h postgres -U postgres -d analytics
# password: postgres
```

Or use the **SQLTools** sidebar in VS Code — two connections are pre-configured:
- `analytics (Postgres)` — the dbt warehouse
- `n8n (Postgres)` — n8n's backing store

Schemas after `dbt run`:
- `raw` — seeds
- `staging` — views
- `marts` — tables (e.g. `customer_summary`)

## n8n

UI on port **5678**. On first visit n8n creates an owner account. Workflows are persisted in the `n8n` database on Postgres (survives container restarts).

To let n8n query the warehouse, create a **Postgres** credential in n8n with:
- Host: `postgres`
- Database: `analytics`
- User: `postgres`
- Password: `postgres`
- Port: `5432`

## Metabase

UI on port **3000**. On first visit Metabase walks you through creating an admin account. The Metabase application data (questions, dashboards, users) is stored in the `metabase` database on Postgres and survives container restarts.

To explore the dbt output, add the warehouse as a database in **Settings → Databases → Add database**:
- Database type: **PostgreSQL**
- Display name: anything (e.g. `analytics`)
- Host: `postgres`
- Port: `5432`
- Database name: `analytics`
- Username: `postgres`
- Password: `postgres`

Once added, Metabase will sync the schemas — `marts.*` is the recommended starting point for dashboards.

### Azure SQL secrets for n8n

n8n can reach Azure SQL using **Codespaces secrets** — credentials never live in the repo.

**Step 1 — Add the secrets in GitHub** (per-user, scoped to this fork)

Go to <https://github.com/settings/codespaces> → **New secret** and create the four secrets below. For each one, under **Repository access**, select your fork of this repo.

| Secret name           | Example value                              |
| --------------------- | ------------------------------------------ |
| `AZURE_SQL_HOST`      | `myserver.database.windows.net`            |
| `AZURE_SQL_DATABASE`  | `mydb`                                     |
| `AZURE_SQL_USER`      | `sqladmin`                                 |
| `AZURE_SQL_PASSWORD`  | `…`                                        |

**Step 2 — (Re)create the codespace**

Codespace secrets are only injected at codespace creation. If your codespace was created before adding the secrets, **delete it and create a new one** (a "Rebuild Container" alone is not enough). New secrets you add later need the same treatment.

**Step 3 — Reference the secrets in n8n**

The secrets are forwarded into the n8n container as env vars. When creating a **Microsoft SQL** credential in n8n (or any expression field), use:

```
={{ $env.AZURE_SQL_HOST }}
={{ $env.AZURE_SQL_DATABASE }}
={{ $env.AZURE_SQL_USER }}
={{ $env.AZURE_SQL_PASSWORD }}
```

n8n ships with the SQL Server driver out of the box. If a secret is missing, the env var is empty and the connection fails with a clear error.

> **Azure SQL firewall:** make sure your server allows the Codespace's outbound IP, or enable "Allow Azure services and resources to access this server" if that fits your scenario.

> **Adding more secrets later:** add the env var to the `n8n` service in [`.devcontainer/docker-compose.yml`](.devcontainer/docker-compose.yml) (using `${MY_SECRET:-}`), commit, and recreate the codespace.

## Layout

```
.devcontainer/
  Dockerfile           # Python 3.12 + uv + psql client
  devcontainer.json    # Codespace config (ports, postCreate, extensions)
  docker-compose.yml   # workspace + postgres + n8n + metabase
  postgres-init/
    01-init-databases.sh   # creates n8n + metabase DBs and raw/staging/marts schemas
dbt/
  pyproject.toml       # uv: dbt-core, dbt-postgres, dbt-duckdb
  dbt_project.yml
  profiles.yml         # postgres (default) + duckdb target
  seeds/               # raw_customers.csv, raw_orders.csv
  models/
    staging/           # stg_customers, stg_orders (views)
    marts/             # customer_summary (table)
```

## Notes

- Postgres, n8n, and Metabase data persist in Docker volumes (`postgres-data`, `n8n-data`, `metabase-data`). Stopping the codespace keeps them; deleting the codespace wipes them.
- If `uv sync` fails, run it manually in `dbt/` and open a new terminal.
