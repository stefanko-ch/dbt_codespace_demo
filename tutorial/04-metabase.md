# Task 4 — Analyze in Metabase

**Goal:** plug Metabase into the `analytics` warehouse and build a small Sales dashboard from the star schema you just created.

By the end you'll have:
- The `analytics` Postgres added as a Metabase data source
- The `marts` schema modeled (descriptions, primary keys, FK relationships)
- Four questions answered from the data
- A dashboard combining them

## Step 1 — Open Metabase and create the admin account

Open port **3000** from the Codespace's Ports panel. On first launch Metabase walks you through:
1. Language → English
2. Admin profile → use any name and email; pick a password you'll remember
3. Add data later → **I'll add my data later**

Metabase's own data (questions, dashboards, users) is persisted in the `metabase` Postgres DB — it survives container restarts.

## Step 2 — Connect to the analytics warehouse

**Settings (gear icon) → Admin Settings → Databases → Add database:**

| Field            | Value                |
| ---------------- | -------------------- |
| Database type    | PostgreSQL           |
| Display name     | `analytics`          |
| Host             | `postgres`           |
| Port             | `5432`               |
| Database name    | `analytics`          |
| Username         | `postgres`           |
| Password         | `postgres`           |
| Schemas          | `marts,staging`      |
| Use a secure connection (SSL) | off    |

Save. Metabase will sync — wait for the "Done" indicator (~30 seconds).

> Tip: limiting **Schemas** to `marts,staging` keeps Metabase from scanning Kestra's internal tables.

## Step 3 — Curate the model (one-time setup)

Metabase needs a few hints to make the star schema usable for non-technical users.

**Admin Settings → Table Metadata → analytics:**

For `marts.fact_sales`:
- Table description: "One row per order line item. Use to count sales, qty, and revenue."
- Hide degenerate columns from regular users: `sales_order_id`, `sales_order_detail_id` → set to "Only in detail views"
- For each `*_key` column, set **Foreign key** target:
  - `customer_key` → `dim_customer.customer_key`
  - `product_key` → `dim_product.product_key`
  - `territory_key` → `dim_sales_territory.territory_key`
  - `sales_person_key` → `dim_sales_person.sales_person_key`
  - `date_key` → `dim_date.date_key`

For each `dim_*`:
- Set the `*_key` column type to **Entity Key**
- Add a short description

This unlocks Metabase's auto-joins and "Drill through" UX.

## Step 4 — Build four questions

Use the GUI query builder (**+ New → Question**). All questions start from `Sales > Fact Sales`.

### Q1: Revenue by month

- Summarize → **Sum of** `net_amount`
- Group by → `Date → Order Date` (joined via `date_key → dim_date.date_actual`) → bucket by **Month**
- Visualization → **Line chart**
- Save as: `Revenue by month`

### Q2: Top 10 products by revenue

- Summarize → Sum of `net_amount` AND Count of rows
- Group by → `Product → Product Name`
- Sort → Sum of `net_amount` desc, limit 10
- Visualization → **Row chart**
- Save as: `Top 10 products by revenue`

### Q3: Sales by territory and category

- Summarize → Sum of `net_amount`
- Group by → `Territory → Region Group` AND `Product → Category Name`
- Visualization → **Pivot table**
- Save as: `Sales by region and category`

### Q4: Top sales people

- Filter → `Sales Person → Sales Person Name` is not empty (excludes online orders)
- Summarize → Sum of `net_amount`, Count of rows, Distinct count of `customer_key`
- Group by → `Sales Person → Sales Person Name`
- Sort → Sum of `net_amount` desc
- Visualization → **Table**
- Save as: `Sales people leaderboard`

## Step 5 — Build the dashboard

**+ New → Dashboard** → name it `Sales Overview`.

Add the four questions:
- Top row: Q1 (full width)
- Middle row: Q2 (left half) and Q3 (right half)
- Bottom row: Q4 (full width)

Add a **dashboard filter** → "Date range" → wire it to the `Order Date` column on Q1, Q2, Q3, Q4.

Save and pin to your collection.

## Acceptance check

You can:
- Pick a date range in the dashboard filter and watch all four cards update
- Click a bar in Q2 and drill through to the underlying line items in `fact_sales`
- Click a sales person name in Q4 and see all their orders

## Hints

- **Numbers wrong?** Check `dbt run --target analytics` last completed successfully. Metabase caches metadata for ~1 hour; force a refresh with **Sync database now** in the database settings.
- **Joins not happening automatically?** Re-check that you set foreign keys on all `*_key` columns in fact_sales (Step 3).
- **Need a custom metric Metabase doesn't expose?** Define it in dbt as a new mart column rather than as a SQL question. The metric becomes available everywhere and is testable.

## Done!

You've walked the full path: source system → bronze (Kestra) → silver/gold (dbt) → BI (Metabase). The pattern scales: add another source by creating a new flow plus `raw.*` tables, write `stg_*` models on top, extend the star schema with new dimensions or facts, and dashboards consume them automatically.

→ Back to [Tutorial overview](README.md)
