-- =============================================================================
-- 215_fn_route_kpi.sql
-- Hàm: fn_route_kpi
-- Mục tiêu:
--   - Trả về KPI thực dụng cho một route trong khoảng ngày.
--   - Dùng trực tiếp cho dashboard/API/benchmark.
-- =============================================================================

CREATE OR REPLACE FUNCTION fn_route_kpi(
    p_origin       CHAR(3),
    p_destination  CHAR(3),
    p_start_date   DATE,
    p_end_date     DATE
)
RETURNS TABLE (
    total_flights      BIGINT,
    completed_flights  BIGINT,
    cancelled_flights  BIGINT,
    cancellation_rate  NUMERIC,
    on_time_pct        NUMERIC,
    avg_arr_delay_min  NUMERIC
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        COUNT(*)::BIGINT,
        COUNT(*) FILTER (WHERE NOT f.cancelled)::BIGINT,
        COUNT(*) FILTER (WHERE f.cancelled)::BIGINT,
        ROUND(100.0 * COUNT(*) FILTER (WHERE f.cancelled) / NULLIF(COUNT(*), 0), 2),
        ROUND(
            100.0 * COUNT(*) FILTER (WHERE NOT f.cancelled AND f.arr_delay_min <= 15)
            / NULLIF(COUNT(*) FILTER (WHERE NOT f.cancelled), 0),
            2
        ),
        ROUND(AVG(f.arr_delay_min) FILTER (WHERE NOT f.cancelled)::NUMERIC, 2)
    FROM flights f
    WHERE f.origin = p_origin
      AND f.destination = p_destination
      AND f.flight_date BETWEEN p_start_date AND p_end_date;
END;
$$ LANGUAGE plpgsql STABLE;

COMMENT ON FUNCTION fn_route_kpi(CHAR, CHAR, DATE, DATE) IS
    'KPI tổng hợp cho một route: volume, cancellation rate, on-time và average delay.';
