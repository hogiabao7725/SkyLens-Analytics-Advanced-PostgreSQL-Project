-- =============================================================================
-- 212_fn_airline_ranking.sql
-- Hàm: fn_airline_ranking
-- Mục tiêu:
--   - Xếp hạng các hãng bay theo performance score trong khoảng ngày.
--   - Loại hãng có volume quá thấp để giảm nhiễu thống kê.
-- =============================================================================

CREATE OR REPLACE FUNCTION fn_airline_ranking(
    p_start_date DATE,
    p_end_date   DATE
)
RETURNS TABLE (
    rank_position       INT,
    airline_code        CHAR(2),
    airline_name        TEXT,
    total_flights       BIGINT,
    on_time_pct         NUMERIC,
    avg_arr_delay_min   NUMERIC,
    cancellation_rate   NUMERIC,
    performance_score   NUMERIC
) AS $$
BEGIN
    RETURN QUERY
    WITH base_stats AS (
        SELECT
            f.airline_code,
            COUNT(*) AS total_flights,
            ROUND(
                100.0 * SUM(CASE WHEN NOT f.cancelled AND f.arr_delay_min <= 15 THEN 1 ELSE 0 END)
                / NULLIF(SUM(CASE WHEN NOT f.cancelled THEN 1 ELSE 0 END), 0),
                2
            ) AS on_time_pct,
            ROUND(AVG(CASE WHEN NOT f.cancelled THEN f.arr_delay_min END)::NUMERIC, 2) AS avg_arr_delay,
            ROUND(100.0 * SUM(CASE WHEN f.cancelled THEN 1 ELSE 0 END) / NULLIF(COUNT(*), 0), 2) AS cancellation_rate
        FROM flights f
        WHERE f.flight_date BETWEEN p_start_date AND p_end_date
        GROUP BY f.airline_code
        HAVING COUNT(*) >= 100
    )
    SELECT
        RANK() OVER (ORDER BY (
            0.50 * s.on_time_pct
            + 0.30 * GREATEST(0, 100 - COALESCE(s.avg_arr_delay, 0))
            + 0.20 * (100 - COALESCE(s.cancellation_rate, 0))
        ) DESC)::INT,
        s.airline_code,
        COALESCE(a.name, 'Unknown')::TEXT,
        s.total_flights,
        s.on_time_pct,
        s.avg_arr_delay,
        s.cancellation_rate,
        ROUND(
            0.50 * s.on_time_pct
            + 0.30 * GREATEST(0, 100 - COALESCE(s.avg_arr_delay, 0))
            + 0.20 * (100 - COALESCE(s.cancellation_rate, 0)),
            2
        )
    FROM base_stats s
    LEFT JOIN airlines a ON a.iata_code = s.airline_code
    ORDER BY rank_position, s.airline_code;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION fn_airline_ranking(DATE, DATE) IS
    'Xếp hạng tất cả hãng bay theo performance score trong khoảng thời gian.';
