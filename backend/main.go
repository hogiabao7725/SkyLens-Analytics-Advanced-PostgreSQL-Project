package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"strconv"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/joho/godotenv"
)

type App struct {
	db *pgxpool.Pool
}

func main() {
	_ = godotenv.Load("../.env")

	db, err := initDB()
	if err != nil {
		log.Fatalf("db init failed: %v", err)
	}
	defer db.Close()

	app := &App{db: db}

	mux := http.NewServeMux()
	mux.HandleFunc("/api/health", app.handleHealth)
	mux.HandleFunc("/api/overview/ranking", app.handleAirlineRanking)
	mux.HandleFunc("/api/overview/airline-score", app.handleAirlineScore)
	mux.HandleFunc("/api/routes/top", app.handleTopRoutes)
	mux.HandleFunc("/api/routes/kpi", app.handleRouteKPI)
	mux.HandleFunc("/api/trends/monthly", app.handleMonthlyTrend)
	mux.HandleFunc("/api/quality/summary", app.handleQualitySummary)

	handler := withCORS(mux)
	port := envOrDefault("API_PORT", "8080")
	log.Printf("SkyLens API listening on :%s", port)
	log.Fatal(http.ListenAndServe(":"+port, handler))
}

func initDB() (*pgxpool.Pool, error) {
	host := envOrDefault("DB_HOST", "localhost")
	port := envOrDefault("DB_PORT", "5432")
	name := envOrDefault("DB_NAME", "skylens")
	user := envOrDefault("DB_USER", "postgres")
	password := os.Getenv("DB_PASSWORD")

	dsn := fmt.Sprintf("host=%s port=%s dbname=%s user=%s password=%s sslmode=disable", host, port, name, user, password)
	cfg, err := pgxpool.ParseConfig(dsn)
	if err != nil {
		return nil, err
	}
	cfg.MaxConns = 8
	return pgxpool.NewWithConfig(context.Background(), cfg)
}

func (a *App) handleHealth(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, map[string]any{
		"ok":   true,
		"time": time.Now().UTC().Format(time.RFC3339),
	})
}

func (a *App) handleAirlineRanking(w http.ResponseWriter, r *http.Request) {
	startDate := queryOrDefault(r, "start_date", "2023-01-01")
	endDate := queryOrDefault(r, "end_date", "2023-12-31")

	rows, err := a.db.Query(r.Context(), `
		SELECT rank_position, airline_code, airline_name, total_flights, on_time_pct,
		       avg_arr_delay_min, cancellation_rate, performance_score
		FROM fn_airline_ranking($1, $2)
		ORDER BY rank_position
		LIMIT 20
	`, startDate, endDate)
	if err != nil {
		writeErr(w, err)
		return
	}
	defer rows.Close()

	type item struct {
		Rank             int32   `json:"rank"`
		AirlineCode      string  `json:"airline_code"`
		AirlineName      string  `json:"airline_name"`
		TotalFlights     int64   `json:"total_flights"`
		OnTimePct        float64 `json:"on_time_pct"`
		AvgArrDelayMin   float64 `json:"avg_arr_delay_min"`
		CancellationRate float64 `json:"cancellation_rate"`
		PerformanceScore float64 `json:"performance_score"`
	}
	var out []item
	for rows.Next() {
		var it item
		if err := rows.Scan(
			&it.Rank, &it.AirlineCode, &it.AirlineName, &it.TotalFlights, &it.OnTimePct,
			&it.AvgArrDelayMin, &it.CancellationRate, &it.PerformanceScore,
		); err != nil {
			writeErr(w, err)
			return
		}
		out = append(out, it)
	}
	writeJSON(w, http.StatusOK, out)
}

func (a *App) handleAirlineScore(w http.ResponseWriter, r *http.Request) {
	airline := queryOrDefault(r, "airline_code", "AA")
	startDate := queryOrDefault(r, "start_date", "2023-01-01")
	endDate := queryOrDefault(r, "end_date", "2023-12-31")

	row := a.db.QueryRow(r.Context(), `
		SELECT airline_code, total_flights, completed_flights, on_time_flights,
		       on_time_pct, avg_arr_delay_min, avg_dep_delay_min, cancellation_rate,
		       severe_delay_pct, performance_score
		FROM fn_airline_score($1, $2, $3)
	`, airline, startDate, endDate)

	type item struct {
		AirlineCode      string  `json:"airline_code"`
		TotalFlights     int64   `json:"total_flights"`
		CompletedFlights int64   `json:"completed_flights"`
		OnTimeFlights    int64   `json:"on_time_flights"`
		OnTimePct        float64 `json:"on_time_pct"`
		AvgArrDelayMin   float64 `json:"avg_arr_delay_min"`
		AvgDepDelayMin   float64 `json:"avg_dep_delay_min"`
		CancellationRate float64 `json:"cancellation_rate"`
		SevereDelayPct   float64 `json:"severe_delay_pct"`
		PerformanceScore float64 `json:"performance_score"`
	}
	var out item
	if err := row.Scan(
		&out.AirlineCode, &out.TotalFlights, &out.CompletedFlights, &out.OnTimeFlights,
		&out.OnTimePct, &out.AvgArrDelayMin, &out.AvgDepDelayMin, &out.CancellationRate,
		&out.SevereDelayPct, &out.PerformanceScore,
	); err != nil {
		writeErr(w, err)
		return
	}
	writeJSON(w, http.StatusOK, out)
}

func (a *App) handleTopRoutes(w http.ResponseWriter, r *http.Request) {
	limit := int32(20)
	if s := r.URL.Query().Get("limit"); s != "" {
		if n, err := strconv.Atoi(s); err == nil && n > 0 && n <= 100 {
			limit = int32(n)
		}
	}

	rows, err := a.db.Query(r.Context(), `
		SELECT origin, destination, origin_city, dest_city,
		       origin_lat, origin_lon, dest_lat, dest_lon,
		       total_flights, avg_arr_delay
		FROM mv_top_routes
		ORDER BY total_flights DESC
		LIMIT $1
	`, limit)
	if err != nil {
		writeErr(w, err)
		return
	}
	defer rows.Close()

	type item struct {
		Origin       string  `json:"origin"`
		Destination  string  `json:"destination"`
		OriginCity   string  `json:"origin_city"`
		DestCity     string  `json:"dest_city"`
		OriginLat    float64 `json:"origin_lat"`
		OriginLon    float64 `json:"origin_lon"`
		DestLat      float64 `json:"dest_lat"`
		DestLon      float64 `json:"dest_lon"`
		TotalFlights int64   `json:"total_flights"`
		AvgDelay     float64 `json:"avg_arr_delay"`
	}
	var out []item
	for rows.Next() {
		var it item
		if err := rows.Scan(
			&it.Origin, &it.Destination, &it.OriginCity, &it.DestCity,
			&it.OriginLat, &it.OriginLon, &it.DestLat, &it.DestLon,
			&it.TotalFlights, &it.AvgDelay,
		); err != nil {
			writeErr(w, err)
			return
		}
		out = append(out, it)
	}
	writeJSON(w, http.StatusOK, out)
}

func (a *App) handleRouteKPI(w http.ResponseWriter, r *http.Request) {
	origin := queryOrDefault(r, "origin", "JFK")
	destination := queryOrDefault(r, "destination", "LAX")
	startDate := queryOrDefault(r, "start_date", "2023-01-01")
	endDate := queryOrDefault(r, "end_date", "2023-12-31")

	row := a.db.QueryRow(r.Context(), `
		SELECT total_flights, completed_flights, cancelled_flights, cancellation_rate,
		       on_time_pct, avg_arr_delay_min
		FROM fn_route_kpi($1, $2, $3, $4)
	`, origin, destination, startDate, endDate)

	type item struct {
		Origin           string  `json:"origin"`
		Destination      string  `json:"destination"`
		TotalFlights     int64   `json:"total_flights"`
		CompletedFlights int64   `json:"completed_flights"`
		CancelledFlights int64   `json:"cancelled_flights"`
		CancellationRate float64 `json:"cancellation_rate"`
		OnTimePct        float64 `json:"on_time_pct"`
		AvgArrDelayMin   float64 `json:"avg_arr_delay_min"`
	}
	var out item
	out.Origin = origin
	out.Destination = destination
	if err := row.Scan(
		&out.TotalFlights, &out.CompletedFlights, &out.CancelledFlights,
		&out.CancellationRate, &out.OnTimePct, &out.AvgArrDelayMin,
	); err != nil {
		writeErr(w, err)
		return
	}
	writeJSON(w, http.StatusOK, out)
}

func (a *App) handleMonthlyTrend(w http.ResponseWriter, r *http.Request) {
	airline := queryOrDefault(r, "airline_code", "AA")
	rows, err := a.db.Query(r.Context(), `
		SELECT month, airline_code, on_time_pct, avg_arr_delay, mom_change_pct
		FROM v_airline_monthly_trend
		WHERE airline_code = $1
		ORDER BY month
	`, airline)
	if err != nil {
		writeErr(w, err)
		return
	}
	defer rows.Close()

	type item struct {
		Month        string   `json:"month"`
		AirlineCode  string   `json:"airline_code"`
		OnTimePct    *float64 `json:"on_time_pct"`
		AvgArrDelay  *float64 `json:"avg_arr_delay"`
		MomChangePct *float64 `json:"mom_change_pct"`
	}
	var out []item
	for rows.Next() {
		var it item
		var month time.Time
		if err := rows.Scan(&month, &it.AirlineCode, &it.OnTimePct, &it.AvgArrDelay, &it.MomChangePct); err != nil {
			writeErr(w, err)
			return
		}
		it.Month = month.Format("2006-01")
		out = append(out, it)
	}
	writeJSON(w, http.StatusOK, out)
}

func (a *App) handleQualitySummary(w http.ResponseWriter, r *http.Request) {
	startDate := queryOrDefault(r, "start_date", "2023-01-01")
	endDate := queryOrDefault(r, "end_date", "2023-12-31")

	rows, err := a.db.Query(r.Context(), `
		SELECT metric_name, metric_value, metric_percent
		FROM fn_data_quality_summary($1, $2)
	`, startDate, endDate)
	if err != nil {
		writeErr(w, err)
		return
	}
	defer rows.Close()

	type item struct {
		MetricName    string   `json:"metric_name"`
		MetricValue   int64    `json:"metric_value"`
		MetricPercent *float64 `json:"metric_percent"`
	}
	var out []item
	for rows.Next() {
		var it item
		if err := rows.Scan(&it.MetricName, &it.MetricValue, &it.MetricPercent); err != nil {
			writeErr(w, err)
			return
		}
		out = append(out, it)
	}
	writeJSON(w, http.StatusOK, out)
}

func withCORS(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Access-Control-Allow-Origin", "*")
		w.Header().Set("Access-Control-Allow-Headers", "Content-Type")
		w.Header().Set("Access-Control-Allow-Methods", "GET, OPTIONS")
		if r.Method == http.MethodOptions {
			w.WriteHeader(http.StatusNoContent)
			return
		}
		next.ServeHTTP(w, r)
	})
}

func writeErr(w http.ResponseWriter, err error) {
	writeJSON(w, http.StatusInternalServerError, map[string]any{
		"error": err.Error(),
	})
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}

func envOrDefault(key, fallback string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return fallback
}

func queryOrDefault(r *http.Request, key, fallback string) string {
	if value := r.URL.Query().Get(key); value != "" {
		return value
	}
	return fallback
}
