# SkyLens Execution Guide

This document provides step-by-step instructions to initialize the database architecture, load the BTS flight data, and optimize the system for performance. Follow these steps in exact order to deploy the environment successfully.

> **Prerequisites:** Please ensure you have `PostgreSQL 16+`, the `PostGIS` extension, and `Python 3` installed locally. The commands below default to the `postgres` user connecting via `localhost`.

---

## Step 0: Database Initialization
Drop the old database (if it exists) and recreate a fresh, clean environment.

```bash
dropdb -U postgres -h localhost --if-exists skylens
createdb -U postgres -h localhost skylens
```

## Step 1: Core Schema & Partitions
Define the foundational tables, relationships, and the automated monthly partitioning structure.

```bash
# 1. Create Core Tables, Data Types, and PostGIS Extension
psql -h localhost -U postgres -d skylens -f sql/schema/001_init.sql

# 2. Allocate Monthly Partitions for the Flights Table
psql -h localhost -U postgres -d skylens -f sql/schema/002_partitions.sql
```

## Step 2: Event-Driven Logic (Triggers & Functions)
Activate database triggers to handle full-text search syncing and flight delay categorizations automatically on insert.

```bash
# 1. Start Triggers (Data Integrity & Auto-Categorization)
psql -h localhost -U postgres -d skylens -f sql/triggers/trg_airports.sql
psql -h localhost -U postgres -d skylens -f sql/triggers/trg_airlines.sql
psql -h localhost -U postgres -d skylens -f sql/triggers/trg_flights.sql

# 2. Deploy PL/pgSQL Business Logic & Benchmarking Procedures
psql -h localhost -U postgres -d skylens -f sql/functions/analytics.sql
psql -h localhost -U postgres -d skylens -f sql/functions/benchmarks.sql
```

## Step 3: Data Ingestion (ETL)
Execute the Python script to extract messy CSV data from the Bureau of Transportation Statistics, transform it, and load it into PostgreSQL.

```bash
# 1. Install required Python packages
pip install -r scripts/requirements.txt

# 2. Import 2023 flight data (This process may take several minutes)
python scripts/ingest.py --year 2023
```

## Step 4: Performance Indexing
**CRITICAL:** Only run this step **AFTER** the data has been fully ingested in Step 3. Building indexes on pre-loaded data is significantly faster and prevents severe index fragmentation.

```bash
psql -h localhost -U postgres -d skylens -f sql/schema/003_indexes.sql
```

---
*Deployment Complete! The SkyLens database is now fully populated, highly optimized, and ready to execute complex analytical queries.*
