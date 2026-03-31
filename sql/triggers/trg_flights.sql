-- =============================================================================
-- sql/triggers/trg_flights.sql
-- Trigger tự động phân loại và ghi log delay khi có chuyến bay INSERT
--
-- Cần chạy sau schema/002_partitions.sql
-- =============================================================================

CREATE OR REPLACE FUNCTION fn_log_delay()
RETURNS TRIGGER AS $$
DECLARE
    v_category TEXT;
BEGIN
    -- Chỉ xử lý chuyến không bị hủy và có dữ liệu delay
    IF NEW.cancelled = FALSE AND NEW.arr_delay_min IS NOT NULL THEN
        v_category := CASE
            WHEN NEW.arr_delay_min <= 0   THEN 'on_time'   -- sớm hoặc đúng giờ
            WHEN NEW.arr_delay_min <= 15  THEN 'minor'     -- trễ ≤ 15 phút (ngưỡng FAA)
            WHEN NEW.arr_delay_min <= 60  THEN 'major'     -- trễ 16–60 phút
            ELSE                               'severe'    -- trễ > 60 phút
        END;

        INSERT INTO delay_audit_log (
            flight_id,
            flight_date,
            airline_code,
            origin,
            destination,
            delay_minutes,
            delay_category
        ) VALUES (
            NEW.id,
            NEW.flight_date,
            NEW.airline_code,
            NEW.origin,
            NEW.destination,
            NEW.arr_delay_min,
            v_category
        );
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Gắn trigger vào bảng flights (partitioned table)
-- FOR EACH ROW: chạy 1 lần cho mỗi dòng INSERT, không phải mỗi câu lệnh
DROP TRIGGER IF EXISTS trg_log_delay ON flights;
CREATE TRIGGER trg_log_delay
    AFTER INSERT ON flights
    FOR EACH ROW
    EXECUTE FUNCTION fn_log_delay();

COMMENT ON FUNCTION fn_log_delay() IS
    'Phân loại delay (on_time/minor/major/severe) và ghi vào delay_audit_log.
     Chạy AFTER INSERT ON flights. Bỏ qua chuyến bị hủy hoặc thiếu arr_delay_min.';

-- KIỂM TRA:
-- INSERT INTO flights (flight_date, airline_code, flight_number, origin, destination, arr_delay_min, cancelled)
-- VALUES ('2023-06-15', 'AA', 'AA100', 'JFK', 'LAX', 75, FALSE);
-- SELECT * FROM delay_audit_log ORDER BY logged_at DESC LIMIT 1;
