-- =============================================================================
-- 003_indexes.sql
-- Tạo indexes cho tất cả các bảng
--
-- Chạy SAU 002_partitions.sql và SAU KHI import dữ liệu xong
-- (tạo index trên bảng đã có data nhanh hơn tạo trước rồi insert từng row)
--
-- Cách dùng:
--   psql -h localhost -U postgres -d skylens -f sql/schema/003_indexes.sql
--
-- Thứ tự tạo index có chủ ý:
--   1. Indexes cho airports & airlines (nhỏ, nhanh)
--   2. Indexes chính cho flights (lớn, tốn thời gian)
--   3. Partial indexes (chỉ index subset rows, nhỏ hơn full index)
--   4. GIN indexes (full-text search)
--   5. BRIN indexes (cho time-series, rất nhỏ)
--   6. PostGIS spatial index
-- =============================================================================

-- Tắt thông báo "already exists" khi chạy lại
SET client_min_messages = 'warning';

\echo '>>> [1/6] Indexes cho airports & airlines...'

-- -----------------------------------------------------------------------------
-- airports
-- -----------------------------------------------------------------------------

-- Tìm kiếm theo quốc gia (PostGIS query: airports trong 1 country)
CREATE INDEX IF NOT EXISTS idx_airports_country
    ON airports (country);

-- PostGIS spatial index — QUAN TRỌNG cho ST_DWithin, ST_Distance
-- Không có index này, query PostGIS sẽ scan toàn bộ 74k airports
CREATE INDEX IF NOT EXISTS idx_airports_location
    ON airports USING GIST (location);

COMMENT ON INDEX idx_airports_location IS
    'Spatial index cho PostGIS queries (ST_DWithin, ST_Distance).
     Bắt buộc để ST_DWithin chạy nhanh trên 74k airports.';

-- Full-text search index cho airports (tìm theo tên/thành phố)
-- GIN index phù hợp cho tsvector vì nó inverted index từng lexeme
CREATE INDEX IF NOT EXISTS idx_airports_fts
    ON airports USING GIN (search_vector)
    WHERE search_vector IS NOT NULL;

COMMENT ON INDEX idx_airports_fts IS
    'GIN index cho full-text search. Dùng với: search_vector @@ to_tsquery(...)';

-- -----------------------------------------------------------------------------
-- airlines
-- -----------------------------------------------------------------------------

-- Full-text search cho airlines
CREATE INDEX IF NOT EXISTS idx_airlines_fts
    ON airlines USING GIN (search_vector)
    WHERE search_vector IS NOT NULL;


\echo '>>> [2/6] Indexes chính cho flights (có thể mất vài phút)...'

-- -----------------------------------------------------------------------------
-- flights — Indexes theo query pattern thực tế
--
-- Nguyên tắc: Mỗi index giải quyết 1 nhóm query cụ thể.
-- Không tạo index thừa vì mỗi index tốn disk và làm chậm INSERT.
-- -----------------------------------------------------------------------------

-- INDEX 1: airline_code + flight_date
-- Query pattern: "Hãng AA hoạt động thế nào trong tháng 6/2023?"
--   WHERE airline_code = 'AA' AND flight_date BETWEEN '...' AND '...'
-- Composite index: airline_code đứng trước vì selectivity cao hơn date range
CREATE INDEX IF NOT EXISTS idx_flights_airline_date
    ON flights (airline_code, flight_date);

COMMENT ON INDEX idx_flights_airline_date IS
    'Tối ưu query lọc theo hãng bay + khoảng thời gian.
     Dùng cho: window function ranking, airline performance analysis.';


-- INDEX 2: origin + destination
-- Query pattern: "Route JFK → LAX có bao nhiêu chuyến? Delay trung bình?"
--   WHERE origin = 'JFK' AND destination = 'LAX'
-- Cũng cover query chỉ lọc theo origin (B-tree prefix rule)
CREATE INDEX IF NOT EXISTS idx_flights_origin_dest
    ON flights (origin, destination);

COMMENT ON INDEX idx_flights_origin_dest IS
    'Tối ưu query theo route (origin → destination) và PostGIS join.
     Cũng cover query chỉ filter origin (idx prefix).';


-- INDEX 3: flight_date đơn lẻ
-- Mặc dù có partition theo date, index này giúp query trong 1 partition
-- khi điều kiện date là range rộng (vd: cả quý, cả năm)
-- Không cần nếu chỉ query theo tháng (partition pruning đã đủ)
CREATE INDEX IF NOT EXISTS idx_flights_date
    ON flights (flight_date DESC);

COMMENT ON INDEX idx_flights_date IS
    'Index cho query ORDER BY flight_date DESC (dashboard "chuyến bay mới nhất").
     DESC vì UI thường hiển thị ngày gần nhất trước.';


-- INDEX 4: Partial index — chỉ chuyến bay bị delay (arr_delay_min > 15)
-- Tại sao partial? Vì ~70% chuyến bay đúng giờ, không cần index chúng.
-- Partial index nhỏ hơn full index ~70%, fit vào RAM tốt hơn.
-- Query pattern: "Top routes bị delay nặng nhất"
--   WHERE arr_delay_min > 15 AND NOT cancelled
CREATE INDEX IF NOT EXISTS idx_flights_delayed
    ON flights (arr_delay_min DESC)
    WHERE arr_delay_min > 15 AND cancelled = FALSE;

COMMENT ON INDEX idx_flights_delayed IS
    'Partial index chỉ cho các chuyến bay bị delay (>15 phút, không bị hủy).
     Nhỏ hơn full index ~70%, phù hợp RAM hơn.
     Điều kiện WHERE phải khớp chính xác trong query để Postgres dùng index này.';


-- INDEX 5: Partial index — chuyến bay bị hủy
-- Query pattern: "Tỷ lệ hủy của từng hãng theo tháng"
-- Partial vì chỉ ~2-3% chuyến bị hủy
CREATE INDEX IF NOT EXISTS idx_flights_cancelled
    ON flights (airline_code, flight_date)
    WHERE cancelled = TRUE;

COMMENT ON INDEX idx_flights_cancelled IS
    'Partial index cho chuyến bay bị hủy (~2-3% tổng số).
     Tối ưu query: GROUP BY airline_code WHERE cancelled = TRUE.';


-- INDEX 6: Composite cho window function query 2 (moving average)
-- Query pattern:
--   SELECT flight_date, airline_code, AVG(arr_delay_min)
--   FROM flights
--   WHERE cancelled = FALSE
--   GROUP BY flight_date, airline_code
--   ORDER BY airline_code, flight_date
-- Index bao gồm arr_delay_min để enable Index-Only Scan (không cần đọc heap)
CREATE INDEX IF NOT EXISTS idx_flights_window_fn
    ON flights (airline_code, flight_date, arr_delay_min)
    WHERE cancelled = FALSE;

COMMENT ON INDEX idx_flights_window_fn IS
    'Covering index cho window function queries (moving average, rolling stats).
     Include arr_delay_min để enable Index-Only Scan.
     WHERE cancelled = FALSE loại bỏ ~2-3% rows không cần thiết.';


-- INDEX 7: origin + flight_date — cho PostGIS join query
-- Query: "Sân bay nào trong bán kính 500km từ NYC bị delay nhiều nhất?"
--   JOIN airports ON airports.iata_code = flights.origin
--   WHERE ST_DWithin(...) AND flight_date >= ...
CREATE INDEX IF NOT EXISTS idx_flights_origin_date
    ON flights (origin, flight_date)
    WHERE cancelled = FALSE;

COMMENT ON INDEX idx_flights_origin_date IS
    'Tối ưu PostGIS join queries: filter theo origin airport + time range.';


\echo '>>> [3/6] BRIN index cho time-series data...'

-- -----------------------------------------------------------------------------
-- BRIN (Block Range INdex) cho flight_date trên toàn bảng
--
-- Tại sao BRIN thay vì B-tree thêm?
--   - BTS data được insert theo thứ tự thời gian (tháng 1, tháng 2, ...)
--   - BRIN lưu min/max date cho mỗi block → rất nhỏ (vài KB cho cả bảng)
--   - Phù hợp cho range scan trên time-series data có correlation cao
--   - Không thay thế được B-tree, nhưng bổ sung cho query range rộng
--
-- Partition pruning đã làm việc này, nhưng BRIN giúp thêm bên trong partition
-- khi query range lớn hơn 1 tháng (vd: WHERE flight_date >= '2023-Q1')
-- -----------------------------------------------------------------------------

CREATE INDEX IF NOT EXISTS idx_flights_date_brin
    ON flights USING BRIN (flight_date)
    WITH (pages_per_range = 128);

COMMENT ON INDEX idx_flights_date_brin IS
    'BRIN index cho flight_date — cực nhỏ (~KB), phù hợp time-series data
     được insert tuần tự theo ngày. Bổ sung cho partition pruning.
     pages_per_range=128: 1 entry đại diện cho 128 pages liên tiếp.';


\echo '>>> [4/6] Indexes cho delay_audit_log...'

-- -----------------------------------------------------------------------------
-- delay_audit_log — bảng này được insert bởi trigger, query chủ yếu là:
--   - "Có bao nhiêu chuyến severe delay của hãng X?"
--   - "Log của route JFK→LAX trong tuần này?"
-- -----------------------------------------------------------------------------

CREATE INDEX IF NOT EXISTS idx_audit_airline_date
    ON delay_audit_log (airline_code, flight_date);

CREATE INDEX IF NOT EXISTS idx_audit_category
    ON delay_audit_log (delay_category, flight_date)
    WHERE delay_category IN ('major', 'severe');

COMMENT ON INDEX idx_audit_category IS
    'Partial index chỉ cho major/severe delays.
     Dùng cho dashboard: "số chuyến delay nghiêm trọng hôm nay".';

CREATE INDEX IF NOT EXISTS idx_audit_logged_at
    ON delay_audit_log (logged_at DESC);

COMMENT ON INDEX idx_audit_logged_at IS
    'Index cho real-time feed: SELECT * FROM delay_audit_log ORDER BY logged_at DESC LIMIT 20';


\echo '>>> [5/6] Indexes cho benchmark_results...'

-- -----------------------------------------------------------------------------
-- benchmark_results — bảng nhỏ, ít cần index
-- Chỉ cần index để sort theo thời gian tạo (dashboard benchmark)
-- -----------------------------------------------------------------------------

CREATE INDEX IF NOT EXISTS idx_benchmark_created
    ON benchmark_results (created_at DESC);


\echo '>>> [6/6] Kiểm tra tất cả indexes...'

-- -----------------------------------------------------------------------------
-- VERIFY: In ra danh sách indexes vừa tạo
-- -----------------------------------------------------------------------------
DO $$
DECLARE
    r       RECORD;
    cnt     INT := 0;
BEGIN
    RAISE NOTICE '';
    RAISE NOTICE '%-40s | %-20s | %-10s | %s',
                 'Index Name', 'Table', 'Type', 'Columns';
    RAISE NOTICE '%', REPEAT('-', 100);

    FOR r IN
        SELECT
            i.relname                          AS index_name,
            t.relname                          AS table_name,
            am.amname                          AS index_type,
            STRING_AGG(a.attname, ', '
                       ORDER BY u.indkey_subscript) AS columns,
            pg_size_pretty(pg_relation_size(i.oid)) AS index_size,
            CASE WHEN ix.indisunique THEN 'UNIQUE' ELSE '' END AS is_unique
        FROM
            pg_index ix
            JOIN pg_class     i  ON i.oid  = ix.indexrelid
            JOIN pg_class     t  ON t.oid  = ix.indrelid
            JOIN pg_am        am ON am.oid = i.relam
            JOIN pg_namespace n  ON n.oid  = t.relnamespace
            JOIN LATERAL unnest(ix.indkey) WITH ORDINALITY
                 AS u(attnum, indkey_subscript) ON TRUE
            LEFT JOIN pg_attribute a
                 ON a.attrelid = t.oid AND a.attnum = u.attnum AND a.attnum > 0
        WHERE n.nspname = 'public'
          AND t.relname IN ('flights', 'airports', 'airlines',
                            'delay_audit_log', 'benchmark_results')
          AND NOT ix.indisprimary
        GROUP BY i.relname, t.relname, am.amname,
                 ix.indisunique, i.oid
        ORDER BY t.relname, i.relname
    LOOP
        RAISE NOTICE '%-40s | %-20s | %-10s | %s (%s) %s',
                     r.index_name, r.table_name, r.index_type,
                     r.columns, r.index_size, r.is_unique;
        cnt := cnt + 1;
    END LOOP;

    RAISE NOTICE '';
    RAISE NOTICE '✓ Tổng cộng % indexes đã được tạo.', cnt;
END;
$$;


-- =============================================================================
-- HƯỚNG DẪN BENCHMARK (copy vào psql để demo cho thầy)
-- =============================================================================
--
-- Sau khi import data, chạy các lệnh sau để demo trước/sau index:
--
-- [1] Disable index tạm thời để đo baseline:
--     SET enable_indexscan   = OFF;
--     SET enable_bitmapscan  = OFF;
--
--     EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT)
--     SELECT airline_code, AVG(arr_delay_min)
--     FROM flights
--     WHERE airline_code = 'AA'
--       AND flight_date BETWEEN '2023-06-01' AND '2023-08-31'
--       AND cancelled = FALSE
--     GROUP BY airline_code;
--
-- [2] Enable lại index:
--     SET enable_indexscan   = ON;
--     SET enable_bitmapscan  = ON;
--
--     -- Chạy lại query trên → so sánh Planning/Execution time
--
-- [3] Kiểm tra Index-Only Scan (idx_flights_window_fn):
--     EXPLAIN (ANALYZE, BUFFERS)
--     SELECT airline_code, flight_date, AVG(arr_delay_min)
--     FROM flights
--     WHERE cancelled = FALSE
--     GROUP BY airline_code, flight_date
--     ORDER BY airline_code, flight_date;
--     -- Mong đợi: "Index Only Scan using idx_flights_window_fn"
--
-- [4] Kiểm tra Partial index hoạt động đúng:
--     EXPLAIN (ANALYZE)
--     SELECT origin, destination, COUNT(*), AVG(arr_delay_min)
--     FROM flights
--     WHERE arr_delay_min > 15 AND cancelled = FALSE
--     GROUP BY origin, destination
--     ORDER BY AVG(arr_delay_min) DESC
--     LIMIT 20;
--     -- Mong đợi: "Bitmap Index Scan on idx_flights_delayed"
--
-- [5] Kiểm tra PostGIS spatial index:
--     EXPLAIN (ANALYZE)
--     SELECT a.iata_code, a.name
--     FROM airports a
--     WHERE ST_DWithin(
--         a.location::GEOGRAPHY,
--         ST_MakePoint(-74.0060, 40.7128)::GEOGRAPHY,
--         500000
--     );
--     -- Mong đợi: "Index Scan using idx_airports_location"
--     -- KHÔNG được là: "Seq Scan on airports" (nếu thấy → index chưa được dùng)
-- =============================================================================
