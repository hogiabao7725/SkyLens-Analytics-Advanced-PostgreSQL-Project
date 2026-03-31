-- =============================================================================
-- sql/functions/analytics.sql
-- Stored Functions & Procedures cho analytics
--
-- Chạy SAU triggers/flight_audit.sql, TRƯỚC hoặc SAU ingest.py đều được
-- Cách dùng:
--   psql -h localhost -U postgres -d skylens -f sql/functions/analytics.sql
-- =============================================================================


-- -----------------------------------------------------------------------------
-- FUNCTION 1: Tính performance score tổng hợp cho 1 hãng bay
--
-- Trả về bảng gồm các metrics: on_time_pct, avg_delay, cancellation_rate,
-- và performance_score (0–100) tổng hợp từ các metrics trên.
--
-- Dùng cho: API endpoint GET /airlines/:code/score
-- Demo: SELECT * FROM fn_airline_score('AA', '2023-01-01', '2023-12-31');
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION fn_airline_score(
    p_airline_code  CHAR(2),
    p_start_date    DATE,
    p_end_date      DATE
)
RETURNS TABLE (
    airline_code        CHAR(2),
    total_flights       BIGINT,
    completed_flights   BIGINT,
    on_time_flights     BIGINT,
    on_time_pct         NUMERIC,
    avg_arr_delay_min   NUMERIC,
    avg_dep_delay_min   NUMERIC,
    cancellation_rate   NUMERIC,
    severe_delay_pct    NUMERIC,
    performance_score   NUMERIC
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        p_airline_code::CHAR(2),

        -- Tổng số chuyến (kể cả bị hủy)
        COUNT(*)::BIGINT,

        -- Số chuyến hoàn thành (không bị hủy)
        SUM(CASE WHEN NOT f.cancelled THEN 1 ELSE 0 END)::BIGINT,

        -- Số chuyến đúng giờ (delay ≤ 15 phút, theo chuẩn FAA)
        SUM(CASE WHEN NOT f.cancelled
                  AND f.arr_delay_min <= 15 THEN 1 ELSE 0 END)::BIGINT,

        -- Tỷ lệ đúng giờ (%)
        ROUND(
            100.0 * SUM(CASE WHEN NOT f.cancelled AND f.arr_delay_min <= 15
                             THEN 1 ELSE 0 END)
            / NULLIF(SUM(CASE WHEN NOT f.cancelled THEN 1 ELSE 0 END), 0),
            2
        ),

        -- Delay trung bình khi đến (chỉ tính chuyến không bị hủy)
        ROUND(AVG(CASE WHEN NOT f.cancelled
                       THEN f.arr_delay_min END)::NUMERIC, 2),

        -- Delay trung bình khi khởi hành
        ROUND(AVG(CASE WHEN NOT f.cancelled
                       THEN f.dep_delay_min END)::NUMERIC, 2),

        -- Tỷ lệ hủy chuyến (%)
        ROUND(100.0 * SUM(CASE WHEN f.cancelled THEN 1 ELSE 0 END)
              / NULLIF(COUNT(*), 0), 2),

        -- Tỷ lệ delay nghiêm trọng > 60 phút (%)
        ROUND(
            100.0 * SUM(CASE WHEN NOT f.cancelled
                              AND f.arr_delay_min > 60 THEN 1 ELSE 0 END)
            / NULLIF(SUM(CASE WHEN NOT f.cancelled THEN 1 ELSE 0 END), 0),
            2
        ),

        -- Performance score tổng hợp (0–100):
        --   50% trọng số on_time_pct
        --   30% trọng số inverse avg_delay (chuẩn hóa: 0 delay = 100đ, 120+ delay = 0đ)
        --   20% trọng số inverse cancellation_rate
        ROUND(
            0.50 * (
                100.0 * SUM(CASE WHEN NOT f.cancelled AND f.arr_delay_min <= 15
                                 THEN 1 ELSE 0 END)
                / NULLIF(SUM(CASE WHEN NOT f.cancelled THEN 1 ELSE 0 END), 0)
            )
            + 0.30 * GREATEST(0,
                100 - COALESCE(AVG(CASE WHEN NOT f.cancelled
                                        THEN f.arr_delay_min END), 0)
              )
            + 0.20 * (
                100 - COALESCE(
                    100.0 * SUM(CASE WHEN f.cancelled THEN 1 ELSE 0 END)
                    / NULLIF(COUNT(*), 0),
                0)
              )
        , 2)

    FROM flights f
    WHERE f.airline_code = p_airline_code
      AND f.flight_date BETWEEN p_start_date AND p_end_date;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION fn_airline_score(CHAR, DATE, DATE) IS
    'Tính performance score (0–100) cho 1 hãng bay trong khoảng thời gian.
     Score = 50% on_time + 30% low_delay + 20% low_cancellation.
     Ví dụ: SELECT * FROM fn_airline_score(''AA'', ''2023-01-01'', ''2023-12-31'');';


-- -----------------------------------------------------------------------------
-- FUNCTION 2: So sánh performance của tất cả hãng bay trong 1 khoảng thời gian
--
-- Dùng cho: Dashboard ranking, bảng xếp hạng hãng bay
-- Demo: SELECT * FROM fn_airline_ranking('2023-06-01', '2023-06-30');
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION fn_airline_ranking(
    p_start_date DATE,
    p_end_date   DATE
)
RETURNS TABLE (
    rank_position       INT,
    airline_code        CHAR(2),
    airline_name        TEXT,
    total_flights       BIGINT,
    on_time_pct         NUMERIC,
    avg_arr_delay_min   NUMERIC,
    cancellation_rate   NUMERIC,
    performance_score   NUMERIC
) AS $$
BEGIN
    RETURN QUERY
    WITH base_stats AS (
        SELECT
            f.airline_code,
            COUNT(*)                                          AS total_flights,
            ROUND(
                100.0 * SUM(CASE WHEN NOT f.cancelled AND f.arr_delay_min <= 15
                                 THEN 1 ELSE 0 END)
                / NULLIF(SUM(CASE WHEN NOT f.cancelled THEN 1 ELSE 0 END), 0),
                2
            )                                                 AS on_time_pct,
            ROUND(AVG(CASE WHEN NOT f.cancelled
                           THEN f.arr_delay_min END)::NUMERIC, 2) AS avg_arr_delay,
            ROUND(100.0 * SUM(CASE WHEN f.cancelled THEN 1 ELSE 0 END)
                  / NULLIF(COUNT(*), 0), 2)                   AS cancellation_rate
        FROM flights f
        WHERE f.flight_date BETWEEN p_start_date AND p_end_date
        GROUP BY f.airline_code
        HAVING COUNT(*) >= 100  -- Bỏ qua hãng quá ít chuyến (không có ý nghĩa thống kê)
    )
    SELECT
        -- RANK() window function: nếu 2 hãng cùng điểm → cùng rank, rank tiếp theo bị nhảy
        RANK() OVER (ORDER BY (
            0.50 * s.on_time_pct
            + 0.30 * GREATEST(0, 100 - COALESCE(s.avg_arr_delay, 0))
            + 0.20 * (100 - COALESCE(s.cancellation_rate, 0))
        ) DESC)::INT,
        s.airline_code,
        COALESCE(a.name, 'Unknown')::TEXT,
        s.total_flights,
        s.on_time_pct,
        s.avg_arr_delay,
        s.cancellation_rate,
        ROUND(
            0.50 * s.on_time_pct
            + 0.30 * GREATEST(0, 100 - COALESCE(s.avg_arr_delay, 0))
            + 0.20 * (100 - COALESCE(s.cancellation_rate, 0)),
            2
        )
    FROM base_stats s
    LEFT JOIN airlines a ON a.iata_code = s.airline_code
    ORDER BY rank_position, s.airline_code;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION fn_airline_ranking(DATE, DATE) IS
    'Xếp hạng tất cả hãng bay theo performance score trong khoảng thời gian.
     Dùng RANK() window function để xử lý tie (đồng điểm).
     Bỏ qua hãng có < 100 chuyến (không có ý nghĩa thống kê).
     Ví dụ: SELECT * FROM fn_airline_ranking(''2023-01-01'', ''2023-03-31'');';


-- -----------------------------------------------------------------------------
-- FUNCTION 3: Thống kê delay theo nguyên nhân cho 1 hãng bay
--
-- BTS chia delay thành 5 loại: carrier, weather, NAS, security, late_aircraft
-- Dùng cho: Biểu đồ phân tích nguyên nhân delay
-- Demo: SELECT * FROM fn_delay_breakdown('DL', '2023-01-01', '2023-12-31');
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION fn_delay_breakdown(
    p_airline_code CHAR(2),
    p_start_date   DATE,
    p_end_date     DATE
)
RETURNS TABLE (
    delay_cause         TEXT,
    total_minutes       BIGINT,
    avg_minutes         NUMERIC,
    flight_count        BIGINT,
    pct_of_total_delay  NUMERIC
) AS $$
BEGIN
    RETURN QUERY
    WITH cause_totals AS (
        SELECT
            SUM(COALESCE(carrier_delay,       0) +
                COALESCE(weather_delay,        0) +
                COALESCE(nas_delay,            0) +
                COALESCE(security_delay,       0) +
                COALESCE(late_aircraft_delay,  0)) AS grand_total
        FROM flights
        WHERE airline_code = p_airline_code
          AND flight_date BETWEEN p_start_date AND p_end_date
          AND NOT cancelled
          AND arr_delay_min > 0
    ),
    breakdown AS (
        SELECT 'Carrier (hãng bay)'       AS cause, carrier_delay       AS minutes FROM flights
            WHERE airline_code = p_airline_code
              AND flight_date BETWEEN p_start_date AND p_end_date
              AND NOT cancelled AND carrier_delay > 0
        UNION ALL
        SELECT 'Weather (thời tiết)',       weather_delay       FROM flights
            WHERE airline_code = p_airline_code
              AND flight_date BETWEEN p_start_date AND p_end_date
              AND NOT cancelled AND weather_delay > 0
        UNION ALL
        SELECT 'NAS (không lưu/sân bay)',   nas_delay           FROM flights
            WHERE airline_code = p_airline_code
              AND flight_date BETWEEN p_start_date AND p_end_date
              AND NOT cancelled AND nas_delay > 0
        UNION ALL
        SELECT 'Security (an ninh)',         security_delay      FROM flights
            WHERE airline_code = p_airline_code
              AND flight_date BETWEEN p_start_date AND p_end_date
              AND NOT cancelled AND security_delay > 0
        UNION ALL
        SELECT 'Late Aircraft (máy bay trễ)', late_aircraft_delay FROM flights
            WHERE airline_code = p_airline_code
              AND flight_date BETWEEN p_start_date AND p_end_date
              AND NOT cancelled AND late_aircraft_delay > 0
    )
    SELECT
        b.cause::TEXT,
        SUM(b.minutes)::BIGINT,
        ROUND(AVG(b.minutes)::NUMERIC, 2),
        COUNT(*)::BIGINT,
        ROUND(100.0 * SUM(b.minutes) / NULLIF(ct.grand_total, 0), 2)
    FROM breakdown b, cause_totals ct
    GROUP BY b.cause, ct.grand_total
    ORDER BY SUM(b.minutes) DESC;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION fn_delay_breakdown(CHAR, DATE, DATE) IS
    'Phân tích nguyên nhân delay (carrier/weather/NAS/security/late_aircraft)
     cho 1 hãng bay, kèm % đóng góp vào tổng delay.
     Ví dụ: SELECT * FROM fn_delay_breakdown(''UA'', ''2023-06-01'', ''2023-08-31'');';


-- -----------------------------------------------------------------------------
-- FUNCTION 4: Tìm route tốt nhất giữa 2 thành phố (có thể có nhiều airport)
--
-- Dùng cho: Feature "gợi ý hãng bay tốt nhất cho route"
-- Demo: SELECT * FROM fn_best_routes_between('JFK', 'LAX', '2023-01-01', '2023-12-31');
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION fn_best_routes_between(
    p_origin      CHAR(3),
    p_destination CHAR(3),
    p_start_date  DATE,
    p_end_date    DATE
)
RETURNS TABLE (
    airline_code        CHAR(2),
    airline_name        TEXT,
    total_flights       BIGINT,
    on_time_pct         NUMERIC,
    avg_arr_delay_min   NUMERIC,
    avg_distance_miles  NUMERIC,
    cancellation_rate   NUMERIC
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        f.airline_code,
        COALESCE(a.name, 'Unknown')::TEXT,
        COUNT(*)::BIGINT,
        ROUND(
            100.0 * SUM(CASE WHEN NOT f.cancelled AND f.arr_delay_min <= 15
                             THEN 1 ELSE 0 END)
            / NULLIF(SUM(CASE WHEN NOT f.cancelled THEN 1 ELSE 0 END), 0),
            2
        ),
        ROUND(AVG(CASE WHEN NOT f.cancelled THEN f.arr_delay_min END)::NUMERIC, 2),
        ROUND(AVG(f.distance_miles)::NUMERIC, 1),
        ROUND(100.0 * SUM(CASE WHEN f.cancelled THEN 1 ELSE 0 END)
              / NULLIF(COUNT(*), 0), 2)
    FROM flights f
    LEFT JOIN airlines a ON a.iata_code = f.airline_code
    WHERE f.origin      = p_origin
      AND f.destination = p_destination
      AND f.flight_date BETWEEN p_start_date AND p_end_date
    GROUP BY f.airline_code, a.name
    HAVING COUNT(*) >= 10
    ORDER BY
        -- Sắp xếp: ưu tiên on_time_pct cao, sau đó delay thấp
        (100.0 * SUM(CASE WHEN NOT f.cancelled AND f.arr_delay_min <= 15
                          THEN 1 ELSE 0 END)
         / NULLIF(SUM(CASE WHEN NOT f.cancelled THEN 1 ELSE 0 END), 0)) DESC NULLS LAST,
        AVG(CASE WHEN NOT f.cancelled THEN f.arr_delay_min END) ASC NULLS LAST;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION fn_best_routes_between(CHAR, CHAR, DATE, DATE) IS
    'So sánh các hãng bay trên cùng 1 route, xếp hạng theo on_time_pct.
     Ví dụ: SELECT * FROM fn_best_routes_between(''JFK'', ''LAX'', ''2023-01-01'', ''2023-12-31'');';


-- =============================================================================
-- KIỂM TRA SAU KHI CHẠY
-- =============================================================================

-- Xem tất cả functions vừa tạo:
--   SELECT routine_name, routine_type
--   FROM information_schema.routines
--   WHERE routine_schema = 'public'
--   ORDER BY routine_name;
--
-- Test fn_airline_score (cần có data):
--   SELECT * FROM fn_airline_score('AA', '2023-01-01', '2023-12-31');
--
-- Test fn_airline_ranking:
--   SELECT * FROM fn_airline_ranking('2023-06-01', '2023-06-30');
--
-- Test fn_delay_breakdown:
--   SELECT * FROM fn_delay_breakdown('DL', '2023-01-01', '2023-12-31');
--
-- Test fn_best_routes_between:
--   SELECT * FROM fn_best_routes_between('JFK', 'LAX', '2023-01-01', '2023-12-31');
