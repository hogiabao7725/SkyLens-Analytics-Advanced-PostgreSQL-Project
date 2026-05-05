-- =============================================================================
-- 211_fn_airline_score.sql
-- Hàm: fn_airline_score
-- Mục tiêu:
--   - Tính bộ KPI tổng hợp và performance score cho 1 hãng trong khoảng ngày.
-- Input:
--   - p_airline_code, p_start_date, p_end_date
-- Output:
--   - 1 dòng metrics gồm on_time_pct, delay, cancellation_rate, performance_score.
-- =============================================================================

CREATE OR REPLACE FUNCTION fn_airline_score(
    p_airline_code  CHAR(2),
    p_start_date    DATE,
    p_end_date      DATE
)
RETURNS TABLE (
    airline_code        CHAR(2),
    total_flights       BIGINT,
    completed_flights   BIGINT,
    on_time_flights     BIGINT,
    on_time_pct         NUMERIC,
    avg_arr_delay_min   NUMERIC,
    avg_dep_delay_min   NUMERIC,
    cancellation_rate   NUMERIC,
    severe_delay_pct    NUMERIC,
    performance_score   NUMERIC
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        p_airline_code::CHAR(2),
        COUNT(*)::BIGINT,
        SUM(CASE WHEN NOT f.cancelled THEN 1 ELSE 0 END)::BIGINT,
        SUM(CASE WHEN NOT f.cancelled AND f.arr_delay_min <= 15 THEN 1 ELSE 0 END)::BIGINT,
        ROUND(
            100.0 * SUM(CASE WHEN NOT f.cancelled AND f.arr_delay_min <= 15 THEN 1 ELSE 0 END)
            / NULLIF(SUM(CASE WHEN NOT f.cancelled THEN 1 ELSE 0 END), 0),
            2
        ),
        ROUND(AVG(CASE WHEN NOT f.cancelled THEN f.arr_delay_min END)::NUMERIC, 2),
        ROUND(AVG(CASE WHEN NOT f.cancelled THEN f.dep_delay_min END)::NUMERIC, 2),
        ROUND(100.0 * SUM(CASE WHEN f.cancelled THEN 1 ELSE 0 END) / NULLIF(COUNT(*), 0), 2),
        ROUND(
            100.0 * SUM(CASE WHEN NOT f.cancelled AND f.arr_delay_min > 60 THEN 1 ELSE 0 END)
            / NULLIF(SUM(CASE WHEN NOT f.cancelled THEN 1 ELSE 0 END), 0),
            2
        ),
        ROUND(
            0.50 * (
                100.0 * SUM(CASE WHEN NOT f.cancelled AND f.arr_delay_min <= 15 THEN 1 ELSE 0 END)
                / NULLIF(SUM(CASE WHEN NOT f.cancelled THEN 1 ELSE 0 END), 0)
            )
            + 0.30 * GREATEST(0, 100 - COALESCE(AVG(CASE WHEN NOT f.cancelled THEN f.arr_delay_min END), 0))
            + 0.20 * (
                100 - COALESCE(
                    100.0 * SUM(CASE WHEN f.cancelled THEN 1 ELSE 0 END) / NULLIF(COUNT(*), 0),
                    0
                )
            ),
            2
        )
    FROM flights f
    WHERE f.airline_code = p_airline_code
      AND f.flight_date BETWEEN p_start_date AND p_end_date;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION fn_airline_score(CHAR, DATE, DATE) IS
    'Tính performance score (0-100) cho 1 hãng bay trong khoảng thời gian.';
