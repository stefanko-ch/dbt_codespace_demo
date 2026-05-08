# dbt + n8n + Postgres Codespace Demo

Codespace-Umgebung für den Workshop. Enthält:

- **Postgres 16** als Data Warehouse
- **n8n** für Workflow-Automation (mit Postgres als Backing Store)
- **dbt** (Postgres + DuckDB Adapter) als uv-Projekt
- VS Code Extensions für dbt + SQL

## Schnellstart

1. Repository auf GitHub forken.
2. Im Fork: **Code → Codespaces → Create codespace on main**.
3. Beim ersten Start baut Codespaces das Image und führt `uv sync` aus (~2–3 Min).
4. Sobald der Codespace bereit ist, sind folgende Ports automatisch geforwarded:
   - **5678** → n8n UI (öffnet automatisch in der Preview)
   - **5432** → Postgres

## dbt benutzen

Die venv wird automatisch aktiviert (über `~/.bashrc`). In einem neuen Terminal:

```bash
cd dbt
dbt debug          # prüft die Postgres-Verbindung
dbt seed           # lädt Beispiel-CSVs nach raw.*
dbt run            # baut staging-views und marts-tables
dbt test           # führt die Tests aus
```

### Target wechseln (Postgres ↔ DuckDB)

Default ist `postgres`. Für lokale DuckDB-Experimente:

```bash
dbt run --target duckdb
```

Die DuckDB-Datei landet als `dbt/analytics.duckdb` (ist gitignored).

## Postgres direkt abfragen

```bash
psql -h postgres -U postgres -d analytics
# Passwort: postgres
```

Schemas nach `dbt run`:
- `raw` — Seeds
- `staging` — Views
- `marts` — Tabellen (z. B. `customer_summary`)

## n8n

UI auf Port **5678**. Beim ersten Aufruf legt n8n einen Owner-Account an. Workflows werden in der `n8n`-DB auf Postgres persistiert (überlebt Container-Neustarts).

Damit n8n auf das Warehouse zugreifen kann, in n8n eine **Postgres**-Credential anlegen mit:
- Host: `postgres`
- Database: `analytics`
- User: `postgres`
- Password: `postgres`
- Port: `5432`

## Struktur

```
.devcontainer/
  Dockerfile           # Python 3.12 + uv + psql client
  devcontainer.json    # Codespace config (Ports, postCreate, Extensions)
  docker-compose.yml   # workspace + postgres + n8n
  postgres-init/
    01-init-databases.sh   # legt n8n DB + raw/staging/marts Schemas an
dbt/
  pyproject.toml       # uv: dbt-core, dbt-postgres, dbt-duckdb
  dbt_project.yml
  profiles.yml         # postgres (default) + duckdb target
  seeds/               # raw_customers.csv, raw_orders.csv
  models/
    staging/           # stg_customers, stg_orders (Views)
    marts/             # customer_summary (Table)
```

## Hinweise

- Daten in Postgres und n8n persistieren in Docker-Volumes (`postgres-data`, `n8n-data`). Beim Stop des Codespaces bleiben sie erhalten; beim Löschen des Codespaces sind sie weg.
- Wenn `uv sync` fehlschlägt: in `dbt/` manuell `uv sync` ausführen und neues Terminal öffnen.
