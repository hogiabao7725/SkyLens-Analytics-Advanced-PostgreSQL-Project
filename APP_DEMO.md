# SkyLens UI Demo (Go + React)

This guide runs a quick but presentable final-term demo app.

## 1) Backend (Go)

```bash
cd backend
go mod tidy
go run .
```

Backend default: `http://localhost:8080`

It reads DB settings from root `.env` (loaded via `../.env`).

## 0) Required SQL objects (very important)

Before running UI, ensure DB objects exist:

```bash
# deploy core objects
psql -d skylens -f sql/deploy.sql

# ingest data
python scripts/ingest.py --year 2023

# create indexes after ingest
psql -d skylens -f sql/schema/003_indexing.sql
```

## 2) Frontend (React + Vite)

```bash
cd frontend
npm install
npm run dev
```

Frontend default: `http://localhost:5173`

Optional API base override:

```bash
VITE_API_BASE=http://localhost:8080 npm run dev
```

## 3) Endpoints used by UI

- `GET /api/overview/ranking`
- `GET /api/overview/airline-score?airline_code=AA`
- `GET /api/routes/top?limit=20`
- `GET /api/routes/kpi?origin=JFK&destination=LAX`
- `GET /api/trends/monthly?airline_code=AA`
- `GET /api/quality/summary`

## Map choice: Google Maps required?

No. Demo UI uses Leaflet + OpenStreetMap (free, no API key required), which is faster for classroom demos.
