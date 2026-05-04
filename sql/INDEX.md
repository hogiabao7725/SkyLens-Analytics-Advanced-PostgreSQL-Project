# SQL Module Index

This file is the quick navigation map for the SQL project.

## Numbering convention

- `001-099`: core schema
- `100-199`: triggers
- `200-299`: scalar/table functions
- `230-299`: procedures
- `300-399`: views/materialized views
- `900-999`: demo/showcase queries

## Execution order

1. `schema/001_core_schema.sql`
2. `schema/002_partitioning.sql`
3. `triggers/101_airports_fts_and_guard.sql`
4. `triggers/102_airlines_fts.sql`
5. `triggers/103_flights_delay_audit.sql`
6. `functions/211_fn_airline_score.sql`
7. `functions/212_fn_airline_ranking.sql`
8. `functions/213_fn_delay_breakdown.sql`
9. `functions/214_fn_best_routes_between.sql`
10. `functions/215_fn_route_kpi.sql`
11. `functions/221_fn_data_quality_summary.sql`
12. `functions/222_fn_invalid_airport_references.sql`
13. `functions/231_sp_run_benchmark.sql`
14. `functions/232_sp_refresh_analytics_views.sql`
15. `functions/241_sp_refresh_all_analytics.sql`
16. `functions/242_sp_capture_core_benchmarks.sql`
17. `views/materialized.sql`
18. `views/321_v_airline_monthly_trend.sql`
19. `views/331_v_airline_daily_ops.sql`
20. `views/332_v_route_risk_score.sql`
21. `schema/003_indexing.sql` (best run after ingest)

## Demo scripts (optional)

- `queries/quality_checks.sql`
- `queries/window_functions.sql`
- `queries/postgis.sql`
- `queries/final_showcase.sql`

## Legacy files

Legacy aggregate files are still kept for backward compatibility. New edits should target the numbered object files above.
