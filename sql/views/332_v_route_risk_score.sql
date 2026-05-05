-- =============================================================================
-- 332_v_route_risk_score.sql
-- View: v_route_risk_score
-- Mục tiêu:
--   - Chấm điểm "rủi ro vận hành" theo route dựa trên delay + cancellation.
-- =============================================================================

CREATE OR REPLACE VIEW v_route_risk_score AS
SELECT
    f.origin,
    f.destination,
    COUNT(*) AS total_flights,
    ROUND(AVG(f.arr_delay_min) FILTER (WHERE NOT f.cancelled)::NUMERIC, 2) AS avg_arr_delay,
    ROUND(100.0 * COUNT(*) FILTER (WHERE f.cancelled) / NULLIF(COUNT(*), 0), 2) AS cancellation_rate,
    ROUND(
        0.7 * COALESCE(AVG(f.arr_delay_min) FILTER (WHERE NOT f.cancelled), 0) +
        0.3 * (100.0 * COUNT(*) FILTER (WHERE f.cancelled) / NULLIF(COUNT(*), 0)),
        2
    ) AS risk_score
FROM flights f
GROUP BY f.origin, f.destination
HAVING COUNT(*) >= 50;

COMMENT ON VIEW v_route_risk_score IS
    'Risk score theo route để xác định route có vận hành kém (delay + cancel).';
