-- =============================================================================
-- sql/functions/benchmarks.sql
-- Stored Procedure Benchmarking và Testing Hệ thống
--
-- Chứa các hàm hỗ trợ đo kiểm Explain Analyze (thời gian trước và sau)
-- Tách riêng biệt khỏi các hàm phân tích chuyến bay (Analytics).
-- =============================================================================

-- -----------------------------------------------------------------------------
-- PROCEDURE: Stored Procedure cập nhật benchmark_results
--
-- Dùng để đo và lưu kết quả EXPLAIN ANALYZE vào DB,
-- sau đó hiển thị lên màn hình Benchmark Viewer trong UI.
-- -----------------------------------------------------------------------------

CREATE OR REPLACE PROCEDURE sp_run_benchmark(
    p_query_name  TEXT,
    p_description TEXT,
    p_sql_before  TEXT,   -- query không có index/optimization
    p_sql_after   TEXT    -- query có index/optimization
)
LANGUAGE plpgsql AS $$
DECLARE
    v_start_ms   NUMERIC;
    v_end_ms     NUMERIC;
    v_before_ms  NUMERIC;
    v_after_ms   NUMERIC;
    v_explain    TEXT;
BEGIN
    -- Đo thời gian query BEFORE
    v_start_ms := EXTRACT(EPOCH FROM clock_timestamp()) * 1000;
    EXECUTE p_sql_before;
    v_end_ms := EXTRACT(EPOCH FROM clock_timestamp()) * 1000;
    v_before_ms := ROUND((v_end_ms - v_start_ms)::NUMERIC, 2);

    -- Lấy EXPLAIN ANALYZE của query AFTER
    EXECUTE 'EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT) ' || p_sql_after
    INTO v_explain;

    -- Đo thời gian query AFTER
    v_start_ms := EXTRACT(EPOCH FROM clock_timestamp()) * 1000;
    EXECUTE p_sql_after;
    v_end_ms := EXTRACT(EPOCH FROM clock_timestamp()) * 1000;
    v_after_ms := ROUND((v_end_ms - v_start_ms)::NUMERIC, 2);

    -- Lưu kết quả
    INSERT INTO benchmark_results (
        query_name, description, before_ms, after_ms, explain_text
    ) VALUES (
        p_query_name, p_description, v_before_ms, v_after_ms, v_explain
    );

    RAISE NOTICE 'Benchmark "%": before=% ms | after=% ms | improvement=% %%',
        p_query_name,
        v_before_ms,
        v_after_ms,
        ROUND(100 * (v_before_ms - v_after_ms) / NULLIF(v_before_ms, 0), 1);
END;
$$;

COMMENT ON PROCEDURE sp_run_benchmark(TEXT, TEXT, TEXT, TEXT) IS
    'Đo thời gian 2 query (before/after optimization) và lưu vào benchmark_results.
     Dùng cho màn hình Benchmark Viewer trong UI.';
