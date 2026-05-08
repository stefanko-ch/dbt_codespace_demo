# Task 1 — Bronze: Ingest AdventureWorks with Kestra

**Goal:** copy nine tables from Azure SQL (AdventureWorks) into the `analytics.raw.*` schema of your local Postgres, 1:1 — no transformations.

This is the bronze layer. We don't clean, rename, or filter here. We just land the data so downstream tools (dbt) can take over.

The repo ships **one table fully done as a worked example** (`Sales.Customer`). You'll extend the same flow to cover the remaining eight tables.

## What's already built

[`flows/bronze_adventureworks.yml`](../flows/bronze_adventureworks.yml) ingests `Sales.Customer` end-to-end with three sequential tasks:

```
[ prepare_schema ]   create raw.customer + truncate
        │
        ▼
[ query_source ]     SELECT from Sales.Customer in Azure SQL,
                     store rows as ION in Kestra storage
        │
        ▼
[ insert_into_bronze ]   Postgres.Batch reads the ION file,
                          runs INSERT INTO raw.customer …
                          row-by-row (no CSV intermediate)
```

The Azure SQL credentials are pre-filled as input defaults — you can hit **Execute** without typing.

## Step 1 — Open Kestra

In the **Ports** panel of VS Code, click the globe icon next to port **8080** (or use the auto-opened preview tab). On first launch Kestra takes ~30–60 seconds to start (JVM warmup); refresh once you see the dashboard.

## Step 2 — Run the example flow

Left sidebar → **Flows** → namespace **`workshop`** → **`bronze_adventureworks`** → **Execute** (top right).

The form shows the four pre-filled Azure SQL inputs. Hit **Execute** at the bottom. The Gantt view renders three green segments end-to-end.

Verify in the Codespace terminal:

```bash
psql -d analytics -c "SELECT count(*) FROM raw.customer"
```

You should see ~19,820 rows. ✅

## Step 3 — Your turn: add the other eight tables

Extend the flow so all nine source tables land in `analytics.raw.*`. The end state should be:

| # | Source (Azure SQL)              | Bronze table (`analytics.raw`) | Approx rows |
| - | ------------------------------- | ------------------------------- | ----------- |
| ✅ | `Sales.Customer`                | `customer`                      | 19,820      |
| 1 | `Sales.SalesOrderHeader`        | `sales_order_header`            | 31,465      |
| 2 | `Sales.SalesOrderDetail`        | `sales_order_detail`            | 121,317     |
| 3 | `Person.Person`                 | `person`                        | 19,972      |
| 4 | `Sales.SalesTerritory`          | `sales_territory`               | 10          |
| 5 | `Sales.SalesPerson`             | `sales_person`                  | 17          |
| 6 | `Production.Product`            | `product`                       | 504         |
| 7 | `Production.ProductSubcategory` | `product_subcategory`           | 37          |
| 8 | `Production.ProductCategory`    | `product_category`              | 4           |

### Pattern for each new table

For each table you need to:

1. Add a `CREATE TABLE IF NOT EXISTS raw.<target>` block to the `prepare_schema` task's SQL, plus extend the trailing `TRUNCATE` list so re-runs stay clean.
2. Add a new `Query` task that pulls from Azure SQL with the column projection you want (snake_case aliases not required — the Postgres column list in the INSERT controls naming).
3. Add a matching `Batch` task with `INSERT INTO raw.<target> (…) VALUES (?, ?, …)` — placeholders in the SAME order as the SELECT columns, since Batch binds positionally.

You'll quickly notice the three tasks per table is repetitive. Once you have two or three tables, refactor to a single `ForEach` loop where each iteration carries a `{select, insert, target}` triple. That's how production-grade flows look — see [the "ForEach" tutorial in Kestra docs](https://kestra.io/docs/tutorial/flowable) for the syntax.

### Hints / suggested column projections

To save you the lookup, here are the columns we'll use in the dimensional model in tasks 2-3. Drop heavy/uninteresting columns (XML demographics, photos, rowguid, etc.).

<details>
<summary><b>Sales.SalesOrderHeader</b> — 24 columns</summary>

```sql
SELECT
  SalesOrderID, RevisionNumber, OrderDate, DueDate, ShipDate, Status,
  OnlineOrderFlag, SalesOrderNumber, PurchaseOrderNumber, AccountNumber,
  CustomerID, SalesPersonID, TerritoryID, BillToAddressID, ShipToAddressID,
  ShipMethodID, CreditCardID, CurrencyRateID, SubTotal, TaxAmt, Freight,
  TotalDue, Comment, ModifiedDate
FROM Sales.SalesOrderHeader
```
</details>

<details>
<summary><b>Sales.SalesOrderDetail</b> — 10 columns</summary>

```sql
SELECT
  SalesOrderID, SalesOrderDetailID, CarrierTrackingNumber, OrderQty,
  ProductID, SpecialOfferID, UnitPrice, UnitPriceDiscount, LineTotal,
  ModifiedDate
FROM Sales.SalesOrderDetail
```
PK is composite: `(sales_order_id, sales_order_detail_id)`.
</details>

<details>
<summary><b>Person.Person</b> — 10 columns</summary>

```sql
SELECT
  BusinessEntityID, PersonType, NameStyle, Title, FirstName, MiddleName,
  LastName, Suffix, EmailPromotion, ModifiedDate
FROM Person.Person
```
</details>

<details>
<summary><b>Sales.SalesTerritory</b> — 9 columns (note <code>[Group]</code> is reserved in MSSQL)</summary>

```sql
SELECT
  TerritoryID, Name, CountryRegionCode, [Group], SalesYTD, SalesLastYear,
  CostYTD, CostLastYear, ModifiedDate
FROM Sales.SalesTerritory
```
In Postgres, the column should also be quoted: `"group"` (it's a reserved word there too).
</details>

<details>
<summary><b>Sales.SalesPerson</b> — 8 columns</summary>

```sql
SELECT
  BusinessEntityID, TerritoryID, SalesQuota, Bonus, CommissionPct,
  SalesYTD, SalesLastYear, ModifiedDate
FROM Sales.SalesPerson
```
</details>

<details>
<summary><b>Production.Product</b> — 24 columns</summary>

```sql
SELECT
  ProductID, Name, ProductNumber, MakeFlag, FinishedGoodsFlag, Color,
  SafetyStockLevel, ReorderPoint, StandardCost, ListPrice, Size,
  SizeUnitMeasureCode, WeightUnitMeasureCode, Weight, DaysToManufacture,
  ProductLine, Class, Style, ProductSubcategoryID, ProductModelID,
  SellStartDate, SellEndDate, DiscontinuedDate, ModifiedDate
FROM Production.Product
```
</details>

<details>
<summary><b>Production.ProductSubcategory</b> — 4 columns</summary>

```sql
SELECT ProductSubcategoryID, ProductCategoryID, Name, ModifiedDate
FROM Production.ProductSubcategory
```
</details>

<details>
<summary><b>Production.ProductCategory</b> — 3 columns</summary>

```sql
SELECT ProductCategoryID, Name, ModifiedDate
FROM Production.ProductCategory
```
</details>

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

Row counts should roughly match the table above. If the stats lag, run `ANALYZE raw.<table>` once.

## Troubleshooting

**The flow doesn't show up in the UI**
- Confirm the volume mount: `docker exec $(docker ps --filter name=kestra -q) ls /app/flows`
- Restart Kestra: `docker compose -f .devcontainer/docker-compose.yml restart kestra`

**`Login failed for user 'bia21'`**
- The pre-filled credentials may have expired. Get fresh ones from the workshop owner. Azure SQL firewall may also be blocking the Codespace's outbound IP — in Azure Portal → SQL Server → Networking, enable **"Allow Azure services and resources to access this server"**.

**`Batch` fails with `column "..." does not exist`**
- Mismatch between the column list in your `INSERT (…)` and the actual table. Re-check the `CREATE TABLE` you added to `prepare_schema`.

**`Batch` fails with type errors (e.g. "expected integer, got string")**
- Placeholder `?` order in the INSERT does not match the SELECT order. Batch binds positionally, not by name.

**`Batch` fails with `duplicate key value violates unique constraint`**
- The `prepare_schema` task should be running TRUNCATE before the inserts. Make sure you appended your new tables to the TRUNCATE list.

**Logs for a stuck run**
- In the Kestra UI: open the execution → click a task → **Logs** subtab.
- Or from the terminal: `docker logs -f --tail 100 $(docker ps --filter name=kestra -q)`.

## Next

→ [Task 2: Silver with dbt](02-silver-dbt.md)
