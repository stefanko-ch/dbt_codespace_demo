# Task 1 — Bronze: Ingest AdventureWorks with n8n

**Goal:** copy nine tables from Azure SQL (AdventureWorks) into the `analytics.raw.*` schema of your local Postgres, 1:1 — no transformations.

This is the bronze layer. We don't clean, rename, or filter here. We just land the data so downstream tools (dbt) can take over.

## What you'll build

One n8n workflow with one branch per source table:

```
[Manual Trigger] ──┬──► [MSSQL: Sales.SalesOrderHeader]    ──► [Postgres: raw.sales_order_header]
                   ├──► [MSSQL: Sales.SalesOrderDetail]    ──► [Postgres: raw.sales_order_detail]
                   ├──► [MSSQL: Sales.Customer]            ──► [Postgres: raw.customer]
                   ├──► [MSSQL: Person.Person]             ──► [Postgres: raw.person]
                   ├──► [MSSQL: Sales.SalesTerritory]      ──► [Postgres: raw.sales_territory]
                   ├──► [MSSQL: Sales.SalesPerson]         ──► [Postgres: raw.sales_person]
                   ├──► [MSSQL: Production.Product]        ──► [Postgres: raw.product]
                   ├──► [MSSQL: Production.ProductSubcategory] ──► [Postgres: raw.product_subcategory]
                   └──► [MSSQL: Production.ProductCategory] ──► [Postgres: raw.product_category]
```

## Tables and queries

| # | Source (Azure SQL)              | Bronze table (Postgres `analytics.raw`) |
| - | ------------------------------- | --------------------------------------- |
| 1 | `Sales.SalesOrderHeader`        | `sales_order_header`                    |
| 2 | `Sales.SalesOrderDetail`        | `sales_order_detail`                    |
| 3 | `Sales.Customer`                | `customer`                              |
| 4 | `Person.Person`                 | `person`                                |
| 5 | `Sales.SalesTerritory`          | `sales_territory`                       |
| 6 | `Sales.SalesPerson`             | `sales_person`                          |
| 7 | `Production.Product`            | `product`                               |
| 8 | `Production.ProductSubcategory` | `product_subcategory`                   |
| 9 | `Production.ProductCategory`    | `product_category`                      |

The `SELECT` queries below pick the columns we need for the dimensional model in tasks 2–3. They drop heavy/uninteresting columns (XML demographics, photos, rowguid, etc.).

### 1. Sales.SalesOrderHeader

```sql
SELECT
    SalesOrderID, RevisionNumber, OrderDate, DueDate, ShipDate,
    Status, OnlineOrderFlag, SalesOrderNumber, PurchaseOrderNumber,
    AccountNumber, CustomerID, SalesPersonID, TerritoryID, BillToAddressID,
    ShipToAddressID, ShipMethodID, CreditCardID, CurrencyRateID,
    SubTotal, TaxAmt, Freight, TotalDue, Comment, ModifiedDate
FROM Sales.SalesOrderHeader;
```

### 2. Sales.SalesOrderDetail

```sql
SELECT
    SalesOrderID, SalesOrderDetailID, CarrierTrackingNumber,
    OrderQty, ProductID, SpecialOfferID, UnitPrice, UnitPriceDiscount,
    LineTotal, ModifiedDate
FROM Sales.SalesOrderDetail;
```

### 3. Sales.Customer

```sql
SELECT
    CustomerID, PersonID, StoreID, TerritoryID, AccountNumber, ModifiedDate
FROM Sales.Customer;
```

### 4. Person.Person

```sql
SELECT
    BusinessEntityID, PersonType, NameStyle, Title, FirstName, MiddleName,
    LastName, Suffix, EmailPromotion, ModifiedDate
FROM Person.Person;
```

### 5. Sales.SalesTerritory

```sql
SELECT
    TerritoryID, Name, CountryRegionCode, [Group], SalesYTD, SalesLastYear,
    CostYTD, CostLastYear, ModifiedDate
FROM Sales.SalesTerritory;
```

### 6. Sales.SalesPerson

```sql
SELECT
    BusinessEntityID, TerritoryID, SalesQuota, Bonus, CommissionPct,
    SalesYTD, SalesLastYear, ModifiedDate
FROM Sales.SalesPerson;
```

### 7. Production.Product

```sql
SELECT
    ProductID, Name, ProductNumber, MakeFlag, FinishedGoodsFlag, Color,
    SafetyStockLevel, ReorderPoint, StandardCost, ListPrice, Size,
    SizeUnitMeasureCode, WeightUnitMeasureCode, Weight, DaysToManufacture,
    ProductLine, Class, Style, ProductSubcategoryID, ProductModelID,
    SellStartDate, SellEndDate, DiscontinuedDate, ModifiedDate
FROM Production.Product;
```

### 8. Production.ProductSubcategory

```sql
SELECT
    ProductSubcategoryID, ProductCategoryID, Name, ModifiedDate
FROM Production.ProductSubcategory;
```

### 9. Production.ProductCategory

```sql
SELECT
    ProductCategoryID, Name, ModifiedDate
FROM Production.ProductCategory;
```

## Step-by-step in n8n

You'll set this up once, then duplicate the pattern for each table.

### A. Create the credentials (one time)

**Microsoft SQL credential**

In n8n, **Credentials → New → Microsoft SQL**, switch each field to **Expression** and paste:

| Field    | Value                                  |
| -------- | -------------------------------------- |
| Server   | `={{ $env.AZURE_SQL_HOST }}`           |
| Database | `={{ $env.AZURE_SQL_DATABASE }}`       |
| User     | `={{ $env.AZURE_SQL_USER }}`           |
| Password | `={{ $env.AZURE_SQL_PASSWORD }}`       |
| Port     | `1433` (Fixed)                         |

In the **Details** tab: enable **TLS / Encrypt**, leave **Trust Server Certificate** off. Save and confirm "Connection tested successfully".

**Postgres credential**

**Credentials → New → Postgres**:

| Field    | Value        |
| -------- | ------------ |
| Host     | `postgres`   |
| Database | `analytics`  |
| User     | `postgres`   |
| Password | `postgres`   |
| Port     | `5432`       |
| SSL      | `disable`    |

### B. Build the workflow

1. **Workflows → New** → name it `bronze_adventureworks`.
2. Add a **Manual Trigger** node — this lets you run the whole workflow on demand.
3. For **each** of the nine tables, add this pair of nodes after the trigger:

   **Microsoft SQL node**
   - Operation: **Execute a SQL query**
   - Credential: the one you just created
   - Query: paste the corresponding `SELECT` from the section above
   - Rename the node to the source table (e.g. `mssql_sales_order_header`) so the canvas stays readable

   **Postgres node**
   - Operation: **Insert rows in database**
   - Credential: the Postgres credential
   - Schema: `raw`
   - Table: the bronze table name (e.g. `sales_order_header`)
   - **Map Automatically** the input columns to table columns
   - Options → **Skip on Conflict** = on (helps if you re-run)
   - Rename the node to `pg_<table_name>`

4. **Connect them in pairs**: Manual Trigger → MSSQL node → Postgres node. Each table is its own branch fanning out from the trigger.

### C. Pre-create the bronze tables

n8n's Postgres "Insert rows" node does NOT create the table — it expects it to exist. Easiest way: let dbt create them as **sources**.

Wait — for **bronze ingestion** we want the tables to exist *before* dbt runs. So create them upfront:

In the Codespace terminal:

```bash
psql -d analytics -f tutorial/sql/01_create_bronze_tables.sql
```

> A ready-to-use `01_create_bronze_tables.sql` file lives at [`tutorial/sql/01_create_bronze_tables.sql`](sql/01_create_bronze_tables.sql) — it creates all nine empty tables in the `raw` schema with the right column types.

### D. Run it

1. In n8n, click **Execute Workflow** (top right).
2. Each branch runs in parallel; the n8n canvas turns green node-by-node.
3. If a branch turns red, click the failing node → right panel → **Error** tab. Common causes:
   - Source column missing in the destination table → re-check the create script
   - Type mismatch (e.g. `MONEY` from SQL Server arrives as string) → cast in your `SELECT` (`CAST(SubTotal AS decimal(19,4))`)

## Acceptance check

In the Codespace terminal:

```bash
psql -d analytics -c "
SELECT table_name, n_live_tup AS approx_rows
FROM pg_stat_user_tables
WHERE schemaname = 'raw'
ORDER BY table_name;
"
```

Expected (numbers approximate):

| table                | approx_rows |
| -------------------- | ----------- |
| customer             | 19,820      |
| person               | 19,972      |
| product              | 504         |
| product_category     | 4           |
| product_subcategory  | 37          |
| sales_order_detail   | 121,317     |
| sales_order_header   | 31,465      |
| sales_person         | 17          |
| sales_territory      | 10          |

If the row counts roughly match, you're done with bronze. ✅

## Tips

- **Re-running the workflow** will *append* duplicate rows unless your tables have primary keys and you set "Skip on Conflict". The provided `01_create_bronze_tables.sql` adds PKs.
- **Truncate before reload** during development:
  ```bash
  psql -d analytics -c "TRUNCATE raw.sales_order_header, raw.sales_order_detail, raw.customer, raw.person, raw.sales_territory, raw.sales_person, raw.product, raw.product_subcategory, raw.product_category;"
  ```
- **Watch n8n logs** during execution if a node fails silently:
  ```bash
  docker logs -f $(docker ps --filter name=n8n -q)
  ```

## Next

→ [Task 2: Silver with dbt](02-silver-dbt.md)
