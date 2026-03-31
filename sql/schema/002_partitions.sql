-- =============================================================================
-- 002_partitions.sql
-- Tạo partition theo tháng cho bảng flights
--
-- Chạy SAU 001_init.sql (bảng flights phải tồn tại với PARTITION BY RANGE)
-- Chạy TRƯỚC khi import dữ liệu (ingest.py)
--
-- Cách dùng:
--   psql -h localhost -U postgres -d skylens -f sql/schema/002_partitions.sql
--
-- Để thêm năm mới (ví dụ 2024):
--   CALL sp_create_monthly_partitions(2024);
-- =============================================================================

-- -----------------------------------------------------------------------------
-- BƯỚC 1: Stored Procedure tạo partition tự động theo năm
--
-- Tại sao dùng Stored Procedure thay vì viết tay 12 CREATE TABLE?
--   → Tái sử dụng được: CALL sp_create_monthly_partitions(2024) là xong
--   → Tránh lỗi typo khi viết tay ngày tháng
--   → Demo được tính năng LOOP + dynamic SQL trong PL/pgSQL (điểm thi)
-- -----------------------------------------------------------------------------

CREATE OR REPLACE PROCEDURE sp_create_monthly_partitions(p_year INT)
LANGUAGE plpgsql AS $$
DECLARE
    v_month       INT;
    v_start_date  DATE;
    v_end_date    DATE;
    v_table_name  TEXT;
    v_exists      BOOLEAN;
BEGIN
    -- Validate năm hợp lệ (tránh tạo nhầm partition cho năm vô nghĩa)
    IF p_year < 2000 OR p_year > 2100 THEN
        RAISE EXCEPTION 'Năm không hợp lệ: %. Chỉ chấp nhận 2000–2100.', p_year;
    END IF;

    FOR v_month IN 1..12 LOOP
        v_start_date := make_date(p_year, v_month, 1);
        v_end_date   := v_start_date + INTERVAL '1 month';
        v_table_name := format('flights_%s_%s',
                               p_year,
                               lpad(v_month::TEXT, 2, '0'));

        -- Kiểm tra partition đã tồn tại chưa để tránh lỗi khi chạy lại
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

        -- Tạo partition
        EXECUTE format(
            'CREATE TABLE %I PARTITION OF flights
             FOR VALUES FROM (%L) TO (%L)',
            v_table_name,
            v_start_date,
            v_end_date
        );

        RAISE NOTICE 'Đã tạo partition: % (% → %)',
                     v_table_name, v_start_date, v_end_date;
    END LOOP;

    RAISE NOTICE '✓ Hoàn tất tạo partitions cho năm %', p_year;
END;
$$;

COMMENT ON PROCEDURE sp_create_monthly_partitions(INT) IS
    'Tạo 12 partition theo tháng cho bảng flights với năm được chỉ định.
     Bỏ qua nếu partition đã tồn tại (idempotent).
     Ví dụ: CALL sp_create_monthly_partitions(2023);';


-- -----------------------------------------------------------------------------
-- BƯỚC 2: Partition DEFAULT
--
-- Tại sao cần partition DEFAULT?
--   → Nếu không có, INSERT với flight_date ngoài range đã tạo sẽ bị lỗi
--   → Giúp ingest.py không crash khi có dữ liệu tháng lẻ
--   → Sau đó có thể MOVE sang partition chính thức bằng:
--        INSERT INTO flights_2024_01
--        SELECT * FROM flights_default WHERE flight_date >= '2024-01-01';
--        DELETE FROM flights_default WHERE flight_date >= '2024-01-01';
--
-- LƯU Ý: Partition DEFAULT phải tạo TRƯỚC khi gọi sp_create_monthly_partitions
-- vì nếu tạo sau, Postgres cần kiểm tra không có row nào trong DEFAULT
-- trùng với range của partition mới → chậm hoặc lỗi nếu đã có data.
-- -----------------------------------------------------------------------------

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE c.relname = 'flights_default'
          AND n.nspname = 'public'
    ) THEN
        CREATE TABLE flights_default PARTITION OF flights DEFAULT;
        RAISE NOTICE 'Đã tạo: flights_default (partition DEFAULT)';
    ELSE
        RAISE NOTICE 'flights_default đã tồn tại, bỏ qua.';
    END IF;
END;
$$;


-- -----------------------------------------------------------------------------
-- BƯỚC 3: Tạo partitions cho năm 2023
--
-- Note: Hiện tại chỉ tạo cho năm 2023 vì dữ liệu dùng để chấm điểm tập trung vào 2023
--   → Thêm năm khác chỉ cần: CALL sp_create_monthly_partitions(2024);
-- -----------------------------------------------------------------------------

CALL sp_create_monthly_partitions(2023);


-- -----------------------------------------------------------------------------
-- BƯỚC 4: Stored Procedure xem tổng quan partitions
--
-- Dùng để kiểm tra sau khi tạo, hoặc demo cho thầy
-- -----------------------------------------------------------------------------

CREATE OR REPLACE PROCEDURE sp_show_partition_stats()
LANGUAGE plpgsql AS $$
DECLARE
    r RECORD;
BEGIN
    RAISE NOTICE '%-30s | %s', 'Partition', 'Số rows (ước tính)';
    RAISE NOTICE '%', REPEAT('-', 55);

    FOR r IN
        SELECT
            c.relname                        AS partition_name,
            c.reltuples::BIGINT              AS estimated_rows,
            pg_size_pretty(pg_relation_size(c.oid)) AS table_size
        FROM pg_class c
        JOIN pg_inherits i  ON i.inhrelid = c.oid
        JOIN pg_class   cp ON cp.oid = i.inhparent
        WHERE cp.relname = 'flights'
          AND c.relkind = 'r'
        ORDER BY c.relname
    LOOP
        RAISE NOTICE '%-30s | %s rows | %s',
                     r.partition_name,
                     r.estimated_rows,
                     r.table_size;
    END LOOP;
END;
$$;

COMMENT ON PROCEDURE sp_show_partition_stats() IS
    'In ra danh sách tất cả partitions của bảng flights kèm số rows ước tính.
     Dùng: CALL sp_show_partition_stats();';


-- -----------------------------------------------------------------------------
-- BƯỚC 5: Function kiểm tra 1 flight_date sẽ vào partition nào
--
-- Hữu ích khi debug, hoặc demo cho thầy thấy partition pruning hoạt động
-- -----------------------------------------------------------------------------

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

COMMENT ON FUNCTION fn_get_partition_for_date(DATE) IS
    'Trả về tên partition sẽ chứa dữ liệu của ngày được chỉ định.
     Ví dụ: SELECT fn_get_partition_for_date(''2023-06-15'');
     → flights_2023_06';


-- -----------------------------------------------------------------------------
-- KIỂM TRA SAU KHI CHẠY
-- -----------------------------------------------------------------------------

-- Xem tất cả partitions đã tạo:
--   SELECT tablename FROM pg_tables
--   WHERE tablename LIKE 'flights_%'
--   ORDER BY tablename;
--
-- Xem stats từng partition:
--   CALL sp_show_partition_stats();
--
-- Kiểm tra 1 ngày sẽ vào partition nào:
--   SELECT fn_get_partition_for_date('2023-07-04');
--
-- Sau khi import data, kiểm tra partition pruning:
--   EXPLAIN (ANALYZE, BUFFERS)
--   SELECT COUNT(*) FROM flights
--   WHERE flight_date BETWEEN '2023-06-01' AND '2023-06-30';
--   -- Kết quả mong đợi: chỉ scan "flights_2023_06", bỏ qua 35 partitions còn lại
