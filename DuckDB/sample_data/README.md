# 📊 Sample Data Documentation

This folder contains sample datasets for learning and practicing DuckDB queries.

---

## 📁 Folder Structure

```
sample_data/
├── AW_CSV/                              # AdventureWorks dataset
│   ├── Person.Address.csv
│   ├── Person.CountryRegion.csv
│   ├── Person.Person.csv
│   ├── Person.StateProvince.csv
│   ├── Production.Product.csv
│   ├── Production.ProductCategory.csv
│   ├── Production.ProductSubcategory.csv
│   ├── Sales.Customer.csv
│   ├── Sales.SalesOrderDetail.csv
│   ├── Sales.SalesOrderHeader.csv
│   └── Sales.SalesTerritory.csv
├── states.csv                           # US states
├── WineQuality.csv                      # Wine quality measurements
├── popular_currency_rate_dollar.csv     # Currency exchange rates
├── weather_timeseries.csv               # Weather time series data
├── blog_posts.csv                       # Blog posts for text analytics
└── product_reviews.csv                  # Product reviews for NLP
```

---

## 🏢 AdventureWorks Dataset

A classic Microsoft sample database representing a fictional bicycle manufacturer. Perfect for practicing JOINs, aggregations, and real-world business analytics.

### ER Diagram

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                              ADVENTUREWORKS SCHEMA                               │
└─────────────────────────────────────────────────────────────────────────────────┘

                                    PERSON SCHEMA
┌──────────────────┐    ┌──────────────────┐    ┌──────────────────┐
│  CountryRegion   │    │  StateProvince   │    │     Address      │
├──────────────────┤    ├──────────────────┤    ├──────────────────┤
│ CountryRegionCode│◄───│ CountryRegionCode│    │ AddressID (PK)   │
│ Name             │    │ StateProvinceID  │◄───│ StateProvinceID  │
└──────────────────┘    │ StateProvinceCode│    │ AddressLine1     │
                        │ Name             │    │ City             │
                        │ TerritoryID      │    │ PostalCode       │
                        └──────────────────┘    └──────────────────┘
                                 │
                                 │
                                 ▼
                        ┌──────────────────┐
                        │     Person       │
                        ├──────────────────┤
                        │ BusinessEntityID │
                        │ PersonType       │
                        │ FirstName        │
                        │ LastName         │
                        │ EmailPromotion   │
                        └──────────────────┘


                                  PRODUCTION SCHEMA
┌──────────────────┐    ┌──────────────────────┐    ┌──────────────────┐
│ ProductCategory  │    │  ProductSubcategory  │    │     Product      │
├──────────────────┤    ├──────────────────────┤    ├──────────────────┤
│ ProductCategoryID│◄───│ ProductCategoryID    │    │ ProductID (PK)   │
│ Name             │    │ ProductSubcategoryID │◄───│ ProductSubcatID  │
└──────────────────┘    │ Name                 │    │ Name             │
                        └──────────────────────┘    │ ProductNumber    │
                                                    │ Color            │
                                                    │ StandardCost     │
                                                    │ ListPrice        │
                                                    │ Size             │
                                                    │ Weight           │
                                                    │ ProductLine      │
                                                    │ Class            │
                                                    │ Style            │
                                                    │ SellStartDate    │
                                                    │ SellEndDate      │
                                                    └──────────────────┘
                                                             │
                                                             │
                                    SALES SCHEMA             │
                                                             ▼
┌──────────────────┐    ┌──────────────────┐    ┌──────────────────────┐
│  SalesTerritory  │    │ SalesOrderHeader │    │   SalesOrderDetail   │
├──────────────────┤    ├──────────────────┤    ├──────────────────────┤
│ TerritoryID (PK) │◄───│ TerritoryID      │    │ SalesOrderID (FK)    │
│ Name             │    │ SalesOrderID(PK) │◄───│ SalesOrderDetailID   │
│ CountryRegionCode│    │ OrderDate        │    │ ProductID (FK)       │──►
│ Group            │    │ DueDate          │    │ OrderQty             │
│ SalesYTD         │    │ ShipDate         │    │ UnitPrice            │
│ SalesLastYear    │    │ Status           │    │ UnitPriceDiscount    │
│ CostYTD          │    │ CustomerID       │    │ LineTotal            │
│ CostLastYear     │    │ ShipToAddressID  │    └──────────────────────┘
└──────────────────┘    │ SubTotal         │
                        │ TaxAmt           │
         ┌──────────────│ Freight          │
         │              │ TotalDue         │
         ▼              └──────────────────┘
┌──────────────────┐             │
│     Customer     │             │
├──────────────────┤             │
│ CustomerID (PK)  │◄────────────┘
│ PersonID         │
│ StoreID          │
│ TerritoryID      │
│ AccountNumber    │
└──────────────────┘
```

### Table Details

#### Person Schema

| Table | Description | Key Columns |
|-------|-------------|-------------|
| `Person.Person` | Individual people | BusinessEntityID, FirstName, LastName, PersonType |
| `Person.Address` | Street addresses | AddressID, AddressLine1, City, PostalCode |
| `Person.StateProvince` | States/provinces | StateProvinceID, Name, CountryRegionCode |
| `Person.CountryRegion` | Countries | CountryRegionCode, Name |

#### Production Schema

| Table | Description | Key Columns |
|-------|-------------|-------------|
| `Production.Product` | Products for sale | ProductID, Name, ListPrice, StandardCost |
| `Production.ProductCategory` | Top-level categories | ProductCategoryID, Name |
| `Production.ProductSubcategory` | Subcategories | ProductSubcategoryID, Name |

#### Sales Schema

| Table | Description | Key Columns |
|-------|-------------|-------------|
| `Sales.Customer` | Customer records | CustomerID, PersonID, TerritoryID |
| `Sales.SalesOrderHeader` | Order headers | SalesOrderID, OrderDate, TotalDue |
| `Sales.SalesOrderDetail` | Order line items | SalesOrderDetailID, ProductID, OrderQty |
| `Sales.SalesTerritory` | Sales regions | TerritoryID, Name, Group |

### Quick Start Queries

```sql
-- Load all AdventureWorks tables
CREATE TABLE products AS SELECT * FROM read_csv_auto('./sample_data/AW_CSV/Production.Product.csv');
CREATE TABLE categories AS SELECT * FROM read_csv_auto('./sample_data/AW_CSV/Production.ProductCategory.csv');
CREATE TABLE orders AS SELECT * FROM read_csv_auto('./sample_data/AW_CSV/Sales.SalesOrderHeader.csv');
CREATE TABLE order_details AS SELECT * FROM read_csv_auto('./sample_data/AW_CSV/Sales.SalesOrderDetail.csv');

-- Example: Top 10 products by revenue
SELECT 
    p.Name,
    SUM(od.OrderQty) as TotalQty,
    SUM(od.LineTotal) as TotalRevenue
FROM order_details od
JOIN products p ON od.ProductID = p.ProductID
GROUP BY p.Name
ORDER BY TotalRevenue DESC
LIMIT 10;
```

---

## 🇺🇸 States Dataset

US states with abbreviations.

| Column | Type | Description |
|--------|------|-------------|
| state | VARCHAR | Full state name |
| abbreviation | VARCHAR | Two-letter code |

```sql
-- Load states
SELECT * FROM read_csv_auto('./sample_data/states.csv');

-- Count states
SELECT COUNT(*) FROM './sample_data/states.csv';
```

---

## 🍷 Wine Quality Dataset

Wine quality measurements for machine learning and analytics practice.

| Column | Type | Description |
|--------|------|-------------|
| fixed_acidity | FLOAT | Fixed acidity level |
| volatile_acidity | FLOAT | Volatile acidity level |
| citric_acid | FLOAT | Citric acid content |
| residual_sugar | FLOAT | Residual sugar amount |
| chlorides | FLOAT | Chloride content |
| free_sulfur_dioxide | FLOAT | Free SO2 |
| total_sulfur_dioxide | FLOAT | Total SO2 |
| density | FLOAT | Wine density |
| pH | FLOAT | pH level |
| sulphates | FLOAT | Sulphate content |
| alcohol | FLOAT | Alcohol percentage |
| quality | INT | Quality score (0-10) |

```sql
-- Load and analyze wine quality
SELECT 
    quality,
    COUNT(*) as count,
    ROUND(AVG(alcohol), 2) as avg_alcohol,
    ROUND(AVG(pH), 2) as avg_ph
FROM './sample_data/WineQuality.csv'
GROUP BY quality
ORDER BY quality;
```

---

## 💱 Currency Exchange Rates

Historical USD exchange rates for major currencies.

| Column | Type | Description |
|--------|------|-------------|
| date | DATE | Exchange rate date |
| currency | VARCHAR | Currency code (EUR, GBP, etc.) |
| rate | FLOAT | Exchange rate vs USD |

```sql
-- Load currency data
SELECT * FROM './sample_data/popular_currency_rate_dollar.csv' LIMIT 10;

-- Latest rates
SELECT currency, rate 
FROM './sample_data/popular_currency_rate_dollar.csv'
WHERE date = (SELECT MAX(date) FROM './sample_data/popular_currency_rate_dollar.csv');
```

---

## 🌤️ Weather Time Series Dataset

Daily weather measurements for time series analysis practice.

| Column | Type | Description |
|--------|------|-------------|
| date | DATE | Measurement date |
| temperature | FLOAT | Temperature in °C |
| humidity | FLOAT | Humidity percentage |
| pressure | FLOAT | Air pressure in hPa |
| wind_speed | FLOAT | Wind speed in km/h |
| precipitation | FLOAT | Precipitation in mm |
| city | VARCHAR | City name |

```sql
-- Time series analysis example
SELECT 
    city,
    date,
    temperature,
    AVG(temperature) OVER (
        PARTITION BY city 
        ORDER BY date 
        ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
    ) as temp_7day_avg
FROM './sample_data/weather_timeseries.csv'
ORDER BY city, date;
```

---

## 📝 Blog Posts Dataset

Sample blog posts for text analytics and full-text search practice.

| Column | Type | Description |
|--------|------|-------------|
| id | INTEGER | Post ID |
| title | VARCHAR | Post title |
| content | VARCHAR | Full post content |
| author | VARCHAR | Author name |
| category | VARCHAR | Post category |
| published_date | DATE | Publication date |
| views | INTEGER | View count |
| likes | INTEGER | Like count |

```sql
-- Text search example
SELECT title, author, category
FROM './sample_data/blog_posts.csv'
WHERE content ILIKE '%data%' OR title ILIKE '%analytics%';
```

---

## ⭐ Product Reviews Dataset

Customer reviews for sentiment analysis and NLP practice.

| Column | Type | Description |
|--------|------|-------------|
| review_id | INTEGER | Review ID |
| product_id | INTEGER | Product ID |
| rating | INTEGER | Rating (1-5 stars) |
| title | VARCHAR | Review title |
| review_text | VARCHAR | Full review text |
| helpful_votes | INTEGER | Helpful vote count |
| review_date | DATE | Review date |

```sql
-- Sentiment analysis prep
SELECT 
    rating,
    COUNT(*) as review_count,
    AVG(LENGTH(review_text)) as avg_review_length
FROM './sample_data/product_reviews.csv'
GROUP BY rating
ORDER BY rating DESC;
```

---

## 📝 Usage Tips

1. **Direct Query**: Use DuckDB's ability to query files directly:
   ```sql
   SELECT * FROM './sample_data/states.csv';
   ```

2. **Create Tables**: For better performance with multiple queries:
   ```sql
   CREATE TABLE states AS SELECT * FROM read_csv_auto('./sample_data/states.csv');
   ```

3. **Glob Patterns**: Query multiple files at once:
   ```sql
   SELECT * FROM './sample_data/AW_CSV/*.csv';
   ```

---

## 🔗 Data Sources

- **AdventureWorks**: [Microsoft Sample Database](https://docs.microsoft.com/en-us/sql/samples/adventureworks-install-configure)
- **Wine Quality**: [UCI Machine Learning Repository](https://archive.ics.uci.edu/ml/datasets/wine+quality)
- **States**: Public domain US state data
- **Currency Rates**: Historical exchange rate data

---

<p align="center"><b>Happy Querying! 🦆</b></p>
