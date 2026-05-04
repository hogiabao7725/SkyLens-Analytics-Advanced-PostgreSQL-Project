-- =============================================================================
-- 102_airlines_fts.sql
-- Mục tiêu:
--   - Đồng bộ cột search_vector cho bảng airlines khi INSERT/UPDATE.
-- =============================================================================

CREATE OR REPLACE FUNCTION fn_update_airline_fts()
RETURNS TRIGGER AS $$
BEGIN
    NEW.search_vector := to_tsvector('english',
        coalesce(NEW.name, '') || ' ' ||
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
