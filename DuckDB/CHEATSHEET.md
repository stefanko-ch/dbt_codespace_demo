# 🦆 DuckDB Cheat Sheet

Quick reference for the most important DuckDB commands and features.

---

## 🚀 Getting Started

```bash
# Start in-memory database
duckdb

# Open/create persistent database
duckdb mydata.db

# Start with Web UI
duckdb mydata.db -ui

# Execute SQL file
duckdb mydata.db < script.sql
```

---

## 📟 Dot Commands (CLI)

| Command | Description |
|---------|-------------|
| `.help` | Show all commands |
| `.tables` | List all tables |
| `.schema [table]` | Show table schema |
| `.databases` | List attached databases |
| `.mode` | Change output format (csv, json, table, etc.) |
| `.output file.txt` | Write output to file |
| `.read script.sql` | Execute SQL from file |
| `.exit` / `.quit` | Exit DuckDB |

---

## 📊 Basic Queries

```sql
-- Select all
SELECT * FROM table_name;

-- Select with conditions
SELECT col1, col2 FROM table_name WHERE col1 > 100;

-- Sorting
SELECT * FROM table_name ORDER BY col1 DESC;

-- Limit results
SELECT * FROM table_name LIMIT 10;

-- Distinct values
SELECT DISTINCT col1 FROM table_name;

-- Count rows
SELECT COUNT(*) FROM table_name;
```

---

## 📁 File Operations

### CSV

```sql
-- Read CSV directly
SELECT * FROM read_csv('data.csv');
SELECT * FROM read_csv_auto('data.csv');
SELECT * FROM 'data.csv';  -- Shorthand

-- Create table from CSV
CREATE TABLE my_table AS SELECT * FROM read_csv_auto('data.csv');

-- Export to CSV
COPY my_table TO 'output.csv' (HEADER, DELIMITER ',');
```

### Parquet

```sql
-- Read Parquet
SELECT * FROM read_parquet('data.parquet');
SELECT * FROM 'data.parquet';  -- Shorthand

-- Export to Parquet
COPY my_table TO 'output.parquet' (FORMAT PARQUET);
```

### JSON

```sql
-- Read JSON
SELECT * FROM read_json('data.json');
SELECT * FROM read_json_auto('data.json');

-- Export to JSON
COPY my_table TO 'output.json';
```

### Multiple Files (Glob)

```sql
-- Read all CSV files in folder
SELECT * FROM read_csv_auto('data/*.csv');

-- Read all Parquet files
SELECT * FROM read_parquet('data/**/*.parquet');
```

---

## 🔗 Joins

```sql
-- Inner Join
SELECT * FROM a INNER JOIN b ON a.id = b.id;

-- Left Join
SELECT * FROM a LEFT JOIN b ON a.id = b.id;

-- Right Join
SELECT * FROM a RIGHT JOIN b ON a.id = b.id;

-- Full Outer Join
SELECT * FROM a FULL OUTER JOIN b ON a.id = b.id;

-- Cross Join
SELECT * FROM a CROSS JOIN b;
```

---

## 📈 Aggregations

```sql
-- Common aggregates
SELECT 
    COUNT(*) as total,
    SUM(amount) as sum,
    AVG(amount) as avg,
    MIN(amount) as min,
    MAX(amount) as max,
    STDDEV(amount) as stddev
FROM sales;

-- Group By
SELECT category, SUM(amount) 
FROM sales 
GROUP BY category;

-- Having (filter groups)
SELECT category, SUM(amount) as total
FROM sales 
GROUP BY category
HAVING total > 1000;
```

---

## 🪟 Window Functions

```sql
-- Row number
SELECT *, ROW_NUMBER() OVER (ORDER BY date) as rn FROM sales;

-- Rank
SELECT *, RANK() OVER (PARTITION BY category ORDER BY amount DESC) FROM sales;

-- Running total
SELECT *, SUM(amount) OVER (ORDER BY date) as running_total FROM sales;

-- Moving average
SELECT *, AVG(amount) OVER (ORDER BY date ROWS BETWEEN 6 PRECEDING AND CURRENT ROW) as ma7 FROM sales;

-- Lead/Lag
SELECT *, 
    LAG(amount, 1) OVER (ORDER BY date) as prev_amount,
    LEAD(amount, 1) OVER (ORDER BY date) as next_amount
FROM sales;
```

---

## 🔄 CTEs (Common Table Expressions)

```sql
-- Simple CTE
WITH sales_summary AS (
    SELECT category, SUM(amount) as total
    FROM sales
    GROUP BY category
)
SELECT * FROM sales_summary WHERE total > 1000;

-- Multiple CTEs
WITH 
    cte1 AS (SELECT ...),
    cte2 AS (SELECT ...)
SELECT * FROM cte1 JOIN cte2 ON ...;

-- Recursive CTE
WITH RECURSIVE hierarchy AS (
    SELECT id, name, parent_id, 1 as level
    FROM employees WHERE parent_id IS NULL
    UNION ALL
    SELECT e.id, e.name, e.parent_id, h.level + 1
    FROM employees e JOIN hierarchy h ON e.parent_id = h.id
)
SELECT * FROM hierarchy;
```

---

## 🦆 DuckDB Special Features

### EXCLUDE & REPLACE

```sql
-- Select all columns except some
SELECT * EXCLUDE (col1, col2) FROM table_name;

-- Replace column in selection
SELECT * REPLACE (col1 * 2 AS col1) FROM table_name;
```

### COLUMNS Expression

```sql
-- Apply function to multiple columns
SELECT COLUMNS('amt_.*') FROM sales;
SELECT MIN(COLUMNS(*)) FROM sales;
```

### SAMPLE

```sql
-- Random sample (10 rows)
SELECT * FROM table_name USING SAMPLE 10;

-- Percentage sample
SELECT * FROM table_name USING SAMPLE 10%;
```

### QUALIFY (Filter window results)

```sql
-- Get top 3 per category
SELECT * FROM sales
QUALIFY ROW_NUMBER() OVER (PARTITION BY category ORDER BY amount DESC) <= 3;
```

### ASOF Join (Time-series)

```sql
SELECT * FROM events ASOF JOIN prices 
ON events.timestamp >= prices.timestamp;
```

### PIVOT / UNPIVOT

```sql
-- Pivot
PIVOT sales ON category USING SUM(amount);

-- Unpivot
UNPIVOT table_name ON col1, col2, col3 INTO NAME category VALUE amount;
```

---

## 🌐 Remote Data

```sql
-- Install & load httpfs
INSTALL httpfs; LOAD httpfs;

-- Read from URL
SELECT * FROM read_csv('https://example.com/data.csv');

-- Read from S3
SET s3_region='us-east-1';
SELECT * FROM read_parquet('s3://bucket/file.parquet');
```

---

## 🔌 Extensions

```sql
-- List installed extensions
SELECT * FROM duckdb_extensions();

-- Install extension
INSTALL extension_name;

-- Load extension
LOAD extension_name;

-- Common extensions
INSTALL httpfs;    -- HTTP/S3 file access
INSTALL json;      -- JSON functions
INSTALL parquet;   -- Parquet support
INSTALL spatial;   -- Geospatial functions
INSTALL fts;       -- Full-text search
```

---

## 🐍 Python Integration

```python
import duckdb

# In-memory connection
conn = duckdb.connect()

# Persistent database
conn = duckdb.connect('mydata.db')

# Execute query
result = conn.execute("SELECT * FROM 'data.csv'").fetchall()

# Get as DataFrame
df = conn.execute("SELECT * FROM 'data.csv'").df()

# Query pandas DataFrame directly
import pandas as pd
df = pd.DataFrame({'a': [1, 2, 3]})
result = duckdb.query("SELECT * FROM df WHERE a > 1").df()
```

---

## 💡 Performance Tips

```sql
-- Show query plan
EXPLAIN SELECT * FROM table_name;

-- Show plan with execution stats
EXPLAIN ANALYZE SELECT * FROM table_name;

-- Create index (for specific use cases)
CREATE INDEX idx_name ON table_name(column);

-- Set threads
SET threads TO 4;

-- Set memory limit
SET memory_limit = '4GB';

-- Enable progress bar
SET enable_progress_bar = true;
```

---

## 📚 Useful Functions

### String Functions
```sql
LOWER(str), UPPER(str), LENGTH(str)
CONCAT(str1, str2), str1 || str2
SUBSTRING(str, start, length)
TRIM(str), LTRIM(str), RTRIM(str)
REPLACE(str, from, to)
SPLIT_PART(str, delimiter, index)
REGEXP_MATCHES(str, pattern)
```

### Date/Time Functions
```sql
CURRENT_DATE, CURRENT_TIMESTAMP
DATE_PART('year', date), EXTRACT(YEAR FROM date)
DATE_TRUNC('month', date)
DATE_DIFF('day', date1, date2)
STRFTIME(date, '%Y-%m-%d')
```

### Type Conversion
```sql
CAST(value AS INTEGER)
value::INTEGER  -- Shorthand
TRY_CAST(value AS INTEGER)  -- Returns NULL on error
```

---

## 🔗 Quick Links

- 📚 [Official Docs](https://duckdb.org/docs/)
- 🔌 [Extensions](https://duckdb.org/docs/extensions/overview)
- 🐍 [Python API](https://duckdb.org/docs/api/python/overview)
- 🌐 [Web Shell](https://shell.duckdb.org/)
- ☁️ [MotherDuck](https://motherduck.com)

---

<p align="center"><b>Happy Quacking! 🦆</b></p>
