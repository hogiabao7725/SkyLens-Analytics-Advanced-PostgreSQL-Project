-- =============================================================================
-- sql/views/materialized.sql
-- Materialized Views cho dashboard và analytics
--
-- Chạy SAU khi import data (ingest.py) và SAU 003_indexing.sql
-- Vì REFRESH MATERIALIZED VIEW cần có data để populate
--
-- Cách dùng:
--   psql -h localhost -U postgres -d skylens -f sql/views/materialized.sql
--
-- Refresh thủ công (sau khi import thêm data):
--   REFRESH MATERIALIZED VIEW CONCURRENTLY mv_airline_summary;
--   REFRESH MATERIALIZED VIEW CONCURRENTLY mv_delay_heatmap;
--   REFRESH MATERIALIZED VIEW CONCURRENTLY mv_top_routes;
--   REFRESH MATERIALIZED VIEW CONCURRENTLY mv_monthly_trend;
--   REFRESH MATERIALIZED VIEW CONCURRENTLY mv_route_performance;
-- =============================================================================


-- -----------------------------------------------------------------------------
-- VIEW 1: Tổng quan hiệu suất từng hãng bay (toàn bộ dataset)
--
-- Dùng cho: Dashboard trang chủ — bảng xếp hạng hãng bay
-- Refresh: Sau mỗi lần import data mới
-- Query time không có view: ~8-15s trên 7M rows
-- Query time với view: <50ms (đọc từ cache)
-- -----------------------------------------------------------------------------

DROP MATERIALIZED VIEW IF EXISTS mv_airline_summary CASCADE;
CREATE MATERIALIZED VIEW mv_airline_summary AS
SELECT
    f.airline_code,
    COALESCE(a.name, 'Unknown')                               AS airline_name,

    -- Volume
    COUNT(*)                                                  AS total_flights,
    SUM(CASE WHEN NOT f.cancelled THEN 1 ELSE 0 END)          AS completed_flights,
    SUM(CASE WHEN f.cancelled     THEN 1 ELSE 0 END)          AS cancelled_flights,

    -- On-time performance
    ROUND(
        100.0 * SUM(CASE WHEN NOT f.cancelled AND f.arr_delay_min <= 15
                         THEN 1 ELSE 0 END)
        / NULLIF(SUM(CASE WHEN NOT f.cancelled THEN 1 ELSE 0 END), 0),
        2
    )                                                         AS on_time_pct,

    -- Delay metrics
    ROUND(AVG(CASE WHEN NOT f.cancelled THEN f.arr_delay_min END)::NUMERIC, 2)
                                                              AS avg_arr_delay_min,
    ROUND(AVG(CASE WHEN NOT f.cancelled THEN f.dep_delay_min END)::NUMERIC, 2)
                                                              AS avg_dep_delay_min,

    -- Cancellation rate
    ROUND(100.0 * SUM(CASE WHEN f.cancelled THEN 1 ELSE 0 END)
          / NULLIF(COUNT(*), 0), 2)                           AS cancellation_rate,

    -- Severe delay (>60 phút)
    SUM(CASE WHEN NOT f.cancelled AND f.arr_delay_min > 60
             THEN 1 ELSE 0 END)                               AS severe_delay_count,

    -- Data range
    MIN(f.flight_date)                                        AS data_from,
    MAX(f.flight_date)                                        AS data_to
FROM flights f
LEFT JOIN airlines a ON a.iata_code = f.airline_code
GROUP BY f.airline_code, a.name
WITH DATA;

-- UNIQUE index bắt buộc để dùng REFRESH CONCURRENTLY
-- (CONCURRENTLY không lock bảng trong lúc refresh → UI không bị downtime)
CREATE UNIQUE INDEX ON mv_airline_summary (airline_code);

COMMENT ON MATERIALIZED VIEW mv_airline_summary IS
    'Tổng hợp hiệu suất từng hãng bay trên toàn bộ dataset.
     Refresh sau mỗi lần import data mới.
     UNIQUE INDEX trên airline_code cho phép REFRESH CONCURRENTLY.';


-- -----------------------------------------------------------------------------
-- VIEW 2: Heatmap delay theo giờ trong ngày × ngày trong tuần
--
-- Dùng cho: Trang Heatmap — "Giờ nào / ngày nào hay bị delay nhất?"
-- 7 × 24 = 168 cells
-- -----------------------------------------------------------------------------

DROP MATERIALIZED VIEW IF EXISTS mv_delay_heatmap CASCADE;
CREATE MATERIALIZED VIEW mv_delay_heatmap AS
SELECT
    -- 0 = Chủ nhật, 1 = Thứ 2, ..., 6 = Thứ 7 (PostgreSQL convention)
    EXTRACT(DOW  FROM f.flight_date)::INT        AS day_of_week,
    EXTRACT(HOUR FROM f.dep_time)::INT           AS hour_of_day,

    COUNT(*)                                     AS flight_count,
    ROUND(AVG(f.arr_delay_min)::NUMERIC, 2)      AS avg_arr_delay,
    ROUND(AVG(f.dep_delay_min)::NUMERIC, 2)      AS avg_dep_delay,

    -- % chuyến delay > 15 phút trong ô heatmap này
    ROUND(
        100.0 * SUM(CASE WHEN f.arr_delay_min > 15 THEN 1 ELSE 0 END)
        / NULLIF(COUNT(*), 0),
        2
    )                                            AS delay_rate_pct
FROM flights f
WHERE f.cancelled = FALSE
  AND f.dep_time IS NOT NULL
GROUP BY
    EXTRACT(DOW  FROM f.flight_date),
    EXTRACT(HOUR FROM f.dep_time)
WITH DATA;

CREATE UNIQUE INDEX ON mv_delay_heatmap (day_of_week, hour_of_day);

COMMENT ON MATERIALIZED VIEW mv_delay_heatmap IS
    'Matrix 7×24: delay trung bình theo ngày trong tuần và giờ trong ngày.
     Dùng để vẽ heatmap trên UI (Recharts hoặc D3).';


-- -----------------------------------------------------------------------------
-- VIEW 3: Top routes — thống kê tổng hợp từng cặp (origin, destination)
--
-- Dùng cho: Route Map (Leaflet), bảng top routes
-- Chỉ lấy routes có ≥ 100 chuyến để tránh nhiễu
-- -----------------------------------------------------------------------------

DROP MATERIALIZED VIEW IF EXISTS mv_top_routes CASCADE;
CREATE MATERIALIZED VIEW mv_top_routes AS
SELECT
    f.origin,
    f.destination,
    o.name                                              AS origin_name,
    d.name                                              AS dest_name,
    o.city                                              AS origin_city,
    d.city                                              AS dest_city,

    -- Tọa độ cho Leaflet polylines
    ST_X(o.location::GEOMETRY)                         AS origin_lon,
    ST_Y(o.location::GEOMETRY)                         AS origin_lat,
    ST_X(d.location::GEOMETRY)                         AS dest_lon,
    ST_Y(d.location::GEOMETRY)                         AS dest_lat,

    -- Volume & performance
    COUNT(*)                                            AS total_flights,
    SUM(CASE WHEN NOT f.cancelled THEN 1 ELSE 0 END)   AS completed_flights,
    ROUND(AVG(CASE WHEN NOT f.cancelled
                   THEN f.arr_delay_min END)::NUMERIC, 2) AS avg_arr_delay,
    ROUND(AVG(f.distance_miles)::NUMERIC, 1)           AS avg_distance_miles,
    ROUND(
        100.0 * SUM(CASE WHEN NOT f.cancelled AND f.arr_delay_min <= 15
                         THEN 1 ELSE 0 END)
        / NULLIF(SUM(CASE WHEN NOT f.cancelled THEN 1 ELSE 0 END), 0),
        2
    )                                                   AS on_time_pct,
    ROUND(100.0 * SUM(CASE WHEN f.cancelled THEN 1 ELSE 0 END)
          / NULLIF(COUNT(*), 0), 2)                     AS cancellation_rate
FROM flights f
JOIN airports o ON o.iata_code = f.origin
JOIN airports d ON d.iata_code = f.destination
WHERE o.location IS NOT NULL
  AND d.location IS NOT NULL
GROUP BY
    f.origin, f.destination,
    o.name, d.name, o.city, d.city,
    o.location, d.location
HAVING COUNT(*) >= 100
WITH DATA;

CREATE UNIQUE INDEX ON mv_top_routes (origin, destination);
CREATE INDEX ON mv_top_routes (total_flights DESC);
CREATE INDEX ON mv_top_routes (avg_arr_delay DESC);

COMMENT ON MATERIALIZED VIEW mv_top_routes IS
    'Tổng hợp thống kê từng route kèm tọa độ GPS cho Leaflet route map.
     Chỉ bao gồm routes có ≥ 100 chuyến bay.
     Tọa độ được extract từ PostGIS GEOGRAPHY column.';


-- -----------------------------------------------------------------------------
-- VIEW 4: Xu hướng delay theo tháng (time-series cho line chart)
--
-- Dùng cho: Line chart "Xu hướng on-time performance qua các tháng"
-- -----------------------------------------------------------------------------

DROP MATERIALIZED VIEW IF EXISTS mv_monthly_trend CASCADE;
CREATE MATERIALIZED VIEW mv_monthly_trend AS
SELECT
    DATE_TRUNC('month', f.flight_date)::DATE        AS month,
    f.airline_code,
    COALESCE(a.name, 'Unknown')                     AS airline_name,

    COUNT(*)                                        AS total_flights,
    ROUND(AVG(CASE WHEN NOT f.cancelled
                   THEN f.arr_delay_min END)::NUMERIC, 2) AS avg_arr_delay,
    ROUND(
        100.0 * SUM(CASE WHEN NOT f.cancelled AND f.arr_delay_min <= 15
                         THEN 1 ELSE 0 END)
        / NULLIF(SUM(CASE WHEN NOT f.cancelled THEN 1 ELSE 0 END), 0),
        2
    )                                               AS on_time_pct,
    ROUND(100.0 * SUM(CASE WHEN f.cancelled THEN 1 ELSE 0 END)
          / NULLIF(COUNT(*), 0), 2)                 AS cancellation_rate,

    -- Delay breakdown theo nguyên nhân (tổng phút)
    SUM(COALESCE(f.carrier_delay,      0))::INT     AS total_carrier_delay_min,
    SUM(COALESCE(f.weather_delay,      0))::INT     AS total_weather_delay_min,
    SUM(COALESCE(f.nas_delay,          0))::INT     AS total_nas_delay_min,
    SUM(COALESCE(f.late_aircraft_delay,0))::INT     AS total_late_aircraft_delay_min
FROM flights f
LEFT JOIN airlines a ON a.iata_code = f.airline_code
GROUP BY
    DATE_TRUNC('month', f.flight_date),
    f.airline_code,
    a.name
WITH DATA;

CREATE UNIQUE INDEX ON mv_monthly_trend (month, airline_code);
CREATE INDEX ON mv_monthly_trend (airline_code, month);

COMMENT ON MATERIALIZED VIEW mv_monthly_trend IS
    'Time-series: metrics theo từng tháng × hãng bay.
     Dùng cho line chart "xu hướng on-time performance".
     Index trên (airline_code, month) để filter nhanh theo hãng.';


-- -----------------------------------------------------------------------------
-- VIEW 5: Route performance theo hãng (cho feature "best airline on route")
--
-- Dùng cho: API endpoint tìm hãng tốt nhất trên 1 route cụ thể
-- Chỉ lấy (route, airline) có ≥ 20 chuyến để đảm bảo ý nghĩa thống kê
-- -----------------------------------------------------------------------------

DROP MATERIALIZED VIEW IF EXISTS mv_route_performance CASCADE;
CREATE MATERIALIZED VIEW mv_route_performance AS
SELECT
    f.origin,
    f.destination,
    f.airline_code,
    COALESCE(a.name, 'Unknown')                     AS airline_name,

    COUNT(*)                                        AS total_flights,
    ROUND(AVG(CASE WHEN NOT f.cancelled
                   THEN f.arr_delay_min END)::NUMERIC, 2) AS avg_arr_delay,
    ROUND(
        100.0 * SUM(CASE WHEN NOT f.cancelled AND f.arr_delay_min <= 15
                         THEN 1 ELSE 0 END)
        / NULLIF(SUM(CASE WHEN NOT f.cancelled THEN 1 ELSE 0 END), 0),
        2
    )                                               AS on_time_pct,
    ROUND(100.0 * SUM(CASE WHEN f.cancelled THEN 1 ELSE 0 END)
          / NULLIF(COUNT(*), 0), 2)                 AS cancellation_rate
FROM flights f
LEFT JOIN airlines a ON a.iata_code = f.airline_code
GROUP BY f.origin, f.destination, f.airline_code, a.name
HAVING COUNT(*) >= 20
WITH DATA;

CREATE UNIQUE INDEX ON mv_route_performance (origin, destination, airline_code);
CREATE INDEX ON mv_route_performance (origin, destination, on_time_pct DESC);

COMMENT ON MATERIALIZED VIEW mv_route_performance IS
    'Hiệu suất từng hãng bay trên từng route cụ thể.
     Dùng cho feature "hãng nào tốt nhất trên route JFK→LAX?".
     Index composite (origin, destination, on_time_pct DESC) để sort ngay trong index.';


-- -----------------------------------------------------------------------------
-- KIỂM TRA SAU KHI CHẠY
-- -----------------------------------------------------------------------------

DO $$
DECLARE
    v_view  TEXT;
    v_count BIGINT;
BEGIN
    RAISE NOTICE '%-30s | %s', 'Materialized View', 'Rows';
    RAISE NOTICE '%', REPEAT('-', 50);
    FOR v_view IN
        SELECT unnest(ARRAY[
            'mv_airline_summary',
            'mv_delay_heatmap',
            'mv_top_routes',
            'mv_monthly_trend',
            'mv_route_performance'
        ])
    LOOP
        EXECUTE format('SELECT COUNT(*) FROM %I', v_view) INTO v_count;
        RAISE NOTICE '%-30s | %s', v_view, v_count;
    END LOOP;
END;
$$;

-- Refresh tất cả (chạy sau mỗi lần import thêm data):
--
--   REFRESH MATERIALIZED VIEW CONCURRENTLY mv_airline_summary;
--   REFRESH MATERIALIZED VIEW CONCURRENTLY mv_delay_heatmap;
--   REFRESH MATERIALIZED VIEW CONCURRENTLY mv_top_routes;
--   REFRESH MATERIALIZED VIEW CONCURRENTLY mv_monthly_trend;
--   REFRESH MATERIALIZED VIEW CONCURRENTLY mv_route_performance;
