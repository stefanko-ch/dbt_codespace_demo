# dbt + Kestra + Postgres Codespace Demo

Codespace environment for the workshop.

## What we're doing

We build a small end-to-end data pipeline:

<p align="center">
  <img src="assets/pipeline.svg" alt="Pipeline: Azure SQL → Kestra → Postgres raw → dbt → Postgres staging/marts → Metabase" width="100%">
</p>

- **Source:** the full **AdventureWorks** sample database hosted on Azure SQL (not AdventureWorksLT — we use the complete schema with `Sales`, `Production`, `Person`, `HumanResources`, etc.).
- **Ingest with Kestra:** a YAML flow ([`flows/bronze_adventureworks.yml`](flows/bronze_adventureworks.yml)) queries Azure SQL and bulk-loads the result into the `raw` schema of the local Postgres via `Postgres.CopyIn`. Credentials are entered at execution time, so no secrets live in the repo.
- **Transform with dbt:** a dbt project on top of Postgres turns the raw tables into clean staging views and curated marts. DuckDB is wired up as an alternative target for offline experiments.
- **Visualize with Metabase:** Metabase connects to the same Postgres warehouse to explore the marts and build dashboards.
- **Everything runs in a Codespace:** Postgres, Kestra, dbt, and Metabase are containers in one `docker-compose` stack. Students fork the repo, open it in a Codespace, and have the full environment in a few minutes.

## Stack

- **Postgres 16** as the warehouse, with four DBs: `analytics` (AdventureWorks target), `playground` (dbt warm-up), `kestra` and `metabase` (backing stores)
- **Kestra** for orchestrating the bronze ingestion (declarative YAML flows, JDBC source/destination)
- **dbt** (Postgres + DuckDB adapters) as a uv-managed Python project, with named targets for `playground` (default) and `analytics`
- **Metabase** for BI and dashboards
- VS Code extensions: dbt Power User and Database Client (Weijan) for browsing/querying Postgres
- `docker` CLI available inside the workspace (via docker-outside-of-docker) for `docker logs`, `docker exec`, etc.

## Quickstart

1. Fork the repository on GitHub.
2. In your fork: **Code → Codespaces → Create codespace on main**.
3. On first start, Codespaces builds the image and runs `uv sync` (~2–3 min). Kestra adds another ~30–60 s for JVM warmup on first launch.
4. Once the codespace is ready, these ports are forwarded automatically:
   - **8080** → Kestra UI (auto-opens in the preview pane)
   - **3000** → Metabase UI
   - **5432** → Postgres

For the full guided path (bronze → silver → gold → BI), see [`tutorial/README.md`](tutorial/README.md).

## Using dbt

The venv is activated automatically (via `~/.bashrc`). In a new terminal:

```bash
cd dbt
dbt debug          # checks the Postgres connection
dbt seed           # loads the example CSVs into raw.*
dbt run            # builds staging views and marts tables
dbt test           # runs the tests
```

### Library warm-up (default target: `playground`)

The repo ships a small **library domain** example so the toolchain is verifiable on day one without depending on Kestra or AdventureWorks:

- Seeds: `raw_books`, `raw_members`, `raw_loans`
- Staging: `stg_books`, `stg_members`, `stg_loans`
- Marts: `book_popularity`, `member_activity`

These are written into the **`playground`** Postgres database (separate from `analytics`, so the warm-up never collides with the AdventureWorks pipeline). The default target in `profiles.yml` points there, so `dbt seed && dbt run && dbt test` just works.

### Switching targets

`dbt/profiles.yml` defines three named outputs:

| Target       | Backend                 | Use case                                                     |
| ------------ | ----------------------- | ------------------------------------------------------------ |
| `playground` | Postgres `playground` DB | **default** — library warm-up                                |
| `analytics`  | Postgres `analytics` DB  | the real project against AdventureWorks data ingested by Kestra |
| `duckdb`     | local file              | offline experiments                                          |

```bash
dbt run                       # default → playground
dbt run --target analytics    # against the analytics warehouse
dbt run --target duckdb       # writes ./analytics.duckdb (gitignored)
```

## Querying Postgres directly

From the terminal:

```bash
psql                           # drops into the playground DB by default
psql -d analytics              # switch DB (or any of: kestra, metabase)
```

Or use the **Database Client** sidebar in VS Code (icon shaped like a cylinder). On first launch, click **+ Add** and create a PostgreSQL connection with:

- Host: `postgres`
- Port: `5432`
- User: `postgres`
- Password: `postgres`
- Default database: any (the tree exposes all four)

The tree view lets you browse `analytics`, `playground`, `kestra`, and `metabase` side by side, run queries, edit table data inline, and view ER diagrams.

Schemas inside the `playground` and `analytics` DBs after `dbt run`:
- `raw` — seeds / ingested tables
- `staging` — views
- `marts` — tables

## Kestra

UI on port **8080**. The sandbox config has authentication off — you land directly in the dashboard.

The container mounts the repo's [`flows/`](flows/) directory read-only into `/app/flows`, so any YAML flow you commit shows up automatically in the UI under its declared `namespace`. Kestra's own state (executions, logs, schedules) lives in the `kestra` Postgres database and survives container restarts.

The bronze ingestion flow [`bronze_adventureworks.yml`](flows/bronze_adventureworks.yml) declares its Azure SQL credentials as **inputs** — Kestra prompts for them at execution time, so they never need to be checked into git or set as Codespace secrets.

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

## Layout

```
.devcontainer/
  Dockerfile           # Python 3.12 + uv + psql client
  devcontainer.json    # Codespace config (ports, postCreate, extensions, docker-in-docker)
  docker-compose.yml   # workspace + postgres + kestra + metabase
  postgres-init/
    01-init-databases.sh   # creates kestra / metabase / playground DBs and raw/staging/marts schemas
flows/
  bronze_adventureworks.yml  # Kestra flow: 9 AdventureWorks tables → analytics.raw
dbt/
  pyproject.toml       # uv: dbt-core, dbt-postgres, dbt-duckdb
  dbt_project.yml
  profiles.yml         # playground (default) + analytics + duckdb targets
  seeds/               # raw_books.csv, raw_members.csv, raw_loans.csv (library warm-up)
  models/
    staging/           # stg_books, stg_members, stg_loans (views)
    marts/             # book_popularity, member_activity (tables)
tutorial/              # guided workshop (Bronze → Silver → Gold → Metabase)
```

## Notes

- Postgres, Kestra, and Metabase data persist in Docker volumes (`postgres-data`, `kestra-data`, `metabase-data`). Stopping the codespace keeps them; deleting the codespace wipes them.
- If `uv sync` fails, run it manually in `dbt/` and open a new terminal.
