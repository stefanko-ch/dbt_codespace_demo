-- Bronze tables for the AdventureWorks ingestion (Task 1).
-- Run from the Codespace terminal:
--   psql -d analytics -f tutorial/sql/01_create_bronze_tables.sql
--
-- Column order and types must match the SELECT projections in
-- flows/bronze_adventureworks.yml, since Kestra's Postgres CopyIn task
-- maps CSV columns onto table columns positionally.
-- Strings default to TEXT, numbers to NUMERIC, dates to TIMESTAMP.

CREATE SCHEMA IF NOT EXISTS raw;

DROP TABLE IF EXISTS raw.sales_order_header CASCADE;
CREATE TABLE raw.sales_order_header (
    sales_order_id        INTEGER PRIMARY KEY,
    revision_number       SMALLINT,
    order_date            TIMESTAMP,
    due_date              TIMESTAMP,
    ship_date             TIMESTAMP,
    status                SMALLINT,
    online_order_flag     BOOLEAN,
    sales_order_number    TEXT,
    purchase_order_number TEXT,
    account_number        TEXT,
    customer_id           INTEGER,
    sales_person_id       INTEGER,
    territory_id          INTEGER,
    bill_to_address_id    INTEGER,
    ship_to_address_id    INTEGER,
    ship_method_id        INTEGER,
    credit_card_id        INTEGER,
    currency_rate_id      INTEGER,
    sub_total             NUMERIC(19, 4),
    tax_amt               NUMERIC(19, 4),
    freight               NUMERIC(19, 4),
    total_due             NUMERIC(19, 4),
    comment               TEXT,
    modified_date         TIMESTAMP
);

DROP TABLE IF EXISTS raw.sales_order_detail CASCADE;
CREATE TABLE raw.sales_order_detail (
    sales_order_id          INTEGER,
    sales_order_detail_id   INTEGER,
    carrier_tracking_number TEXT,
    order_qty               SMALLINT,
    product_id              INTEGER,
    special_offer_id        INTEGER,
    unit_price              NUMERIC(19, 4),
    unit_price_discount     NUMERIC(19, 4),
    line_total              NUMERIC(38, 6),
    modified_date           TIMESTAMP,
    PRIMARY KEY (sales_order_id, sales_order_detail_id)
);

DROP TABLE IF EXISTS raw.customer CASCADE;
CREATE TABLE raw.customer (
    customer_id    INTEGER PRIMARY KEY,
    person_id      INTEGER,
    store_id       INTEGER,
    territory_id   INTEGER,
    account_number TEXT,
    modified_date  TIMESTAMP
);

DROP TABLE IF EXISTS raw.person CASCADE;
CREATE TABLE raw.person (
    business_entity_id INTEGER PRIMARY KEY,
    person_type        TEXT,
    name_style         BOOLEAN,
    title              TEXT,
    first_name         TEXT,
    middle_name        TEXT,
    last_name          TEXT,
    suffix             TEXT,
    email_promotion    INTEGER,
    modified_date      TIMESTAMP
);

DROP TABLE IF EXISTS raw.sales_territory CASCADE;
CREATE TABLE raw.sales_territory (
    territory_id        INTEGER PRIMARY KEY,
    name                TEXT,
    country_region_code TEXT,
    "group"             TEXT,
    sales_ytd           NUMERIC(19, 4),
    sales_last_year     NUMERIC(19, 4),
    cost_ytd            NUMERIC(19, 4),
    cost_last_year      NUMERIC(19, 4),
    modified_date       TIMESTAMP
);

DROP TABLE IF EXISTS raw.sales_person CASCADE;
CREATE TABLE raw.sales_person (
    business_entity_id INTEGER PRIMARY KEY,
    territory_id       INTEGER,
    sales_quota        NUMERIC(19, 4),
    bonus              NUMERIC(19, 4),
    commission_pct     NUMERIC(10, 4),
    sales_ytd          NUMERIC(19, 4),
    sales_last_year    NUMERIC(19, 4),
    modified_date      TIMESTAMP
);

DROP TABLE IF EXISTS raw.product CASCADE;
CREATE TABLE raw.product (
    product_id              INTEGER PRIMARY KEY,
    name                    TEXT,
    product_number          TEXT,
    make_flag               BOOLEAN,
    finished_goods_flag     BOOLEAN,
    color                   TEXT,
    safety_stock_level      SMALLINT,
    reorder_point           SMALLINT,
    standard_cost           NUMERIC(19, 4),
    list_price              NUMERIC(19, 4),
    size                    TEXT,
    size_unit_measure_code  TEXT,
    weight_unit_measure_code TEXT,
    weight                  NUMERIC(8, 2),
    days_to_manufacture     INTEGER,
    product_line            TEXT,
    class                   TEXT,
    style                   TEXT,
    product_subcategory_id  INTEGER,
    product_model_id        INTEGER,
    sell_start_date         TIMESTAMP,
    sell_end_date           TIMESTAMP,
    discontinued_date       TIMESTAMP,
    modified_date           TIMESTAMP
);

DROP TABLE IF EXISTS raw.product_subcategory CASCADE;
CREATE TABLE raw.product_subcategory (
    product_subcategory_id INTEGER PRIMARY KEY,
    product_category_id    INTEGER,
    name                   TEXT,
    modified_date          TIMESTAMP
);

DROP TABLE IF EXISTS raw.product_category CASCADE;
CREATE TABLE raw.product_category (
    product_category_id INTEGER PRIMARY KEY,
    name                TEXT,
    modified_date       TIMESTAMP
);
