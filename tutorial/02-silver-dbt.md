# Task 2 — Silver: Clean Staging Models with dbt

**Goal:** turn the raw bronze tables into clean, typed, well-named **staging views** that the dimensional model in Task 3 can rely on. Along the way you'll learn the dbt project structure, sources, models, generic and custom tests, and the documentation site.

Plan to spend ~2 hours here. Don't rush — staging is where data quality is enforced, and most production dbt projects spend the bulk of their model count in this layer.

## What "silver / staging" means

The staging layer is the **only** place where raw column names and types from the source get touched. After staging, every downstream model can assume:

- Column names are snake_case
- Types are correct (dates are `date`, money is `numeric`, booleans are `boolean`)
- Light derivations exist (`full_name = first || ' ' || last`, `is_active = end_date is null`)
- Test/dummy rows are filtered out

Things you should **NOT** do in staging:
- Join tables together (that's marts territory)
- Aggregate or change grain
- Apply business logic (e.g. "sale is 'big' when amount > 1000" — that's marts)
- Hard deduplication (light dedup is OK if same row appears twice in source)

The rule of thumb: **one source table → exactly one `stg_*` view**.

## Conventions used here

- One `stg_*` model per bronze table; prefix `stg_aw__` (`aw` for AdventureWorks) so we know which source it came from
- Materialization: **view** (cheap to rebuild, always reflects bronze)
- Schema: `staging` inside the `analytics` database
- Run target: `analytics` (the playground target is for the library warm-up only)
- File layout:
  ```
  dbt/models/staging/adventureworks/
    _adventureworks__sources.yml
    _adventureworks__models.yml
    stg_aw__customer.sql
    stg_aw__person.sql
    stg_aw__product.sql
    stg_aw__product_subcategory.sql
    stg_aw__product_category.sql
    stg_aw__sales_territory.sql
    stg_aw__sales_person.sql
    stg_aw__sales_order_header.sql
    stg_aw__sales_order_detail.sql
  ```

## Step 0 — Tour the dbt project

Before you write anything, get familiar with what's already in `dbt/`:

```bash
cd dbt
ls -la
```

You should see `dbt_project.yml`, `profiles.yml`, `pyproject.toml`, `models/`, `seeds/`, plus the `.venv/` from `uv sync`.

Open [`dbt/dbt_project.yml`](../dbt/dbt_project.yml) and look at the `models:` block:

```yaml
models:
  dbt_codespace_demo:
    staging:
      +materialized: view
      +schema: staging
    marts:
      +materialized: table
      +schema: marts
```

This says: anything in `models/staging/...` defaults to `view` materialization in the `staging` schema; anything in `models/marts/...` defaults to `table` in `marts`. The folder structure drives behavior — no per-file config needed.

Open [`dbt/profiles.yml`](../dbt/profiles.yml). Three named outputs are pre-defined (`playground`, `analytics`, `duckdb`); you'll work against `analytics`.

Quickly verify the connection:

```bash
dbt debug --target analytics
```

All checks should be green. If `Connection test: ERROR` shows up, fix it before continuing — re-check the Postgres container is running with `docker ps`.

## Step 1 — Declare the sources

dbt needs a manifest of where the raw data lives. Create the folder and the sources file:

```bash
mkdir -p models/staging/adventureworks
```

Create `models/staging/adventureworks/_adventureworks__sources.yml` with this content:

```yaml
version: 2

sources:
  - name: adventureworks
    description: |
      Bronze tables ingested from the Azure SQL AdventureWorks sample
      database by the `bronze_adventureworks` Kestra flow.
    database: analytics
    schema: raw
    loaded_at_field: modified_date
    freshness:
      warn_after:  { count: 24, period: hour }
      error_after: { count: 72, period: hour }

    tables:
      - name: customer
        description: "Source: Sales.Customer. One row per customer (individual or store)."
        columns:
          - name: customer_id
            description: "Natural key from SQL Server."
            tests: [unique, not_null]

      - name: person
        description: "Source: Person.Person. People who are individuals (not stores)."
        columns:
          - name: business_entity_id
            tests: [unique, not_null]

      - name: product
        description: "Source: Production.Product. Active and discontinued products."

      - name: product_subcategory
        description: "Source: Production.ProductSubcategory."

      - name: product_category
        description: "Source: Production.ProductCategory."

      - name: sales_territory
        description: "Source: Sales.SalesTerritory."

      - name: sales_person
        description: "Source: Sales.SalesPerson. Internal sales reps."

      - name: sales_order_header
        description: "Source: Sales.SalesOrderHeader. Order header — one row per order."

      - name: sales_order_detail
        description: "Source: Sales.SalesOrderDetail. Order line items — one row per line."
```

A few things worth noticing:

- **Source-level `freshness`** lets you later run `dbt source freshness` to flag data that hasn't been refreshed by the Kestra flow.
- **Tests on source columns** (e.g. `unique` on `customer.customer_id`) catch bad data at the bronze edge — before downstream models compound the bug.
- The `source(...)` function in models will use `database: analytics` and `schema: raw` automatically.

Run the source freshness check (will pass once you've successfully run the Kestra bronze flow):

```bash
dbt source freshness --target analytics
```

## Step 2 — Build your first staging model: `stg_aw__customer`

We start with the smallest interesting table. Create `models/staging/adventureworks/stg_aw__customer.sql`:

```sql
with source as (
    select * from {{ source('adventureworks', 'customer') }}
),

renamed as (
    select
        customer_id,
        person_id,
        store_id,
        territory_id,

        -- Derived: classify the customer. Sales.Customer in AdventureWorks
        -- mixes individuals (have a person_id) and stores (have a store_id).
        case
            when person_id is not null then 'individual'
            when store_id  is not null then 'store'
            else 'unknown'
        end as customer_type,

        modified_date as source_modified_at
    from source
)

select * from renamed
```

The CTE structure (`source` → optional intermediate steps → final `select`) is the dbt staging convention — keeps each transformation visible.

Run it:

```bash
dbt run --target analytics --select stg_aw__customer
```

You should see one model materialized as a view in `analytics.staging`. Check the SQL dbt actually produced:

```bash
cat target/run/dbt_codespace_demo/models/staging/adventureworks/stg_aw__customer.sql
```

Inspect a few rows in psql:

```bash
psql -d analytics -c "SELECT customer_type, count(*) FROM staging.stg_aw__customer GROUP BY 1"
```

You should see counts for `individual` and `store`.

### Add tests for this model

Create `models/staging/adventureworks/_adventureworks__models.yml` and start it with:

```yaml
version: 2

models:
  - name: stg_aw__customer
    description: "One row per customer; derived `customer_type` distinguishes individuals from stores."
    columns:
      - name: customer_id
        description: "Natural key from `Sales.Customer`."
        tests:
          - unique
          - not_null

      - name: customer_type
        description: "'individual', 'store', or 'unknown'."
        tests:
          - not_null
          - accepted_values:
              values: ['individual', 'store', 'unknown']
```

Run the tests:

```bash
dbt test --target analytics --select stg_aw__customer
```

All three tests should pass. If `accepted_values` fails, you have rows where neither `person_id` nor `store_id` is set — investigate before patching the test.

## Step 3 — Build the dimension staging models

Now the rest of the dimensions. For each, create the SQL file, run it, then immediately add a test block to `_adventureworks__models.yml` and run `dbt test --select <model>`.

### `stg_aw__person`

```sql
-- models/staging/adventureworks/stg_aw__person.sql
with source as (
    select * from {{ source('adventureworks', 'person') }}
)

select
    business_entity_id as person_id,
    person_type,
    title,
    first_name,
    middle_name,
    last_name,
    suffix,

    -- Derived: a single display name. NULLIF + concat with separator.
    trim(
        concat_ws(' ',
            nullif(trim(first_name),  ''),
            nullif(trim(middle_name), ''),
            nullif(trim(last_name),   '')
        )
    ) as full_name,

    email_promotion,
    modified_date as source_modified_at
from source
```

YAML block:

```yaml
- name: stg_aw__person
  description: "One row per person (individuals — not stores)."
  columns:
    - name: person_id
      tests: [unique, not_null]
    - name: full_name
      tests: [not_null]
    - name: person_type
      tests:
        - not_null
        - accepted_values:
            # 6 codes from AdventureWorks: SC=Store contact, IN=Individual,
            # SP=Sales person, EM=Employee, VC=Vendor contact, GC=General contact
            values: ['SC', 'IN', 'SP', 'EM', 'VC', 'GC']
```

### `stg_aw__product_category`

```sql
with source as (
    select * from {{ source('adventureworks', 'product_category') }}
)
select
    product_category_id,
    name as category_name,
    modified_date as source_modified_at
from source
```

YAML:

```yaml
- name: stg_aw__product_category
  columns:
    - name: product_category_id
      tests: [unique, not_null]
    - name: category_name
      tests: [unique, not_null]
```

### `stg_aw__product_subcategory`

```sql
with source as (
    select * from {{ source('adventureworks', 'product_subcategory') }}
)
select
    product_subcategory_id,
    product_category_id,
    name as subcategory_name,
    modified_date as source_modified_at
from source
```

YAML — note the `relationships` test that catches orphan FKs:

```yaml
- name: stg_aw__product_subcategory
  columns:
    - name: product_subcategory_id
      tests: [unique, not_null]
    - name: product_category_id
      tests:
        - not_null
        - relationships:
            to: ref('stg_aw__product_category')
            field: product_category_id
```

### `stg_aw__product`

```sql
with source as (
    select * from {{ source('adventureworks', 'product') }}
)
select
    product_id,
    name as product_name,
    product_number,
    color,
    standard_cost,
    list_price,
    size,
    weight,
    product_line,
    class as product_class,
    style as product_style,
    product_subcategory_id,
    sell_start_date,
    sell_end_date,
    discontinued_date,

    -- Derived: a product is "active" if it never reached its sell_end_date
    -- and was not explicitly discontinued.
    (sell_end_date is null and discontinued_date is null) as is_active,

    modified_date as source_modified_at
from source
```

YAML — adds business-rule tests:

```yaml
- name: stg_aw__product
  columns:
    - name: product_id
      tests: [unique, not_null]
    - name: product_name
      tests: [not_null]
    - name: list_price
      tests:
        - dbt_utils.expression_is_true:
            expression: ">= 0"
    - name: standard_cost
      tests:
        - dbt_utils.expression_is_true:
            expression: ">= 0"
    - name: product_subcategory_id
      tests:
        # Product can be uncategorized (NULL); only enforce FK when set.
        - relationships:
            to: ref('stg_aw__product_subcategory')
            field: product_subcategory_id
            where: "product_subcategory_id is not null"
```

> The `dbt_utils.expression_is_true` test needs the dbt-utils package — install it now (you'll need it again in Task 3):
>
> Create `dbt/packages.yml`:
> ```yaml
> packages:
>   - package: dbt-labs/dbt_utils
>     version: [">=1.1.0", "<2.0.0"]
> ```
> Then:
> ```bash
> dbt deps
> ```

### `stg_aw__sales_territory`

```sql
with source as (
    select * from {{ source('adventureworks', 'sales_territory') }}
)
select
    territory_id,
    name as territory_name,
    country_region_code,
    "group" as region_group,
    sales_ytd,
    sales_last_year,
    cost_ytd,
    cost_last_year,
    modified_date as source_modified_at
from source
```

YAML:

```yaml
- name: stg_aw__sales_territory
  columns:
    - name: territory_id
      tests: [unique, not_null]
    - name: territory_name
      tests: [unique, not_null]
    - name: region_group
      tests:
        - accepted_values:
            values: ['North America', 'Europe', 'Pacific']
```

### `stg_aw__sales_person`

```sql
with source as (
    select * from {{ source('adventureworks', 'sales_person') }}
)
select
    business_entity_id as sales_person_id,
    territory_id,
    sales_quota,
    bonus,
    commission_pct,
    sales_ytd,
    sales_last_year,
    modified_date as source_modified_at
from source
```

YAML:

```yaml
- name: stg_aw__sales_person
  columns:
    - name: sales_person_id
      tests:
        - unique
        - not_null
        - relationships:
            to: ref('stg_aw__person')
            field: person_id
    - name: territory_id
      tests:
        - relationships:
            to: ref('stg_aw__sales_territory')
            field: territory_id
            where: "territory_id is not null"
    - name: commission_pct
      tests:
        - dbt_utils.expression_is_true:
            expression: ">= 0 and commission_pct <= 1"
```

Run everything you've built so far:

```bash
dbt build --target analytics --select stg_aw__customer stg_aw__person stg_aw__product+
```

`dbt build` runs **and** tests in dependency order. The `+` selector includes downstream — when you add new models later, they'll be picked up automatically.

## Step 4 — Build the fact-side staging models

These two are the heart of the analytical model. Be careful with the column lists.

### `stg_aw__sales_order_header`

```sql
with source as (
    select * from {{ source('adventureworks', 'sales_order_header') }}
)
select
    sales_order_id,
    customer_id,
    sales_person_id,
    territory_id,

    order_date::date as order_date,
    due_date::date   as due_date,
    ship_date::date  as ship_date,

    online_order_flag as is_online,
    sales_order_number,
    purchase_order_number,
    account_number,

    sub_total as subtotal_amount,
    tax_amt   as tax_amount,
    freight   as freight_amount,
    total_due as total_amount,

    -- Derived consistency check: subtotal + tax + freight should equal total.
    -- We'll test this as a post-hoc invariant in the YAML.
    (sub_total + tax_amt + freight) as computed_total,

    status,
    case status
        when 1 then 'in process'
        when 2 then 'approved'
        when 3 then 'backordered'
        when 4 then 'rejected'
        when 5 then 'shipped'
        when 6 then 'cancelled'
        else 'unknown'
    end as status_name,

    modified_date as source_modified_at
from source
```

YAML — includes a singular test on the computed_total invariant:

```yaml
- name: stg_aw__sales_order_header
  columns:
    - name: sales_order_id
      tests: [unique, not_null]
    - name: order_date
      tests: [not_null]
    - name: customer_id
      tests:
        - not_null
        - relationships:
            to: ref('stg_aw__customer')
            field: customer_id
    - name: territory_id
      tests:
        - relationships:
            to: ref('stg_aw__sales_territory')
            field: territory_id
    - name: sales_person_id
      tests:
        - relationships:
            to: ref('stg_aw__sales_person')
            field: sales_person_id
            where: "sales_person_id is not null"
    - name: total_amount
      tests:
        - dbt_utils.expression_is_true:
            expression: ">= 0"
    - name: status_name
      tests:
        - accepted_values:
            values:
              - 'in process'
              - 'approved'
              - 'backordered'
              - 'rejected'
              - 'shipped'
              - 'cancelled'
              - 'unknown'
```

### `stg_aw__sales_order_detail`

```sql
with source as (
    select * from {{ source('adventureworks', 'sales_order_detail') }}
)
select
    sales_order_id,
    sales_order_detail_id,
    product_id,
    order_qty,
    unit_price,
    unit_price_discount,
    line_total,
    carrier_tracking_number,
    modified_date as source_modified_at
from source
```

YAML:

```yaml
- name: stg_aw__sales_order_detail
  columns:
    - name: sales_order_detail_id
      tests: [unique, not_null]
    - name: sales_order_id
      tests:
        - not_null
        - relationships:
            to: ref('stg_aw__sales_order_header')
            field: sales_order_id
    - name: product_id
      tests:
        - not_null
        - relationships:
            to: ref('stg_aw__product')
            field: product_id
    - name: order_qty
      tests:
        - not_null
        - dbt_utils.expression_is_true:
            expression: "> 0"
    - name: unit_price
      tests:
        - dbt_utils.expression_is_true:
            expression: ">= 0"
    - name: line_total
      tests:
        - dbt_utils.expression_is_true:
            expression: ">= 0"
```

## Step 5 — Add a custom (singular) test

So far you've used **generic** tests (those that take parameters). dbt also supports **singular** tests — arbitrary SQL that returns failing rows.

Create `dbt/tests/assert_order_total_matches_lines.sql`:

```sql
-- Singular test: sum of order_detail.line_total per order should match
-- order_header.subtotal_amount within a small rounding tolerance.

with line_totals as (
    select
        sales_order_id,
        sum(line_total) as lines_sum
    from {{ ref('stg_aw__sales_order_detail') }}
    group by sales_order_id
),
header_totals as (
    select
        sales_order_id,
        subtotal_amount
    from {{ ref('stg_aw__sales_order_header') }}
)

select
    h.sales_order_id,
    h.subtotal_amount,
    l.lines_sum,
    abs(h.subtotal_amount - l.lines_sum) as diff
from header_totals h
join line_totals  l using (sales_order_id)
where abs(h.subtotal_amount - l.lines_sum) > 0.01
```

Run it:

```bash
dbt test --select assert_order_total_matches_lines
```

If the test fails, look at the failed-rows output — there might be legitimate rounding, line-item discounts not modeled at the header, or a real bug.

## Step 6 — Document everything

Empty `description` fields are an anti-pattern. Go back to your two YAML files and write a one-line description for **every** model and **every** column you tested. Future-you (and your dbt docs site) will thank you.

For longer descriptions, use a doc block. Create `dbt/models/staging/adventureworks/_adventureworks__docs.md`:

```markdown
{% docs aw_status_name %}
Decoded form of `Sales.SalesOrderHeader.Status`. Mapping:

| Code | Name        |
| ---- | ----------- |
| 1    | in process  |
| 2    | approved    |
| 3    | backordered |
| 4    | rejected    |
| 5    | shipped     |
| 6    | cancelled   |
{% enddocs %}
```

Reference it in the YAML:

```yaml
- name: status_name
  description: '{{ doc("aw_status_name") }}'
```

Generate and serve the docs site:

```bash
dbt docs generate --target analytics
dbt docs serve --port 8080
```

Open port **8080** in the Codespace Ports panel. Browse the lineage graph (top-right) and click through your models — you'll see descriptions, columns, tests, sources, and the compiled SQL.

`Ctrl+C` to stop the server when done.

## Step 7 — Run everything end-to-end

```bash
dbt build --target analytics --select staging
```

`dbt build` runs in dependency order: seed → run → test, and stops at the first failure. The `staging` selector picks up the whole folder.

Expected output:

```
Found 9 models, X tests, 9 sources, ...
1 of N PASS stg_aw__product_category
2 of N PASS stg_aw__product_subcategory
...
N of N PASS test stg_aw__sales_order_detail.relationships ...
```

Everything green = silver layer done.

## Acceptance check

```bash
psql -d analytics -c "\dv staging.stg_aw__*"
```

Nine views.

```bash
dbt build --target analytics --select staging
```

All green.

```bash
dbt source freshness --target analytics
```

Pass (or warn at most — staging is fed by a manual Kestra run, so freshness can lag).

## Hands-on exercises

Pick at least three of these to spend time on:

1. **`product.color`** — find products with empty-string colors. Add a `not_null` and `dbt_utils.not_empty_string` test on `color` (defining "empty" as null, "", or whitespace).
2. **`sales_order_header.ship_date < order_date`** — write a singular test that flags any orders where the ship date precedes the order date.
3. **Currency exposure** — add a `currency_code` column to `stg_aw__sales_order_header` (it doesn't exist in source — derive 'USD' for all rows) and add an `accepted_values` test.
4. **`product.list_price > standard_cost`** — write a `dbt_utils.expression_is_true` test that catches products being sold below cost.
5. **Source freshness with `loaded_at_field`** — add `loaded_at_field: source_modified_at` to all your model YAML entries (not source) so freshness can be tracked at the staging layer too.
6. **dbt selectors** — try each of these and observe what runs:
   - `dbt run --select stg_aw__customer+` (the model and everything downstream)
   - `dbt run --select +stg_aw__customer` (the model and everything upstream)
   - `dbt run --select tag:dim` (after tagging dim staging models)
7. **Tag your models** — add tags to each YAML entry (`tags: ['dim']` or `tags: ['fact']`), then use them in selectors.

## Hints

- `dbt show --select <model> --limit 5 --target analytics` previews any model's output without leaving the terminal. Useful when you don't want to switch to psql.
- `--store-failures` (`dbt test --store-failures`) writes failing rows to `staging.dbt_test__audit.<test_name>` so you can `psql` into them.
- Don't fix data issues in staging silently. If `stg_aw__customer` should never have nulls in `customer_id` and you find some, **let the test fail** — surface the bug, then decide whether to filter, fix at source, or accept.
- `(name)::text` is rarely needed — Postgres TEXT columns auto-coerce. Save explicit casts for `int`, `date`, `numeric`, `boolean`.
- Two-underscore separator (`stg_aw__customer`) is the dbt Labs naming convention. The double underscore makes the source-prefix vs entity-name boundary visually obvious.

## Common issues

| Symptom | Likely cause |
| ------- | ------------ |
| `Compilation Error: source 'adventureworks' not found` | The `_adventureworks__sources.yml` file isn't valid YAML, or you created it outside the `staging/` tree. |
| `relation "raw.customer" does not exist` | Bronze flow hasn't run yet (Task 1) — or it ran against `playground` instead of `analytics`. |
| `permission denied for schema staging` | You're connected as a non-superuser; the workshop default is `postgres` which has full rights. |
| Tests pass but show 0 rows | The model is empty — likely your bronze table is empty. `psql -d analytics -c "select count(*) from raw.<table>"` to confirm. |
| `dbt run` works on `playground` but fails on `analytics` | You forgot `--target analytics`. The default target is `playground`. |

## Next

→ [Task 3: Gold — Dimensional Model](03-gold-dimensional-model.md)
