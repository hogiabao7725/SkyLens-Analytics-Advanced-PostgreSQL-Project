#!/usr/bin/env python3
"""
ingest.py — SkyLens Data Ingestion Script
==========================================
Import dữ liệu từ 2 nguồn vào PostgreSQL:
  1. OurAirports CSV  → bảng airports
  2. BTS On-Time CSV  → bảng airlines + flights

Cách dùng:
  # Import airports + tất cả BTS CSV trong data/bts/
  python scripts/ingest.py

  # Chỉ import airports
  python scripts/ingest.py --only airports

  # Chỉ import flights từ 1 file cụ thể
  python scripts/ingest.py --only flights --file data/bts/2023_01.csv

  # Import toàn bộ năm 2023 (tìm file data/bts/2023_*.csv)
  python scripts/ingest.py --year 2023

  # Xóa sạch dữ liệu cũ rồi import lại
  python scripts/ingest.py --year 2023 --truncate

  # Dry-run: chỉ validate, không insert
  python scripts/ingest.py --year 2023 --dry-run

Yêu cầu:
  pip install psycopg2-binary pandas tqdm python-dotenv requests

Cấu trúc thư mục:
  data/
  ├── airports.csv          ← từ ourairports.com/data/airports.csv
  └── bts/
      ├── 2023_01.csv       ← BTS monthly CSV (download thủ công)
      ├── 2023_02.csv
      └── ...
"""

import os
import sys
import csv
import math
import argparse
import logging
import time
import glob
from datetime import datetime, date
from pathlib import Path
from typing import Optional

import pandas as pd
import psycopg2
import psycopg2.extras
import requests
from tqdm import tqdm
from dotenv import load_dotenv

# ─────────────────────────────────────────────
# Cấu hình logging
# ─────────────────────────────────────────────
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%H:%M:%S",
    handlers=[
        logging.StreamHandler(sys.stdout),
        logging.FileHandler("ingest.log", encoding="utf-8"),
    ],
)
log = logging.getLogger(__name__)

# ─────────────────────────────────────────────
# Constants
# ─────────────────────────────────────────────

# Đường dẫn file dữ liệu
DATA_DIR        = Path("data")
AIRPORTS_CSV    = DATA_DIR / "airports.csv"
BTS_DIR         = DATA_DIR / "bts"
AIRPORTS_URL    = "https://davidmegginson.github.io/ourairports-data/airports.csv"

# Batch size khi insert vào Postgres (tối ưu cho tốc độ vs memory)
BATCH_SIZE = 5_000

# Mapping cột BTS CSV → tên cột trong schema
# Key = tên cột gốc trong BTS file, Value = tên cột trong DB
BTS_COLUMN_MAP = {
    "FL_DATE":                             "flight_date",
    "OP_UNIQUE_CARRIER":                   "airline_code",
    "OP_CARRIER_FL_NUM":                   "flight_number",
    "ORIGIN":                              "origin",
    "DEST":                                "destination",
    "DEP_TIME":                            "dep_time",
    "DEP_DELAY":                           "dep_delay_min",
    "ARR_TIME":                            "arr_time",
    "ARR_DELAY":                           "arr_delay_min",
    "CANCELLED":                           "cancelled",
    "DIVERTED":                            "diverted",
    "DISTANCE":                            "distance_miles",
    "CARRIER_DELAY":                       "carrier_delay",
    "WEATHER_DELAY":                       "weather_delay",
    "NAS_DELAY":                           "nas_delay",
    "SECURITY_DELAY":                      "security_delay",
    "LATE_AIRCRAFT_DELAY":                 "late_aircraft_delay",
}

# IATA code
KNOWN_AIRLINES = {
    "AA": ("American Airlines",         "US"),
    "AS": ("Alaska Airlines",           "US"),
    "B6": ("JetBlue Airways",           "US"),
    "DL": ("Delta Air Lines",           "US"),
    "F9": ("Frontier Airlines",         "US"),
    "G4": ("Allegiant Air",             "US"),
    "HA": ("Hawaiian Airlines",         "US"),
    "NK": ("Spirit Airlines",           "US"),
    "OH": ("PSA Airlines",              "US"),
    "OO": ("SkyWest Airlines",          "US"),
    "QX": ("Horizon Air",               "US"),
    "UA": ("United Airlines",           "US"),
    "WN": ("Southwest Airlines",        "US"),
    "WS": ("WestJet",                   "CA"),
    "MQ": ("Envoy Air",                 "US"),
    "YV": ("Mesa Airlines",             "US"),
    "YX": ("Republic Airways",          "US"),
    "9E": ("Endeavor Air",              "US"),
    "ZW": ("Air Wisconsin",             "US"),
    "CP": ("Compass Airlines",          "US"),
}


# ─────────────────────────────────────────────
# Database connection
# ─────────────────────────────────────────────

def get_connection() -> psycopg2.extensions.connection:
    """
    Tạo kết nối Postgres từ biến môi trường.
    Đọc từ .env file nếu có, fallback về giá trị mặc định Docker Compose.
    """
    load_dotenv()

    dsn = {
        "host":     os.getenv("DB_HOST",     "localhost"),
        "port":     int(os.getenv("DB_PORT", "5432")),
        "dbname":   os.getenv("DB_NAME",     "skylens"),
        "user":     os.getenv("DB_USER",     "postgres"),
        "password": os.getenv("DB_PASSWORD", "postgres"),
    }

    log.info(f"Kết nối tới {dsn['user']}@{dsn['host']}:{dsn['port']}/{dsn['dbname']}")
    try:
        conn = psycopg2.connect(**dsn)
        conn.autocommit = False
        return conn
    except psycopg2.OperationalError as e:
        log.error(f"Không thể kết nối database: {e}")
        log.error("Kiểm tra Docker Compose đã chạy chưa: docker compose up -d")
        sys.exit(1)


# ─────────────────────────────────────────────
# Helper functions
# ─────────────────────────────────────────────

def safe_int(val) -> Optional[int]:
    """Convert sang int, trả về None nếu không hợp lệ."""
    if val is None or (isinstance(val, float) and math.isnan(val)):
        return None
    try:
        return int(float(val))
    except (ValueError, TypeError):
        return None


def safe_float(val) -> Optional[float]:
    """Convert sang float, trả về None nếu không hợp lệ."""
    if val is None or (isinstance(val, float) and math.isnan(val)):
        return None
    try:
        f = float(val)
        return None if math.isnan(f) else f
    except (ValueError, TypeError):
        return None


def parse_hhmm_to_time(val) -> Optional[str]:
    """
    BTS lưu giờ dạng HHMM (ví dụ: 830 = 08:30, 2359 = 23:59).
    Trả về string 'HH:MM:SS' để Postgres nhận dạng kiểu TIME.
    """
    n = safe_int(val)
    if n is None:
        return None
    # BTS đôi khi có giá trị 2400 (midnight) → normalize về 0000
    n = n % 2400
    hh = n // 100
    mm = n % 100
    # Validate: giờ 0-23, phút 0-59
    if hh > 23 or mm > 59:
        return None
    return f"{hh:02d}:{mm:02d}:00"


def parse_bool(val) -> bool:
    """BTS encode cancelled/diverted là 1.0 / 0.0."""
    f = safe_float(val)
    if f is None:
        return False
    return f == 1.0


def parse_date(val) -> Optional[date]:
    """Parse FlightDate dạng 'YYYY-MM-DD' hoặc 'M/D/YYYY ...'."""
    if pd.isna(val) or not val:
        return None
    val_str = str(val).strip()

    # TH1: Thử parse dạng YYYY-MM-DD
    try:
        return datetime.strptime(val_str, "%Y-%m-%d").date()
    except ValueError:
        pass

    # TH2: M/D/YYYY hoặc M/D/YYYY HH:MM:SS AM
    try:
        date_part = val_str.split(" ")[0]
        parts = date_part.split("/")
        if len(parts) == 3:
            m, d, y = parts
            return date(int(y), int(m), int(d))
    except (ValueError, TypeError):
        pass

    return None


def chunks(lst: list, size: int):
    """Chia list thành các chunk có độ lớn `size`."""
    for i in range(0, len(lst), size):
        yield lst[i : i + size]


# ─────────────────────────────────────────────
# STEP 1: Import Airports
# ─────────────────────────────────────────────

def download_airports_csv() -> None:
    """Tự động tải airports.csv nếu chưa có."""
    if AIRPORTS_CSV.exists():
        log.info(f"Airports CSV đã tồn tại: {AIRPORTS_CSV} ({AIRPORTS_CSV.stat().st_size:,} bytes)")
        return

    log.info(f"Tải airports.csv từ {AIRPORTS_URL} ...")
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    try:
        resp = requests.get(AIRPORTS_URL, timeout=30, stream=True)
        resp.raise_for_status()
        total = int(resp.headers.get("content-length", 0))
        with open(AIRPORTS_CSV, "wb") as f, tqdm(
            total=total, unit="B", unit_scale=True, desc="airports.csv"
        ) as bar:
            for chunk in resp.iter_content(chunk_size=8192):
                f.write(chunk)
                bar.update(len(chunk))
        log.info(f"Đã tải: {AIRPORTS_CSV}")
    except requests.RequestException as e:
        log.error(f"Lỗi khi tải airports.csv: {e}")
        log.error(f"Tải thủ công tại: {AIRPORTS_URL}")
        sys.exit(1)


def import_airports(conn: psycopg2.extensions.connection, dry_run: bool = False) -> int:
    """
    Import airports.csv vào bảng airports.

    OurAirports CSV schema (các cột quan trọng):
      ident, type, name, latitude_deg, longitude_deg,
      elevation_ft, iso_country, iso_region, municipality,
      iata_code, ...

    Chỉ import:
      - Sân bay có iata_code hợp lệ (3 ký tự)
      - type IN ('large_airport', 'medium_airport', 'small_airport')
      - Bỏ qua helipad, seaplane base, ...
    """
    download_airports_csv()

    log.info(f"Đọc {AIRPORTS_CSV} ...")
    df = pd.read_csv(AIRPORTS_CSV, dtype=str, low_memory=False)

    # Normalize tên cột (OurAirports có thể thay đổi format nhẹ)
    df.columns = [c.strip().lower() for c in df.columns]

    # Filter: chỉ lấy sân bay có IATA code + đúng loại
    valid_types = {"large_airport", "medium_airport", "small_airport"}
    df = df[
        df["iata_code"].notna()
        & (df["iata_code"].str.strip() != "")
        & (df["iata_code"].str.len() == 3)
        & df["type"].isin(valid_types)
    ].copy()

    # Bỏ duplicate iata_code (ưu tiên large_airport)
    type_priority = {"large_airport": 0, "medium_airport": 1, "small_airport": 2}
    df["type_rank"] = df["type"].map(type_priority)
    df = df.sort_values("type_rank").drop_duplicates("iata_code").drop("type_rank", axis=1)

    log.info(f"Tìm thấy {len(df):,} sân bay hợp lệ sau khi filter")

    # Build records
    records = []
    skipped = 0
    for _, row in df.iterrows():
        iata   = str(row.get("iata_code", "")).strip().upper()
        name   = str(row.get("name", "")).strip()
        city   = str(row.get("municipality", "")).strip() or None
        country = str(row.get("iso_country", "")).strip()[:2] or None

        lat = safe_float(row.get("latitude_deg"))
        lon = safe_float(row.get("longitude_deg"))
        elev = safe_int(row.get("elevation_ft"))

        # Timezone: OurAirports dùng cột 'tzid' hoặc 'time_zone'
        tz = (
            str(row.get("tzid", "") or row.get("time_zone", "") or "").strip() or None
        )

        if not iata or len(iata) != 3 or not name:
            skipped += 1
            continue
        if lat is None or lon is None:
            skipped += 1
            continue

        records.append((iata, name, city, country, lon, lat, elev, tz))

    log.info(f"Records hợp lệ: {len(records):,} | Bỏ qua: {skipped:,}")

    if dry_run:
        log.info("[DRY-RUN] Không insert airports.")
        return len(records)

    # Insert với ON CONFLICT DO UPDATE (upsert)
    # → chạy lại script không bị lỗi duplicate
    sql = """
        INSERT INTO airports (iata_code, name, city, country, location, elevation_ft, timezone)
        VALUES (
            %s, %s, %s, %s,
            ST_SetSRID(ST_MakePoint(%s, %s), 4326)::GEOGRAPHY,
            %s, %s
        )
        ON CONFLICT (iata_code) DO UPDATE SET
            name         = EXCLUDED.name,
            city         = EXCLUDED.city,
            country      = EXCLUDED.country,
            location     = EXCLUDED.location,
            elevation_ft = EXCLUDED.elevation_ft,
            timezone     = EXCLUDED.timezone;
    """

    inserted = 0
    with conn.cursor() as cur:
        for batch in chunks(records, BATCH_SIZE):
            psycopg2.extras.execute_batch(cur, sql, batch, page_size=BATCH_SIZE)
            inserted += len(batch)
            log.info(f"  Airports: {inserted:,}/{len(records):,}")

    conn.commit()
    log.info(f"✓ Import airports hoàn tất: {inserted:,} records")
    return inserted


# ─────────────────────────────────────────────
# STEP 2: Import Airlines
# ─────────────────────────────────────────────

def extract_airlines_from_bts(bts_files: list[Path]) -> dict[str, tuple]:
    """
    Quét tất cả BTS file để tìm các airline code xuất hiện.
    Trả về dict: iata_code → (name, country)
    """
    found_codes: set[str] = set()

    for f in bts_files:
        try:
            # Chỉ cần đọc cột airline, không cần load cả file
            df = pd.read_csv(f, usecols=["OP_UNIQUE_CARRIER"], dtype=str, low_memory=False)
            codes = df["OP_UNIQUE_CARRIER"].dropna().str.strip().str.upper().unique()
            found_codes.update(codes)
        except Exception as e:
            log.warning(f"Không đọc được airline từ {f.name}: {e}")

    result = {}
    for code in sorted(found_codes):
        if len(code) == 2:
            name, country = KNOWN_AIRLINES.get(code, (f"Airline {code}", "US"))
            result[code] = (name, country)

    log.info(f"Tìm thấy {len(result)} airline codes: {', '.join(sorted(result.keys()))}")
    return result


def import_airlines(
    conn: psycopg2.extensions.connection,
    bts_files: list[Path],
    dry_run: bool = False,
) -> int:
    """
    Insert airlines vào DB.
    search_vector sẽ được điền tự động bởi trigger trg_airline_fts
    (nếu trigger chưa tạo thì điền thủ công ở đây).
    """
    airlines = extract_airlines_from_bts(bts_files)
    if not airlines:
        log.warning("Không tìm thấy airline nào trong BTS files.")
        return 0

    if dry_run:
        log.info(f"[DRY-RUN] Sẽ insert {len(airlines)} airlines.")
        return len(airlines)

    sql = """
        INSERT INTO airlines (iata_code, name, country)
        VALUES (%s, %s, %s)
        ON CONFLICT (iata_code) DO UPDATE SET
            name    = EXCLUDED.name,
            country = EXCLUDED.country;
    """
    records = [(code, name, country) for code, (name, country) in airlines.items()]

    with conn.cursor() as cur:
        psycopg2.extras.execute_batch(cur, sql, records)

    conn.commit()
    log.info(f"✓ Import airlines hoàn tất: {len(records)} records")
    return len(records)


# ─────────────────────────────────────────────
# STEP 3: Import Flights
# ─────────────────────────────────────────────

def validate_bts_columns(df: pd.DataFrame, filepath: Path) -> bool:
    """
    Kiểm tra file BTS có đủ cột cần thiết không.
    BTS đôi khi thêm/bỏ cột giữa các năm.
    """
    required = set(BTS_COLUMN_MAP.keys())
    present  = set(df.columns)
    missing  = required - present

    if missing:
        log.error(f"File {filepath.name} thiếu cột: {missing}")
        log.error(f"Các cột có trong file: {sorted(present)}")
        return False
    return True


def parse_bts_row(row: pd.Series) -> Optional[tuple]:
    """
    Parse 1 dòng BTS CSV thành tuple để insert vào bảng flights.

    Trả về None nếu dòng không hợp lệ (thiếu dữ liệu bắt buộc).

    Thứ tự tuple phải khớp với INSERT statement bên dưới:
      (flight_date, airline_code, flight_number, origin, destination,
       dep_time, dep_delay_min, arr_time, arr_delay_min,
       cancelled, diverted, distance_miles,
       carrier_delay, weather_delay, nas_delay,
       security_delay, late_aircraft_delay)
    """
    flight_date  = parse_date(row.get("FL_DATE"))
    airline_code = str(row.get("OP_UNIQUE_CARRIER", "") or "").strip().upper()
    origin       = str(row.get("ORIGIN", "") or "").strip().upper()
    destination  = str(row.get("DEST", "") or "").strip().upper()

    # Bắt buộc phải có các trường này
    if not flight_date or not airline_code or not origin or not destination:
        return None
    if len(airline_code) != 2 or len(origin) != 3 or len(destination) != 3:
        return None

    flight_number = str(row.get("OP_CARRIER_FL_NUM", "") or "").strip()
    flight_number = flight_number[:10] if flight_number else None

    dep_time      = parse_hhmm_to_time(row.get("DEP_TIME"))
    dep_delay_min = safe_int(row.get("DEP_DELAY"))
    arr_time      = parse_hhmm_to_time(row.get("ARR_TIME"))
    arr_delay_min = safe_int(row.get("ARR_DELAY"))

    cancelled     = parse_bool(row.get("CANCELLED"))
    diverted      = parse_bool(row.get("DIVERTED"))
    distance      = safe_int(row.get("DISTANCE"))

    # Delay breakdown — chỉ có nghĩa khi chuyến bay không bị hủy
    carrier_delay      = safe_int(row.get("CARRIER_DELAY"))
    weather_delay      = safe_int(row.get("WEATHER_DELAY"))
    nas_delay          = safe_int(row.get("NAS_DELAY"))
    security_delay     = safe_int(row.get("SECURITY_DELAY"))
    late_aircraft_delay = safe_int(row.get("LATE_AIRCRAFT_DELAY"))

    # Sanity check: delay không thể âm quá -60 phút (sớm hơn 1 tiếng là bất thường)
    if arr_delay_min is not None and arr_delay_min < -120:
        arr_delay_min = None
    if dep_delay_min is not None and dep_delay_min < -120:
        dep_delay_min = None

    return (
        flight_date, airline_code, flight_number, origin, destination,
        dep_time, dep_delay_min, arr_time, arr_delay_min,
        cancelled, diverted, distance,
        carrier_delay, weather_delay, nas_delay,
        security_delay, late_aircraft_delay,
    )


def import_flights_from_file(
    conn: psycopg2.extensions.connection,
    filepath: Path,
    dry_run: bool = False,
    truncate_first: bool = False,
) -> dict:
    """
    Import 1 file BTS CSV vào bảng flights.

    Trả về dict thống kê:
      { total_rows, inserted, skipped, errors, duration_sec }
    """
    log.info(f"─── Đang xử lý: {filepath.name} ───")
    start = time.time()

    # Đọc CSV
    try:
        df = pd.read_csv(
            filepath,
            dtype=str,          # đọc tất cả dạng string, parse thủ công
            low_memory=False,
            na_values=["", "NA", "N/A", "nan", "NaN"],
            keep_default_na=True,
        )
    except Exception as e:
        log.error(f"Không đọc được file {filepath.name}: {e}")
        return {"total_rows": 0, "inserted": 0, "skipped": 0, "errors": 1, "duration_sec": 0}

    # BTS CSV đôi khi có cột rác ở cuối (unnamed columns)
    df = df.loc[:, ~df.columns.str.startswith("Unnamed")]
    df.columns = [c.strip() for c in df.columns]

    if not validate_bts_columns(df, filepath):
        return {"total_rows": 0, "inserted": 0, "skipped": 0, "errors": 1, "duration_sec": 0}

    total_rows = len(df)
    log.info(f"  Tổng dòng trong file: {total_rows:,}")

    if dry_run:
        # Validate 1000 dòng đầu để kiểm tra parse logic
        sample = df.head(1000)
        parse_errors = 0
        for _, row in sample.iterrows():
            if parse_bts_row(row) is None:
                parse_errors += 1
        log.info(f"[DRY-RUN] Sample 1000 dòng: {parse_errors} lỗi parse ({parse_errors/10:.1f}%)")
        return {
            "total_rows": total_rows,
            "inserted": 0,
            "skipped": parse_errors,
            "errors": 0,
            "duration_sec": round(time.time() - start, 2),
        }

    # Truncate partition tương ứng nếu yêu cầu
    if truncate_first:
        _truncate_flights_for_file(conn, filepath)

    # Parse tất cả rows
    records  = []
    skipped  = 0
    for _, row in df.iterrows():
        parsed = parse_bts_row(row)
        if parsed is None:
            skipped += 1
            continue
        records.append(parsed)

    log.info(f"  Parse xong: {len(records):,} hợp lệ | {skipped:,} bỏ qua")

    if not records:
        log.warning(f"  Không có record nào hợp lệ trong {filepath.name}")
        return {
            "total_rows": total_rows,
            "inserted": 0,
            "skipped": skipped,
            "errors": 0,
            "duration_sec": round(time.time() - start, 2),
        }

    # Insert theo batch
    sql = """
        INSERT INTO flights (
            flight_date, airline_code, flight_number,
            origin, destination,
            dep_time, dep_delay_min,
            arr_time, arr_delay_min,
            cancelled, diverted, distance_miles,
            carrier_delay, weather_delay, nas_delay,
            security_delay, late_aircraft_delay
        ) VALUES (
            %s, %s, %s,
            %s, %s,
            %s, %s,
            %s, %s,
            %s, %s, %s,
            %s, %s, %s,
            %s, %s
        )
        ON CONFLICT DO NOTHING;
    """

    inserted = 0
    errors   = 0

    with tqdm(total=len(records), unit="rows", desc=f"  Insert {filepath.name}") as bar:
        for batch in chunks(records, BATCH_SIZE):
            try:
                with conn.cursor() as cur:
                    psycopg2.extras.execute_batch(cur, sql, batch, page_size=BATCH_SIZE)
                conn.commit()
                inserted += len(batch)
                bar.update(len(batch))
            except psycopg2.Error as e:
                conn.rollback()
                errors += len(batch)
                log.error(f"  Lỗi insert batch: {e}")
                bar.update(len(batch))

    duration = round(time.time() - start, 2)
    rate = inserted / duration if duration > 0 else 0

    log.info(
        f"  ✓ {filepath.name}: "
        f"inserted={inserted:,} | skipped={skipped:,} | errors={errors:,} | "
        f"time={duration}s | rate={rate:,.0f} rows/s"
    )

    return {
        "total_rows": total_rows,
        "inserted": inserted,
        "skipped": skipped,
        "errors": errors,
        "duration_sec": duration,
    }


def _truncate_flights_for_file(conn: psycopg2.extensions.connection, filepath: Path) -> None:
    """
    Xóa dữ liệu của tháng tương ứng với file BTS.

    Tên file BTS convention: 2023_01.csv → tháng 2023-01
    Nếu không parse được tháng từ tên file → xóa toàn bộ flights (cẩn thận!).
    """
    stem = filepath.stem  # e.g. "2023_01"
    parts = stem.split("_")

    if len(parts) == 2:
        try:
            year  = int(parts[0])
            month = int(parts[1])
            start = date(year, month, 1)
            # Tháng tiếp theo
            if month == 12:
                end = date(year + 1, 1, 1)
            else:
                end = date(year, month + 1, 1)

            with conn.cursor() as cur:
                cur.execute(
                    "DELETE FROM flights WHERE flight_date >= %s AND flight_date < %s",
                    (start, end),
                )
            conn.commit()
            log.info(f"  Đã xóa flights từ {start} đến {end} (truncate mode)")
            return
        except ValueError:
            pass

    # Fallback: truncate toàn bộ — cảnh báo
    log.warning("  Không xác định được tháng từ tên file → TRUNCATE toàn bộ bảng flights!")
    with conn.cursor() as cur:
        cur.execute("TRUNCATE TABLE flights RESTART IDENTITY CASCADE;")
    conn.commit()


# ─────────────────────────────────────────────
# STEP 4: Post-import tasks
# ─────────────────────────────────────────────

def refresh_materialized_views(conn: psycopg2.extensions.connection) -> None:
    """
    Refresh tất cả materialized views sau khi import.
    Bỏ qua nếu view chưa tồn tại (chưa chạy materialized.sql).
    """
    views = [
        "mv_airline_summary",
        "mv_delay_heatmap",
        "mv_top_routes",
    ]

    log.info("Refresh materialized views ...")
    for view in views:
        try:
            with conn.cursor() as cur:
                cur.execute(f"REFRESH MATERIALIZED VIEW CONCURRENTLY {view};")
            conn.commit()
            log.info(f"  ✓ REFRESH {view}")
        except psycopg2.errors.UndefinedTable:
            log.warning(f"  ⚠ View '{view}' chưa tồn tại, bỏ qua.")
            conn.rollback()
        except psycopg2.Error as e:
            log.warning(f"  ⚠ Không refresh được {view}: {e}")
            conn.rollback()


def print_summary(conn: psycopg2.extensions.connection) -> None:
    """In thống kê số lượng records trong DB sau khi import."""
    queries = {
        "airports": "SELECT COUNT(*) FROM airports",
        "airlines": "SELECT COUNT(*) FROM airlines",
        "flights":  "SELECT COUNT(*) FROM flights",
        "delay_audit_log": "SELECT COUNT(*) FROM delay_audit_log",
    }

    log.info("─── Tổng kết DB ───")
    for table, sql in queries.items():
        try:
            with conn.cursor() as cur:
                cur.execute(sql)
                count = cur.fetchone()[0]
            log.info(f"  {table:<20} {count:>12,} rows")
        except psycopg2.Error as e:
            log.warning(f"  {table:<20} Lỗi: {e}")
            conn.rollback()

    # Thống kê flights theo tháng
    try:
        with conn.cursor() as cur:
            cur.execute("""
                SELECT
                    DATE_TRUNC('month', flight_date) AS month,
                    COUNT(*) AS cnt
                FROM flights
                GROUP BY 1
                ORDER BY 1;
            """)
            rows = cur.fetchall()
        if rows:
            log.info("  Flights theo tháng:")
            for month, cnt in rows:
                log.info(f"    {str(month)[:7]}  {cnt:>12,}")
    except psycopg2.Error:
        conn.rollback()


# ─────────────────────────────────────────────
# CLI
# ─────────────────────────────────────────────

def find_bts_files(year: Optional[int] = None, specific_file: Optional[str] = None) -> list[Path]:
    """
    Tìm các file BTS CSV cần import.

    Priority:
      1. Nếu --file được chỉ định → chỉ dùng file đó
      2. Nếu --year được chỉ định → tìm data/bts/{year}_*.csv
      3. Nếu không có gì → tìm tất cả data/bts/*.csv
    """
    if specific_file:
        p = Path(specific_file)
        if not p.exists():
            log.error(f"File không tồn tại: {specific_file}")
            sys.exit(1)
        return [p]

    BTS_DIR.mkdir(parents=True, exist_ok=True)
    pattern = f"{year}_*.csv" if year else "*.csv"
    files = sorted(BTS_DIR.glob(pattern))

    if not files:
        log.error(f"Không tìm thấy file BTS nào trong {BTS_DIR} với pattern '{pattern}'")
        log.error("Tải BTS data tại: https://www.transtats.bts.gov/DL_SelectFields.aspx")
        log.error(f"Đặt file vào: {BTS_DIR}/YYYY_MM.csv (ví dụ: 2023_01.csv)")
        sys.exit(1)

    log.info(f"Tìm thấy {len(files)} file BTS: {[f.name for f in files]}")
    return files


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="SkyLens — Import dữ liệu hàng không vào PostgreSQL",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Ví dụ:
  python scripts/ingest.py                          # Import tất cả
  python scripts/ingest.py --year 2023              # Import năm 2023
  python scripts/ingest.py --only airports          # Chỉ import airports
  python scripts/ingest.py --only flights --year 2023
  python scripts/ingest.py --file data/bts/2023_06.csv
  python scripts/ingest.py --year 2023 --truncate   # Xóa cũ, import mới
  python scripts/ingest.py --year 2023 --dry-run    # Validate không insert
        """,
    )
    parser.add_argument(
        "--only",
        choices=["airports", "airlines", "flights", "all"],
        default="all",
        help="Chỉ import phần được chỉ định (default: all)",
    )
    parser.add_argument(
        "--year",
        type=int,
        help="Chỉ import BTS files của năm này (ví dụ: 2023)",
    )
    parser.add_argument(
        "--file",
        type=str,
        help="Import 1 file BTS cụ thể (override --year)",
    )
    parser.add_argument(
        "--truncate",
        action="store_true",
        help="Xóa dữ liệu cũ trước khi import (theo tháng tương ứng)",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Validate data, không insert vào DB",
    )
    parser.add_argument(
        "--no-refresh",
        action="store_true",
        help="Bỏ qua bước refresh materialized views sau import",
    )
    return parser.parse_args()


# ─────────────────────────────────────────────
# Main
# ─────────────────────────────────────────────

def main() -> None:
    args = parse_args()

    if args.dry_run:
        log.info("=" * 50)
        log.info("CHẾ ĐỘ DRY-RUN: Không có gì được insert vào DB")
        log.info("=" * 50)

    conn = get_connection()

    total_stats = {
        "airports": 0,
        "airlines": 0,
        "flights_inserted": 0,
        "flights_skipped": 0,
        "flights_errors": 0,
        "start_time": time.time(),
    }

    try:
        # ── Import Airports ──────────────────────
        if args.only in ("airports", "all"):
            log.info("\n[1/3] Import Airports")
            total_stats["airports"] = import_airports(conn, dry_run=args.dry_run)

        # ── Tìm BTS files ────────────────────────
        bts_files = []
        if args.only in ("airlines", "flights", "all"):
            bts_files = find_bts_files(year=args.year, specific_file=args.file)

        # ── Import Airlines ──────────────────────
        if args.only in ("airlines", "all"):
            log.info("\n[2/3] Import Airlines")
            total_stats["airlines"] = import_airlines(conn, bts_files, dry_run=args.dry_run)

        # ── Import Flights ───────────────────────
        if args.only in ("flights", "all"):
            log.info(f"\n[3/3] Import Flights ({len(bts_files)} files)")
            for i, bts_file in enumerate(bts_files, 1):
                log.info(f"\nFile {i}/{len(bts_files)}: {bts_file.name}")
                stats = import_flights_from_file(
                    conn,
                    bts_file,
                    dry_run=args.dry_run,
                    truncate_first=args.truncate,
                )
                total_stats["flights_inserted"] += stats["inserted"]
                total_stats["flights_skipped"]  += stats["skipped"]
                total_stats["flights_errors"]   += stats["errors"]

        # ── Refresh Materialized Views ───────────
        if not args.dry_run and not args.no_refresh and args.only in ("flights", "all"):
            log.info("\n[Post] Refresh Materialized Views")
            refresh_materialized_views(conn)

        # ── In thống kê cuối ─────────────────────
        if not args.dry_run:
            print_summary(conn)

    except KeyboardInterrupt:
        log.warning("\nDừng lại bởi người dùng (Ctrl+C)")
        conn.rollback()
    finally:
        conn.close()

    # Tổng kết
    duration = round(time.time() - total_stats["start_time"], 2)
    log.info("\n" + "=" * 50)
    log.info("HOÀN TẤT")
    log.info(f"  Airports  : {total_stats['airports']:,}")
    log.info(f"  Airlines  : {total_stats['airlines']:,}")
    log.info(f"  Flights   : {total_stats['flights_inserted']:,} inserted")
    log.info(f"  Skipped   : {total_stats['flights_skipped']:,}")
    log.info(f"  Errors    : {total_stats['flights_errors']:,}")
    log.info(f"  Thời gian : {duration}s ({duration/60:.1f} phút)")
    log.info("=" * 50)

    if total_stats["flights_errors"] > 0:
        sys.exit(1)


if __name__ == "__main__":
    main()
