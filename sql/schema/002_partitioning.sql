-- =============================================================================
-- 002_partitioning.sql
-- Mục tiêu:
--   - Tạo partition theo tháng cho bảng flights.
--   - Cung cấp procedure/function hỗ trợ kiểm tra partition khi demo.
-- Cách dùng nhanh:
--   - CALL sp_create_monthly_partitions(2023);
--   - CALL sp_show_partition_stats();
-- =============================================================================

-- =============================================================================
-- 002_partitioning.sql
-- Tạo partition theo tháng cho bảng flights
-- =============================================================================

CREATE OR REPLACE PROCEDURE sp_create_monthly_partitions(p_year INT)
LANGUAGE plpgsql AS $$
DECLARE
    v_month       INT;
    v_start_date  DATE;
    v_end_date    DATE;
    v_table_name  TEXT;
    v_exists      BOOLEAN;
BEGIN
    IF p_year < 2000 OR p_year > 2100 THEN
        RAISE EXCEPTION 'Năm không hợp lệ: %. Chỉ chấp nhận 2000–2100.', p_year;
    END IF;

    FOR v_month IN 1..12 LOOP
        v_start_date := make_date(p_year, v_month, 1);
        v_end_date   := v_start_date + INTERVAL '1 month';
        v_table_name := format('flights_%s_%s', p_year, lpad(v_month::TEXT, 2, '0'));

        SELECT EXISTS (
            SELECT 1 FROM pg_class c
            JOIN pg_namespace n ON n.oid = c.relnamespace
            WHERE c.relname = v_table_name
              AND n.nspname = 'public'
        ) INTO v_exists;

        IF v_exists THEN
            RAISE NOTICE 'Partition đã tồn tại, bỏ qua: %', v_table_name;
            CONTINUE;
        END IF;

        EXECUTE format(
            'CREATE TABLE %I PARTITION OF flights FOR VALUES FROM (%L) TO (%L)',
            v_table_name, v_start_date, v_end_date
        );

        RAISE NOTICE 'Đã tạo partition: % (% → %)', v_table_name, v_start_date, v_end_date;
    END LOOP;
END;
$$;

COMMENT ON PROCEDURE sp_create_monthly_partitions(INT) IS
    'Tạo 12 partition theo tháng cho bảng flights với năm được chỉ định.';

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE c.relname = 'flights_default'
          AND n.nspname = 'public'
    ) THEN
        CREATE TABLE flights_default PARTITION OF flights DEFAULT;
    END IF;
END;
$$;

CALL sp_create_monthly_partitions(2023);

CREATE OR REPLACE PROCEDURE sp_show_partition_stats()
LANGUAGE plpgsql AS $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN
        SELECT
            c.relname AS partition_name,
            c.reltuples::BIGINT AS estimated_rows,
            pg_size_pretty(pg_relation_size(c.oid)) AS table_size
        FROM pg_class c
        JOIN pg_inherits i ON i.inhrelid = c.oid
        JOIN pg_class cp ON cp.oid = i.inhparent
        WHERE cp.relname = 'flights'
          AND c.relkind = 'r'
        ORDER BY c.relname
    LOOP
        RAISE NOTICE '% | % rows | %', r.partition_name, r.estimated_rows, r.table_size;
    END LOOP;
END;
$$;

CREATE OR REPLACE FUNCTION fn_get_partition_for_date(p_date DATE)
RETURNS TEXT AS $$
DECLARE
    v_year  INT := EXTRACT(YEAR  FROM p_date)::INT;
    v_month INT := EXTRACT(MONTH FROM p_date)::INT;
    v_name  TEXT;
BEGIN
    v_name := format('flights_%s_%s', v_year, lpad(v_month::TEXT, 2, '0'));

    IF EXISTS (
        SELECT 1 FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE c.relname = v_name AND n.nspname = 'public'
    ) THEN
        RETURN v_name;
    ELSE
        RETURN 'flights_default (partition chưa được tạo cho ' || v_name || ')';
    END IF;
END;
$$ LANGUAGE plpgsql;
