-- =============================================================================
-- 232_sp_refresh_analytics_views.sql
-- Procedure: sp_refresh_analytics_views
-- Mục tiêu:
--   - Refresh toàn bộ materialized views phục vụ analytics.
-- =============================================================================

CREATE OR REPLACE PROCEDURE sp_refresh_analytics_views()
LANGUAGE plpgsql AS $$
BEGIN
    REFRESH MATERIALIZED VIEW CONCURRENTLY mv_airline_summary;
    REFRESH MATERIALIZED VIEW CONCURRENTLY mv_delay_heatmap;
    REFRESH MATERIALIZED VIEW CONCURRENTLY mv_top_routes;
    REFRESH MATERIALIZED VIEW CONCURRENTLY mv_monthly_trend;
    REFRESH MATERIALIZED VIEW CONCURRENTLY mv_route_performance;
END;
$$;

COMMENT ON PROCEDURE sp_refresh_analytics_views() IS
    'Refresh đồng bộ toàn bộ materialized views phục vụ analytics dashboard.';
