# Tổng quan về Triggers và Window Functions trong Airline-PostgreSQL

Dự án **Airline-PostgreSQL** sử dụng các tính năng nâng cao của PostgreSQL để đảm bảo tính toàn vẹn dữ liệu, tự động hóa quy trình (thông qua Triggers) và phân tích dữ liệu chuyên sâu (thông qua Window Functions).

Dưới đây là chi tiết về các thành phần này:

## 1. Triggers (Trình kích hoạt)

Dự án có tổng cộng **4 Triggers** được định nghĩa riêng biệt trong thư mục `sql/triggers/`. Chúng đóng vai trò tự động hóa việc cập nhật dữ liệu và ngăn chặn các hành động không hợp lệ.

### 1.1 Trigger: `trg_airline_fts`
- **File:** `sql/triggers/102_airlines_fts.sql`
- **Áp dụng trên bảng:** `airlines`
- **Hành động:** `BEFORE INSERT OR UPDATE`
- **Chức năng:** Tự động tạo và cập nhật dữ liệu cho cột Full-Text Search (`search_vector` kiểu `tsvector`). Khi có một hãng hàng không mới được thêm vào hoặc tên hãng bị sửa đổi, trigger này sẽ chuẩn hóa văn bản thành các vector tìm kiếm, giúp cho việc truy vấn tên đối tượng nhanh chóng và chính xác.

### 1.2 Trigger: `trg_airport_fts`
- **File:** `sql/triggers/101_airports_fts_and_guard.sql`
- **Áp dụng trên bảng:** `airports`
- **Hành động:** `BEFORE INSERT OR UPDATE`
- **Chức năng:** Tương tự như trigger trên bảng `airlines`, trigger này đảm bảo cột `search_vector` của bảng `airports` luôn được cập nhật tự động mỗi khi thông tin sân bay thay đổi. Điều này rất hữu ích cho tính năng tìm kiếm tên sân bay hoặc thành phố.

### 1.3 Trigger: `trg_prevent_airport_delete`
- **File:** `sql/triggers/101_airports_fts_and_guard.sql`
- **Áp dụng trên bảng:** `airports`
- **Hành động:** `BEFORE DELETE`
- **Chức năng:** Đảm bảo toàn vẹn dữ liệu (Referential Integrity). Trước khi hệ thống hoặc người dùng cố gắng xóa một sân bay khỏi cơ sở dữ liệu, trigger này sẽ tự động kiểm tra xem có bất kỳ chuyến bay nào (trong bảng `flights`) đang sử dụng sân bay này làm điểm đi (Origin) hoặc điểm đến (Destination) hay không. Nếu có, nó sẽ ném ra một lỗi (Exception) và ngăn chặn việc xóa.

### 1.4 Trigger: `trg_log_delay`
- **File:** `sql/triggers/103_flights_delay_audit.sql`
- **Áp dụng trên bảng:** `flights`
- **Hành động:** `AFTER INSERT`
- **Chức năng:** Tự động giám sát và lưu vết (Audit Log). Mỗi khi có một chuyến bay được thêm vào hệ thống chứa thông tin về độ hoãn chuyến (delay > 0), trigger này sẽ phân loại mức độ trễ của sự kiện và tự động chèn một bản ghi tương ứng vào bảng lưu vết trễ chuyến (`delay_audit_log`).

---

## 2. Window Functions (Hàm Cửa Sổ)

Hệ thống tận dụng tính năng Window Functions vô cùng mạnh mẽ vào quá trình phân tích dữ liệu chuyên sâu. Các lệnh này nằm tại `sql/queries/window_functions.sql`, cộng thêm truy vấn PostGIS và functions được đóng gói. Tính năng này cho phép thực hiện phân tích số liệu thống kê mà vẫn giữ nguyên mức độ chi tiết của dòng dữ liệu.

Các Window Function bao gồm:

### 2.1 Xếp hạng dữ liệu (Ranking)
- **`RANK() OVER (...)`**: Chuyên dùng để xếp hạng cho các chuyến bay, nhóm các hãng hoặc sân bay theo tiêu chí xếp hạng (ví dụ: mức độ delay). Khi các giá trị xếp hạng bằng nhau, chúng có chung một hạng và hạng tiếp sẽ bị nhảy số (VD: 1, 2, 2, 4).
- **`DENSE_RANK() OVER (...)`**: Cung cấp cách tính tương tự như `RANK()` nhưng không có khe hở (nhảy số) nào giữa các hạng kết quả (VD: 1, 2, 2, 3).
- **File sử dụng:** `sql/queries/window_functions.sql`, `sql/functions/211_fn_airline_score.sql`, `sql/functions/212_fn_airline_ranking.sql`

### 2.2 Đọc giá trị liền kề / So sánh dòng thời gian (Row Offset)
- **`LAG(column, offset) OVER (...)`**: Tính năng này cung cấp cách thức truy xuất giá trị của một hàng ở vị trí trước đó (hoặc ngày/tháng ngay phía trước). Rất hữu hiệu để đánh giá hiệu suất, lấy chênh lệch delay của hôm nay trừ cho ngày hôm qua.
- **File sử dụng:** `sql/queries/window_functions.sql`

### 2.3 Phân tích Cửa sổ Khung Di động (Window Framing / Moving Aggregations)
- **`AVG() OVER (ROWS BETWEEN 6 PRECEDING AND CURRENT ROW)`**: 
  - Tính Toán Trung bình Động (Moving Average). 
  - Khung thời gian được thiết lập kéo dài từ thao tác trên 6 hàng phía trước cho tới hàng hiện tại (hiểu theo nghĩa phân tích là chu kỳ 7 ngày). Giúp làm trơn nhẵn các ngoại lai từ biểu đồ hoãn chuyến.
- **`SUM() OVER (ORDER BY... ROWS UNBOUNDED PRECEDING)`**: 
  - Tính Tổng Lũy kế (Running Sum/Cumulative Total). Nó giữ giá trị tích lũy số lượng chuyến bay hoặc tổng phút chậm trễ xuyên xuốt chiều dài dữ liệu từ ngày đầu tiên cho tới dòng hiện tại.
- **`AVG() OVER (PARTITION BY ...) / AVG() OVER ()`**: 
  - Lấy giá trị trung bình trên một vách ngăn/phân vùng (PARTITION) hay trên toàn bộ dữ liệu mà không cần phải gộp lại bằng `GROUP BY` triệt để, cho phép gán trực tiếp mức trung bình này kế bên từng chuyến bay gốc.
- **File sử dụng:** `sql/queries/window_functions.sql`

### 2.4 Chia nhóm Phân phối & Định Vị Phần Trăm (Distribution & Partitioning)
- **`NTILE(10) OVER (...) / NTILE(4) OVER (...)`**: Giúp bạn gán và chia đều dữ liệu từ các hãng/chuyến bay thành 10 phần (Deciles) hoặc 4 nhóm hiệu suất (Quartiles). Hữu ích cho việc phát hiện các nhóm top 10% hay 25% chậm trễ cực đoan nhất.
- **`PERCENT_RANK() OVER (...)`**: Chỉ định vị trí bằng tỷ lệ phần trăm (được tính từ 0 đến 1) của một hàng.
- **`CUME_DIST() OVER (...)`**: Tính toán phân bố tích lũy, giúp biết tổng quát đã có bao nhiêu phần trăm dữ liệu là nhỏ hơn hoặc đạt đúng bằng mức giá trị đó.
- **File sử dụng:** `sql/queries/window_functions.sql`

### 2.5 Gom cụm Không gian Cửa Sổ (Spatial Window Function)
- **`ST_ClusterKMeans(...) OVER ()`**: Một Window function đặc thù áp dụng PostGIS nâng cao (Spatial Data). Thuật toán Machine Learning K-Means sẽ được vận hành trên biến tọa độ thiết yếu của địa lý, giúp tự động gom cụm các sân bay gần nhau nhất tạo thành các phân vùng định tuyến di chuyển.
- **File sử dụng:** `sql/queries/postgis.sql`
