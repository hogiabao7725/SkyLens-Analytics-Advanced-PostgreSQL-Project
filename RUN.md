# SkyLens Execution Guide

This document provides step-by-step instructions to initialize the database architecture, load the BTS flight data, and optimize the system for performance. Follow these steps in exact order to deploy the environment successfully.

> **Prerequisites:** `PostgreSQL 16+`, the `PostGIS` extension, and `Python 3` with the standard library **`venv`** module (typically bundled with Python 3.3+).
>
> **Connection modes (choose one):**
> - **Mode A - Explicit connection**: `-h localhost -U postgres` (works when pg_hba uses password/md5/scram).
> - **Mode B - Peer auth local**: `psql -d skylens ...` (works when your OS user is mapped by peer auth).

---

## Step 0: Database Initialization
Drop the old database (if it exists) and recreate a fresh, clean environment.

```bash
# Mode A (explicit host/user)
dropdb -U postgres -h localhost --if-exists skylens
createdb -U postgres -h localhost skylens

# Mode B (peer auth local)
dropdb --if-exists skylens
createdb skylens
```

## Step 1: One-shot SQL Deployment (without indexing)
Deploy toàn bộ schema, partitioning, triggers, functions/procedures và views bằng 1 lệnh.

```bash
# Mode A
psql -h localhost -U postgres -d skylens -f sql/deploy.sql

# Mode B
psql -d skylens -f sql/deploy.sql
```

> Canonical module map: `sql/INDEX.md`

## Step 2: Data Ingestion (ETL)
Execute the Python script to extract messy CSV data from the Bureau of Transportation Statistics, transform it, and load it into PostgreSQL.

Use a **project virtual environment** (`.venv` in the repo root) so ingest dependencies (`pandas`, `psycopg2`, …) do not collide with system Python (*môi trường ảo — làm một lần cho mỗi máy/cloned repo*).

### 2a — Create venv (chỉ cần chạy một lần)

```bash
# at repository root (directory containing README.md / sql/)
python3 -m venv .venv
```

### 2b — Activate venv và cài dependencies (mỗi lần mở terminal mới làm ingest)

Linux / macOS:

```bash
source .venv/bin/activate
pip install --upgrade pip
pip install -r scripts/requirements.txt
```

Windows (PowerShell):

```powershell
.\.venv\Scripts\Activate.ps1
pip install --upgrade pip
pip install -r scripts/requirements.txt
```

(Bash trên Git for Windows): `source .venv/Scripts/activate`

### 2c — Chạy ingest

```bash
# Trong terminal đã activate .venv — có thể mất vài phút
python scripts/ingest.py --year 2023
```

Khi không cần nữa: `deactivate` để thoát venv.

> **Lưu ý:** `.env` ở thư mục gốc repo (PostgreSQL URI, …) vẫn được `ingest.py` đọc như trước; venv chỉ bọc các gói Python.

## Step 3: Performance Indexing
**CRITICAL:** Only run this step **AFTER** the data has been fully ingested in Step 2. Building indexes on pre-loaded data is significantly faster and prevents severe index fragmentation.

```bash
# Mode A
psql -h localhost -U postgres -d skylens -f sql/schema/003_indexing.sql
# Mode B
psql -d skylens -f sql/schema/003_indexing.sql
```

---
*Deployment Complete! The SkyLens database is now fully populated, highly optimized, and ready to execute complex analytical queries.*

## Step 4: Final-Term SQL Showcase (Optional)
Run end-to-end quality checks, analytics, and benchmark capture for presentation/demo.

```bash
# Mode A
psql -h localhost -U postgres -d skylens -f sql/queries/quality_checks.sql
psql -h localhost -U postgres -d skylens -f sql/queries/final_showcase.sql
# Mode B
psql -d skylens -f sql/queries/quality_checks.sql
psql -d skylens -f sql/queries/final_showcase.sql
```
