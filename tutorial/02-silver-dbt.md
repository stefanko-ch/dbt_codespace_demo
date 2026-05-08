# Task 2 — Silver: Clean Staging Models with dbt

**Goal:** turn the raw bronze tables into clean, typed, well-named **staging views** that the dimensional model in Task 3 can rely on.

The staging layer is the place to:
- rename columns to consistent snake_case
- cast types where the source was lazy
- add light derived columns (e.g. `is_online`, `full_name`)
- filter out test/dummy rows if needed

We do **not** join, deduplicate hard, or change grain in staging. One source table → one `stg_*` view.

## Conventions

- One `stg_*` model per bronze table
- Materialization: **view** (cheap, always fresh)
- Schema: `staging` (already configured in `dbt_project.yml`)
- Run against the **`analytics`** target:
  ```bash
  cd dbt
  dbt run --target analytics --select staging
  ```
- File layout:
  ```
  dbt/models/staging/adventureworks/
    _adventureworks__sources.yml
    _adventureworks__models.yml
    stg_aw__sales_order_header.sql
    stg_aw__sales_order_detail.sql
    stg_aw__customer.sql
    stg_aw__person.sql
    stg_aw__sales_territory.sql
    stg_aw__sales_person.sql
    stg_aw__product.sql
    stg_aw__product_subcategory.sql
    stg_aw__product_category.sql
  ```
  The `aw` prefix marks the source system; helps when later projects ingest from elsewhere.

## Step 1 — Declare the sources

Create `dbt/models/staging/adventureworks/_adventureworks__sources.yml`:

```yaml
version: 2

sources:
  - name: adventureworks
    description: "Bronze tables ingested from Azure SQL AdventureWorks by n8n."
    database: analytics
    schema: raw
    tables:
      - name: sales_order_header
        loaded_at_field: modified_date
      - name: sales_order_detail
      - name: customer
      - name: person
      - name: sales_territory
      - name: sales_person
      - name: product
      - name: product_subcategory
      - name: product_category
```

This lets you write `{{ source('adventureworks', 'sales_order_header') }}` in models and run `dbt source freshness` later.

## Step 2 — Write each staging model

Pattern for every model:

```sql
-- stg_aw__sales_order_header.sql
with source as (
    select * from {{ source('adventureworks', 'sales_order_header') }}
)
select
    sales_order_id,
    customer_id,
    sales_person_id,
    territory_id,
    order_date::date          as order_date,
    due_date::date            as due_date,
    ship_date::date           as ship_date,
    online_order_flag         as is_online,
    sub_total                 as subtotal_amount,
    tax_amt                   as tax_amount,
    freight                   as freight_amount,
    total_due                 as total_amount,
    modified_date             as source_modified_at
from source
```

Suggested column projections per table:

| Table                      | Columns to keep / clean                                                                                            |
| -------------------------- | ------------------------------------------------------------------------------------------------------------------ |
| `stg_aw__sales_order_header` | `sales_order_id`, `customer_id`, `sales_person_id`, `territory_id`, dates as `date`, `is_online`, monetary amounts |
| `stg_aw__sales_order_detail` | `sales_order_id`, `sales_order_detail_id`, `product_id`, `order_qty`, `unit_price`, `unit_price_discount`, `line_total` |
| `stg_aw__customer`         | `customer_id`, `person_id`, `store_id`, `territory_id`, derived `customer_type` (`'individual'` if person_id not null else `'store'`) |
| `stg_aw__person`           | `person_id` (= business_entity_id), `first_name`, `last_name`, derived `full_name`, `email_promotion`              |
| `stg_aw__sales_territory`  | `territory_id`, `territory_name` (= name), `country_region_code`, `region_group` (= "group" — quoted in source)    |
| `stg_aw__sales_person`     | `sales_person_id` (= business_entity_id), `territory_id`, `sales_quota`, `commission_pct`                          |
| `stg_aw__product`          | `product_id`, `product_name`, `product_number`, `color`, `standard_cost`, `list_price`, `product_subcategory_id`, `sell_start_date`, `sell_end_date`, derived `is_active` (sell_end_date is null) |
| `stg_aw__product_subcategory` | `product_subcategory_id`, `product_category_id`, `subcategory_name`                                            |
| `stg_aw__product_category` | `product_category_id`, `category_name`                                                                             |

## Step 3 — Add tests

Create `dbt/models/staging/adventureworks/_adventureworks__models.yml`:

```yaml
version: 2

models:
  - name: stg_aw__sales_order_header
    columns:
      - name: sales_order_id
        tests: [unique, not_null]
      - name: customer_id
        tests: [not_null]

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

  - name: stg_aw__customer
    columns:
      - name: customer_id
        tests: [unique, not_null]

  - name: stg_aw__person
    columns:
      - name: person_id
        tests: [unique, not_null]

  - name: stg_aw__product
    columns:
      - name: product_id
        tests: [unique, not_null]

  - name: stg_aw__product_subcategory
    columns:
      - name: product_subcategory_id
        tests: [unique, not_null]

  - name: stg_aw__product_category
    columns:
      - name: product_category_id
        tests: [unique, not_null]

  - name: stg_aw__sales_territory
    columns:
      - name: territory_id
        tests: [unique, not_null]

  - name: stg_aw__sales_person
    columns:
      - name: sales_person_id
        tests: [unique, not_null]
```

## Acceptance check

```bash
cd dbt
dbt run --target analytics --select staging
dbt test --target analytics --select staging
```

Both commands should finish green. Verify the views exist:

```bash
psql -d analytics -c "\dv staging.*"
```

You should see all nine `stg_aw__*` views.

## Hints

- If a column is `NULL`-heavy in the source, document it in the YAML rather than discarding the row.
- `(name)::text` is rarely needed — Postgres auto-coerces TEXT columns. Save casting for `int`, `date`, `numeric`.
- If you find a quality issue (e.g. `unit_price = 0` rows), don't fix it here. Add a `dbt_utils.expression_is_true` test and decide what to do in the gold layer.
- Hot reload while iterating: `dbt run --target analytics --select stg_aw__product+` (the `+` runs downstream too).

## Next

→ [Task 3: Gold — Dimensional Model](03-gold-dimensional-model.md)
