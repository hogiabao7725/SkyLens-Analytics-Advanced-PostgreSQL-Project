-- =============================================================================
-- 221_fn_data_quality_summary.sql
-- Hàm: fn_data_quality_summary
-- Mục tiêu:
--   - Tổng hợp nhanh các chỉ số chất lượng dữ liệu theo khoảng ngày.
--   - Hỗ trợ kiểm tra trước khi làm báo cáo/benchmark.
-- =============================================================================

CREATE OR REPLACE FUNCTION fn_data_quality_summary(
    p_start_date DATE,
    p_end_date   DATE
)
RETURNS TABLE (
    metric_name    TEXT,
    metric_value   BIGINT,
    metric_percent NUMERIC
) AS $$
DECLARE
    v_total BIGINT;
BEGIN
    SELECT COUNT(*) INTO v_total
    FROM flights
    WHERE flight_date BETWEEN p_start_date AND p_end_date;

    RETURN QUERY
    WITH base AS (
        SELECT * FROM flights
        WHERE flight_date BETWEEN p_start_date AND p_end_date
    ),
    metrics AS (
        SELECT 'total_rows'::TEXT AS name, COUNT(*)::BIGINT AS value FROM base
        UNION ALL SELECT 'null_dep_time', COUNT(*)::BIGINT FROM base WHERE dep_time IS NULL
        UNION ALL SELECT 'null_arr_time', COUNT(*)::BIGINT FROM base WHERE arr_time IS NULL
        UNION ALL SELECT 'cancelled_rows', COUNT(*)::BIGINT FROM base WHERE cancelled = TRUE
        UNION ALL SELECT 'negative_distance', COUNT(*)::BIGINT FROM base WHERE distance_miles IS NOT NULL AND distance_miles <= 0
        UNION ALL
        SELECT 'missing_delay_breakdown_on_delayed', COUNT(*)::BIGINT
        FROM base
        WHERE cancelled = FALSE
          AND arr_delay_min > 15
          AND carrier_delay IS NULL
          AND weather_delay IS NULL
          AND nas_delay IS NULL
          AND security_delay IS NULL
          AND late_aircraft_delay IS NULL
    )
    SELECT
        m.name,
        m.value,
        ROUND(100.0 * m.value / NULLIF(v_total, 0), 3)
    FROM metrics m
    ORDER BY CASE WHEN m.name = 'total_rows' THEN 0 ELSE 1 END, m.value DESC;
END;
$$ LANGUAGE plpgsql STABLE;

COMMENT ON FUNCTION fn_data_quality_summary(DATE, DATE) IS
    'Tổng hợp data quality theo khoảng ngày cho flights.';
