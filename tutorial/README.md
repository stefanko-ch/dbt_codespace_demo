# Tutorial — From AdventureWorks to a Star Schema

End-to-end workshop: take the **AdventureWorks** sample database on Azure SQL, ingest it into Postgres with **Kestra**, and build a **dimensional model** with **dbt**.

You'll work through three tasks. Each task is a self-contained markdown with goal, steps, and an acceptance check.

> The BI layer (Metabase) follows in a separate session and isn't part of the current stack.

## What you'll build

<p align="center">
  <img src="../assets/pipeline.svg" alt="Pipeline diagram: Azure SQL → Kestra → Postgres raw → dbt → staging/marts" width="100%">
</p>

The `analytics` Postgres database receives all production data. Schemas inside it follow the medallion convention:

| Schema     | Layer  | Owned by | What lives here                                  |
| ---------- | ------ | -------- | ------------------------------------------------ |
| `raw`      | Bronze | Kestra   | Raw 1:1 copies of source tables                  |
| `staging`  | Silver | dbt      | Cleaned, typed, renamed views                    |
| `marts`    | Gold   | dbt      | Star schema: `fact_sales` + `dim_*` (tables)     |

The `playground` database is left alone for the dbt warm-up (`dbt seed && dbt run` against the library example) — it never sees AdventureWorks data.

## Tasks

| # | Task                                                            | Tool        |
| - | --------------------------------------------------------------- | ----------- |
| 1 | [Bronze: ingest AdventureWorks with Kestra](01-bronze-kestra.md) | Kestra      |
| 2 | [Silver: clean staging models](02-silver-dbt.md)                | dbt         |
| 3 | [Gold: dimensional model](03-gold-dimensional-model.md)         | dbt         |

## Ports in the Codespace

The Codespace forwards two ports — find them in the **Ports** panel at the bottom of VS Code, or under "Forwarded Addresses" in the Codespaces UI.

| Port  | What it is    | How to open                                                                       |
| ----- | ------------- | --------------------------------------------------------------------------------- |
| 8080  | **Kestra** UI | Click the globe icon next to port 8080 (auto-opens as a preview on first start)   |
| 5432  | **Postgres**  | Not for the browser — used by dbt, SQLTools, `psql`                               |

> The forwarded URL looks like `https://<codespace-name>-8080.app.github.dev` — that's normal. Each port gets its own subdomain.

## Before you start

1. Codespace is up and running (see [main README](../README.md))
2. You have credentials to the Azure SQL AdventureWorks database. They are entered into the Kestra flow at execution time (or pre-filled as defaults in the flow) — no Codespace secrets required.
3. The dbt warm-up runs successfully:
   ```bash
   cd dbt
   dbt seed && dbt run && dbt test
   ```
   This proves your Postgres connection, dbt installation, and venv are healthy. If anything fails here, fix it before moving on — the rest of the tutorial assumes a working stack.

## Conventions used in this tutorial

- All bronze table names are **snake_case** of the source table (`Sales.SalesOrderHeader` → `sales_order_header`). The schema prefix from SQL Server is dropped because we land everything in `raw`.
- All target dbt models live under the `dbt_codespace_demo` project, target `analytics`.
- Run dbt from the `dbt/` directory unless stated otherwise.
- Code blocks are copy-paste ready unless they contain a `<placeholder>`.
