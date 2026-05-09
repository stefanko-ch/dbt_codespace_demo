#!/usr/bin/env python3
"""
Builds the Sales Overview dashboard in Metabase from scratch via the REST API.

Idempotent: deletes any existing 'AW: ...' questions and 'AW Sales Overview'
dashboard before creating fresh ones, so you can re-run this safely after
changing the SQL or layout.

Prerequisites:
  - Metabase running (docker compose up; port 3000 reachable)
  - The `analytics` Postgres registered in Metabase as a data source
    with display name 'analytics' (Tutorial 04 Step 1)
  - dbt build --target analytics has run, so marts.* exists
  - MB_API_KEY env var set to a Metabase admin API key
    (Admin -> Settings -> Authentication -> API Keys)

Usage:
  cd /workspaces/dbt_codespace_demo
  export MB_API_KEY='mb_...'
  python Metabase/setup_dashboard.py

Run again to refresh after editing this file.
"""

import os
import sys
import time

import requests

BASE_URL = os.environ.get("METABASE_URL", "http://metabase:3000")
DB_NAME = os.environ.get("METABASE_DATABASE", "analytics")
API_KEY = os.environ.get("MB_API_KEY")

if not API_KEY:
    sys.exit("MB_API_KEY env var is not set. See script docstring for setup.")

session = requests.Session()
session.headers["x-api-key"] = API_KEY


# ---------------------------------------------------------------------------
# Lookups
# ---------------------------------------------------------------------------

def get_database_id() -> int:
    r = session.get(f"{BASE_URL}/api/database")
    r.raise_for_status()
    for db in r.json()["data"]:
        if db["name"] == DB_NAME:
            return db["id"]
    sys.exit(
        f"Metabase database '{DB_NAME}' not found. Add Postgres in "
        f"Admin -> Databases with display name '{DB_NAME}', or set "
        f"METABASE_DATABASE env var."
    )


def find_field_id(db_id: int, table_name: str, field_name: str) -> int:
    """Look up a field id by table + column name; needed for date-filter wiring."""
    r = session.get(f"{BASE_URL}/api/database/{db_id}/metadata")
    r.raise_for_status()
    for tbl in r.json()["tables"]:
        if tbl["name"] == table_name:
            for fld in tbl["fields"]:
                if fld["name"] == field_name:
                    return fld["id"]
    sys.exit(f"Field {table_name}.{field_name} not found. Has Metabase synced the marts schema?")


# ---------------------------------------------------------------------------
# Cleanup of previous runs
# ---------------------------------------------------------------------------

NAME_PREFIX = "AW: "
DASHBOARD_NAME = "AW Sales Overview"


def cleanup() -> None:
    r = session.get(f"{BASE_URL}/api/card")
    r.raise_for_status()
    for card in r.json():
        if card["name"].startswith(NAME_PREFIX):
            session.delete(f"{BASE_URL}/api/card/{card['id']}")
            print(f"  removed old card: {card['name']}")

    r = session.get(f"{BASE_URL}/api/dashboard")
    r.raise_for_status()
    for d in r.json():
        if d["name"] == DASHBOARD_NAME:
            session.delete(f"{BASE_URL}/api/dashboard/{d['id']}")
            print(f"  removed old dashboard: {d['name']}")


# ---------------------------------------------------------------------------
# Card / dashboard helpers
# ---------------------------------------------------------------------------

def create_native_card(
    name: str,
    sql: str,
    db_id: int,
    display: str = "table",
    visualization_settings: dict | None = None,
    template_tags: dict | None = None,
) -> int:
    payload = {
        "name": name,
        "dataset_query": {
            "type": "native",
            "database": db_id,
            "native": {
                "query": sql,
                "template-tags": template_tags or {},
            },
        },
        "display": display,
        "visualization_settings": visualization_settings or {},
    }
    r = session.post(f"{BASE_URL}/api/card", json=payload)
    r.raise_for_status()
    return r.json()["id"]


def date_filter_template_tag(field_id: int) -> dict:
    """Field-filter template tag bound to a single date-typed column."""
    return {
        "date_filter": {
            "id": "date_filter",
            "name": "date_filter",
            "display-name": "Date filter",
            "type": "dimension",
            "dimension": ["field", field_id, None],
            "widget-type": "date/range",
            "required": False,
        }
    }


def create_dashboard(name: str) -> int:
    r = session.post(f"{BASE_URL}/api/dashboard", json={"name": name})
    r.raise_for_status()
    return r.json()["id"]


def set_dashboard_cards_and_filter(
    dashboard_id: int,
    cards: list[dict],
    parameter_id: str,
) -> None:
    """Attach all cards + the date parameter to the dashboard in one call.

    `cards` is a list of dicts: {card_id, row, col, size_x, size_y}. Each card
    is auto-wired to the date parameter via its `date_filter` template tag.
    """
    # Define the dashboard parameter
    session.put(
        f"{BASE_URL}/api/dashboard/{dashboard_id}",
        json={
            "parameters": [
                {
                    "id": parameter_id,
                    "name": "Date range",
                    "slug": "date_range",
                    "type": "date/range",
                    "sectionId": "date",
                }
            ]
        },
    ).raise_for_status()

    # Bulk-add the cards with parameter mappings
    payload = {
        "cards": [
            {
                "id": -(i + 1),  # negative ids = new cards in the bulk-update API
                "card_id": c["card_id"],
                "row": c["row"],
                "col": c["col"],
                "size_x": c["size_x"],
                "size_y": c["size_y"],
                "parameter_mappings": [
                    {
                        "parameter_id": parameter_id,
                        "card_id": c["card_id"],
                        "target": ["dimension", ["template-tag", "date_filter"]],
                    }
                ],
                "visualization_settings": {},
            }
            for i, c in enumerate(cards)
        ]
    }
    r = session.put(f"{BASE_URL}/api/dashboard/{dashboard_id}/cards", json=payload)
    r.raise_for_status()


# ---------------------------------------------------------------------------
# The four questions
# ---------------------------------------------------------------------------

Q1_SQL = """
SELECT date_trunc('month', d.date_actual)::date AS month,
       sum(f.net_amount)                       AS revenue
FROM   marts.fact_sales       f
JOIN   marts.dim_date         d ON f.date_key = d.date_key
WHERE  {{date_filter}}
GROUP  BY 1
ORDER  BY 1
""".strip()

Q2_SQL = """
SELECT p.product_name,
       sum(f.net_amount) AS revenue,
       count(*)          AS line_items
FROM   marts.fact_sales f
JOIN   marts.dim_product   p ON f.product_key = p.product_key
JOIN   marts.dim_date      d ON f.date_key    = d.date_key
WHERE  {{date_filter}}
GROUP  BY p.product_name
ORDER  BY revenue DESC
LIMIT  10
""".strip()

Q3_SQL = """
SELECT t.region_group,
       p.category_name,
       sum(f.net_amount) AS revenue
FROM   marts.fact_sales         f
JOIN   marts.dim_sales_territory t ON f.territory_key = t.territory_key
JOIN   marts.dim_product         p ON f.product_key   = p.product_key
JOIN   marts.dim_date            d ON f.date_key      = d.date_key
WHERE  {{date_filter}}
GROUP  BY 1, 2
ORDER  BY 1, 2
""".strip()

Q4_SQL = """
SELECT sp.sales_person_name,
       sum(f.net_amount)              AS revenue,
       count(*)                       AS orders,
       count(DISTINCT f.customer_key) AS customers
FROM   marts.fact_sales      f
JOIN   marts.dim_sales_person sp ON f.sales_person_key = sp.sales_person_key
JOIN   marts.dim_date         d  ON f.date_key         = d.date_key
WHERE  sp.sales_person_name IS NOT NULL
  AND  {{date_filter}}
GROUP  BY sp.sales_person_name
ORDER  BY revenue DESC
""".strip()


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> None:
    print(f"Metabase: {BASE_URL}")
    print(f"Database: {DB_NAME}")
    print()

    db_id = get_database_id()
    date_field_id = find_field_id(db_id, "dim_date", "date_actual")
    print(f"  database id = {db_id}, dim_date.date_actual field id = {date_field_id}")

    print("\nCleaning up previous run...")
    cleanup()

    print("\nCreating questions...")
    template_tags = date_filter_template_tag(date_field_id)

    q1 = create_native_card(
        f"{NAME_PREFIX}Revenue by month",
        Q1_SQL,
        db_id,
        display="line",
        visualization_settings={
            "graph.dimensions": ["month"],
            "graph.metrics": ["revenue"],
        },
        template_tags=template_tags,
    )
    print(f"  Q1 id={q1}")

    q2 = create_native_card(
        f"{NAME_PREFIX}Top 10 products by revenue",
        Q2_SQL,
        db_id,
        display="row",
        visualization_settings={
            "graph.dimensions": ["product_name"],
            "graph.metrics": ["revenue"],
        },
        template_tags=template_tags,
    )
    print(f"  Q2 id={q2}")

    q3 = create_native_card(
        f"{NAME_PREFIX}Sales by region and category",
        Q3_SQL,
        db_id,
        display="pivot",
        visualization_settings={
            "pivot_table.column_split": {
                "rows": ["region_group"],
                "columns": ["category_name"],
                "values": ["revenue"],
            }
        },
        template_tags=template_tags,
    )
    print(f"  Q3 id={q3}")

    q4 = create_native_card(
        f"{NAME_PREFIX}Sales people leaderboard",
        Q4_SQL,
        db_id,
        display="table",
        template_tags=template_tags,
    )
    print(f"  Q4 id={q4}")

    print("\nCreating dashboard...")
    dashboard_id = create_dashboard(DASHBOARD_NAME)
    print(f"  dashboard id={dashboard_id}")

    # Layout: 18-column grid (Metabase convention)
    cards = [
        {"card_id": q1, "row": 0,  "col": 0, "size_x": 18, "size_y": 6},   # full width
        {"card_id": q2, "row": 6,  "col": 0, "size_x": 9,  "size_y": 8},   # left half
        {"card_id": q3, "row": 6,  "col": 9, "size_x": 9,  "size_y": 8},   # right half
        {"card_id": q4, "row": 14, "col": 0, "size_x": 18, "size_y": 8},   # full width
    ]
    set_dashboard_cards_and_filter(dashboard_id, cards, parameter_id="date_range_param")
    print(f"  added {len(cards)} cards + date-range filter")

    print(f"\nDone. Open: {BASE_URL}/dashboard/{dashboard_id}")


if __name__ == "__main__":
    main()
