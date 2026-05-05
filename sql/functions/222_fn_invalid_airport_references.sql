-- =============================================================================
-- 222_fn_invalid_airport_references.sql
-- Hàm: fn_invalid_airport_references
-- Mục tiêu:
--   - Phát hiện các mã sân bay mồ côi trong flights (origin/destination).
-- =============================================================================

CREATE OR REPLACE FUNCTION fn_invalid_airport_references()
RETURNS TABLE (
    source_col    TEXT,
    iata_code     CHAR(3),
    affected_rows BIGINT
) AS $$
BEGIN
    RETURN QUERY
    WITH origin_issues AS (
        SELECT 'origin'::TEXT AS source_col, f.origin AS iata_code, COUNT(*)::BIGINT AS affected_rows
        FROM flights f
        LEFT JOIN airports a ON a.iata_code = f.origin
        WHERE a.iata_code IS NULL
        GROUP BY f.origin
    ),
    dest_issues AS (
        SELECT 'destination'::TEXT AS source_col, f.destination AS iata_code, COUNT(*)::BIGINT AS affected_rows
        FROM flights f
        LEFT JOIN airports a ON a.iata_code = f.destination
        WHERE a.iata_code IS NULL
        GROUP BY f.destination
    )
    SELECT * FROM origin_issues
    UNION ALL
    SELECT * FROM dest_issues
    ORDER BY affected_rows DESC, source_col, iata_code;
END;
$$ LANGUAGE plpgsql STABLE;

COMMENT ON FUNCTION fn_invalid_airport_references() IS
    'Kiểm tra mã sân bay mồ côi trong flights (origin/destination).';
