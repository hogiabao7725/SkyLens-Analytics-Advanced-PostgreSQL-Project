-- =============================================================================
-- quality_checks.sql
-- Mục tiêu:
--   - Bộ truy vấn kiểm tra nhanh độ tin cậy dữ liệu trước khi demo/báo cáo.
-- Cách dùng:
--   - Chạy toàn bộ file bằng psql để xem snapshot chất lượng dữ liệu.
-- =============================================================================

-- =============================================================================
-- sql/queries/quality_checks.sql
-- Validation queries for data reliability and integrity
-- =============================================================================

-- Out-of-range values (should be close to 0)
SELECT
    COUNT(*) FILTER (WHERE dep_delay_min < -120) AS bad_dep_delay_rows,
    COUNT(*) FILTER (WHERE arr_delay_min < -120) AS bad_arr_delay_rows,
    COUNT(*) FILTER (WHERE distance_miles <= 0) AS bad_distance_rows
FROM flights;

-- Duplicates on business key (should be 0 due to unique index)
SELECT
    flight_date,
    airline_code,
    flight_number,
    origin,
    destination,
    dep_time,
    COUNT(*) AS cnt
FROM flights
GROUP BY 1,2,3,4,5,6
HAVING COUNT(*) > 1
ORDER BY cnt DESC
LIMIT 50;

-- Partition distribution overview
SELECT
    date_trunc('month', flight_date)::date AS month,
    COUNT(*) AS row_count
FROM flights
GROUP BY 1
ORDER BY 1;

-- Trigger effect check: delay_audit_log coverage for severe delay
SELECT
    COUNT(*) AS severe_flights,
    (
      SELECT COUNT(*) FROM delay_audit_log WHERE delay_category = 'severe'
    ) AS severe_logged
FROM flights
WHERE cancelled = FALSE AND arr_delay_min > 60;
