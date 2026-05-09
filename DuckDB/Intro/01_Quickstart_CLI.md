# DuckDB Quickstart - CLI Guide

This guide walks you through using DuckDB directly from the command line interface (CLI).

## Table of Contents
1. [Getting Started](#getting-started)
2. [In-Memory Database](#in-memory-database)
3. [Persistent Database](#persistent-database)
4. [Working with CSV Files](#working-with-csv-files)
5. [Extensions and Remote Data](#extensions-and-remote-data)
6. [DuckDB Web UI](#duckdb-web-ui)
7. [MotherDuck Integration](#motherduck-integration)

---

## Getting Started

### Prerequisites
- DuckDB installed on your system
- Terminal/Command line access

### Navigate to Your DuckDB Folder
```bash
cd /workspaces/DuckDB
```

---

## In-Memory Database

In-memory databases are temporary and exist only during your session.

### Start DuckDB
```bash
duckdb
```

### Create and Query a Table
```sql
-- Create an in-memory table
CREATE TABLE ducks AS SELECT 3 AS age, 'mandarin' AS breed;

-- Query the table
SELECT * FROM ducks;

-- Alternative syntax (DuckDB shorthand)
FROM ducks;
```

### Exit DuckDB
```sql
.exit
```

---

## Persistent Database

Persistent databases save your data to a file.

### Create a Persistent Database
```bash
duckdb demo_duck.db
```

This creates a file `demo_duck.db` that persists your data.

---

## Working with CSV Files

DuckDB can read CSV files directly without importing them first!

### Read CSV File Directly
```sql
-- Read CSV without loading into a table
SELECT * FROM read_csv_auto('./sample_data/states.csv');
```

### Create Schema and Tables

```sql
-- Create a schema
CREATE SCHEMA demo;

-- Create tables from CSV files
CREATE TABLE demo.states AS SELECT * FROM read_csv_auto('./sample_data/states.csv');
CREATE TABLE demo.wine_quality AS SELECT * FROM read_csv_auto('./sample_data/WineQuality.csv');
CREATE TABLE demo.currency_rates AS SELECT * FROM read_csv_auto('./sample_data/popular_currency_rate_dollar.csv');
```

### Query Tables
```sql
-- Query your tables
FROM demo.states;
FROM demo.wine_quality;
FROM demo.currency_rates;
```

### Exit and Connect with DBeaver
```sql
.exit
```

You can now connect to `demo_duck.db` using DBeaver or any other database client.

---

## Extensions and Remote Data

DuckDB supports extensions for additional functionality.

### Start DuckDB
```bash
duckdb
```

### View Available Extensions
```sql
SELECT * FROM duckdb_extensions();
```

### Install and Load Extensions
```sql
-- HTTP file system support
INSTALL httpfs;
LOAD httpfs;

-- AWS S3 support
INSTALL aws;
LOAD aws;
```

### Query Remote Parquet Files (S3)

```sql
-- Set AWS region
SET s3_region='us-east-1';

-- Query Parquet file directly from S3
SELECT * FROM read_parquet('s3://us-prd-motherduck-open-datasets/nyc_taxi/parquet/yellow_cab_nyc_2022_11.parquet');

-- Count rows
SELECT COUNT(*) 
FROM read_parquet('s3://us-prd-motherduck-open-datasets/nyc_taxi/parquet/yellow_cab_nyc_2022_11.parquet');

-- Aggregate query
SELECT
   passenger_count,
   avg(total_amount) AS avg_amount
FROM read_parquet('s3://us-prd-motherduck-open-datasets/nyc_taxi/parquet/yellow_cab_nyc_2022_11.parquet')
GROUP BY passenger_count
ORDER BY passenger_count;
```

### Exit DuckDB
```sql
.exit
```

---

## DuckDB Web UI

DuckDB includes a built-in web interface for easy querying.

### Start DuckDB with UI
```bash
duckdb demo_duck.db -ui
```

This opens a web browser with an interactive SQL interface connected to your database.

- Write and execute SQL queries
- View results in tables
- Visualize data
- Export results

---

## MotherDuck Integration

### What is MotherDuck?

[MotherDuck](https://motherduck.com) is a **serverless cloud analytics platform** built on DuckDB. It combines the speed and simplicity of DuckDB with cloud capabilities:

| Feature | Description |
|---------|-------------|
| ☁️ **Cloud Storage** | Your data lives in the cloud, accessible from anywhere |
| 🤝 **Collaboration** | Share databases and queries with your team |
| 🔗 **Hybrid Queries** | Query local AND cloud data in the same SQL statement |
| 📊 **Sample Datasets** | Pre-loaded datasets (NYC taxi, weather, etc.) for learning |
| 🔐 **Secure** | Enterprise-grade security and authentication |
| 💻 **No Infrastructure** | Serverless - no servers to manage |

### ⚠️ Account Required

To use MotherDuck, you need to **create a free account** at [motherduck.com](https://motherduck.com).

**Free Tier includes:**
- ✅ **10 GB cloud storage** for your databases
- ✅ **Unlimited local queries** (hybrid execution)
- ✅ **Access to sample datasets** (NYC taxi, COVID data, etc.)
- ✅ **Share databases** with up to 3 team members
- ✅ **Web UI** for querying in the browser
- ✅ **No credit card required**

> 💡 The free tier is perfect for learning, personal projects, and small teams!

**Use Cases:**
- Team data sharing and collaboration
- Backup your local DuckDB databases to the cloud
- Access large datasets without downloading them
- Run analytics from any device

### Connect to MotherDuck

```bash
# Start DuckDB with your database
duckdb demo_duck.db
```

```sql
-- Install MotherDuck extension
INSTALL motherduck;
LOAD motherduck;

-- Connect to MotherDuck (opens browser for authentication)
ATTACH 'md:';
```

> 🔑 On first connection, a browser window opens for authentication. After login, your token is cached locally.

### Query MotherDuck Sample Data

```sql
-- View sample data
SELECT * FROM sample_data.nyc.service_requests LIMIT 10;

-- Query with filters
SELECT 
  created_date, 
  agency_name, 
  complaint_type, 
  descriptor, 
  incident_address, 
  resolution_description
FROM sample_data.nyc.service_requests 
WHERE 
  created_date >= '2022-03-27' AND 
  created_date <= '2022-03-31';
```

---

## Upload Data to MotherDuck

### Test Local CSV Reading

```bash
duckdb
```

```sql
-- Test reading local CSV
SELECT * FROM read_csv_auto('./sample_data/AW_CSV/Person.Person.csv');

-- Install and load MotherDuck
INSTALL motherduck;
LOAD motherduck;

-- Connect to MotherDuck
ATTACH 'md:';
```

### Create Database and Upload Tables

```sql
-- Create a new database in MotherDuck
CREATE DATABASE AdventureWorks_Landing;

-- Switch to the new database
USE AdventureWorks_Landing;

-- Upload Person tables
CREATE OR REPLACE TABLE person_person 
AS SELECT * FROM read_csv_auto('./sample_data/AW_CSV/Person.Person.csv');

CREATE OR REPLACE TABLE person_countryregion 
AS SELECT * FROM read_csv_auto('./sample_data/AW_CSV/Person.CountryRegion.csv');

CREATE OR REPLACE TABLE person_stateprovince 
AS SELECT * FROM read_csv_auto('./sample_data/AW_CSV/Person.StateProvince.csv');

CREATE OR REPLACE TABLE person_address 
AS SELECT * FROM read_csv_auto('./sample_data/AW_CSV/Person.Address.csv');

-- Upload Production tables
CREATE OR REPLACE TABLE production_product 
AS SELECT * FROM read_csv_auto('./sample_data/AW_CSV/Production.Product.csv');

CREATE OR REPLACE TABLE production_productcategory 
AS SELECT * FROM read_csv_auto('./sample_data/AW_CSV/Production.ProductCategory.csv');

CREATE OR REPLACE TABLE production_productsubcategory 
AS SELECT * FROM read_csv_auto('./sample_data/AW_CSV/Production.ProductSubcategory.csv');

-- Upload Sales tables
CREATE OR REPLACE TABLE sales_customer 
AS SELECT * FROM read_csv_auto('./sample_data/AW_CSV/Sales.Customer.csv');

CREATE OR REPLACE TABLE sales_salesorderdetail 
AS SELECT * FROM read_csv_auto('./sample_data/AW_CSV/Sales.SalesOrderDetail.csv');

CREATE OR REPLACE TABLE sales_salesorderheader 
AS SELECT * FROM read_csv_auto('./sample_data/AW_CSV/Sales.SalesOrderHeader.csv');

CREATE OR REPLACE TABLE sales_salesterritory 
AS SELECT * FROM read_csv_auto('./sample_data/AW_CSV/Sales.SalesTerritory.csv');
```

---

## Useful DuckDB Commands

### Dot Commands
```sql
.help           -- Show all available commands
.tables         -- List all tables
.schema         -- Show schema of all tables
.schema TABLE   -- Show schema of specific table
.exit           -- Exit DuckDB
.quit           -- Quit DuckDB (same as .exit)
```

### Show System Info
```sql
-- Show DuckDB version
SELECT version();

-- Show all extensions
SELECT * FROM duckdb_extensions();

-- Show all settings
SELECT * FROM duckdb_settings();

-- Show all tables
SHOW TABLES;

-- Describe table structure
DESCRIBE table_name;
```

---

## Tips and Tricks

### 1. **Reading Multiple CSV Files**
```sql
-- Read all CSV files in a directory
SELECT * FROM read_csv_auto('./sample_data/AW_CSV/*.csv');

-- Read with specific pattern
SELECT * FROM read_csv_auto('./sample_data/AW_CSV/Person.*.csv');
```

### 2. **Export Query Results**
```sql
-- Export to CSV
COPY (SELECT * FROM demo.states) TO './exports/states.csv' (HEADER, DELIMITER ',');

-- Export to Parquet
COPY (SELECT * FROM demo.states) TO './exports/states.parquet' (FORMAT PARQUET);

-- Export to JSON
COPY (SELECT * FROM demo.states) TO './exports/states.json';
```

### 3. **Performance Optimization**
```sql
-- Check query execution plan
EXPLAIN SELECT * FROM demo.states WHERE name = 'California';

-- Analyze query performance
EXPLAIN ANALYZE SELECT * FROM demo.states WHERE name = 'California';
```

### 4. **Import/Export Database**
```bash
# First exit DuckDB if you're in a session
.exit

# Export entire database
duckdb demo_duck.db ".dump" > ./exports/backup.sql

# Import from SQL file (note: you may need to create schemas first)
duckdb imported_database.db
```

```sql
-- If your backup uses schemas, create them first
CREATE SCHEMA IF NOT EXISTS demo;

-- Then read the backup file
.read ./exports/backup.sql
```

> ⚠️ **Note:** DuckDB's `.dump` doesn't include `CREATE SCHEMA` statements. Create schemas manually before importing.

---

## Common Workflows

### Workflow 1: Local Data Analysis
```bash
# 1. Start DuckDB with persistent DB
duckdb analysis.db

# 2. Load your data
CREATE TABLE data AS SELECT * FROM read_csv_auto('data.csv');

# 3. Run analysis
SELECT category, COUNT(*), AVG(amount) FROM data GROUP BY category;

# 4. Export results
COPY (SELECT * FROM results) TO 'analysis_results.csv';

# 5. Exit
.exit
```

### Workflow 2: Cloud Data Processing
```bash
# 1. Start DuckDB
duckdb

# 2. Install extensions
INSTALL httpfs; LOAD httpfs;
INSTALL aws; LOAD aws;

# 3. Set region
SET s3_region='us-east-1';

# 4. Query remote data
SELECT * FROM read_parquet('s3://bucket/data/*.parquet');

# 5. Process and save locally
CREATE TABLE local_results AS 
SELECT * FROM read_parquet('s3://bucket/data/*.parquet')
WHERE date >= '2024-01-01';

# 6. Exit
.exit
```

---

## Troubleshooting

### Issue: "File not found"
- Check that you're in the correct directory
- Use absolute paths: `/full/path/to/file.csv`
- Verify file permissions

### Issue: "Extension not found"
```sql
-- Install the extension first
INSTALL extension_name;
LOAD extension_name;
```

### Issue: Database locked
- Make sure no other process is using the database
- Close DBeaver or other database clients
- Exit all DuckDB sessions

---

## Resources

- **Official Documentation**: https://duckdb.org/docs/
- **MotherDuck**: https://motherduck.com
- **Extensions**: https://duckdb.org/docs/extensions/overview
- **DuckLake Specification**: https://ducklake.select/docs/stable/specification/introduction

---

## Next Steps

Now that you've learned the terminal basics:
1. Explore the Jupyter notebooks in `notebooks/`

Happy querying! 🦆
