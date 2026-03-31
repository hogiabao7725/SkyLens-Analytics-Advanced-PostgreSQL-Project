-- =============================================================================
-- sql/queries/postgis.sql
-- Demo queries sử dụng PostGIS — phần thi CUỐI KỲ
--
-- Yêu cầu: extension PostGIS đã được cài (có trong postgis/postgis Docker image)
-- Kiểm tra: SELECT PostGIS_Version();
-- =============================================================================


-- =============================================================================
-- QUERY 1: Khoảng cách thực tế (Great Circle) giữa 2 sân bay
--
-- ST_Distance trên GEOGRAPHY tự động tính Great Circle distance (meters)
-- Khác với GEOMETRY (phẳng, tính Euclidean distance — sai với tọa độ địa lý)
-- =============================================================================

SELECT
    a1.iata_code                                    AS origin,
    a1.name                                         AS origin_name,
    a2.iata_code                                    AS destination,
    a2.name                                         AS dest_name,

    -- ST_Distance trên GEOGRAPHY → kết quả là meters → chia 1000 ra km
    ROUND((ST_Distance(
        a1.location::GEOGRAPHY,
        a2.location::GEOGRAPHY
    ) / 1000)::NUMERIC, 1)                          AS distance_km,

    -- So sánh với distance_miles trong BTS data (kiểm tra độ chính xác)
    ROUND(AVG(f.distance_miles) * 1.60934, 1)       AS bts_distance_km
FROM airports a1
JOIN airports a2 ON a2.iata_code != a1.iata_code
JOIN flights f   ON f.origin = a1.iata_code AND f.destination = a2.iata_code
WHERE a1.iata_code IN ('JFK', 'LAX', 'ORD', 'ATL', 'DFW')
  AND a2.iata_code IN ('JFK', 'LAX', 'ORD', 'ATL', 'DFW')
  AND a1.iata_code < a2.iata_code  -- Tránh duplicate (JFK→LAX và LAX→JFK)
GROUP BY a1.iata_code, a1.name, a2.iata_code, a2.name, a1.location, a2.location
ORDER BY distance_km DESC;


-- =============================================================================
-- QUERY 2: Top 20 routes bận nhất + tọa độ cho Leaflet route map
--
-- ST_AsGeoJSON: chuyển GEOGRAPHY → GeoJSON string
-- Frontend Leaflet nhận GeoJSON để vẽ polylines
--
-- Kết quả JSON trông như:
--   {"type":"Point","coordinates":[-73.7789,40.6398]}
-- =============================================================================

SELECT
    f.origin,
    f.destination,
    o.name                                          AS origin_name,
    d.name                                          AS dest_name,
    o.city                                          AS origin_city,
    d.city                                          AS dest_city,
    COUNT(*)                                        AS total_flights,
    ROUND(AVG(CASE WHEN NOT f.cancelled
                   THEN f.arr_delay_min END)::NUMERIC, 2) AS avg_delay_min,

    -- Tọa độ riêng lẻ (dễ dùng hơn trong React Leaflet)
    ST_Y(o.location::GEOMETRY)                      AS origin_lat,
    ST_X(o.location::GEOMETRY)                      AS origin_lon,
    ST_Y(d.location::GEOMETRY)                      AS dest_lat,
    ST_X(d.location::GEOMETRY)                      AS dest_lon,

    -- GeoJSON cho API response
    ST_AsGeoJSON(o.location::GEOMETRY)::JSON        AS origin_geojson,
    ST_AsGeoJSON(d.location::GEOMETRY)::JSON        AS dest_geojson,

    -- Khoảng cách thực tế
    ROUND((ST_Distance(
        o.location::GEOGRAPHY,
        d.location::GEOGRAPHY
    ) / 1000)::NUMERIC, 1)                          AS distance_km
FROM flights f
JOIN airports o ON o.iata_code = f.origin
JOIN airports d ON d.iata_code = f.destination
WHERE f.cancelled = FALSE
  AND o.location IS NOT NULL
  AND d.location IS NOT NULL
GROUP BY
    f.origin, f.destination,
    o.name, d.name, o.city, d.city,
    o.location, d.location
ORDER BY total_flights DESC
LIMIT 20;


-- =============================================================================
-- QUERY 3: Sân bay nào trong bán kính X km từ 1 điểm bị delay nhiều nhất?
--
-- ST_DWithin(geog1, geog2, distance_meters):
--   Trả về TRUE nếu 2 điểm cách nhau ≤ distance_meters
--   Dùng GEOGRAPHY để tự động tính khoảng cách theo mặt cầu Trái Đất
--   Yêu cầu idx_airports_location (GIST index) để chạy nhanh
-- =============================================================================

-- Sân bay trong bán kính 800km từ New York (JFK: -73.7789, 40.6398)
SELECT
    a.iata_code,
    a.name,
    a.city,
    ROUND((ST_Distance(
        a.location::GEOGRAPHY,
        ST_MakePoint(-73.7789, 40.6398)::GEOGRAPHY
    ) / 1000)::NUMERIC, 1)                          AS dist_from_jfk_km,

    COUNT(f.id)                                     AS total_departures,
    ROUND(AVG(CASE WHEN NOT f.cancelled
                   THEN f.arr_delay_min END)::NUMERIC, 2) AS avg_arr_delay,
    ROUND(100.0 * SUM(CASE WHEN f.cancelled THEN 1 ELSE 0 END)
          / NULLIF(COUNT(*), 0), 2)                 AS cancellation_rate
FROM airports a
JOIN flights f ON f.origin = a.iata_code
WHERE ST_DWithin(
    a.location::GEOGRAPHY,
    ST_MakePoint(-73.7789, 40.6398)::GEOGRAPHY,
    800000  -- 800km = 800,000 meters
)
  AND a.iata_code != 'JFK'  -- Loại trừ bản thân JFK
  AND f.flight_date BETWEEN '2023-01-01' AND '2023-12-31'
GROUP BY a.iata_code, a.name, a.city, a.location
HAVING COUNT(f.id) >= 1000  -- Chỉ lấy sân bay đủ lớn
ORDER BY avg_arr_delay DESC
LIMIT 15;


-- =============================================================================
-- QUERY 4: Cluster sân bay theo vùng địa lý + thống kê delay
--
-- ST_ClusterKMeans: gom sân bay thành K cụm theo vị trí địa lý
-- Hữu ích để phân tích "vùng nào của Mỹ bị delay nhiều nhất?"
-- =============================================================================

WITH airport_clusters AS (
    SELECT
        a.iata_code,
        a.name,
        a.city,
        a.country,
        -- Gom thành 6 cụm (6 vùng địa lý của Mỹ: NE, SE, MW, SW, W, NW)
        ST_ClusterKMeans(a.location::GEOMETRY, 6) OVER () AS cluster_id
    FROM airports a
    WHERE a.country = 'US'
      AND a.location IS NOT NULL
),
cluster_stats AS (
    SELECT
        ac.cluster_id,
        COUNT(DISTINCT ac.iata_code)                AS airport_count,
        COUNT(f.id)                                 AS total_flights,
        ROUND(AVG(CASE WHEN NOT f.cancelled
                       THEN f.arr_delay_min END)::NUMERIC, 2) AS avg_delay,

        -- Tâm của cluster (centroid)
        ST_AsText(ST_Centroid(
            ST_Collect(ac.location::GEOMETRY)
        ))                                          AS cluster_centroid,
        STRING_AGG(DISTINCT ac.city, ', '
                   ORDER BY ac.city
                   LIMIT 5)                         AS sample_cities
    FROM airport_clusters ac
    LEFT JOIN flights f ON f.origin = ac.iata_code
      AND f.flight_date BETWEEN '2023-01-01' AND '2023-12-31'
    GROUP BY ac.cluster_id
)
SELECT
    cluster_id,
    airport_count,
    total_flights,
    avg_delay,
    cluster_centroid,
    sample_cities
FROM cluster_stats
ORDER BY avg_delay DESC;


-- =============================================================================
-- QUERY 5: Tìm các cặp sân bay gần nhau nhưng cùng route thường xuyên
--
-- Interesting insight: route ngắn nhưng bị delay nhiều
-- (thường do congestion ở hub airports, không phải thời tiết)
-- =============================================================================

SELECT
    f.origin,
    f.destination,
    o.name                                          AS origin_name,
    d.name                                          AS dest_name,
    ROUND((ST_Distance(
        o.location::GEOGRAPHY,
        d.location::GEOGRAPHY
    ) / 1000)::NUMERIC, 1)                          AS distance_km,
    COUNT(*)                                        AS total_flights,
    ROUND(AVG(CASE WHEN NOT f.cancelled
                   THEN f.arr_delay_min END)::NUMERIC, 2) AS avg_delay,
    ROUND(AVG(CASE WHEN NOT f.cancelled
                   THEN f.arr_delay_min END)::NUMERIC, 2)
        / NULLIF(ROUND((ST_Distance(
            o.location::GEOGRAPHY,
            d.location::GEOGRAPHY
        ) / 1000)::NUMERIC, 1), 0)                  AS delay_per_km  -- delay nhiều hơn so với khoảng cách
FROM flights f
JOIN airports o ON o.iata_code = f.origin
JOIN airports d ON d.iata_code = f.destination
WHERE f.cancelled = FALSE
  AND o.location IS NOT NULL
  AND d.location IS NOT NULL
  AND f.flight_date BETWEEN '2023-01-01' AND '2023-12-31'
GROUP BY f.origin, f.destination, o.name, d.name, o.location, d.location
HAVING COUNT(*) >= 500
   AND ST_Distance(o.location::GEOGRAPHY, d.location::GEOGRAPHY) < 500000  -- < 500km
ORDER BY delay_per_km DESC NULLS LAST
LIMIT 20;


-- =============================================================================
-- KIỂM TRA POSTGIS HOẠT ĐỘNG ĐÚNG
-- =============================================================================

-- Kiểm tra extension:
--   SELECT PostGIS_Full_Version();
--
-- Kiểm tra spatial index được dùng:
--   EXPLAIN (ANALYZE, BUFFERS)
--   SELECT iata_code FROM airports
--   WHERE ST_DWithin(
--       location::GEOGRAPHY,
--       ST_MakePoint(-73.7789, 40.6398)::GEOGRAPHY,
--       500000
--   );
--   -- Phải thấy: "Index Scan using idx_airports_location"
--   -- KHÔNG được: "Seq Scan" (nếu thấy → chưa tạo GIST index)
