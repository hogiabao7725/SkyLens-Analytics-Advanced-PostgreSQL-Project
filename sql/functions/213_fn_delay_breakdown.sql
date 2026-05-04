-- =============================================================================
-- 213_fn_delay_breakdown.sql
-- Hàm: fn_delay_breakdown
-- Mục tiêu:
--   - Tách tổng delay theo từng nguyên nhân (carrier/weather/NAS/security/late).
--   - Trả về tỷ trọng từng nguyên nhân trong tổng delay.
-- =============================================================================

CREATE OR REPLACE FUNCTION fn_delay_breakdown(
    p_airline_code CHAR(2),
    p_start_date   DATE,
    p_end_date     DATE
)
RETURNS TABLE (
    delay_cause         TEXT,
    total_minutes       BIGINT,
    avg_minutes         NUMERIC,
    flight_count        BIGINT,
    pct_of_total_delay  NUMERIC
) AS $$
BEGIN
    RETURN QUERY
    WITH cause_totals AS (
        SELECT
            SUM(COALESCE(carrier_delay, 0) + COALESCE(weather_delay, 0) + COALESCE(nas_delay, 0)
                + COALESCE(security_delay, 0) + COALESCE(late_aircraft_delay, 0)) AS grand_total
        FROM flights
        WHERE airline_code = p_airline_code
          AND flight_date BETWEEN p_start_date AND p_end_date
          AND NOT cancelled
          AND arr_delay_min > 0
    ),
    breakdown AS (
        SELECT 'Carrier' AS cause, carrier_delay AS minutes FROM flights
        WHERE airline_code = p_airline_code AND flight_date BETWEEN p_start_date AND p_end_date
          AND NOT cancelled AND carrier_delay > 0
        UNION ALL
        SELECT 'Weather', weather_delay FROM flights
        WHERE airline_code = p_airline_code AND flight_date BETWEEN p_start_date AND p_end_date
          AND NOT cancelled AND weather_delay > 0
        UNION ALL
        SELECT 'NAS', nas_delay FROM flights
        WHERE airline_code = p_airline_code AND flight_date BETWEEN p_start_date AND p_end_date
          AND NOT cancelled AND nas_delay > 0
        UNION ALL
        SELECT 'Security', security_delay FROM flights
        WHERE airline_code = p_airline_code AND flight_date BETWEEN p_start_date AND p_end_date
          AND NOT cancelled AND security_delay > 0
        UNION ALL
        SELECT 'Late Aircraft', late_aircraft_delay FROM flights
        WHERE airline_code = p_airline_code AND flight_date BETWEEN p_start_date AND p_end_date
          AND NOT cancelled AND late_aircraft_delay > 0
    )
    SELECT
        b.cause::TEXT,
        SUM(b.minutes)::BIGINT,
        ROUND(AVG(b.minutes)::NUMERIC, 2),
        COUNT(*)::BIGINT,
        ROUND(100.0 * SUM(b.minutes) / NULLIF(ct.grand_total, 0), 2)
    FROM breakdown b, cause_totals ct
    GROUP BY b.cause, ct.grand_total
    ORDER BY SUM(b.minutes) DESC;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION fn_delay_breakdown(CHAR, DATE, DATE) IS
    'Phân tích nguyên nhân delay theo hãng bay và khoảng thời gian.';
