# dbt Solution — Walkthrough & Rationale

> Companion document to [tutorial 02 (Silver)](02-silver-dbt.md) and [tutorial 03 (Gold)](03-gold-dimensional-model.md).
>
> The two tutorials tell you **how to type each step**. This document explains **why each decision was made** — the conventions, the materialization choices, the test design, the build order — so you can defend the work in a code review and re-apply the same patterns to a different domain.

## 1. Project layout — and why it looks this way

```
dbt/
├── dbt_project.yml          # project config: model paths + materialization defaults
├── packages.yml             # external dbt packages (dbt-utils)
├── profiles.yml             # connection targets (playground / analytics / duckdb)
├── pyproject.toml           # uv-managed Python deps
├── tests/                   # singular (custom SQL) tests
└── models/
    ├── staging/
    │   ├── stg_books.sql    # library warm-up; ignored by the AW pipeline
    │   ├── stg_loans.sql
    │   ├── stg_members.sql
    │   ├── schema.yml
    │   └── adventureworks/                   # the AW pipeline lives here
    │       ├── _adventureworks__sources.yml
    │       ├── _adventureworks__models.yml
    │       ├── _adventureworks__docs.md
    │       └── stg_aw__*.sql                 # 9 staging views
    └── marts/
        ├── book_popularity.sql               # library warm-up
        ├── member_activity.sql
        ├── schema.yml
        └── adventureworks/                   # 5 dims + 1 fact
            ├── _adventureworks_marts__models.yml
            ├── _adventureworks_marts__docs.md
            ├── dim_*.sql
            └── fact_sales.sql
```

A few decisions baked in:

- **Subfolder per source system** (`adventureworks/`). The library warm-up sits next to the AW models without polluting it. When a second source arrives later (Salesforce, GA, …) it gets `models/staging/salesforce/` and the existing models are unaffected.
- **`stg_aw__` prefix** with double underscore. The first segment names the source (`aw` = AdventureWorks); the second segment is the entity. The double underscore makes the boundary visually obvious in long filenames. This is the dbt Labs naming convention.
- **YAML files prefixed with `_`** so they sort to the top of the folder in any file browser. Using underscore-prefix instead of arbitrary names makes the project layout discoverable.
- **Materialization defaults set in `dbt_project.yml`**, not per-file: `staging/* → view`, `marts/* → table`. New models inherit the right behaviour from their folder. Per-model `{{ config(...) }}` is reserved for exceptions (e.g. `dim_date` and `fact_sales` re-state `materialized='table'` defensively, since they're large enough to never want a view).

## 2. Sources — the contract with the bronze layer

[`_adventureworks__sources.yml`](../dbt/models/staging/adventureworks/_adventureworks__sources.yml) declares every `raw.*` table to dbt:

```yaml
sources:
  - name: adventureworks
    database: analytics
    schema: raw
    loaded_at_field: modified_date
    freshness:
      warn_after:  { count: 24, period: hour }
      error_after: { count: 72, period: hour }
    tables:
      - name: customer
        columns:
          - name: customer_id
            tests: [unique, not_null]
      ...
```

Why bother declaring sources at all? Three concrete payoffs:

1. **`{{ source('adventureworks', 'customer') }}`** in models is rewritten by dbt to the fully-qualified `analytics.raw.customer`. If the bronze schema ever moves (different DB, renamed schema, new prefix), one YAML edit fixes every model that references it.
2. **`dbt source freshness --target analytics`** uses the `loaded_at_field` and `freshness` block to flag stale data. If Kestra hasn't refreshed `raw.*` in 24 hours, you get a warning; after 72 hours, an error. This is the cheapest possible "is the pipeline alive?" monitor.
3. **Source-level tests** (e.g. `unique` on `customer_id`) catch bad data **at the bronze edge** before any downstream model can compound the bug. We declare them on the most critical natural keys; everything else is tested at the staging level.

## 3. Staging — one model per source table, view-materialised

Every staging model follows the same pattern:

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

The CTE structure (`source` → optional intermediate steps → final `select`) keeps each transformation visible and reviewable. It also makes incremental fixes easy: a column rename only touches the `renamed` block; a derivation only touches its own CTE.

### What staging IS for

- **Snake_case column names** (e.g. `BusinessEntityID` → `person_id`).
- **Type casting** where the source got it wrong: `datetime` columns that always contain a date become `date` (see `stg_aw__sales_order_header`'s `order_date::date`).
- **Light derivations** that every downstream model would otherwise duplicate:
  - `customer_type` ('individual' vs 'store')
  - `full_name = trim(concat_ws(' ', first_name, middle_name, last_name))`
  - `is_active = (sell_end_date is null and discontinued_date is null)`
  - `status_name` decoding the cryptic `Status` int into 'in process' / 'shipped' / etc.
- **Reserved-keyword aliasing**: `Sales.SalesTerritory.Group` was already aliased to `group_name` in bronze (Postgres reserves `group`); staging keeps the safe name.
- **Dropping noise**: `rowguid`, internal XML blobs, anything that no model will ever read.

### What staging is NOT for

- **Joins** between tables. The grain of `stg_aw__customer` is one row per customer; joining `stg_aw__person` would change that. Joining belongs in marts where the grain change is explicit.
- **Aggregations**. Same reason.
- **Business logic** — *"a sale is 'big' when amount > 1000"* belongs in marts because it's a downstream interpretation, not a structural cleanup.
- **Hard deduplication** on dirty rows. If you find duplicates in source, surface them via tests and decide upstream whether to filter or fix; don't silently swallow them.

### View materialization — why?

The whole staging layer rebuilds in seconds because views don't store data — they're just compiled SQL on top of `raw.*`. Two consequences:

- **Always reflects bronze.** No "did dbt run yet?" question; the moment Kestra refreshes raw, staging is current.
- **Safe to iterate.** Tweaking a column derivation and re-running is free, so there's no friction during development.

The cost — every downstream query re-executes the view — is only paid once per query, and Postgres' query planner inlines the view, so the overhead is essentially zero.

## 4. Tests — three layers, three jobs

```
                                                                      Cost
                                                                     ─────►
generic              dbt-utils                  singular
(unique, not_null,   (expression_is_true,        (custom SQL,
 accepted_values,     unique_combination_of_     anything that
 relationships)       columns, equality)          compiles to a query
                                                  returning failing
                                                  rows)
```

A test passes when its compiled query returns **zero rows**. That's the entire contract.

### Generic tests — declare in YAML, free

Most tests are one-liners in [`_adventureworks__models.yml`](../dbt/models/staging/adventureworks/_adventureworks__models.yml). They cover the boring-but-critical invariants:

```yaml
- name: customer_id
  tests:
    - unique
    - not_null
- name: customer_type
  tests:
    - accepted_values:
        values: ['individual', 'store', 'unknown']
- name: territory_id
  tests:
    - relationships:
        to: ref('stg_aw__sales_territory')
        field: territory_id
        where: "territory_id is not null"
```

The `where` clause on `relationships` is essential when the FK is genuinely nullable — without it, every row with `NULL territory_id` would fail the test. We use it for `sales_person_id`, `territory_id`, and `product_subcategory_id`.

### dbt-utils tests — generic with a parameter

For business rules, plain generic tests aren't enough. `dbt_utils.expression_is_true` lets you assert any boolean SQL expression on a column or model:

```yaml
- name: list_price
  tests:
    - dbt_utils.expression_is_true:
        expression: ">= 0"     # no negative prices
- name: commission_pct
  tests:
    - dbt_utils.expression_is_true:
        expression: ">= 0 and commission_pct <= 1"
```

`dbt_utils.unique_combination_of_columns` enforces composite uniqueness — used on `fact_sales (sales_order_id, sales_order_detail_id)` since neither column alone is unique on the line-item grain.

### Singular tests — when generic doesn't fit

A singular test is just a SQL file under [`tests/`](../dbt/tests/) that compiles to a query returning failing rows. We have two:

#### `assert_order_total_matches_lines.sql`

```sql
with line_totals as (
    select sales_order_id, sum(line_total) as lines_sum
    from {{ ref('stg_aw__sales_order_detail') }}
    group by sales_order_id
),
header_totals as (
    select sales_order_id, subtotal_amount
    from {{ ref('stg_aw__sales_order_header') }}
)
select
    h.sales_order_id, h.subtotal_amount, l.lines_sum,
    abs(h.subtotal_amount - l.lines_sum) as diff
from header_totals h
join line_totals l using (sales_order_id)
where abs(h.subtotal_amount - l.lines_sum) > 0.01
```

**What it catches:** the order header carries `SubTotal` (sum of all line items, computed by the source system); the order detail carries the individual `LineTotal`s. If they ever drift apart by more than a cent, something is wrong — either the source system has bad data, the bronze ingest dropped lines, or staging filtered something it shouldn't have.

**Why singular?** No generic test combines two models with a per-key aggregation comparison. This invariant is a statement about a *relationship* between two tables, not a property of a single column.

**Why ε = 0.01?** Floating-point money arithmetic introduces sub-cent rounding. AdventureWorks stores `money` (4 decimals) and `numeric(38,6)` for line totals — small drift is inherent, real bugs produce dollar-level deltas.

#### `assert_fact_sales_subtotal_consistency.sql`

The same invariant applied one layer up: per-order sum of `fact_sales.net_amount` should match the header's `subtotal_amount`. Catches breakage introduced by the join in `fact_sales` itself — e.g. if the inner join silently dropped lines because their parent header was filtered, this test fails.

We deliberately keep both: the staging test catches issues from bronze; the marts test catches issues introduced by our own modeling. They form a *belt and suspenders* pair.

## 5. Marts — Kimball star schema

Five dimensions and one fact, all in `analytics.marts.*`:

```
        dim_date
            ▲
            │
dim_customer ───► fact_sales ◄─── dim_product
                    ▲
                    │
       dim_sales_territory   dim_sales_person
```

### Grain choice — line-item, not header

The first decision in any fact-table design is *what does one row mean?* For `Sales.SalesOrderDetail` we picked **one row per `(sales_order_id, sales_order_detail_id)`**, i.e. the line-item grain. Trade-offs we considered:

| Grain | What you can ask | What you lose |
|---|---|---|
| Header (one row per order) | Order count, total revenue per customer | Can't answer per-product questions |
| **Line item** | All product-level questions, plus everything header could answer (with `count(distinct sales_order_id)`) | Header-only attributes (status, freight) repeat per line — costs storage, not analysis |
| Daily aggregate | Lightning-fast aggregate queries | Loses customer + product detail entirely |

Once chosen, **the grain is sacred**: every measure on `fact_sales` must make sense at the line grain. `order_qty` does. `unit_price * order_qty` does. `freight_amount` does *not* — it's a header-level value that would double-count if summed across lines. So we don't put it on `fact_sales`; if a future report needs it, that's a new fact table at header grain.

### Surrogate keys — and why we don't expose natural keys

Every dim has a surrogate `*_key` generated via `dbt_utils.generate_surrogate_key`:

```sql
{{ dbt_utils.generate_surrogate_key(['customer_id']) }} as customer_key
```

Under the hood that's `md5(coalesce(cast(customer_id as varchar), '_dbt_utils_surrogate_key_null_'))` — a 32-character hex string.

Why bother instead of just joining on the natural `customer_id`?

1. **Single-column joins regardless of source key shape.** When the source has a composite natural key (or a UUID, or a string), the surrogate is always a single varchar. Joins stay simple.
2. **Decouples from source key strategy.** If AdventureWorks ever re-IDs customers (merger, deduplication, …) the surrogate hash changes for affected rows but the surrounding architecture is unaffected.
3. **Easier to add SCD type 2 later.** With a surrogate, history can have multiple rows per natural key, each with its own surrogate — the fact joins to the right historical snapshot via the surrogate.

The natural `customer_id` is kept on the dim as a column ("degenerate" in the dim itself, but useful for traceability when a number looks weird).

### Degenerate dimensions on the fact

`sales_order_id`, `sales_order_detail_id`, `sales_order_number`, `order_status`, `is_online` live directly on `fact_sales` rather than as their own tiny dimension tables. Two reasons:

- Cardinality: an order ID is essentially unique per fact row — there's no value in extracting it.
- Filterability: BI users want to filter "show me cancelled orders" without joining a `dim_order_status`. Carrying `order_status` on the fact makes that one click in Metabase instead of a JOIN.

## 5b. The six marts in detail

For each model: what it represents, its grain, where the data comes from, and the design decisions that aren't obvious from the SQL.

### `dim_date` — the calendar

[`dim_date.sql`](../dbt/models/marts/adventureworks/dim_date.sql)

- **Grain:** one row per day, 2010-01-01 → 2030-12-31 (~7 670 rows).
- **Source:** none — fully generated from `dbt_utils.date_spine`. No staging dependency, which is why it's the easiest place to start the build.
- **Surrogate key:** `date_key = md5(date_actual)` where `date_actual` is the calendar date.

What's in it:

| Column | Why |
|---|---|
| `date_actual` | The date itself — also a unique key, useful for joining when you have the date but not the surrogate. |
| `year`, `quarter`, `month`, `month_name` | Pre-computed parts so BI users don't repeat `EXTRACT(...)` in every report. |
| `day_of_month`, `day_of_week`, `day_name`, `iso_week` | Same idea — let dimensional model do the work once. |
| `is_weekend`, `is_quarter_start`, `is_month_end` | Boolean flags for common BI filters. *"Sales last quarter"* becomes `where dim_date.is_quarter_start` plus a year filter. |

Decisions baked in:

- **Range generous** (21 years). `date_spine` is cheap to extend later but extending means rebuilding the dim **and** every fact join — better to go wide once.
- **`spine_as_date` CTE** casts `date_day::date` before generating the surrogate key. `date_spine` returns timestamps in Postgres (because `generate_series` does); without the cast, the hash didn't match `fact_sales.date_key` (which hashes `order_date::date`). See section 6.3.
- **`materialized='table'`** explicit — even though the folder default is already table, this dim is large and joined-against often, so we restate it defensively.

### `dim_customer` — individuals + stores

[`dim_customer.sql`](../dbt/models/marts/adventureworks/dim_customer.sql)

- **Grain:** one row per customer (~19 820 rows).
- **Source:** `stg_aw__customer` LEFT JOIN `stg_aw__person`.
- **Surrogate key:** `customer_key = md5(customer_id)`.

The trick here is that `Sales.Customer` in AdventureWorks mixes two kinds of customer:

- **Individuals** — have `person_id`, no `store_id`. Their name comes from `Person.Person`.
- **Stores** — have `store_id`, no `person_id`. They have no person record; their `customer_name` is genuinely NULL.

The LEFT JOIN to `stg_aw__person` picks up the name when it exists and leaves it NULL otherwise. The derived `customer_type` (already computed in staging) preserves the distinction:

```sql
case
    when person_id is not null then 'individual'
    when store_id  is not null then 'store'
    else 'unknown'
end as customer_type
```

So a BI user filtering `customer_type = 'individual'` sees only people; filtering `'store'` sees only B2B accounts. The `customer_id` natural key is kept on the dim for traceability when investigating odd numbers.

### `dim_product` — flattened hierarchy

[`dim_product.sql`](../dbt/models/marts/adventureworks/dim_product.sql)

- **Grain:** one row per product (504 rows).
- **Source:** `stg_aw__product` LEFT JOIN `stg_aw__product_subcategory` LEFT JOIN `stg_aw__product_category`.
- **Surrogate key:** `product_key = md5(product_id)`.

This is the textbook **denormalize-for-BI** move. The source has a 3-level hierarchy:

```
product → product_subcategory → product_category
```

In an OLTP schema, you keep it normalised so a category rename hits one row. In a BI schema, you flatten it: every product row carries `subcategory_name`, `product_category_id`, **and** `category_name` directly. Result: a Metabase user dragging "Category" gets one column, no JOIN dialog.

LEFT JOINs are deliberate — a product can have no subcategory (`product_subcategory_id IS NULL`), and we keep those rows with NULL category fields rather than dropping them. Loss of data is worse than NULL category cells.

`is_active` is carried over from staging where it was derived as `(sell_end_date is null and discontinued_date is null)`. A common BI filter — "active products only" — becomes one click.

### `dim_sales_territory` — the small dim

[`dim_sales_territory.sql`](../dbt/models/marts/adventureworks/dim_sales_territory.sql)

- **Grain:** one row per territory (10 rows).
- **Source:** `stg_aw__sales_territory` only — no joins.
- **Surrogate key:** `territory_key = md5(territory_id)`.

Almost trivial: rename, hash, done. The only thing worth pointing out is that `region_group` (e.g. "North America", "Europe", "Pacific") originates from MSSQL's reserved-word column `[Group]` — bronze aliased it to `group_name`, staging renamed it again to `region_group` (clearer semantic). Three separate names for the same concept along the pipeline is a minor smell, but each rename had a reason: bronze couldn't use `group` (Postgres reserved), staging chose a more descriptive name.

### `dim_sales_person` — internal reps

[`dim_sales_person.sql`](../dbt/models/marts/adventureworks/dim_sales_person.sql)

- **Grain:** one row per sales rep (17 rows).
- **Source:** `stg_aw__sales_person` LEFT JOIN `stg_aw__person`.
- **Surrogate key:** `sales_person_key = md5(sales_person_id)`.

Same join pattern as `dim_customer` but smaller: the `sales_person_id` is the same `business_entity_id` used for personhood. In AdventureWorks every salesperson is also a person, so an INNER JOIN would also work — but **always LEFT-JOIN dimension lookups** unless you have a positive reason. If a salesperson record is later created without a corresponding person row (data-cleanup error, tooling bug), an INNER JOIN silently drops them; a LEFT JOIN surfaces the gap as NULL `sales_person_name`, which a `not_null` test would then catch.

`territory_id` is carried as a column for direct filtering. The corresponding `territory_key` lives only on `fact_sales` — that's intentional: a salesperson's territory can change (and AdventureWorks `Sales.SalesPerson` only stores the *current* one), so analytical questions about "sales per territory" should go through the fact's `territory_key`, not the dim's.

### `fact_sales` — the heart

[`fact_sales.sql`](../dbt/models/marts/adventureworks/fact_sales.sql)

- **Grain:** one row per order line item (~121 317 rows).
- **Source:** `stg_aw__sales_order_detail` INNER JOIN `stg_aw__sales_order_header` USING (sales_order_id).
- **Composite natural key:** `(sales_order_id, sales_order_detail_id)` — enforced by the `dbt_utils.unique_combination_of_columns` test.

#### Why INNER JOIN?

A line item without a header is a referential-integrity bug. We `INNER JOIN` so any orphan lines are dropped from the fact — but the row count drop is then visible (the singular test `assert_fact_sales_subtotal_consistency` would also catch it via missing per-order totals). If we LEFT JOINed, orphan lines would survive with NULL header attributes and corrupt aggregations.

In a stricter shop you'd surface the orphans as a separate test that fails noisily. The current approach trusts the source's referential integrity since AdventureWorks is a well-formed sample.

#### Five surrogate FKs, two of them nullable

```sql
{{ dbt_utils.generate_surrogate_key(['j.order_date']) }}      as date_key,
{{ dbt_utils.generate_surrogate_key(['j.customer_id']) }}     as customer_key,
{{ dbt_utils.generate_surrogate_key(['j.product_id']) }}      as product_key,
case when j.territory_id is not null
     then {{ dbt_utils.generate_surrogate_key(['j.territory_id']) }} end
                                                              as territory_key,
case when j.sales_person_id is not null
     then {{ dbt_utils.generate_surrogate_key(['j.sales_person_id']) }} end
                                                              as sales_person_key,
```

Note the `case when ... is not null` wrappers on `territory_key` and `sales_person_key`. Online orders genuinely have no salesperson and sometimes no territory; **we want NULL keys, not a sentinel hash that points nowhere**. See section 6.3 for the full story.

`date_key`, `customer_key`, `product_key` are required (always non-null in source); they get unconditional surrogates plus a `not_null` test in the YAML.

#### Three categories of column

| Category | Examples | Why on the fact |
|---|---|---|
| **Surrogate FKs** | `customer_key`, `product_key`, `date_key`, `territory_key`, `sales_person_key` | The whole point — joins to the dims happen here. |
| **Degenerate dims** | `sales_order_id`, `sales_order_detail_id`, `sales_order_number`, `order_status`, `is_online` | Filterable directly without an extra JOIN. Especially `order_status` — "show me only shipped orders" is the most common ad-hoc filter. |
| **Measures** | `order_qty`, `unit_price`, `unit_price_discount`, `line_total`, `gross_amount`, `discount_amount`, `net_amount` | Numbers you sum, average, and aggregate. All additive at line grain. |

#### Derived measures

```sql
j.unit_price * j.order_qty                          as gross_amount,
j.unit_price * j.order_qty * j.unit_price_discount  as discount_amount,
j.line_total                                        as net_amount
```

`line_total` is what the source system already calculated; we expose it as `net_amount` because that's the more conventional name in BI tools. `gross_amount` and `discount_amount` are derived so a BI user can answer "what's our total list-price revenue before discounts?" without writing the multiplication. Pre-computing them in the fact also means every dashboard agrees on the formula — there's no "team A multiplies, team B doesn't" drift.

## 6. Why dimensions are built **before** facts

Two reasons — one structural (dbt enforces it for you), one semantic (it would still be the right call even if dbt didn't).

### 6.1 Structural: the DAG forces it

Every model is a node; every `{{ ref('other_model') }}` is an edge. dbt assembles a Directed Acyclic Graph and runs models in **topological order** — every dependency before its dependents.

`fact_sales` references all five dimensions:

```sql
{{ dbt_utils.generate_surrogate_key(['j.customer_id']) }} as customer_key,
{{ dbt_utils.generate_surrogate_key(['j.product_id']) }}  as product_key,
...
```

Plus the YAML test block adds:

```yaml
- name: customer_key
  tests:
    - relationships: { to: ref('dim_customer'), field: customer_key }
```

Each `ref()` is an explicit edge from `fact_sales` → `dim_customer`. dbt notices: *fact depends on dim → build dim first*. You can't accidentally reverse this with `dbt build`; the order is computed, not chosen.

### 6.2 Semantic: the relationships tests need a target

Even if you forced fact-first, the `relationships` test on `fact_sales.customer_key → dim_customer.customer_key` would fail until `dim_customer` exists with at least one matching row. So:

- Dim built first → its rows define the **canonical set of valid keys**.
- Fact built second → its `*_key` columns are validated *against* that set.

If a fact row's `customer_key` doesn't appear in `dim_customer`, that's a real referential-integrity bug — usually meaning the fact has a customer the dim doesn't (filtered too aggressively, or the source has orphan FKs). The test should fail loudly.

### 6.3 The trap when surrogate-key inputs disagree

We hit this during the build: `fact_sales.date_key` was using `md5('2010-01-01 00:00:00')` while `dim_date.date_key` was `md5('2010-01-01')` — same logical date, different hashes, **100% of fact rows had no matching dim row** even though the data was correct.

Root cause: `dbt_utils.date_spine` returns `date_day` as a **timestamp** in Postgres (because `generate_series` always returns timestamps), but `stg_aw__sales_order_header` casts `order_date` to **date**. The hash is `md5(cast(... as varchar))`, and a timestamp casts to `'2010-01-01 00:00:00'` while a date casts to `'2010-01-01'`.

Fix: cast `date_day` to `date` inside `dim_date` before generating the surrogate key. The lesson: **surrogate keys only match if the hash inputs are the exact same string**. Both sides must agree on type *and* format.

A second related trap: `generate_surrogate_key` does **not** produce NULL when the input is NULL. It produces `md5('_dbt_utils_surrogate_key_null_')` — a fixed sentinel hash. For `fact_sales.sales_person_key` (online orders have NULL `sales_person_id`), this means every online line item generated a non-null hash that didn't exist in `dim_sales_person`. Fix: wrap the surrogate-key call in `case when sales_person_id is not null then ... end` so genuine NULLs stay NULL, and add `where sales_person_key is not null` to the relationships test so they're skipped.

### 6.4 Build-from-scratch recipe

```bash
cd dbt
dbt deps                              # install dbt-utils once
dbt build --target analytics          # full DAG: dims → fact, tests after each
```

`dbt build` is the right command because it runs both **models** and their **tests** in one pass, in dependency order, stopping at the first failure. Compare:

- `dbt run` → only builds models, doesn't test
- `dbt test` → only tests, doesn't build
- `dbt build` → both, interleaved correctly

For partial rebuilds during development:

```bash
dbt build --target analytics --select fact_sales+      # this model and everything downstream
dbt build --target analytics --select +fact_sales      # this model and everything upstream
dbt build --target analytics --select staging marts    # by folder
```

## 7. Acceptance — what "done" looks like

After a clean build:

```bash
psql -d analytics -c "
SELECT
  (SELECT count(*) FROM marts.fact_sales)              AS fact_rows,
  (SELECT count(*) FROM marts.dim_customer)            AS dim_customer,
  (SELECT count(*) FROM marts.dim_product)             AS dim_product,
  (SELECT count(*) FROM marts.dim_sales_person)        AS dim_sales_person,
  (SELECT count(*) FROM marts.dim_sales_territory)     AS dim_sales_territory,
  (SELECT count(*) FROM marts.dim_date)                AS dim_date;
"
```

| metric | expected |
|---|---|
| `fact_rows` | ~121 317 |
| `dim_customer` | ~19 820 |
| `dim_product` | 504 |
| `dim_sales_person` | 17 |
| `dim_sales_territory` | 10 |
| `dim_date` | ~7 670 |

`dbt build --target analytics --select staging marts` finishes green — that's the production-style command a CI/CD pipeline would run.

## 8. dbt-utils — what we actually use

`dbt-utils` is the only external package; everything we lean on:

| Macro / test | Where used | What it gives us |
|---|---|---|
| `generate_surrogate_key` | every `dim_*` + `fact_sales` | MD5 hash of business key as a single column |
| `date_spine` | `dim_date` | date series between two boundaries |
| `expression_is_true` | staging + marts YAML | parameterized boolean assertion test |
| `unique_combination_of_columns` | `fact_sales` model-level test | composite uniqueness |

Pinned in [`packages.yml`](../dbt/packages.yml):

```yaml
packages:
  - package: dbt-labs/dbt_utils
    version: [">=1.1.0", "<2.0.0"]
```

The version pin is important: dbt-utils has had breaking macro signature changes in major versions. `[">=1.1.0", "<2.0.0"]` accepts patch + minor updates within v1.x but blocks accidental v2 upgrades.

## 9. Patterns to take away

Five things from this build that generalise to any dbt project:

1. **One source table → one staging model.** No exceptions. If you need to combine, do it in marts where the new grain is explicit.
2. **Test source columns at the bronze edge** for the most critical natural keys. Catch bad data before it propagates.
3. **Use `dbt build`, not `dbt run` then `dbt test`** — interleaving means a failed test stops dependent models from building on bad data.
4. **Surrogate keys must hash identical inputs on both sides of the join.** Type and NULL behaviour are the two traps.
5. **Build dimensions before facts** — dbt enforces it via the DAG, but the *reason* is that dims define the canonical set of valid keys against which the fact is validated.

## 10. Where to next

- [Tutorial 04: Analyze in Metabase](04-metabase.md) — connect Metabase to `analytics`, model the marts, build dashboards
- [dbt's docs on tests](https://docs.getdbt.com/docs/build/data-tests) — the official taxonomy, including SCD-2 specific tests
- [The Kimball Group's design tip archive](https://www.kimballgroup.com/category/data-warehouse-business-intelligence-resources/design-tips/) — 30 years of dimensional-modeling judgment, condensed
