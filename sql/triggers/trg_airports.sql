-- =============================================================================
-- sql/triggers/trg_airports.sql
-- Triggers cập nhật Full-text search và Ngăn xoá dữ liệu đối với bảng Airports
-- =============================================================================

-- -----------------------------------------------------------------------------
-- TRIGGER 1: Tự động cập nhật tsvector cho airports (full-text search)
--
-- Mục đích: Hỗ trợ search sân bay theo tên/thành phố/code, tự động build tsvector
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_update_airport_fts()
RETURNS TRIGGER AS $$
BEGIN
    NEW.search_vector := to_tsvector('english',
        coalesce(NEW.name,      '') || ' ' ||
        coalesce(NEW.city,      '') || ' ' ||
        coalesce(NEW.iata_code, '') || ' ' ||
        coalesce(NEW.country,   '')
    );
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_airport_fts ON airports;
CREATE TRIGGER trg_airport_fts
    BEFORE INSERT OR UPDATE ON airports
    FOR EACH ROW
    EXECUTE FUNCTION fn_update_airport_fts();

COMMENT ON FUNCTION fn_update_airport_fts() IS
    'Tự động cập nhật search_vector cho airports khi INSERT/UPDATE.
     Ghép name + city + iata_code + country để hỗ trợ tìm kiếm đa dạng.';

-- -----------------------------------------------------------------------------
-- TRIGGER 2: Ngăn xóa airport đang có dữ liệu flights
--
-- Mục đích: Bảo vệ data integrity — không cho DELETE airport nếu còn tham chiếu.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_prevent_airport_delete()
RETURNS TRIGGER AS $$
DECLARE
    v_flight_count BIGINT;
BEGIN
    SELECT COUNT(*) INTO v_flight_count
    FROM flights
    WHERE origin = OLD.iata_code OR destination = OLD.iata_code
    LIMIT 1;  -- LIMIT 1 vì chỉ cần biết có hay không, không cần đếm hết

    IF v_flight_count > 0 THEN
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

COMMENT ON FUNCTION fn_prevent_airport_delete() IS
    'Ngăn DELETE airport nếu còn flights tham chiếu (origin hoặc destination).
     Bảo vệ referential integrity thủ công.';
