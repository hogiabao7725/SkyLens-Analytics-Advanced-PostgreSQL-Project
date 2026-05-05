-- =============================================================================
-- 241_sp_refresh_all_analytics.sql
-- Procedure: sp_refresh_all_analytics
-- Mục tiêu:
--   - Gọi refresh views + optional ANALYZE để planner có thống kê mới.
-- =============================================================================

CREATE OR REPLACE PROCEDURE sp_refresh_all_analytics(p_analyze_after BOOLEAN DEFAULT TRUE)
LANGUAGE plpgsql AS $$
BEGIN
    CALL sp_refresh_analytics_views();

    IF p_analyze_after THEN
        ANALYZE flights;
        ANALYZE airports;
        ANALYZE airlines;
        ANALYZE delay_audit_log;
    END IF;
END;
$$;

COMMENT ON PROCEDURE sp_refresh_all_analytics(BOOLEAN) IS
    'Refresh toàn bộ materialized views và ANALYZE để planner có statistics mới.';
