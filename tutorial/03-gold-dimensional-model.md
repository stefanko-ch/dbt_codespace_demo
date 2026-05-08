# Task 3 — Gold: Dimensional Model

**Goal:** turn the silver staging views into a Kimball-style **star schema** that BI users can pivot on without thinking.

The output of this task is one fact + four dimensions, all in `analytics.marts.*`:

```
                    ┌──────────────────┐
                    │  dim_date        │
                    └─────────┬────────┘
                              │ date_key
                              │
┌──────────────┐    ┌─────────┴────────┐    ┌──────────────────┐
│ dim_customer │────│  fact_sales      │────│ dim_product      │
└──────────────┘    │                  │    └──────────────────┘
   customer_key     │ grain: 1 row per │      product_key
                    │  order line      │
┌──────────────┐    │                  │    ┌──────────────────┐
│ dim_territory│────│                  │────│ dim_sales_person │
└──────────────┘    └──────────────────┘    └──────────────────┘
  territory_key                                sales_person_key
```

## Grain decision

Pick the grain **before** writing any SQL.

> **One row per order line item** — `(sales_order_id, sales_order_detail_id)`.

This grain lets us answer "how many of product X sold per month/territory/customer", which is the most useful question for AdventureWorks. The header-level metrics (freight, tax) get allocated proportionally if needed, or kept in a separate `fact_orders` later.

## Conventions

- File layout:
  ```
  dbt/models/marts/adventureworks/
    _adventureworks_marts__models.yml
    dim_customer.sql
    dim_product.sql
    dim_sales_person.sql
    dim_sales_territory.sql
    dim_date.sql
    fact_sales.sql
  ```
- Materialization: **table** (already configured for `marts/*` in `dbt_project.yml`)
- Surrogate keys generated with `dbt_utils.generate_surrogate_key` — install the package first (see below)
- Column naming: `<entity>_key` for the surrogate PK/FK, `<entity>_id` for the natural source ID

## Step 1 — Install dbt_utils

In `dbt/packages.yml` (create if missing):

```yaml
packages:
  - package: dbt-labs/dbt_utils
    version: [">=1.1.0", "<2.0.0"]
```

Then:

```bash
cd dbt
dbt deps
```

## Step 2 — Build the dimensions

### `dim_date.sql`

Use `dbt_utils.date_spine` to generate one row per day from 2010 to 2030:

```sql
{{ config(materialized='table') }}

with spine as (
    {{ dbt_utils.date_spine(
        datepart="day",
        start_date="cast('2010-01-01' as date)",
        end_date="cast('2031-01-01' as date)"
    ) }}
)
select
    {{ dbt_utils.generate_surrogate_key(['date_day']) }} as date_key,
    date_day                                   as date_actual,
    extract(year   from date_day)::int         as year,
    extract(quarter from date_day)::int        as quarter,
    extract(month  from date_day)::int         as month,
    to_char(date_day, 'TMMonth')               as month_name,
    extract(day    from date_day)::int         as day_of_month,
    extract(dow    from date_day)::int         as day_of_week,
    to_char(date_day, 'TMDay')                 as day_name,
    extract(week   from date_day)::int         as iso_week
from spine
```

### `dim_customer.sql`

Joins `customer` with `person` to get a name for individual customers:

```sql
with customers as (select * from {{ ref('stg_aw__customer') }}),
     people    as (select * from {{ ref('stg_aw__person') }})
select
    {{ dbt_utils.generate_surrogate_key(['c.customer_id']) }} as customer_key,
    c.customer_id,
    c.customer_type,
    p.full_name             as customer_name,
    c.territory_id,
    c.store_id
from customers c
left join people p on p.person_id = c.person_id
```

### `dim_product.sql`

Flattens the product → subcategory → category hierarchy:

```sql
with p  as (select * from {{ ref('stg_aw__product') }}),
     sc as (select * from {{ ref('stg_aw__product_subcategory') }}),
     c  as (select * from {{ ref('stg_aw__product_category') }})
select
    {{ dbt_utils.generate_surrogate_key(['p.product_id']) }} as product_key,
    p.product_id,
    p.product_name,
    p.product_number,
    p.color,
    p.standard_cost,
    p.list_price,
    p.is_active,
    sc.subcategory_name,
    c.category_name
from p
left join sc on sc.product_subcategory_id = p.product_subcategory_id
left join c  on c.product_category_id     = sc.product_category_id
```

### `dim_sales_territory.sql`

```sql
with t as (select * from {{ ref('stg_aw__sales_territory') }})
select
    {{ dbt_utils.generate_surrogate_key(['territory_id']) }} as territory_key,
    territory_id,
    territory_name,
    country_region_code,
    region_group
from t
```

### `dim_sales_person.sql`

```sql
with sp as (select * from {{ ref('stg_aw__sales_person') }}),
     p  as (select * from {{ ref('stg_aw__person') }})
select
    {{ dbt_utils.generate_surrogate_key(['sp.sales_person_id']) }} as sales_person_key,
    sp.sales_person_id,
    p.full_name as sales_person_name,
    sp.territory_id,
    sp.sales_quota,
    sp.commission_pct
from sp
left join p on p.person_id = sp.sales_person_id
```

## Step 3 — Build `fact_sales`

```sql
{{ config(materialized='table') }}

with detail as (
    select * from {{ ref('stg_aw__sales_order_detail') }}
),
header as (
    select * from {{ ref('stg_aw__sales_order_header') }}
),
joined as (
    select
        d.sales_order_id,
        d.sales_order_detail_id,
        h.order_date,
        h.customer_id,
        h.sales_person_id,
        h.territory_id,
        d.product_id,
        d.order_qty,
        d.unit_price,
        d.unit_price_discount,
        d.line_total
    from detail d
    inner join header h using (sales_order_id)
)
select
    -- surrogate FKs
    {{ dbt_utils.generate_surrogate_key(['j.order_date']) }}        as date_key,
    {{ dbt_utils.generate_surrogate_key(['j.customer_id']) }}       as customer_key,
    {{ dbt_utils.generate_surrogate_key(['j.product_id']) }}        as product_key,
    {{ dbt_utils.generate_surrogate_key(['j.territory_id']) }}      as territory_key,
    {{ dbt_utils.generate_surrogate_key(['j.sales_person_id']) }}   as sales_person_key,

    -- degenerate dims
    j.sales_order_id,
    j.sales_order_detail_id,

    -- measures
    j.order_qty,
    j.unit_price,
    j.unit_price_discount,
    j.line_total,
    j.unit_price * j.order_qty                                 as gross_amount,
    j.unit_price * j.order_qty * j.unit_price_discount         as discount_amount,
    j.line_total                                               as net_amount
from joined j
```

## Step 4 — Tests

`dbt/models/marts/adventureworks/_adventureworks_marts__models.yml`:

```yaml
version: 2

models:
  - name: dim_date
    columns:
      - name: date_key
        tests: [unique, not_null]

  - name: dim_customer
    columns:
      - name: customer_key
        tests: [unique, not_null]

  - name: dim_product
    columns:
      - name: product_key
        tests: [unique, not_null]

  - name: dim_sales_territory
    columns:
      - name: territory_key
        tests: [unique, not_null]

  - name: dim_sales_person
    columns:
      - name: sales_person_key
        tests: [unique, not_null]

  - name: fact_sales
    columns:
      - name: customer_key
        tests:
          - not_null
          - relationships: {to: ref('dim_customer'),         field: customer_key}
      - name: product_key
        tests:
          - not_null
          - relationships: {to: ref('dim_product'),          field: product_key}
      - name: territory_key
        tests:
          - relationships: {to: ref('dim_sales_territory'),  field: territory_key}
      - name: sales_person_key
        tests:
          - relationships: {to: ref('dim_sales_person'),     field: sales_person_key}
      - name: date_key
        tests:
          - not_null
          - relationships: {to: ref('dim_date'),             field: date_key}
```

## Acceptance check

```bash
cd dbt
dbt run  --target analytics --select marts
dbt test --target analytics --select marts
```

All green? Verify in Postgres:

```bash
psql -d analytics -c "
SELECT
    (SELECT count(*) FROM marts.fact_sales)         AS fact_rows,
    (SELECT count(*) FROM marts.dim_customer)       AS dim_customer,
    (SELECT count(*) FROM marts.dim_product)        AS dim_product,
    (SELECT count(*) FROM marts.dim_sales_person)   AS dim_sales_person,
    (SELECT count(*) FROM marts.dim_sales_territory) AS dim_territory,
    (SELECT count(*) FROM marts.dim_date)           AS dim_date;
"
```

`fact_sales` should have ~121,000 rows (matches the line items count from bronze).

## Hints

- If you get NULL `customer_key` in `fact_sales`, you have orders pointing at a `customer_id` that's missing from `stg_aw__customer`. Investigate before patching — it's a real data quality signal.
- `dim_date` joins via `date_key = generate_surrogate_key(order_date)` — make sure the cast/format matches on both sides (use `order_date::date` everywhere).
- Want SCD Type 2 on `dim_customer`? That's a follow-up exercise — start by reading [dbt snapshots](https://docs.getdbt.com/docs/build/snapshots).

## Next

→ Back to [Tutorial overview](README.md). The BI / dashboard layer (Metabase) follows in a separate session.
