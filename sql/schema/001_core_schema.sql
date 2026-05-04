-- =============================================================================
-- 001_core_schema.sql
-- Mục tiêu:
--   - Khởi tạo toàn bộ bảng lõi cho hệ thống phân tích chuyến bay.
--   - Thiết lập ràng buộc dữ liệu để giảm lỗi ngay tại tầng database.
-- Ghi chú:
--   - Bảng flights là bảng partitioned theo flight_date.
--   - Chạy file này trước tất cả các file khác trong schema.
-- =============================================================================

-- CREATE DATABASE skylens;

CREATE EXTENSION IF NOT EXISTS postgis;

-- airports: thông tin sân bay + tọa độ PostGIS
CREATE TABLE airports (
    iata_code     CHAR(3) PRIMARY KEY,
    name          TEXT NOT NULL,
    city          TEXT,
    country       CHAR(2),
    location      GEOGRAPHY(POINT, 4326),  -- PostGIS
    elevation_ft  INT,
    timezone      TEXT,
    search_vector TSVECTOR  -- Full-text search
);

-- airlines: hãng hàng không
CREATE TABLE airlines (
    iata_code     CHAR(2) PRIMARY KEY,
    name          TEXT NOT NULL,
    country       CHAR(2),
    search_vector TSVECTOR  -- Full-text search
);

-- flights: bảng chính, sẽ được PARTITION
-- (xem phần partitioning bên dưới)
CREATE TABLE flights (
    id              BIGSERIAL,
    flight_date     DATE NOT NULL,
    airline_code    CHAR(2) REFERENCES airlines(iata_code),
    flight_number   VARCHAR(10),
    origin          CHAR(3) REFERENCES airports(iata_code),
    destination     CHAR(3) REFERENCES airports(iata_code),
    dep_time        TIME,
    dep_delay_min   INT,
    arr_time        TIME,
    arr_delay_min   INT,
    cancelled       BOOLEAN DEFAULT FALSE,
    diverted        BOOLEAN DEFAULT FALSE,
    distance_miles  INT,
    carrier_delay   INT,
    weather_delay   INT,
    nas_delay       INT,
    security_delay  INT,
    late_aircraft_delay INT,
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    CONSTRAINT pk_flights PRIMARY KEY (id, flight_date),
    CONSTRAINT chk_flights_origin_dest_diff CHECK (origin <> destination),
    CONSTRAINT chk_flights_distance_positive CHECK (distance_miles IS NULL OR distance_miles > 0),
    CONSTRAINT chk_flights_dep_delay_reasonable CHECK (dep_delay_min IS NULL OR dep_delay_min >= -120),
    CONSTRAINT chk_flights_arr_delay_reasonable CHECK (arr_delay_min IS NULL OR arr_delay_min >= -120),
    CONSTRAINT chk_flights_delay_breakdown_nonnegative CHECK (
        (carrier_delay IS NULL OR carrier_delay >= 0) AND
        (weather_delay IS NULL OR weather_delay >= 0) AND
        (nas_delay IS NULL OR nas_delay >= 0) AND
        (security_delay IS NULL OR security_delay >= 0) AND
        (late_aircraft_delay IS NULL OR late_aircraft_delay >= 0)
    )
) PARTITION BY RANGE (flight_date);  -- PARTITION key

CREATE UNIQUE INDEX uq_flights_business_key
    ON flights (flight_date, airline_code, flight_number, origin, destination, dep_time);

-- delay_audit_log: trigger sẽ insert vào đây
CREATE TABLE delay_audit_log (
    id              BIGSERIAL PRIMARY KEY,
    flight_id       BIGINT,
    flight_date     DATE,
    airline_code    CHAR(2),
    origin          CHAR(3),
    destination     CHAR(3),
    delay_minutes   INT,
    delay_category  TEXT,  -- 'on_time', 'minor', 'major', 'severe'
    logged_at       TIMESTAMPTZ DEFAULT NOW()
);

-- benchmark_results: lưu kết quả so sánh index performance
CREATE TABLE benchmark_results (
    id            BIGSERIAL PRIMARY KEY,
    query_name    TEXT NOT NULL,
    description   TEXT,
    before_ms     NUMERIC,
    after_ms      NUMERIC,
    explain_text  TEXT,
    created_at    TIMESTAMPTZ DEFAULT NOW()
);
