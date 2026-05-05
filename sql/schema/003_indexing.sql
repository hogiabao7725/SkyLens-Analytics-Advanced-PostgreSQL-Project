-- =============================================================================
-- 003_indexing.sql
-- Mục tiêu:
--   - Tạo index tối ưu cho truy vấn analytics, PostGIS và audit.
-- Khuyến nghị:
--   - Chạy sau khi ingest dữ liệu để tạo index nhanh hơn.
-- =============================================================================

SET client_min_messages = 'warning';

CREATE INDEX IF NOT EXISTS idx_airports_country ON airports (country);
CREATE INDEX IF NOT EXISTS idx_airports_location ON airports USING GIST (location);
CREATE INDEX IF NOT EXISTS idx_airports_fts ON airports USING GIN (search_vector) WHERE search_vector IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_airlines_fts ON airlines USING GIN (search_vector) WHERE search_vector IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_flights_airline_date ON flights (airline_code, flight_date);
CREATE INDEX IF NOT EXISTS idx_flights_origin_dest ON flights (origin, destination);
CREATE INDEX IF NOT EXISTS idx_flights_date ON flights (flight_date DESC);
CREATE INDEX IF NOT EXISTS idx_flights_delayed ON flights (arr_delay_min DESC)
    WHERE arr_delay_min > 15 AND cancelled = FALSE;
CREATE INDEX IF NOT EXISTS idx_flights_cancelled ON flights (airline_code, flight_date)
    WHERE cancelled = TRUE;
CREATE INDEX IF NOT EXISTS idx_flights_window_fn ON flights (airline_code, flight_date, arr_delay_min)
    WHERE cancelled = FALSE;
CREATE INDEX IF NOT EXISTS idx_flights_origin_date ON flights (origin, flight_date)
    WHERE cancelled = FALSE;
CREATE INDEX IF NOT EXISTS idx_flights_date_brin ON flights USING BRIN (flight_date)
    WITH (pages_per_range = 128);

CREATE INDEX IF NOT EXISTS idx_audit_airline_date ON delay_audit_log (airline_code, flight_date);
CREATE INDEX IF NOT EXISTS idx_audit_category ON delay_audit_log (delay_category, flight_date)
    WHERE delay_category IN ('major', 'severe');
CREATE INDEX IF NOT EXISTS idx_audit_logged_at ON delay_audit_log (logged_at DESC);

CREATE INDEX IF NOT EXISTS idx_benchmark_created ON benchmark_results (created_at DESC);
