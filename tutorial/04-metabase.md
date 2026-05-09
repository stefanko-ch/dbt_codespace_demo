# Task 4 — Analyze in Metabase

**Goal:** plug Metabase into the `analytics` warehouse and build a small Sales dashboard from the star schema you just created — and see what makes a *dbt-driven* BI setup different from a plain one.

By the end you'll have:
- The `analytics` Postgres added as a Metabase data source
- The marts schema **modeled automatically from your dbt project** — descriptions, primary keys, foreign-key relationships, semantic types, all synced via `dbt-metabase` (no clicking through admin screens)
- Four questions answered from the data
- A dashboard combining them

> ## First time using Metabase?
> This task assumes you already know what Metabase **is** and how its UI is roughly organised — Questions, Dashboards, Collections. If those terms are new, spend ~30 min in the official, free [**Metabase Learn**](https://www.metabase.com/learn/metabase-basics/getting-started/) tutorials before continuing. They cover concepts, the query builder, dashboards, filters, and summarisation — exactly the basics this task builds on.
>
> The *interesting* part of this task isn't "how does Metabase work" — it's how dbt and Metabase reinforce each other when you stop treating them as separate tools.

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

At this point Metabase has discovered your tables — but it knows nothing about them. No descriptions, no relationships, no idea which columns are primary keys. If you click **Browse data → analytics → marts → fact_sales**, you'll see raw column names with no structure on top.

A traditional Metabase setup would now have you clicking through **Admin → Table Metadata** for every table, manually setting:
- A description per table and column
- "Entity Key" markers on `*_key` columns
- "Foreign Key" targets pointing each `fact_sales.*_key` to its dim
- Semantic types for emails, currencies, URLs

That's ~80 clicks for our six marts. **And** it has to be redone whenever the schema changes.

We can do better.

## Step 3 — Sync the dbt model into Metabase with `dbt-metabase`

[`dbt-metabase`](https://github.com/gouline/dbt-metabase) is an actively maintained Python tool (v1.7.x as of 2026) that reads your dbt project's manifest and propagates everything Metabase needs to know about your tables — directly from your `*.yml` files.

What gets synced from dbt → Metabase:

| dbt source                                  | Metabase result                            |
| ------------------------------------------- | ------------------------------------------ |
| `description:` on a model or column          | Metabase table / column description         |
| `tests: [unique, not_null]` on a key column  | "Entity Key" marker                         |
| `tests: relationships:`                     | "Foreign Key" target on the column         |
| Column-name conventions (`*_email`, `*_url`, `..._id`) | Inferred semantic types                    |
| `meta:` blocks in YAML (custom)             | Display names, hidden flags, semantic types |

### 3.1 — Create a Metabase API key

In Metabase: **Admin → Settings → Authentication → API Keys → Create API key**.

- Name: `dbt-metabase`
- Group: **Administrators** (the sync needs admin scope to write metadata)

Copy the resulting `mb_...` token to your clipboard. Treat it like a password — it grants full admin access. Store it as an environment variable rather than pasting it on the command line:

```bash
export MB_API_KEY='mb_paste_your_key_here'
```

### 3.2 — Compile the dbt manifest

`dbt-metabase` reads `target/manifest.json`, which is regenerated every time you run any dbt command. To produce one without re-running models:

```bash
cd dbt
dbt compile --target analytics
```

The manifest now lives at `dbt/target/manifest.json` and contains every model, column, description, test, and tag in your project.

### 3.3 — Run the sync

```bash
dbt-metabase models \
  --manifest-path target/manifest.json \
  --metabase-url http://localhost:3000 \
  --metabase-api-key "$MB_API_KEY" \
  --metabase-database analytics \
  --include-schemas marts staging
```

Expected output: a list of synced models with the count of fields updated per model. ~5 seconds total.

Now refresh Metabase (**Browse data → analytics → marts → fact_sales**) and look at the column list. Compare with the "before" state:

- `customer_key`, `product_key`, `date_key`, `territory_key`, `sales_person_key` are now marked as **Foreign Key** with the right target dim auto-set.
- The natural-key columns on each dim (`customer_id`, `product_id`, …) are marked as **Entity Key**.
- Every column you described in [`_adventureworks_marts__models.yml`](../dbt/models/marts/adventureworks/_adventureworks_marts__models.yml) carries that description in Metabase's UI as a tooltip.

### 3.4 — Verify with a question

Click **+ New → Question → Sales > Fact Sales**. Try **Summarize → Sum of `net_amount` → Group by `Customer → Customer Type`**. Notice:

- You can navigate `Customer → ...` because the FK is set.
- The drill-down options for each row include "View customer" and "View underlying records" because Metabase now knows the relationships.

That single CLI call replaced ~80 clicks. More importantly: your dbt YAML is now the **single source of truth** for the semantic layer. When you add a column description in dbt, re-run `dbt compile && dbt-metabase models ...` and Metabase picks it up. No drift between the warehouse and the BI tool.

> **Round-trip exercise:** add `description: "..."` to one of the columns in [`_adventureworks_marts__models.yml`](../dbt/models/marts/adventureworks/_adventureworks_marts__models.yml), re-run the sync, and watch the description appear as a tooltip in Metabase.

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
- Hover a column in any table view and see the description that came from your dbt YAML

## Why this matters — the dbt-driven BI loop

The pattern you just set up has three properties that hand-curated Metabase setups don't:

1. **Single source of truth.** Descriptions, semantic types, and FK relationships live in `dbt/models/**/*.yml`, version-controlled, code-reviewed, and tested. Metabase becomes a *projection* of that.
2. **Repeatable.** A new joiner runs `dbt-metabase models ...` once and gets a fully-curated Metabase. No tribal knowledge ("ask Sarah how to set up Metabase").
3. **Drift-resistant.** When the schema changes in dbt, Metabase is one CLI call away from being current. There's no "the description in Metabase is wrong because someone changed the column upstream and forgot to update the BI tool."

This is what gives the dbt + Metabase combination a different shape than e.g. dbt + Looker (where LookML is the semantic layer) or dbt + Tableau (where you'd hand-curate the data source).

## Hints

- **Numbers wrong?** Check `dbt run --target analytics` last completed successfully. Metabase caches metadata for ~1 hour; force a refresh with **Sync database now** in the database settings.
- **`dbt-metabase` says "model not found"?** Either your `--include-schemas` is wrong, or you forgot `dbt compile` after a model rename. The tool can only see what's in `manifest.json`.
- **API key expired?** They don't expire in OSS Metabase, but if the user that created the key is deactivated, the key dies. Recreate it under a service-account user if this matters in production.
- **Need a custom metric Metabase doesn't expose?** Define it in dbt as a new mart column rather than as a SQL question. Then `dbt-metabase` propagates the description and it becomes available everywhere — testable, documented, single source of truth.
- **Want to push descriptions but not FKs?** `dbt-metabase models --help` lists per-section flags like `--metabase-fk-columns-only` and `--metabase-exclude-sources`.

## Common issues

| Symptom | Likely cause |
| ------- | ------------ |
| `dbt-metabase` exits 0 but Metabase still shows no descriptions | Metabase's metadata sync is async — wait 30 seconds and refresh, or hit "Sync database now" |
| FK targets are set but drill-through doesn't work | The dim hasn't been synced yet — make sure the dim's `--include-schemas` covers it (we use `marts staging`) |
| `Authentication failed (401)` | Wrong / expired `mb_...` key, or you used a session token instead of an API key |
| Sync runs forever / timeouts | The Metabase DB sync is still in progress from Step 2; wait for the "Done" indicator before running `dbt-metabase` |

## Done!

You've walked the full path: source system → bronze (Kestra) → silver/gold (dbt) → BI (Metabase) — with **dbt as the semantic layer** end to end.

→ Back to [Tutorial overview](README.md)
