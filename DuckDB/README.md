# 🦆 DuckDB Learning Environment

[![DuckDB](https://img.shields.io/badge/DuckDB-FFF000?style=for-the-badge&logo=duckdb&logoColor=black)](https://duckdb.org/)
[![Python](https://img.shields.io/badge/Python-3776AB?style=for-the-badge&logo=python&logoColor=white)](https://www.python.org/)
[![Jupyter](https://img.shields.io/badge/Jupyter-F37626?style=for-the-badge&logo=jupyter&logoColor=white)](https://jupyter.org/)

A learning environment for **DuckDB** – the fast, embedded analytical database.

---

## 📋 Contents

- [Quick Start](#-quick-start)
- [Project Structure](#-project-structure)
- [Tutorials](#-tutorials)
- [Exercises](#-exercises)
- [Resources](#-resources)

---

## 🚀 Quick Start

### GitHub Codespaces ⭐

1. **"Code"** → **"Codespaces"** → **"Create codespace"**
2. Wait (~2 minutes)
3. Start learning!

### Local

```bash
# Clone repository
cd DuckDB

# Install dependencies
pip install -r requirements.txt

# Start DuckDB
duckdb
```

---

## 📁 Project Structure

```
DuckDB/
├── 📄 README.md                    # This file
├── 📄 CHEATSHEET.md                # SQL Cheatsheet
├── 📄 SETUP.md                     # Setup guide
├── 📄 requirements.txt             # Python dependencies
│
├── 📂 Intro/                       # Introduction
│   ├── 01_Quickstart_CLI.md
│   ├── 02_DuckDB_Introduction.ipynb
│   └── 03_DuckDB_Python_Basics.ipynb
│
├── 📂 Notebooks/                   # Tutorial Notebooks
│   ├── 01_DuckDB_Introduction.ipynb
│   ├── 02_DuckDB_Python_Basics.ipynb
│   ├── 03_Pandas_Polars_Integration.ipynb
│   ├── 04_SQL_Fundamentals.ipynb
│   └── 05_Advanced_SQL.ipynb
│
├── 📂 exercises/                   # Exercises
│   ├── 01_First_Steps.ipynb
│   ├── 02_Working_with_CSV.ipynb
│   ├── 03_Joins_and_Relationships.ipynb
│   ├── 04_Advanced_Analytics.ipynb
│   └── 05_Real_World_Project.ipynb
│
├── 📂 exercises_solutions/         # Solutions
│
├── 📂 sample_data/                 # Sample data
│
└── 📂 exports/                     # Exported data
```

---

## 📚 Tutorials

| Nr. | Topic | Description | Level |
|-----|-------|-------------|-------|
| 01 | DuckDB Introduction | Getting started, installation, connection | 🟢 |
| 02 | Python Basics | Python API for DuckDB | 🟢 |
| 03 | Pandas & Polars | DataFrame integration | 🟡 |
| 04 | SQL Fundamentals | DDL, DML, SELECT, GROUP BY | 🟡 |
| 05 | Advanced SQL | JOINs, Subqueries, CTEs, Window Functions | 🔴 |

---

## 💪 Exercises

| Nr. | Exercise | Topics | Level |
|-----|----------|--------|-------|
| 01 | First Steps | Connection, create tables, simple queries | 🟢 |
| 02 | Working with CSV | Import, transform, analyze CSV files | 🟢 |
| 03 | Joins and Relationships | INNER/LEFT/RIGHT JOINs | 🟡 |
| 04 | Advanced Analytics | Aggregations, Window Functions | 🔴 |
| 05 | Real World Project | Complete project | 🔴 |

---

## 📖 Resources

- 📚 [DuckDB Docs](https://duckdb.org/docs/)
- 🐍 [Python API](https://duckdb.org/docs/api/python/overview)
- 🌐 [DuckDB Web Shell](https://shell.duckdb.org/)
- 💬 [Discord](https://discord.duckdb.org/)

---

<p align="center">
  <b>Happy Quacking! 🦆</b>
</p>