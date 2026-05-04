-- =============================================================================
-- 321_v_airline_monthly_trend.sql
-- View: v_airline_monthly_trend
-- Mục tiêu:
--   - Theo dõi xu hướng hiệu suất theo tháng.
--   - Có sẵn cột month-over-month (LAG) và rank trong tháng.
-- =============================================================================

CREATE OR REPLACE VIEW v_airline_monthly_trend AS
WITH monthly AS (
    SELECT
        DATE_TRUNC('month', f.flight_date)::DATE AS month,
        f.airline_code,
        COUNT(*) FILTER (WHERE NOT f.cancelled) AS completed_flights,
        ROUND(
            100.0 * COUNT(*) FILTER (WHERE NOT f.cancelled AND f.arr_delay_min <= 15)
            / NULLIF(COUNT(*) FILTER (WHERE NOT f.cancelled), 0),
            2
        ) AS on_time_pct,
        ROUND(AVG(f.arr_delay_min) FILTER (WHERE NOT f.cancelled)::NUMERIC, 2) AS avg_arr_delay
    FROM flights f
    GROUP BY 1, 2
)
SELECT
    m.month,
    m.airline_code,
    m.completed_flights,
    m.on_time_pct,
    m.avg_arr_delay,
    LAG(m.on_time_pct) OVER (PARTITION BY m.airline_code ORDER BY m.month) AS prev_on_time_pct,
    ROUND(m.on_time_pct - LAG(m.on_time_pct) OVER (PARTITION BY m.airline_code ORDER BY m.month), 2) AS mom_change_pct,
    RANK() OVER (PARTITION BY m.month ORDER BY m.on_time_pct DESC NULLS LAST) AS rank_in_month
FROM monthly m;

COMMENT ON VIEW v_airline_monthly_trend IS
    'Window-function view theo tháng cho từng hãng: previous month, MoM change và ranking.';
