-- =============================================================================
-- 331_v_airline_daily_ops.sql
-- View: v_airline_daily_ops
-- Mục tiêu:
--   - Tổng hợp vận hành theo ngày cho từng hãng.
-- =============================================================================

CREATE OR REPLACE VIEW v_airline_daily_ops AS
SELECT
    f.flight_date,
    f.airline_code,
    COUNT(*) AS total_flights,
    COUNT(*) FILTER (WHERE NOT f.cancelled) AS completed_flights,
    COUNT(*) FILTER (WHERE f.cancelled) AS cancelled_flights,
    ROUND(
        100.0 * COUNT(*) FILTER (WHERE NOT f.cancelled AND f.arr_delay_min <= 15)
        / NULLIF(COUNT(*) FILTER (WHERE NOT f.cancelled), 0), 2
    ) AS on_time_pct,
    ROUND(AVG(f.arr_delay_min) FILTER (WHERE NOT f.cancelled)::NUMERIC, 2) AS avg_arr_delay_min
FROM flights f
GROUP BY f.flight_date, f.airline_code;

COMMENT ON VIEW v_airline_daily_ops IS
    'Operational daily metrics theo hãng bay; dùng làm input cho BI query và báo cáo.';
