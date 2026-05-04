-- =============================================================================
-- 214_fn_best_routes_between.sql
-- Hàm: fn_best_routes_between
-- Mục tiêu:
--   - So sánh các hãng trên cùng 1 route (origin -> destination).
--   - Sắp xếp ưu tiên on_time cao, delay thấp.
-- =============================================================================

CREATE OR REPLACE FUNCTION fn_best_routes_between(
    p_origin      CHAR(3),
    p_destination CHAR(3),
    p_start_date  DATE,
    p_end_date    DATE
)
RETURNS TABLE (
    airline_code        CHAR(2),
    airline_name        TEXT,
    total_flights       BIGINT,
    on_time_pct         NUMERIC,
    avg_arr_delay_min   NUMERIC,
    avg_distance_miles  NUMERIC,
    cancellation_rate   NUMERIC
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        f.airline_code,
        COALESCE(a.name, 'Unknown')::TEXT,
        COUNT(*)::BIGINT,
        ROUND(
            100.0 * SUM(CASE WHEN NOT f.cancelled AND f.arr_delay_min <= 15 THEN 1 ELSE 0 END)
            / NULLIF(SUM(CASE WHEN NOT f.cancelled THEN 1 ELSE 0 END), 0),
            2
        ),
        ROUND(AVG(CASE WHEN NOT f.cancelled THEN f.arr_delay_min END)::NUMERIC, 2),
        ROUND(AVG(f.distance_miles)::NUMERIC, 1),
        ROUND(100.0 * SUM(CASE WHEN f.cancelled THEN 1 ELSE 0 END) / NULLIF(COUNT(*), 0), 2)
    FROM flights f
    LEFT JOIN airlines a ON a.iata_code = f.airline_code
    WHERE f.origin = p_origin
      AND f.destination = p_destination
      AND f.flight_date BETWEEN p_start_date AND p_end_date
    GROUP BY f.airline_code, a.name
    HAVING COUNT(*) >= 10
    ORDER BY
        (100.0 * SUM(CASE WHEN NOT f.cancelled AND f.arr_delay_min <= 15 THEN 1 ELSE 0 END)
         / NULLIF(SUM(CASE WHEN NOT f.cancelled THEN 1 ELSE 0 END), 0)) DESC NULLS LAST,
        AVG(CASE WHEN NOT f.cancelled THEN f.arr_delay_min END) ASC NULLS LAST;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION fn_best_routes_between(CHAR, CHAR, DATE, DATE) IS
    'So sánh các hãng bay trên cùng một route và xếp hạng theo on-time performance.';
