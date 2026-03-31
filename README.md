# SkyLens Analytics: Advanced PostgreSQL Project

SkyLens is an academic data engineering and analytics project built around the [BTS (Bureau of Transportation Statistics)](https://www.transtats.bts.gov/) flight dataset. The primary goal of this project is to model, store, and analyze massive amounts of aviation data utilizing the full power of advanced PostgreSQL features.

---

## 🗺️ Project Roadmap

The project is divided into two major academic milestones to ensure a logical progression from raw database architecture to a fully functional modern web application.

### 📍 Midterm Objective: The Database Layer (Current Phase)
The first half of the project focuses strictly on **Database Architecture and Advanced SQL Techniques**. The goal is to build an extremely robust, highly optimized, and self-sufficient database system.
*   **Data Ingestion:** A robust Python pipeline that parses messy CSV datasets and normalizes them for the database.
*   **Partitioning:** Dividing the massive `flights` table into monthly partitions (`PARTITION BY RANGE`) to drastically improve query performance via Partition Pruning.
*   **Advanced Indexing:** Utilizing specialized indexes like **GIN** for Full-Text Search, **BRIN** for sequential time-series data, and **Partial Indexes** for highly targeted queries.
*   **Triggers & Automation:** Using trigger functions to auto-classify flight delays, asynchronously update `tsvector` search columns, and enforce strict referential integrity.
*   **Stored Functions:** Offloading heavy business logic (like calculating aggregate airline performance scores) from the future application layer directly into the database using `PL/pgSQL`.
*   **Window Functions:** Leveraging advanced analytical queries (`LAG`, `OVER`, `PARTITION BY`, `ROWS BETWEEN`) to compute moving averages and identify time-series anomalies.
*   **Geospatial Processing:** Using the PostGIS extension to handle exact airport coordinate points and calculate spatial routing.

*(Note: There is no UI or API during this phase, all interactions happen via the terminal and pure SQL).*

### 📍 Final Term Objective: The Application Layer (Upcoming Phase)
The second half of the project will shift focus towards transforming this powerful database into an accessible, visual product.
*   **Backend API Development:** Building a secure API (using Golang or Node.js) to serve as a bridge between the database functions and the client.
*   **Materialized Views Integration:** Implementing `MATERIALIZED VIEW` constructs running on automated CRON jobs to pre-calculate heavy dashboard statistics overnight.
*   **Frontend Dashboard:** Developing a modern UI (React/Next.js) to visualize flight delays, display interactive PostGIS maps, and rank airlines via charts.
*   **System Benchmarking UI:** Creating an admin screen that visualizes the difference in query execution times (before/after indexing) based on the database's internal `benchmark_results` table.

---

## 📂 Directory Structure Explained

Every file in the `/sql` directory serves a specific, isolated purpose—adhering strictly to the Single Responsibility Principle.

```text
.
├── data/
│   └── bts/                  # Raw BTS CSV dataset files (Ignored in Git)
├── scripts/
│   ├── ingest.py             # Python ETL script for cleaning and inserting data
│   └── requirements.txt      # Python dependencies (pandas, psycopg2)
├── sql/
│   ├── schema/               # Step 1: Core Definitions (MUST be run in order)
│   │   ├── 001_init.sql      # Database tables, data types, and PostGIS extension
│   │   ├── 002_partitions.sql# Automatic monthly table partition allocations
│   │   └── 003_indexes.sql   # Performance optimizations (B-Tree, GIN, BRIN)
│   ├── triggers/             # Step 2: Event-Driven Logic
│   │   ├── trg_flights.sql   # Auto-classifies flight delays upon insert
│   │   ├── trg_airlines.sql  # Updates airline full-text search vectors
│   │   └── trg_airports.sql  # Search vectors & prevents deletion of active airports
│   ├── functions/            # Step 3: Business Logic
│   │   ├── analytics.sql     # PL/pgSQL functions for scoring and ranking airlines
│   │   └── benchmarks.sql    # Profiling tools to measure index execution speeds
│   ├── views/                # Final Phase Items
│   │   └── materialized.sql  # Pre-aggregated reporting tables (Currently unused)
│   └── queries/              # Demonstration Scripts
│       ├── postgis.sql       # Spatial queries examples (Finding nearby airports)
│       └── window_functions.sql # Complex analytical queries used for presentations
├── RUN.md                    # Exact ordered terminal commands to deploy the system
└── README.md                 # Project Overview Document
```

---

## 🚀 Prerequisites

To run this project locally, ensure you have the following installed directly on your system:
*   **PostgreSQL 16+** (Local Installation)
*   **PostGIS** Database Extension
*   **Python 3.10+** (For the ingestion script)

## 📖 Deployment & Demonstration

Please refer to the **`RUN.md`** file located in the root directory. 
It contains the exact sequential terminal commands required to initialize the database, ingest the Python data, and run the advanced PostgreSQL feature demonstrations for grading purposes.
