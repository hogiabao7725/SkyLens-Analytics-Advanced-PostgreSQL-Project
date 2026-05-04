-- =============================================================================
-- 103_flights_delay_audit.sql
-- Mục tiêu:
--   - Tự động phân loại delay và ghi vào delay_audit_log sau mỗi INSERT flights.
-- =============================================================================

CREATE OR REPLACE FUNCTION fn_log_delay()
RETURNS TRIGGER AS $$
DECLARE
    v_category TEXT;
BEGIN
    IF NEW.cancelled = FALSE AND NEW.arr_delay_min IS NOT NULL THEN
        v_category := CASE
            WHEN NEW.arr_delay_min <= 0 THEN 'on_time'
            WHEN NEW.arr_delay_min <= 15 THEN 'minor'
            WHEN NEW.arr_delay_min <= 60 THEN 'major'
            ELSE 'severe'
        END;

        INSERT INTO delay_audit_log (
            flight_id, flight_date, airline_code, origin, destination, delay_minutes, delay_category
        ) VALUES (
            NEW.id, NEW.flight_date, NEW.airline_code, NEW.origin, NEW.destination, NEW.arr_delay_min, v_category
        );
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_log_delay ON flights;
CREATE TRIGGER trg_log_delay
    AFTER INSERT ON flights
    FOR EACH ROW
    EXECUTE FUNCTION fn_log_delay();
