-- =============================================================================
-- sql/triggers/trg_airlines.sql
-- Triggers cập nhật Full-text search cho bảng Airlines
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Tự động cập nhật tsvector cho airlines (full-text search)
--
-- Mục đích: Giữ cột search_vector luôn đồng bộ khi INSERT/UPDATE airlines.
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION fn_update_airline_fts()
RETURNS TRIGGER AS $$
BEGIN
    -- to_tsvector parse text thành lexemes (bỏ stop words, stem từ)
    -- Ghép name + country để tìm được cả "United States" hay "US"
    NEW.search_vector := to_tsvector('english',
        coalesce(NEW.name,    '') || ' ' ||
        coalesce(NEW.iata_code, '') || ' ' ||
        coalesce(NEW.country, '')
    );
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_airline_fts ON airlines;
CREATE TRIGGER trg_airline_fts
    BEFORE INSERT OR UPDATE ON airlines
    FOR EACH ROW
    EXECUTE FUNCTION fn_update_airline_fts();

COMMENT ON FUNCTION fn_update_airline_fts() IS
    'Tự động cập nhật search_vector cho full-text search khi INSERT/UPDATE airlines.
     Chạy BEFORE INSERT OR UPDATE để NEW.search_vector được lưu cùng row.';

-- KIỂM TRA:
-- INSERT INTO airlines (iata_code, name, country) VALUES ('ZZ', 'Test Airline', 'US');
-- SELECT iata_code, search_vector FROM airlines WHERE iata_code = 'ZZ';
-- DELETE FROM airlines WHERE iata_code = 'ZZ';
