-- =============================================================================
-- final_showcase.sql
-- Mục tiêu:
--   - Kịch bản chạy demo cuối kỳ theo thứ tự: quality -> KPI -> views -> benchmark.
-- =============================================================================

-- =============================================================================
-- sql/queries/final_showcase.sql
-- Final defense showcase script (run top-to-bottom)
-- =============================================================================

-- 1) Data quality snapshot
SELECT * FROM fn_data_quality_summary('2023-01-01', '2023-12-31');
SELECT * FROM fn_invalid_airport_references();

-- 2) Core business KPI
SELECT * FROM fn_airline_score('AA', '2023-01-01', '2023-12-31');
SELECT * FROM fn_route_kpi('JFK', 'LAX', '2023-01-01', '2023-12-31');

-- 3) Window analytics
SELECT *
FROM v_airline_monthly_trend
WHERE airline_code IN ('AA', 'DL', 'UA')
ORDER BY airline_code, month;

-- 4) Materialized view usage
CALL sp_refresh_all_analytics(TRUE);
SELECT *
FROM mv_top_routes
ORDER BY total_flights DESC
LIMIT 20;

-- 5) Lightweight reporting views
SELECT *
FROM v_route_risk_score
ORDER BY risk_score DESC
LIMIT 20;

SELECT *
FROM v_airline_daily_ops
WHERE airline_code = 'AA'
ORDER BY flight_date DESC
LIMIT 30;

-- 6) Benchmark capture
CALL sp_capture_core_benchmarks();
SELECT id, query_name, before_ms, after_ms, created_at
FROM benchmark_results
ORDER BY created_at DESC
LIMIT 10;
