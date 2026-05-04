-- =============================================================================
-- 101_airports_fts_and_guard.sql
-- Mục tiêu:
--   - Đồng bộ full-text search cho bảng airports.
--   - Chặn xóa sân bay nếu còn flights tham chiếu.
-- =============================================================================

CREATE OR REPLACE FUNCTION fn_update_airport_fts()
RETURNS TRIGGER AS $$
BEGIN
    NEW.search_vector := to_tsvector('english',
        coalesce(NEW.name, '') || ' ' ||
        coalesce(NEW.city, '') || ' ' ||
        coalesce(NEW.iata_code, '') || ' ' ||
        coalesce(NEW.country, '')
    );
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_airport_fts ON airports;
CREATE TRIGGER trg_airport_fts
    BEFORE INSERT OR UPDATE ON airports
    FOR EACH ROW
    EXECUTE FUNCTION fn_update_airport_fts();

CREATE OR REPLACE FUNCTION fn_prevent_airport_delete()
RETURNS TRIGGER AS $$
DECLARE
    v_has_reference BOOLEAN;
BEGIN
    SELECT EXISTS (
        SELECT 1
        FROM flights
        WHERE origin = OLD.iata_code OR destination = OLD.iata_code
    ) INTO v_has_reference;

    IF v_has_reference THEN
        RAISE EXCEPTION
            'Không thể xóa airport "%" vì còn tồn tại dữ liệu flights tham chiếu đến nó.',
            OLD.iata_code
        USING HINT = 'Xóa flights liên quan trước, hoặc dùng UPDATE để đánh dấu inactive.';
    END IF;

    RETURN OLD;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_prevent_airport_delete ON airports;
CREATE TRIGGER trg_prevent_airport_delete
    BEFORE DELETE ON airports
    FOR EACH ROW
    EXECUTE FUNCTION fn_prevent_airport_delete();
