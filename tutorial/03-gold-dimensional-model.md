# Task 3 — Gold: Dimensional Model

**Goal:** turn the silver staging views into a Kimball-style **star schema** that BI users can pivot on without thinking. By the end you'll have one fact and five dimensions, all surrogate-keyed, fully tested, and documented.

Plan to spend ~2-3 hours. This is where data modelling judgment matters most — keep stopping to ask yourself "would a non-technical user of `fact_sales` find this column useful?".

## What you'll build

<p align="center">
  <img src="../assets/star_schema.svg" alt="Star schema target" width="100%">
</p>

Five dimensions arranged around a single fact, all in `analytics.marts.*`:

| Model                  | Type      | Grain                          | Materialization |
| ---------------------- | --------- | ------------------------------ | --------------- |
| `fact_sales`           | fact      | one row per order line item    | table           |
| `dim_customer`         | dimension | one row per customer           | table           |
| `dim_product`          | dimension | one row per product            | table           |
| `dim_sales_territory`  | dimension | one row per territory          | table           |
| `dim_sales_person`     | dimension | one row per salesperson        | table           |
| `dim_date`             | dimension | one row per day, 2010-01-01 → 2030-12-31 | table |

## Step 0 — Pin down the grain

**Read this section twice before writing any SQL.**

Grain = "what does one row in `fact_sales` represent?" Your answer determines what's possible to ask of the model.

Choices for AdventureWorks sales:
- **Order header level** (one row per order) — easy to model, but you can't ask product-level questions ("how many bikes sold per month?")
- **Order line item level** (one row per `(order_id, order_detail_id)`) — answers product-level questions, but header-level metrics like freight need allocation if you want them per line
- **Daily aggregated** (one row per day per territory) — fast queries, but loses customer/product detail

We pick **order line item** — most flexible, matches the AdventureWorks `Sales.SalesOrderDetail` grain. Header-only attributes (status, freight) can be carried along on each line as denormalized columns where useful.

Once chosen, the grain is sacred: every measure in `fact_sales` must make sense at the line-item grain.

## Conventions used here

- One file per model, all under `dbt/models/marts/adventureworks/`
- Surrogate keys generated with `dbt_utils.generate_surrogate_key` — never expose the source's natural keys as joins downstream
- Naming: `<entity>_key` for surrogate primary key (and matching FK in `fact_sales`); `<entity>_id` retained as a degenerate column for traceability
- Materialization: **table** (already configured for `models/marts/*` in `dbt_project.yml`)
- File layout:
  ```
  dbt/models/marts/adventureworks/
    _adventureworks_marts__models.yml
    _adventureworks_marts__docs.md
    dim_customer.sql
    dim_product.sql
    dim_sales_territory.sql
    dim_sales_person.sql
    dim_date.sql
    fact_sales.sql
  ```

## Step 1 — Install dbt_utils

You probably installed this in Task 2; if not:

`dbt/packages.yml`:

```yaml
packages:
  - package: dbt-labs/dbt_utils
    version: [">=1.1.0", "<2.0.0"]
```

```bash
cd dbt
dbt deps
```

This pulls macros like `dbt_utils.generate_surrogate_key` and `dbt_utils.date_spine`.

## Step 2 — Build `dim_date`

Date dim is the easiest place to start: it has no source dependencies, just a generated calendar.

Create `dbt/models/marts/adventureworks/dim_date.sql`:

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

    date_day                            as date_actual,
    extract(year    from date_day)::int as year,
    extract(quarter from date_day)::int as quarter,
    extract(month   from date_day)::int as month,
    to_char(date_day, 'TMMonth')        as month_name,
    extract(day     from date_day)::int as day_of_month,
    extract(dow     from date_day)::int as day_of_week,
    to_char(date_day, 'TMDay')          as day_name,
    extract(week    from date_day)::int as iso_week,

    -- Useful flags for BI filters
    (extract(dow from date_day) in (0, 6)) as is_weekend,
    (date_trunc('quarter', date_day) = date_day) as is_quarter_start,
    (date_day = (date_trunc('month', date_day) + interval '1 month' - interval '1 day')::date) as is_month_end
from spine
```

Run + test:

```bash
dbt run  --target analytics --select dim_date
dbt show --target analytics --select dim_date --limit 5
```

You should see ~7,670 rows (≈ 21 years × 365 days).

## Step 3 — Build `dim_customer`

Joins `stg_aw__customer` with `stg_aw__person` so individual customers carry their name. Stores keep their `customer_type='store'` flag and a NULL name.

`dbt/models/marts/adventureworks/dim_customer.sql`:

```sql
with customers as (
    select * from {{ ref('stg_aw__customer') }}
),
people as (
    select * from {{ ref('stg_aw__person') }}
)

select
    {{ dbt_utils.generate_surrogate_key(['c.customer_id']) }} as customer_key,

    c.customer_id,
    c.customer_type,
    p.full_name as customer_name,
    p.first_name,
    p.last_name,
    p.email_promotion,
    c.territory_id,
    c.store_id
from customers c
left join people p on p.person_id = c.person_id
```

Run + sanity-check:

```bash
dbt run --target analytics --select dim_customer
psql -d analytics -c "
  SELECT customer_type, count(*),
         count(customer_name) AS with_name
  FROM marts.dim_customer
  GROUP BY 1;
"
```

You should see `individual` rows where ~all have a `customer_name`, and `store` rows where it's mostly NULL.

## Step 4 — Build `dim_product`

Flattens the `product → subcategory → category` hierarchy into one row per product. This is a textbook **denormalize-for-BI** move: BI users get one box to drag without `JOIN`s.

`dbt/models/marts/adventureworks/dim_product.sql`:

```sql
with p as (
    select * from {{ ref('stg_aw__product') }}
),
sc as (
    select * from {{ ref('stg_aw__product_subcategory') }}
),
c as (
    select * from {{ ref('stg_aw__product_category') }}
)

select
    {{ dbt_utils.generate_surrogate_key(['p.product_id']) }} as product_key,

    p.product_id,
    p.product_name,
    p.product_number,
    p.color,
    p.size,
    p.weight,
    p.product_line,
    p.product_class,
    p.product_style,
    p.standard_cost,
    p.list_price,

    -- Denormalized hierarchy
    p.product_subcategory_id,
    sc.subcategory_name,
    sc.product_category_id,
    c.category_name,

    p.sell_start_date,
    p.sell_end_date,
    p.discontinued_date,
    p.is_active

from p
left join sc on sc.product_subcategory_id = p.product_subcategory_id
left join c  on c.product_category_id     = sc.product_category_id
```

```bash
dbt run --target analytics --select dim_product
```

## Step 5 — Build `dim_sales_territory` and `dim_sales_person`

Smaller, faster wins.

`dbt/models/marts/adventureworks/dim_sales_territory.sql`:

```sql
with t as (
    select * from {{ ref('stg_aw__sales_territory') }}
)
select
    {{ dbt_utils.generate_surrogate_key(['territory_id']) }} as territory_key,
    territory_id,
    territory_name,
    country_region_code,
    region_group
from t
```

`dbt/models/marts/adventureworks/dim_sales_person.sql`:

```sql
with sp as (
    select * from {{ ref('stg_aw__sales_person') }}
),
p as (
    select * from {{ ref('stg_aw__person') }}
)

select
    {{ dbt_utils.generate_surrogate_key(['sp.sales_person_id']) }} as sales_person_key,

    sp.sales_person_id,
    p.full_name as sales_person_name,
    sp.territory_id,
    sp.sales_quota,
    sp.commission_pct,
    sp.sales_ytd,
    sp.sales_last_year
from sp
left join p on p.person_id = sp.sales_person_id
```

Run them:

```bash
dbt run --target analytics --select dim_sales_territory dim_sales_person
```

Quick sanity check:

```bash
psql -d analytics -c "SELECT * FROM marts.dim_sales_territory ORDER BY region_group, territory_name"
```

You should see 10 rows across 3 region groups.

## Step 6 — Build `fact_sales`

This is the heart. Joins line-item details with their order header to pick up customer / territory / salesperson, and computes denormalized FK keys.

`dbt/models/marts/adventureworks/fact_sales.sql`:

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

        -- Measures (line-item grain)
        d.order_qty,
        d.unit_price,
        d.unit_price_discount,
        d.line_total,

        -- Carry-along header attributes that are useful at line grain
        h.is_online,
        h.status_name as order_status,
        h.sales_order_number
    from detail d
    inner join header h using (sales_order_id)
)

select
    -- Surrogate FKs (must match the dim's generate_surrogate_key inputs)
    {{ dbt_utils.generate_surrogate_key(['j.order_date']) }}      as date_key,
    {{ dbt_utils.generate_surrogate_key(['j.customer_id']) }}     as customer_key,
    {{ dbt_utils.generate_surrogate_key(['j.product_id']) }}      as product_key,
    {{ dbt_utils.generate_surrogate_key(['j.territory_id']) }}    as territory_key,
    {{ dbt_utils.generate_surrogate_key(['j.sales_person_id']) }} as sales_person_key,

    -- Degenerate dimensions (kept on the fact, no separate dim table)
    j.sales_order_id,
    j.sales_order_detail_id,
    j.sales_order_number,
    j.order_status,
    j.is_online,

    -- Measures (additive at the line grain)
    j.order_qty,
    j.unit_price,
    j.unit_price_discount,
    j.line_total,

    -- Derived measures
    j.unit_price * j.order_qty                                    as gross_amount,
    j.unit_price * j.order_qty * j.unit_price_discount            as discount_amount,
    j.line_total                                                  as net_amount

from joined j
```

Run it:

```bash
dbt run --target analytics --select fact_sales
```

Expected row count is roughly the same as `staging.stg_aw__sales_order_detail` (~121k rows). Verify:

```bash
psql -d analytics -c "
  SELECT
    (SELECT count(*) FROM marts.fact_sales)                AS fact_rows,
    (SELECT count(*) FROM staging.stg_aw__sales_order_detail) AS detail_rows;
"
```

Numbers should match. If `fact_rows < detail_rows`, you have line items pointing at orders that don't exist in `header` — a referential integrity issue worth investigating before patching.

## Step 7 — Add tests

Create `dbt/models/marts/adventureworks/_adventureworks_marts__models.yml`:

```yaml
version: 2

models:
  - name: dim_date
    description: "Calendar dimension, one row per day from 2010-01-01 through 2030-12-31."
    columns:
      - name: date_key
        description: "Surrogate key (md5 hash of date_actual)."
        tests: [unique, not_null]
      - name: date_actual
        tests: [unique, not_null]

  - name: dim_customer
    columns:
      - name: customer_key
        tests: [unique, not_null]
      - name: customer_id
        tests: [unique, not_null]
      - name: customer_type
        tests:
          - accepted_values:
              values: ['individual', 'store', 'unknown']

  - name: dim_product
    columns:
      - name: product_key
        tests: [unique, not_null]
      - name: product_id
        tests: [unique, not_null]
      - name: list_price
        tests:
          - dbt_utils.expression_is_true:
              expression: ">= 0"

  - name: dim_sales_territory
    columns:
      - name: territory_key
        tests: [unique, not_null]
      - name: territory_id
        tests: [unique, not_null]

  - name: dim_sales_person
    columns:
      - name: sales_person_key
        tests: [unique, not_null]
      - name: sales_person_id
        tests: [unique, not_null]

  - name: fact_sales
    description: "One row per order line item. Five FKs link to the conformed dimensions; degenerate dims live on the fact itself."
    columns:
      - name: customer_key
        tests:
          - not_null
          - relationships: { to: ref('dim_customer'),         field: customer_key }
      - name: product_key
        tests:
          - not_null
          - relationships: { to: ref('dim_product'),          field: product_key }
      - name: territory_key
        tests:
          - relationships: { to: ref('dim_sales_territory'),  field: territory_key }
      - name: sales_person_key
        tests:
          - relationships: { to: ref('dim_sales_person'),     field: sales_person_key }
      - name: date_key
        tests:
          - not_null
          - relationships: { to: ref('dim_date'),             field: date_key }
      - name: order_qty
        tests:
          - not_null
          - dbt_utils.expression_is_true:
              expression: "> 0"
      - name: net_amount
        tests:
          - not_null
          - dbt_utils.expression_is_true:
              expression: ">= 0"

    # Composite uniqueness: the line-item grain must hold.
    tests:
      - dbt_utils.unique_combination_of_columns:
          combination_of_columns:
            - sales_order_id
            - sales_order_detail_id
```

Run all the tests:

```bash
dbt test --target analytics --select marts
```

Every test should pass. If a `relationships` test fails, you have a fact row pointing at a dim that doesn't exist — usually a sign that the dim was filtered or the source had orphan FKs. Fix at the dim level (don't relax the test).

## Step 8 — Add a singular invariant test

Sum of `fact_sales.net_amount` per order should match `stg_aw__sales_order_header.subtotal_amount` within rounding.

`dbt/tests/assert_fact_sales_subtotal_consistency.sql`:

```sql
with fact_per_order as (
    select sales_order_id, sum(net_amount) as fact_subtotal
    from {{ ref('fact_sales') }}
    group by sales_order_id
),
header as (
    select sales_order_id, subtotal_amount
    from {{ ref('stg_aw__sales_order_header') }}
)
select
    h.sales_order_id,
    h.subtotal_amount,
    f.fact_subtotal,
    abs(h.subtotal_amount - f.fact_subtotal) as diff
from header h
join fact_per_order f using (sales_order_id)
where abs(h.subtotal_amount - f.fact_subtotal) > 0.01
```

```bash
dbt test --select assert_fact_sales_subtotal_consistency
```

If this fails, the fact's net_amount aggregation drifts from what the header claimed — either header has misaligned totals, or you're missing line items.

## Step 9 — Document with doc blocks

Long descriptions belong in `.md` files. Create `dbt/models/marts/adventureworks/_adventureworks_marts__docs.md`:

```markdown
{% docs fact_sales_grain %}
**Grain:** one row per `(sales_order_id, sales_order_detail_id)`.

Every measure on `fact_sales` is additive at this grain. Header-level
attributes carried along (status, online flag, order number) repeat for
every line on the order — that's intentional, it lets BI users filter
without joining back to a header table.
{% enddocs %}

{% docs surrogate_key %}
Generated via `dbt_utils.generate_surrogate_key` (an MD5 hash of the
business key). This decouples downstream from the source's natural key
strategy and makes joins trivially indexable.
{% enddocs %}
```

Reference them in the YAML:

```yaml
- name: fact_sales
  description: '{{ doc("fact_sales_grain") }}'
  columns:
    - name: customer_key
      description: '{{ doc("surrogate_key") }}'
    # ... etc.
```

Generate and serve:

```bash
dbt docs generate --target analytics
dbt docs serve --port 8080
```

The lineage graph will now show the full pipeline: source → staging → marts. Click `fact_sales` and follow the upstream path back to bronze.

## Step 10 — Production-style build

Use `dbt build` to run + test in dependency order, stopping on first failure:

```bash
dbt build --target analytics --select staging marts
```

This is what a CI/CD pipeline would run. If everything is green, you have a fully validated bronze → silver → gold pipeline.

## Acceptance check

```bash
psql -d analytics -c "
SELECT
  (SELECT count(*) FROM marts.fact_sales)             AS fact_rows,
  (SELECT count(*) FROM marts.dim_customer)           AS dim_customer,
  (SELECT count(*) FROM marts.dim_product)            AS dim_product,
  (SELECT count(*) FROM marts.dim_sales_person)       AS dim_sales_person,
  (SELECT count(*) FROM marts.dim_sales_territory)    AS dim_sales_territory,
  (SELECT count(*) FROM marts.dim_date)               AS dim_date;
"
```

Expected (approximate):

| metric              | value     |
| ------------------- | --------- |
| fact_rows           | ~121,000  |
| dim_customer        | ~19,820   |
| dim_product         | ~504      |
| dim_sales_person    | ~17       |
| dim_sales_territory | 10        |
| dim_date            | ~7,670    |

`dbt build --target analytics --select marts` finishes green.

## Hands-on exercises

Pick at least three to spend time on.

1. **Top 10 products by revenue** — write the SQL by hand using only the marts tables, then verify your number against a direct query of the staging layer.
2. **Sales by territory and quarter** — pivot net_amount with `dim_date.quarter` × `dim_sales_territory.region_group`.
3. **`dim_customer` SCD type 2** — most customers are stable, but `territory_id` changes occasionally. Convert `dim_customer` to a snapshot using [`dbt snapshots`](https://docs.getdbt.com/docs/build/snapshots) so historical assignments are preserved. Add a `valid_from` / `valid_to` column pair.
4. **Add a `dim_currency`** — `Sales.SalesOrderHeader.CurrencyRateID` references `Sales.CurrencyRate`. Extend Task 1's bronze flow + Task 2's staging to bring `currency_rate` in, then create `dim_currency` and link it from `fact_sales`.
5. **A second fact: `fact_orders`** — header-grain (one row per order) with allocation of freight/tax. Discuss with a peer how this complements `fact_sales` rather than replacing it.
6. **Materialize `fact_sales` as `incremental`** — once the table is large, full refresh on every `dbt run` is wasteful. Convert to `materialized='incremental'` with `unique_key='[sales_order_id, sales_order_detail_id]'` and a `where modified_at > (select max(...) from {{ this }})` filter.
7. **Exposures** — declare a downstream `exposure` (the future Metabase dashboard) so `dbt source freshness` and `dbt build --select +exposure:sales_dashboard` work.
8. **Macros** — every `generate_surrogate_key` in the project takes a single column. Wrap the pattern in your own macro `dim_key(natural_key_column)` that just calls `dbt_utils.generate_surrogate_key([column])` — see how macros work.

## Hints

- **Order of building matters during dev:** dims first, fact last. The fact's `relationships` tests will fail if the dim doesn't exist yet.
- `dbt run --select dim_date+` (with `+`) runs the model and everything downstream that depends on it. Useful when you change a dim and want to refresh the fact too.
- `dbt build` uses topological order by default. Don't fight it — let it figure out dependency order.
- If `generate_surrogate_key` produces NULL keys, you have NULL in the natural key. Decide whether to filter, default, or raise.
- The `where` clause in `relationships` tests is your friend. Use it for genuinely-nullable FKs (e.g., `sales_person_id` is nullable on `fact_sales` because online orders have no rep).
- **Don't index** — Postgres adds default indexes on PKs, and dbt's tests run efficiently without them. If queries are slow in production, add indexes via [`indexes` config](https://docs.getdbt.com/reference/resource-configs/postgres-configs#indexes).

## Common issues

| Symptom | Likely cause |
| ------- | ------------ |
| `relationships` test fails on `customer_key` | Customers exist in `fact_sales` that aren't in `dim_customer`. Look for fact rows where `customer_id` is NULL or for a dim filter you forgot to remove. |
| Row counts in fact don't match `stg_aw__sales_order_detail` | Inner join with header dropped lines. Switch to a `left join` and investigate orphans. |
| `generate_surrogate_key` collisions | The arg list isn't unique — for `dim_customer` we use `customer_id`; if you accidentally use `territory_id` you'll collide for every customer in the same territory. |
| `dbt run` takes forever | You're running staging + marts on every iteration. Use `--select <model>+` to scope. |
| `dim_date` join doesn't match facts | The two sides need to use the *same* generate_surrogate_key input. We use `date_day` for the dim and `order_date` for the fact — but they're both `::date`, so the hash matches. If one were a timestamp, hashes would differ. |

## Next

→ [Task 4: Analyze in Metabase](04-metabase.md)
