-- =============================================================================
-- 242_sp_capture_core_benchmarks.sql
-- Procedure: sp_capture_core_benchmarks
-- Mục tiêu:
--   - Chạy bộ benchmark mẫu cho buổi demo cuối kỳ.
-- =============================================================================

CREATE OR REPLACE PROCEDURE sp_capture_core_benchmarks()
LANGUAGE plpgsql AS $$
BEGIN
    CALL sp_run_benchmark(
        'route_kpi_lookup',
        'KPI route JFK-LAX (before: no helpful filter; after: route/date filter)',
        $$SELECT COUNT(*) FROM flights WHERE flight_date BETWEEN '2023-01-01' AND '2023-12-31'$$,
        $$SELECT * FROM fn_route_kpi('JFK','LAX','2023-01-01','2023-12-31')$$
    );

    CALL sp_run_benchmark(
        'monthly_trend_slice',
        'Monthly trend read (before direct aggregate, after materialized view)',
        $$SELECT airline_code, DATE_TRUNC('month', flight_date), AVG(arr_delay_min)
          FROM flights
          WHERE cancelled = FALSE
          GROUP BY airline_code, DATE_TRUNC('month', flight_date)$$,
        $$SELECT * FROM mv_monthly_trend WHERE airline_code = 'AA' ORDER BY month$$
    );
END;
$$;

COMMENT ON PROCEDURE sp_capture_core_benchmarks() IS
    'Chạy benchmark lõi cho cuối kỳ: route KPI và monthly trend materialized view.';
