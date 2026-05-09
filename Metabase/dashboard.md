# Pre-built Sales Overview Dashboard

If you want the same dashboard that Tutorial 04 walks you through manually, but **without the clicking**, run this script. It builds the four questions plus the dashboard with a date-range filter via the Metabase REST API.

It's idempotent: re-run it any time and it deletes the previous "AW: …" questions + dashboard before recreating them.

## Prerequisites

1. Metabase is running (port 3000 reachable; if you're working in the Codespace, that's automatic).
2. Postgres is registered in Metabase as a data source named `analytics` (Tutorial 04 Step 1) and the schema is synced.
3. dbt has built the marts (`dbt build --target analytics`) — `marts.fact_sales`, `marts.dim_*` must exist.
4. You have a Metabase admin API key. Create one in **Admin → Settings → Authentication → API Keys**, then:
   ```bash
   export MB_API_KEY='mb_paste_your_key_here'
   ```

## Run it

```bash
cd /workspaces/dbt_codespace_demo
python Metabase/setup_dashboard.py
```

Expected output:

```
Metabase: http://metabase:3000
Database: analytics

  database id = 2, dim_date.date_actual field id = 142

Cleaning up previous run...

Creating questions...
  Q1 id=5
  Q2 id=6
  Q3 id=7
  Q4 id=8

Creating dashboard...
  dashboard id=2
  added 4 cards + date-range filter

Done. Open: http://metabase:3000/dashboard/2
```

Click the printed URL (or open Metabase, **Browse → Dashboards → AW Sales Overview**).

## What gets built

| Card | Visualization | Source |
|---|---|---|
| AW: Revenue by month | Line | `fact_sales` × `dim_date` |
| AW: Top 10 products by revenue | Row chart | `fact_sales` × `dim_product` |
| AW: Sales by region and category | Pivot table | `fact_sales` × `dim_sales_territory` × `dim_product` |
| AW: Sales people leaderboard | Table | `fact_sales` × `dim_sales_person` |

Layout: Q1 full-width on top, Q2/Q3 side-by-side in the middle, Q4 full-width at the bottom — same as Tutorial 04 Step 5.

A **Date range** dashboard filter sits at the top and is wired to all four cards via field-filter template tags. Pick a range and watch every card update.

## How it works (briefly)

The script uses the Metabase REST API:

| Endpoint | What for |
|---|---|
| `GET /api/database` | Find the `analytics` database id |
| `GET /api/database/<id>/metadata` | Find the field id for `dim_date.date_actual` (needed by the field-filter parameter) |
| `GET /api/card`, `DELETE /api/card/<id>` | Idempotent cleanup of previous run |
| `POST /api/card` | Create each Question (native SQL with a `{{date_filter}}` template tag) |
| `POST /api/dashboard` | Create the dashboard shell |
| `PUT /api/dashboard/<id>` | Add the date-range parameter |
| `PUT /api/dashboard/<id>/cards` | Bulk-add cards with parameter-mapping wiring |

The questions use **native SQL** (not the GUI / MBQL builder) because native is far easier to construct programmatically and survives Metabase upgrades better. Trade-off: drill-through (clicking a row to navigate to a dim) doesn't auto-light-up the way it does for GUI questions; that's why Tutorial 04 builds GUI questions for the manual walk-through.

## When to use the script vs. Tutorial 04

| Use the script when | Use Tutorial 04 when |
|---|---|
| You want the dashboard up in 30 seconds for a demo | You're a student learning Metabase |
| You re-spin the Codespace and need the dashboard back | You want drill-through behaviour |
| Your dbt-metabase sync has run and the metadata is curated | You're building something new and bespoke |

## Customising

If you want different SQL, different layout, more questions: this is just a Python file. Edit `Q1_SQL`, `Q2_SQL`, …, change the `cards` layout in `main()`. Re-run.

The `NAME_PREFIX = "AW: "` is what the cleanup function uses to know which old cards to delete on re-run. If you change it, also change anything you've manually saved with that prefix or it'll get nuked.

## Troubleshooting

| Symptom | Cause |
|---|---|
| `MB_API_KEY env var is not set` | Forgot the `export`. See Prerequisites. |
| `Metabase database 'analytics' not found` | Either the DB isn't registered, or the display name is something else (e.g. "Postgres"). Set `METABASE_DATABASE=Postgres` env var or rename in Metabase Admin. |
| `Field dim_date.date_actual not found` | Metabase hasn't synced the marts yet. Hit **Admin → Databases → analytics → Sync database schema now**, wait 30 s, retry. |
| `Connection refused` on http://metabase:3000 | You're running outside the Codespace. Set `METABASE_URL=http://localhost:3000`. |
| HTTP 401 / 403 | API key is wrong, expired, or not Admin-group scoped. |
| Dashboard renders but cards say "No results" | The `{{date_filter}}` field-filter parameter has no default — that's fine, but if you set a range that excludes all data you'll see nothing. Clear the filter to verify. |
| Dashboard renders, "AW: Revenue by month" shows zero | dbt build hasn't run yet, or hasn't been pointed at `analytics`. Run `dbt build --target analytics`. |
