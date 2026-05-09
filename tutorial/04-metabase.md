# Task 4 — BI: Connect Metabase and Model the Star Schema

**Goal:** wire Metabase to the `analytics` warehouse, then **manually** curate the marts so a non-technical user can browse them — adding descriptions, marking primary and foreign keys, picking semantic types. By the end you'll have a queryable, click-to-drill-through model that Tutorial 5 will then show you how to automate.

> ## Prerequisite — get comfortable with Metabase first
>
> This task assumes you already know your way around Metabase: Questions vs Dashboards, the query builder, summarisation, filters. If those are new, **stop here** and work through [`Metabase/README.md`](../../Metabase/README.md) first — it walks you through logging in, the official [Metabase Learn](https://www.metabase.com/learn/) tutorial (~30 min), and the concepts you'll need below.
>
> Don't skip this. The clicking in Step 3 doesn't make sense without first seeing what those settings *do* in the GUI.

Plan to spend ~1 hour on this task.

## Why we model manually first

Tutorial 5 introduces `dbt-metabase`, a CLI tool that takes everything you'll click through in Step 3 and applies it from your dbt YAML files automatically. So why do the manual version at all?

- **You learn what the settings actually mean.** "Foreign Key", "Entity Key", "Semantic Type — currency" — these are real Metabase concepts, not just YAML knobs. Once you've curated five tables by hand, the automation tool's flags make sense; you know what each one is replacing.
- **You can debug from first principles.** When the automated sync misses something, you know whether the issue is on the Metabase side, the dbt side, or the bridge. Skip the manual step and you can't tell.
- **Day-to-day BI work involves manual curation anyway.** Not every column or table is worth describing in dbt. For one-off questions, ad-hoc segments, dashboard-specific renamings, you'll always click in Metabase. Tutorial 5 augments this skill, it doesn't replace it.

## Step 1 — Connect to the analytics warehouse

You should already be logged into Metabase from the [Metabase intro](../../Metabase/README.md). Now add Postgres as a data source:

**Settings (gear icon) → Admin Settings → Databases → Add database:**

| Field            | Value             |
| ---------------- | ----------------- |
| Database type    | PostgreSQL        |
| Display name     | `analytics`       |
| Host             | `postgres`        |
| Port             | `5432`            |
| Database name    | `analytics`       |
| Username         | `postgres`        |
| Password         | `postgres`        |
| Schemas          | `marts`           |
| Use a secure connection (SSL) | off  |

Save. Metabase syncs the schema (~30 seconds). Wait for the **"Done"** indicator before continuing.

> **Why only `marts`?** Staging is a dbt-internal layer — `stg_aw__sales_order_header` is intermediate, not BI material. Showing it to end users alongside `fact_sales` invites accidental queries against intermediate state. We deliberately scope Metabase to the gold layer only.

> **Display name matters.** Tutorial 5 will reference this database by the display name you typed (`analytics`). If you took the default ("Postgres"), you'll need to either rename it later or pass `--metabase-database Postgres` to the sync tool. Pick `analytics` now and skip the friction.

### Quick sanity check

In Metabase: **Browse data → analytics → marts**. You should see eight tables:

```
book_popularity      ← from the library warm-up; ignore for this task
dim_customer
dim_date
dim_product
dim_sales_person
dim_sales_territory
fact_sales
member_activity      ← from the library warm-up; ignore for this task
```

Click `fact_sales`. You'll get a generic table view with raw column names like `customer_key`, `product_id`, `unit_price`. No descriptions, no relationships, no idea which columns are keys. That's what Step 3 fixes.

If you click a value in `customer_key` (an MD5 hash like `f5e3a...`), nothing useful happens. By the end of Step 3, clicking that same value will offer "View this customer", drill through to the matching `dim_customer` row, because the foreign-key relationship will be set.

## Step 2 — Curate the dimensions

We model dimensions before the fact for the same reason dbt builds them in that order: the fact's foreign keys point *at* dimensions, so the dim rows need to be there first (they already are, from `dbt build`), but in Metabase the FK target dropdown only shows tables that have been marked with an Entity Key.

For each dimension, we'll do three things in **Admin → Table Metadata → analytics → marts → `<table>`**:

1. **Table-level description** — what does this dim represent?
2. **Entity Key** on the natural key column (`customer_id`, `product_id`, etc.) — the column that uniquely identifies a row.
3. **Hidden flags** — hide rarely-useful columns (e.g. `rowguid` if it had survived) from regular users.
4. **Per-column descriptions** for the columns that aren't self-explanatory.

> The natural key (`customer_id`) is the Entity Key in Metabase, **not** the surrogate `customer_key`. Why? Because Entity Key in Metabase semantically means "the unique business identifier of this entity", and our `*_key` columns are MD5 hashes — useful for fact joins but not human-friendly. If a user clicks "View this entity", they want to see customer 17, not hash `f5e3a...`.

### `dim_date`

- **Description:** *"Calendar dimension. One row per day from 2010-01-01 through 2030-12-31. Use the pre-computed parts (year, quarter, month, day_name, is_weekend) instead of EXTRACT() in your questions."*
- **Entity Key:** `date_actual`
- **Field types to set:**
  - `date_actual` → Type: **Creation date** (so Metabase treats it as the canonical date for joins via auto-discovered relationships)
  - `is_weekend`, `is_quarter_start`, `is_month_end` → Hide from "Filtering on this field" (just hide; they're flags for Group By, not filters)
- **Hide:** `date_key` from "Regular tables" — it's the surrogate hash, only used internally for joins. Set Visibility: **Only in detail views**.

### `dim_customer`

- **Description:** *"One row per customer. Mixes individuals (with a name from `dim_person`) and stores (no name, identified by `store_id`). Use `customer_type` to distinguish."*
- **Entity Key:** `customer_id`
- **Per-column descriptions:**
  - `customer_type` → *"'individual', 'store', or 'unknown'."*
  - `customer_name` → *"Full name for individuals; NULL for stores (which are identified by store_id)."*
  - `email_promotion` → *"AdventureWorks email-marketing opt-in flag (0/1/2)."*
- **Hide:** `customer_key`, `store_id` (rarely queried), set both to "Only in detail views".

### `dim_product`

- **Description:** *"One row per product. The product → subcategory → category hierarchy is denormalized — `subcategory_name` and `category_name` are right here on the dim, no JOIN needed."*
- **Entity Key:** `product_id`
- **Per-column descriptions:**
  - `is_active` → *"Product is currently being sold (sell_end_date and discontinued_date are both NULL)."*
  - `list_price` → *"Standard list price in USD."*
  - `standard_cost` → *"Standard cost in USD; for margin calculations."*
- **Field types:**
  - `list_price` → Type: **Currency**
  - `standard_cost` → Type: **Currency**
  - `weight` → Type: **No semantic type** (it's a number; AdventureWorks doesn't tell us the unit)
- **Hide:** `product_key`, `product_subcategory_id`, `product_category_id` → Only in detail views.

### `dim_sales_territory`

- **Description:** *"One row per sales territory (10 total). Group by `region_group` for continent-level totals."*
- **Entity Key:** `territory_id`
- **Per-column descriptions:**
  - `region_group` → *"'North America', 'Europe', or 'Pacific'."*
- **Field types:**
  - `sales_ytd`, `sales_last_year`, `cost_ytd`, `cost_last_year` → Type: **Currency**
- **Hide:** `territory_key` → Only in detail views.

### `dim_sales_person`

- **Description:** *"One row per internal sales rep (17 total). Online orders have NO salesperson — filter for `sales_person_name is not empty` to exclude them in Q4 leaderboards."*
- **Entity Key:** `sales_person_id`
- **Per-column descriptions:**
  - `commission_pct` → *"Commission as a fraction (0-1, not percent)."*
  - `sales_quota` → *"Annual quota in USD; NULL means no quota set."*
- **Field types:**
  - `sales_quota`, `bonus`, `sales_ytd`, `sales_last_year` → Type: **Currency**
- **Hide:** `sales_person_key` → Only in detail views.

## Step 3 — Curate the fact

`fact_sales` is where the wiring matters most. The five `*_key` columns need to be set as **Foreign Key** with explicit targets — that's what unlocks Metabase's auto-joins and drill-through.

**Admin → Table Metadata → analytics → marts → fact_sales:**

### Table description

> *"One row per order line item (~121k rows). Five surrogate FKs link to the dimensions; degenerate dims (`sales_order_id`, `order_status`, `is_online`) live on the fact for direct filtering. Every measure is additive at the line-item grain."*

### Foreign-key wiring

This is the heart of Step 3. For each `*_key` column:

| Column on `fact_sales` | Field type        | Foreign-key target              |
| ---------------------- | ----------------- | ------------------------------- |
| `customer_key`         | **Foreign key**   | `dim_customer.customer_key`     |
| `product_key`          | **Foreign key**   | `dim_product.product_key`       |
| `territory_key`        | **Foreign key**   | `dim_sales_territory.territory_key` |
| `sales_person_key`     | **Foreign key**   | `dim_sales_person.sales_person_key` |
| `date_key`             | **Foreign key**   | `dim_date.date_key`             |

For each: click the column → **"Type"** dropdown → select **Foreign key** → in the new dropdown that appears, pick the target column.

> **Why target the surrogate `*_key` and not the natural `*_id`?** Two reasons. First, the surrogate is what's actually populated in the fact (the natural ID isn't there as a separate column for most dims). Second, the surrogate is the cleanest single-column join — what dbt designed it for.

### Field types for measures

| Column           | Type      |
| ---------------- | --------- |
| `unit_price`     | Currency  |
| `unit_price_discount` | Percentage |
| `line_total`     | Currency  |
| `gross_amount`   | Currency  |
| `discount_amount` | Currency |
| `net_amount`     | Currency  |
| `order_qty`      | Quantity  |

### Hide internal-use columns

These show up in the "View detail" pop-out but shouldn't clutter the Browse Data UI:

- `sales_order_id`, `sales_order_detail_id` → Visibility: **Only in detail views** (degenerate dims, not for Group By)
- All five `*_key` columns → leave **visible** despite the hash, because they're necessary for FK navigation in advanced questions. (You could hide them — opinions differ.)

### Per-column descriptions

Add at minimum:

- `order_status` → *"Decoded from `Sales.SalesOrderHeader.Status`. Values: 'in process', 'approved', 'backordered', 'rejected', 'shipped', 'cancelled'."*
- `is_online` → *"True for online orders (no salesperson). False for orders placed through a sales rep."*
- `net_amount` → *"`line_total` from the source — the standard revenue measure for sums."*
- `unit_price_discount` → *"Discount as a fraction (0-1)."*

## Step 4 — Verify the wiring

Build a quick question to make sure the foreign keys do what they should.

**+ New → Question → Sales > Fact Sales:**

- Summarize → **Sum of** `net_amount`
- Group by → **Customer → Customer Type** (you can navigate the joined dimension because the FK is set)
- Visualization → Bar chart
- Save as `Revenue by customer type` (in your collection)

If the **Customer** option doesn't appear in the Group By picker, the `customer_key` foreign-key target wasn't set correctly — go back to Step 3.

Click any bar in the chart. You should get **"View these Fact Sales"** + **"Break out by …"** options, and crucially **"View this Customer"** which drills through to the dim's row. That drill-through is the payoff for the FK wiring.

## Step 5 — Build a four-question dashboard

All questions start from `Sales > Fact Sales`.

### Q1: Revenue by month

- Summarize → **Sum of** `net_amount`
- Group by → `Date → Order Date` (joined via `date_key → dim_date.date_actual`) → bucket by **Month**
- Visualization → **Line chart**
- Save as `Revenue by month`.

### Q2: Top 10 products by revenue

- Summarize → Sum of `net_amount` AND Count of rows
- Group by → `Product → Product Name`
- Sort → Sum of `net_amount` desc, limit 10
- Visualization → **Row chart**
- Save as `Top 10 products by revenue`.

### Q3: Sales by territory and category

- Summarize → Sum of `net_amount`
- Group by → `Territory → Region Group` AND `Product → Category Name`
- Visualization → **Pivot table**
- Save as `Sales by region and category`.

### Q4: Top sales people

- Filter → `Sales Person → Sales Person Name` is not empty (excludes online orders)
- Summarize → Sum of `net_amount`, Count of rows, Distinct count of `customer_key`
- Group by → `Sales Person → Sales Person Name`
- Sort → Sum of `net_amount` desc
- Visualization → **Table**
- Save as `Sales people leaderboard`.

### Wire them into a dashboard

**+ New → Dashboard** → name `Sales Overview`.

Layout:
- Top row: Q1 (full width)
- Middle row: Q2 (left half) and Q3 (right half)
- Bottom row: Q4 (full width)

Add a **dashboard filter → Date range** → wire it to `Order Date` on Q1, Q2, Q3, Q4.

Save and pin.

## Acceptance check

You can:
- Pick a date range in the dashboard filter and watch all four cards update in sync
- Click a bar in Q2 and drill through to the underlying line items
- Click a sales person name in Q4 and see all their orders (the dim navigation works because of the FK)
- Hover any column header in `fact_sales` and see the description you set in Step 3

## What you just built — and why this is fragile

You now have a fully-curated semantic layer in Metabase. Schemas, descriptions, FK relationships, semantic types — all set, all working.

But: **none of this lives in version control.** It's stored in Metabase's own `metabase` Postgres database. If you delete the Codespace, all of it goes with the volume. If a colleague spins up their own Codespace, they start from a blank Metabase.

Worse: **it can drift from dbt.** You add a new column to `fact_sales` in dbt with `description: "..."` in YAML — Metabase doesn't know. You rename `unit_price_discount` to `discount_pct` in dbt — Metabase keeps the old name as the description.

This is exactly what Tutorial 5 fixes.

## Next

→ [Tutorial 5: Sync dbt → Metabase automatically](05-dbt-metabase-sync.md)

The next tutorial replaces 80% of the clicking you just did with one CLI command, driven by your dbt YAML files. The patterns you learned here will help you understand exactly what gets synced and how to debug it.

## Common issues

| Symptom | Likely cause |
| ------- | ------------ |
| Foreign-key dropdown is empty / doesn't list the dim | The dim's `customer_id` (or equivalent) isn't marked as **Entity Key**. Step 2 must complete before Step 3 wires up the fact. |
| Foreign-key target column dropdown shows hash columns only | The dim's natural-key column isn't marked **Entity Key**; only Entity-Keyed columns can be FK targets. |
| Drill-through "View this Customer" missing on a bar chart | The relevant FK on `fact_sales` either isn't set, or points at the wrong target. Re-check `customer_key → dim_customer.customer_key`. |
| Revenue numbers look wrong by ~10x | Unit confusion — `unit_price_discount` is a fraction (0.1 = 10%), set its type to **Percentage** so Metabase formats it. |
| Dashboard filter doesn't update one of the cards | Dashboard filters need explicit wiring per card to a date column. Edit the dashboard, click the filter pill, click each card in turn, pick `Order Date` for all four. |

## Hints

- `Admin → Audit` (Pro / EE feature only) shows who clicked what; in the OSS version you don't have this, so consider noting big curation changes in a `CHANGELOG.md` somewhere.
- The "X-Ray" feature on a dim (e.g. `dim_customer`) auto-generates an exploratory dashboard — useful for sanity-checking that your FK wiring works end-to-end.
- Click "**Sync database now**" in Admin → Databases after a `dbt build` to refresh Metabase's view of new columns or renamed tables.
- Save curation work in chunks: it's easy to lose half an hour of clicking if you accidentally close a tab during config.
