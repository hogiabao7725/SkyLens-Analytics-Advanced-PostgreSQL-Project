-- =============================================================================
-- 231_sp_run_benchmark.sql
-- Procedure: sp_run_benchmark
-- Mục tiêu:
--   - So sánh before/after cho hai câu SQL.
--   - Chạy nhiều lần lấy trung bình, lưu EXPLAIN vào benchmark_results.
-- =============================================================================

CREATE OR REPLACE PROCEDURE sp_run_benchmark(
    p_query_name  TEXT,
    p_description TEXT,
    p_sql_before  TEXT,
    p_sql_after   TEXT
)
LANGUAGE plpgsql AS $$
DECLARE
    v_start_ms      NUMERIC;
    v_end_ms        NUMERIC;
    v_before_total  NUMERIC := 0;
    v_after_total   NUMERIC := 0;
    v_before_ms     NUMERIC;
    v_after_ms      NUMERIC;
    v_explain_after TEXT;
    v_runs          INT := 3;
    i               INT;
    v_plan_line     TEXT;
BEGIN
    IF trim(coalesce(p_sql_before, '')) = '' OR trim(coalesce(p_sql_after, '')) = '' THEN
        RAISE EXCEPTION 'Benchmark SQL không được rỗng';
    END IF;

    EXECUTE p_sql_before;
    EXECUTE p_sql_after;

    FOR i IN 1..v_runs LOOP
        v_start_ms := EXTRACT(EPOCH FROM clock_timestamp()) * 1000;
        EXECUTE p_sql_before;
        v_end_ms := EXTRACT(EPOCH FROM clock_timestamp()) * 1000;
        v_before_total := v_before_total + (v_end_ms - v_start_ms);

        v_start_ms := EXTRACT(EPOCH FROM clock_timestamp()) * 1000;
        EXECUTE p_sql_after;
        v_end_ms := EXTRACT(EPOCH FROM clock_timestamp()) * 1000;
        v_after_total := v_after_total + (v_end_ms - v_start_ms);
    END LOOP;

    v_before_ms := ROUND((v_before_total / v_runs)::NUMERIC, 2);
    v_after_ms := ROUND((v_after_total / v_runs)::NUMERIC, 2);

    v_explain_after := '';
    FOR v_plan_line IN EXECUTE 'EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT) ' || p_sql_after LOOP
        v_explain_after := v_explain_after || v_plan_line || E'\n';
    END LOOP;

    INSERT INTO benchmark_results (query_name, description, before_ms, after_ms, explain_text)
    VALUES (p_query_name, p_description, v_before_ms, v_after_ms, v_explain_after);
END;
$$;

COMMENT ON PROCEDURE sp_run_benchmark(TEXT, TEXT, TEXT, TEXT) IS
    'Đo benchmark before/after bằng trung bình 3 lần chạy và lưu full EXPLAIN plan.';
