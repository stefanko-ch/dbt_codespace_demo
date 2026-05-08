# Task 1 — Bronze: Ingest AdventureWorks with Kestra

**Goal:** copy nine tables from Azure SQL (AdventureWorks) into the `analytics.raw.*` schema of your local Postgres, 1:1 — no transformations.

This is the bronze layer. We don't clean, rename, or filter here. We just land the data so downstream tools (dbt) can take over.

## What you'll build

A single Kestra flow that fans out across all nine source tables in parallel. Each iteration runs two tasks:

```
                    ┌────────────────────────────────────────────────┐
                    │ ForEach (concurrencyLimit: 3)                  │
                    │  for each {target, select} in 9 tables:        │
                    │                                                │
                    │   [SqlServer.Query]  ──► CSV in Kestra storage │
                    │           │                                    │
                    │           ▼                                    │
                    │   [Postgres.CopyIn] ──► raw.<target>           │
                    └────────────────────────────────────────────────┘
```

The flow is already in the repo: [`flows/bronze_adventureworks.yml`](../flows/bronze_adventureworks.yml). Kestra picks it up automatically because the workspace mounts `/flows` into the Kestra container.

## Tables ingested

| # | Source (Azure SQL)              | Bronze table (`analytics.raw`) |
| - | ------------------------------- | ------------------------------- |
| 1 | `Sales.SalesOrderHeader`        | `sales_order_header`            |
| 2 | `Sales.SalesOrderDetail`        | `sales_order_detail`            |
| 3 | `Sales.Customer`                | `customer`                      |
| 4 | `Person.Person`                 | `person`                        |
| 5 | `Sales.SalesTerritory`          | `sales_territory`               |
| 6 | `Sales.SalesPerson`             | `sales_person`                  |
| 7 | `Production.Product`            | `product`                       |
| 8 | `Production.ProductSubcategory` | `product_subcategory`           |
| 9 | `Production.ProductCategory`    | `product_category`              |

The exact column lists (snake_case aliases, no XML/blob columns) are baked into the flow YAML — open it to see what's projected per table.

## Step 1 — Pre-create the bronze tables

`Postgres.CopyIn` runs a Postgres `COPY FROM` and **expects the target table to already exist**. We ship a SQL script that creates all nine bronze tables with sensible column types and primary keys.

In the Codespace terminal:

```bash
psql -d analytics -f tutorial/sql/01_create_bronze_tables.sql
```

Verify:

```bash
psql -d analytics -c "\dt raw.*"
```

You should see nine empty tables in the `raw` schema.

## Step 2 — Open Kestra

In the **Ports** panel of VS Code, click the globe icon next to port **8080** (or use the auto-opened preview tab). On first launch Kestra takes ~30–60 seconds to start (JVM warmup); refresh once you see the dashboard.

The sandbox config has authentication off — you land directly in the UI.

## Step 3 — Find the flow

Left sidebar → **Flows** → namespace **`workshop`** → **`bronze_adventureworks`**.

If it's not there, the volume mount didn't take effect. Verify:

```bash
docker exec $(docker ps --filter name=kestra -q) ls /app/flows
```

You should see `bronze_adventureworks.yml`.

## Step 4 — Execute the flow

Click **Execute** (top right of the flow page). Kestra prompts for the four inputs the flow declares:

| Input                | Value                                       |
| -------------------- | ------------------------------------------- |
| `azure_sql_host`     | `<your-server>.database.windows.net`        |
| `azure_sql_database` | `AdventureWorks` (default — leave as-is)    |
| `azure_sql_user`     | your SQL login                              |
| `azure_sql_password` | your SQL password                           |

Click **Execute**. The Gantt view shows the ForEach fanning out — three table pairs run concurrently (`concurrencyLimit: 3`), each pair being `query_source` → `copy_to_bronze`.

When it finishes, every task should be green.

## Acceptance check

In the Codespace terminal:

```bash
psql -d analytics -c "
SELECT table_name, n_live_tup AS approx_rows
FROM pg_stat_user_tables
WHERE schemaname = 'raw'
ORDER BY table_name;
"
```

Expected (numbers approximate — Postgres stats lag, run `ANALYZE raw.<table>` if you see zeros):

| table                | approx_rows |
| -------------------- | ----------- |
| customer             | 19,820      |
| person               | 19,972      |
| product              | 504         |
| product_category     | 4           |
| product_subcategory  | 37          |
| sales_order_detail   | 121,317     |
| sales_order_header   | 31,465      |
| sales_person         | 17          |
| sales_territory      | 10          |

If row counts roughly match, bronze is done. ✅

## Troubleshooting

**The flow doesn't show up in the UI**
- Confirm the volume mount: `docker exec $(docker ps --filter name=kestra -q) ls /app/flows`
- Restart Kestra: `docker compose -f .devcontainer/docker-compose.yml restart kestra`

**`Login failed for user '...'` from `query_source`**
- Wrong credentials, or Azure SQL firewall blocking the Codespace's outbound IP. In Azure Portal → SQL Server → Networking, enable **"Allow Azure services and resources to access this server"** or add the Codespace IP.

**`relation "raw.sales_order_header" does not exist` from `copy_to_bronze`**
- You skipped Step 1 — run the create script.

**`CopyIn` fails with column count or type mismatch**
- The SELECT in [`flows/bronze_adventureworks.yml`](../flows/bronze_adventureworks.yml) and the CREATE TABLE in [`tutorial/sql/01_create_bronze_tables.sql`](sql/01_create_bronze_tables.sql) must agree on **column order and count**. If you tweak one, tweak the other.

**Logs for a stuck run**
- In the Kestra UI: open the execution → click a task → **Logs** subtab. Each task has its own scoped log.
- Or from the terminal: `docker logs -f --tail 100 $(docker ps --filter name=kestra -q)`.

**Re-running the flow fails with primary-key conflicts**
- The bronze tables have PKs, so `COPY` errors out on duplicates. Truncate before reload during development:
  ```bash
  psql -d analytics -c "
    TRUNCATE raw.sales_order_header, raw.sales_order_detail, raw.customer,
             raw.person, raw.sales_territory, raw.sales_person, raw.product,
             raw.product_subcategory, raw.product_category;
  "
  ```

## Next

→ [Task 2: Silver with dbt](02-silver-dbt.md)
