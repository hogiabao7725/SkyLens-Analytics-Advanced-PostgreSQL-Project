-- =============================================================================
-- sql/deploy.sql
-- One-shot SQL deployment cho toàn bộ database project
-- Gợi ý:
--   psql -h localhost -U postgres -d skylens -f sql/deploy.sql
-- =============================================================================

\echo '>>> [1/6] Core schema'
\i sql/schema/001_core_schema.sql
\i sql/schema/002_partitioning.sql

\echo '>>> [2/6] Triggers'
\i sql/triggers/101_airports_fts_and_guard.sql
\i sql/triggers/102_airlines_fts.sql
\i sql/triggers/103_flights_delay_audit.sql

\echo '>>> [3/6] Functions and procedures'
\i sql/functions/211_fn_airline_score.sql
\i sql/functions/212_fn_airline_ranking.sql
\i sql/functions/213_fn_delay_breakdown.sql
\i sql/functions/214_fn_best_routes_between.sql
\i sql/functions/215_fn_route_kpi.sql
\i sql/functions/221_fn_data_quality_summary.sql
\i sql/functions/222_fn_invalid_airport_references.sql
\i sql/functions/231_sp_run_benchmark.sql
\i sql/functions/232_sp_refresh_analytics_views.sql
\i sql/functions/241_sp_refresh_all_analytics.sql
\i sql/functions/242_sp_capture_core_benchmarks.sql

\echo '>>> [4/6] Views'
\i sql/views/materialized.sql
\i sql/views/321_v_airline_monthly_trend.sql
\i sql/views/331_v_airline_daily_ops.sql
\i sql/views/332_v_route_risk_score.sql

\echo '>>> [5/5] Deployment complete (không bao gồm indexing)'
