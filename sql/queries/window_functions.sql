-- =============================================================================
-- sql/queries/window_functions.sql
-- Demo queries sử dụng Window Functions — phần thi GIỮA KỲ
--
-- Mỗi query có comment giải thích:
--   - Dùng window function gì
--   - Tại sao dùng cách này
--   - Kết quả trông như thế nào
--
-- Chạy từng query riêng lẻ trong psql hoặc DBeaver
-- =============================================================================


-- =============================================================================
-- QUERY 1: Xếp hạng hãng bay theo tỷ lệ đúng giờ mỗi tháng
--
-- Window function: RANK() OVER (PARTITION BY ... ORDER BY ...)
--
-- Tại sao RANK() thay vì ROW_NUMBER()?
--   RANK() cho 2 hãng cùng on_time_pct → cùng rank (ví dụ: 2 hãng đều rank 3)
--   ROW_NUMBER() luôn gán số thứ tự khác nhau dù cùng giá trị
--   → RANK() phản ánh thực tế hơn khi so sánh hiệu suất
--
-- PARTITION BY month: tính rank độc lập cho từng tháng
--   (rank của tháng 1 không liên quan rank tháng 2)
-- =============================================================================

SELECT
    DATE_TRUNC('month', flight_date)::DATE              AS month,
    airline_code,
    COUNT(*)                                            AS total_flights,
    SUM(CASE WHEN NOT cancelled AND arr_delay_min <= 15
             THEN 1 ELSE 0 END)                         AS on_time_flights,
    ROUND(
        100.0 * SUM(CASE WHEN NOT cancelled AND arr_delay_min <= 15
                         THEN 1 ELSE 0 END)
        / NULLIF(SUM(CASE WHEN NOT cancelled THEN 1 ELSE 0 END), 0),
        2
    )                                                   AS on_time_pct,
    ROUND(AVG(CASE WHEN NOT cancelled
                   THEN arr_delay_min END)::NUMERIC, 2) AS avg_delay_min,

    -- RANK: hãng nào on_time_pct cao nhất trong tháng đó → rank 1
    RANK() OVER (
        PARTITION BY DATE_TRUNC('month', flight_date)
        ORDER BY
            SUM(CASE WHEN NOT cancelled AND arr_delay_min <= 15
                     THEN 1 ELSE 0 END)::FLOAT
            / NULLIF(SUM(CASE WHEN NOT cancelled THEN 1 ELSE 0 END), 0) DESC
    )                                                   AS rank_on_time,

    -- DENSE_RANK: tương tự RANK nhưng không nhảy số
    -- Ví dụ RANK: 1,2,2,4 — DENSE_RANK: 1,2,2,3
    DENSE_RANK() OVER (
        PARTITION BY DATE_TRUNC('month', flight_date)
        ORDER BY AVG(CASE WHEN NOT cancelled THEN arr_delay_min END) ASC
    )                                                   AS dense_rank_by_delay
FROM flights
WHERE flight_date BETWEEN '2023-01-01' AND '2023-12-31'
GROUP BY DATE_TRUNC('month', flight_date), airline_code
ORDER BY month, rank_on_time;


-- =============================================================================
-- QUERY 2: 7-day moving average delay theo hãng bay
--
-- Window function: AVG() OVER (ROWS BETWEEN 6 PRECEDING AND CURRENT ROW)
--
-- Tại sao moving average?
--   Delay hàng ngày biến động nhiều (thời tiết, ngày lễ, ...)
--   Moving average làm mịn trend, dễ thấy xu hướng dài hạn hơn
--
-- ROWS BETWEEN 6 PRECEDING AND CURRENT ROW:
--   Tính trung bình của 7 ngày: ngày hiện tại + 6 ngày trước
--   Khác với RANGE BETWEEN: ROWS tính theo số dòng vật lý, RANGE theo giá trị
-- =============================================================================

WITH daily_avg AS (
    -- Bước 1: Tính delay trung bình mỗi ngày cho từng hãng
    SELECT
        flight_date,
        airline_code,
        COUNT(*)                                            AS daily_flights,
        ROUND(AVG(CASE WHEN NOT cancelled
                       THEN arr_delay_min END)::NUMERIC, 2) AS daily_avg_delay
    FROM flights
    WHERE cancelled = FALSE
      AND flight_date BETWEEN '2023-01-01' AND '2023-12-31'
    GROUP BY flight_date, airline_code
)
SELECT
    flight_date,
    airline_code,
    daily_flights,
    daily_avg_delay,

    -- 7-day moving average: làm mịn nhiễu ngắn hạn
    ROUND(AVG(daily_avg_delay) OVER (
        PARTITION BY airline_code
        ORDER BY flight_date
        ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
    ), 2)                                                   AS moving_avg_7day,

    -- 30-day moving average: xu hướng dài hạn hơn
    ROUND(AVG(daily_avg_delay) OVER (
        PARTITION BY airline_code
        ORDER BY flight_date
        ROWS BETWEEN 29 PRECEDING AND CURRENT ROW
    ), 2)                                                   AS moving_avg_30day,

    -- Cumulative average từ đầu năm đến ngày hiện tại
    ROUND(AVG(daily_avg_delay) OVER (
        PARTITION BY airline_code
        ORDER BY flight_date
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ), 2)                                                   AS cumulative_avg
FROM daily_avg
ORDER BY airline_code, flight_date;


-- =============================================================================
-- QUERY 3: Phát hiện route có delay tăng đột biến tháng này so với tháng trước
--
-- Window function: LAG() OVER (PARTITION BY ... ORDER BY ...)
--
-- LAG(value, offset): lấy giá trị của dòng đứng trước N vị trí
--   trong cùng partition (cùng route)
--
-- Tại sao hữu ích?
--   Phát hiện anomaly: route bình thường đúng giờ, đột nhiên tháng này delay cao
--   Có thể do: thay đổi lịch bay, vấn đề hạ tầng sân bay, mùa cao điểm...
-- =============================================================================

WITH monthly_route_delay AS (
    SELECT
        DATE_TRUNC('month', flight_date)::DATE  AS month,
        origin,
        destination,
        COUNT(*)                                AS flight_count,
        ROUND(AVG(CASE WHEN NOT cancelled
                       THEN arr_delay_min END)::NUMERIC, 2) AS avg_delay
    FROM flights
    WHERE flight_date BETWEEN '2023-01-01' AND '2023-12-31'
    GROUP BY DATE_TRUNC('month', flight_date), origin, destination
    HAVING COUNT(*) >= 50  -- Chỉ xét route có đủ lượng chuyến
)
SELECT
    month,
    origin,
    destination,
    flight_count,
    avg_delay                                   AS current_avg_delay,

    -- LAG: delay trung bình của tháng trước cùng route này
    LAG(avg_delay, 1) OVER (
        PARTITION BY origin, destination
        ORDER BY month
    )                                           AS prev_month_avg_delay,

    -- % thay đổi so với tháng trước
    ROUND(
        100.0 * (
            avg_delay - LAG(avg_delay, 1) OVER (
                PARTITION BY origin, destination ORDER BY month
            )
        ) / NULLIF(LAG(avg_delay, 1) OVER (
            PARTITION BY origin, destination ORDER BY month
        ), 0),
        2
    )                                           AS pct_change,

    -- Phân loại mức thay đổi
    CASE
        WHEN avg_delay - LAG(avg_delay, 1) OVER (
                PARTITION BY origin, destination ORDER BY month
             ) > 30 THEN '🔴 Tăng mạnh'
        WHEN avg_delay - LAG(avg_delay, 1) OVER (
                PARTITION BY origin, destination ORDER BY month
             ) > 10 THEN '🟡 Tăng nhẹ'
        WHEN avg_delay - LAG(avg_delay, 1) OVER (
                PARTITION BY origin, destination ORDER BY month
             ) < -10 THEN '🟢 Cải thiện'
        ELSE '⚪ Ổn định'
    END                                         AS trend
FROM monthly_route_delay
ORDER BY ABS(
    avg_delay - LAG(avg_delay, 1) OVER (
        PARTITION BY origin, destination ORDER BY month
    )
) DESC NULLS LAST
LIMIT 50;


-- =============================================================================
-- QUERY 4: Phân phối delay theo percentile (NTILE, PERCENT_RANK, CUME_DIST)
--
-- Dùng 3 loại window function khác nhau để so sánh:
--   NTILE(n):        chia rows vào n nhóm bằng nhau (decile/quartile)
--   PERCENT_RANK():  vị trí tương đối 0.0 → 1.0 (0% = thấp nhất, 100% = cao nhất)
--   CUME_DIST():     tỷ lệ rows có giá trị ≤ giá trị hiện tại
-- =============================================================================

SELECT
    arr_delay_min,
    COUNT(*)                                        AS frequency,

    -- Chia thành 10 nhóm (decile): nhóm 1 = delay thấp nhất, nhóm 10 = cao nhất
    NTILE(10) OVER (ORDER BY arr_delay_min)         AS decile,

    -- Chia thành 4 nhóm (quartile)
    NTILE(4)  OVER (ORDER BY arr_delay_min)         AS quartile,

    -- Vị trí tương đối: 0.0 → 1.0
    ROUND(PERCENT_RANK() OVER (ORDER BY arr_delay_min)::NUMERIC, 4)
                                                    AS percent_rank,

    -- Tỷ lệ tích lũy: bao nhiêu % chuyến có delay ≤ giá trị này
    ROUND(CUME_DIST()    OVER (ORDER BY arr_delay_min)::NUMERIC, 4)
                                                    AS cumulative_dist
FROM flights
WHERE cancelled = FALSE
  AND arr_delay_min BETWEEN -60 AND 360  -- Loại bỏ outliers cực đoan
GROUP BY arr_delay_min
ORDER BY arr_delay_min;


-- =============================================================================
-- QUERY 5: Running total — tổng số chuyến bay tích lũy theo thời gian
--
-- Window function: SUM() OVER (ORDER BY ... ROWS UNBOUNDED PRECEDING)
--
-- Dùng cho: Line chart "tổng số chuyến bay từ đầu năm"
-- Tương tự "cumulative sum" trong pandas (df.cumsum())
-- =============================================================================

WITH daily_flights AS (
    SELECT
        flight_date,
        COUNT(*)                                    AS flights_today,
        SUM(CASE WHEN cancelled THEN 1 ELSE 0 END)  AS cancelled_today
    FROM flights
    WHERE flight_date BETWEEN '2023-01-01' AND '2023-12-31'
    GROUP BY flight_date
)
SELECT
    flight_date,
    flights_today,
    cancelled_today,

    -- Running total: tổng chuyến bay từ 2023-01-01 đến ngày hiện tại
    SUM(flights_today) OVER (
        ORDER BY flight_date
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    )                                               AS cumulative_flights,

    -- Running total chuyến bị hủy
    SUM(cancelled_today) OVER (
        ORDER BY flight_date
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    )                                               AS cumulative_cancelled,

    -- Tỷ lệ hủy tích lũy (%)
    ROUND(
        100.0 * SUM(cancelled_today) OVER (
            ORDER BY flight_date
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        )
        / NULLIF(SUM(flights_today) OVER (
            ORDER BY flight_date
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ), 0),
        2
    )                                               AS cumulative_cancel_rate
FROM daily_flights
ORDER BY flight_date;


-- =============================================================================
-- QUERY 6: So sánh hiệu suất hãng bay với AVERAGE toàn ngành (baseline)
--
-- Window function: AVG() OVER () — window không có PARTITION → tính trên ALL rows
--
-- Dùng để trả lời: "Hãng AA tốt hơn hay tệ hơn mức trung bình toàn ngành?"
-- =============================================================================

WITH airline_monthly AS (
    SELECT
        DATE_TRUNC('month', flight_date)::DATE      AS month,
        airline_code,
        ROUND(AVG(CASE WHEN NOT cancelled
                       THEN arr_delay_min END)::NUMERIC, 2) AS avg_delay
    FROM flights
    WHERE flight_date BETWEEN '2023-01-01' AND '2023-12-31'
    GROUP BY DATE_TRUNC('month', flight_date), airline_code
)
SELECT
    month,
    airline_code,
    avg_delay                                       AS airline_avg_delay,

    -- Trung bình toàn ngành trong tháng đó (window = tất cả hãng cùng tháng)
    ROUND(AVG(avg_delay) OVER (
        PARTITION BY month
    ), 2)                                           AS industry_avg_delay,

    -- Chênh lệch so với trung bình ngành (âm = tốt hơn ngành)
    ROUND(avg_delay - AVG(avg_delay) OVER (
        PARTITION BY month
    ), 2)                                           AS diff_from_industry,

    -- Xếp loại
    CASE
        WHEN avg_delay < AVG(avg_delay) OVER (PARTITION BY month) - 5
            THEN 'Tốt hơn ngành'
        WHEN avg_delay > AVG(avg_delay) OVER (PARTITION BY month) + 5
            THEN 'Tệ hơn ngành'
        ELSE 'Ngang bằng ngành'
    END                                             AS vs_industry
FROM airline_monthly
ORDER BY month, diff_from_industry;
