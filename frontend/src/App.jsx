import { useEffect, useMemo, useState } from "react";
import {
  LineChart,
  Line,
  XAxis,
  YAxis,
  Tooltip,
  CartesianGrid,
  ResponsiveContainer
} from "recharts";
import { MapContainer, Polyline, TileLayer, Popup } from "react-leaflet";
import { api } from "./api";

function useLoad(fn, deps = []) {
  const [data, setData] = useState([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");
  const [reloadTick, setReloadTick] = useState(0);

  useEffect(() => {
    let alive = true;
    setLoading(true);
    setError("");
    fn()
      .then((d) => alive && setData(d))
      .catch((e) => alive && setError(e.message))
      .finally(() => alive && setLoading(false));
    return () => {
      alive = false;
    };
  }, [...deps, reloadTick]); // eslint-disable-line react-hooks/exhaustive-deps

  return { data, loading, error, reload: () => setReloadTick((v) => v + 1) };
}

export default function App() {
  const [airlineCode, setAirlineCode] = useState("AA");
  const [origin, setOrigin] = useState("JFK");
  const [destination, setDestination] = useState("LAX");

  const ranking = useLoad(() => api.ranking(), []);
  const score = useLoad(() => api.airlineScore(airlineCode), [airlineCode]);
  const trend = useLoad(() => api.trend(airlineCode), [airlineCode]);
  const routes = useLoad(() => api.topRoutes(20), []);
  const quality = useLoad(() => api.quality(), []);
  const routeKPI = useLoad(() => api.routeKPI(origin, destination), [origin, destination]);

  const mapCenter = useMemo(() => [39.5, -98.35], []);
  const hasErrors =
    !!ranking.error || !!score.error || !!trend.error || !!routes.error || !!quality.error || !!routeKPI.error;

  return (
    <div className="page">
      <header className="hero">
        <h1>SkyLens Analytics Demo</h1>
        <p>Go Backend + React Dashboard + Leaflet Route Map</p>
      </header>

      {hasErrors && (
        <div className="alert">
          Một số dữ liệu chưa tải được. Kiểm tra lại deploy SQL hoặc dùng nút retry ở từng khối.
        </div>
      )}

      <section className="card-grid">
        <Card title="Airline Score">
          <div className="controls">
            <label>
              Airline:
              <input value={airlineCode} onChange={(e) => setAirlineCode(e.target.value.toUpperCase())} />
            </label>
          </div>
          <DataState {...score}>
            {score.data && (
              <ul className="kpi-list">
                <li>Performance: {fmt(score.data.performance_score)}</li>
                <li>On-time: {fmt(score.data.on_time_pct)}%</li>
                <li>Avg Delay: {fmt(score.data.avg_arr_delay_min)} min</li>
                <li>Cancellation: {fmt(score.data.cancellation_rate)}%</li>
              </ul>
            )}
          </DataState>
        </Card>

        <Card title="Route KPI">
          <div className="controls row">
            <label>
              Origin
              <input value={origin} onChange={(e) => setOrigin(e.target.value.toUpperCase())} />
            </label>
            <label>
              Destination
              <input value={destination} onChange={(e) => setDestination(e.target.value.toUpperCase())} />
            </label>
          </div>
          <DataState {...routeKPI}>
            {routeKPI.data && (
              <ul className="kpi-list">
                <li>Total Flights: {routeKPI.data.total_flights}</li>
                <li>On-time: {fmt(routeKPI.data.on_time_pct)}%</li>
                <li>Avg Delay: {fmt(routeKPI.data.avg_arr_delay_min)} min</li>
                <li>Cancelled: {routeKPI.data.cancelled_flights}</li>
              </ul>
            )}
          </DataState>
        </Card>
      </section>

      <section className="card">
        <h2>Monthly Trend ({airlineCode})</h2>
        <DataState {...trend}>
          <div className="chart">
            <ResponsiveContainer width="100%" height="100%">
              <LineChart data={trend.data}>
                <CartesianGrid strokeDasharray="3 3" />
                <XAxis dataKey="month" />
                <YAxis />
                <Tooltip />
                <Line type="monotone" dataKey="on_time_pct" name="On Time %" stroke="#0f766e" />
                <Line type="monotone" dataKey="avg_arr_delay" name="Avg Delay" stroke="#0369a1" />
              </LineChart>
            </ResponsiveContainer>
          </div>
        </DataState>
      </section>

      <section className="card">
        <h2>Top Routes Map (No Google Maps Key Needed)</h2>
        <DataState {...routes}>
          <div className="map-wrap">
            <MapContainer center={mapCenter} zoom={4} scrollWheelZoom={true}>
              <TileLayer
                attribution='&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>'
                url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"
              />
              {routes.data.map((r, idx) => (
                <Polyline
                  key={`${r.origin}-${r.destination}-${idx}`}
                  positions={[
                    [r.origin_lat, r.origin_lon],
                    [r.dest_lat, r.dest_lon]
                  ]}
                  pathOptions={{ color: "#2563eb", weight: 2, opacity: 0.55 }}
                >
                  <Popup>
                    {r.origin} ({r.origin_city}) → {r.destination} ({r.dest_city})
                    <br />
                    Flights: {r.total_flights}
                    <br />
                    Avg Delay: {fmt(r.avg_arr_delay)} min
                  </Popup>
                </Polyline>
              ))}
            </MapContainer>
          </div>
        </DataState>
      </section>

      <section className="card-grid">
        <Card title="Top Airlines">
          <DataState {...ranking}>
            <SimpleTable
              rows={ranking.data}
              columns={["rank", "airline_code", "airline_name", "performance_score", "on_time_pct"]}
            />
          </DataState>
        </Card>
        <Card title="Data Quality Snapshot">
          <DataState {...quality}>
            <SimpleTable rows={quality.data} columns={["metric_name", "metric_value", "metric_percent"]} />
          </DataState>
        </Card>
      </section>
    </div>
  );
}

function Card({ title, children }) {
  return (
    <div className="card">
      <h2>{title}</h2>
      {children}
    </div>
  );
}

function DataState({ loading, error, reload, children }) {
  if (loading) return <p className="state">Loading...</p>;
  if (error)
    return (
      <div className="state error-block">
        <p>{error}</p>
        <button className="retry" onClick={reload}>
          Retry
        </button>
      </div>
    );
  return children;
}

function SimpleTable({ rows = [], columns = [] }) {
  return (
    <div className="table-wrap">
      <table>
        <thead>
          <tr>
            {columns.map((col) => (
              <th key={col}>{col}</th>
            ))}
          </tr>
        </thead>
        <tbody>
          {rows.map((row, idx) => (
            <tr key={idx}>
              {columns.map((col) => (
                <td key={col}>{fmt(row[col])}</td>
              ))}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

function fmt(v) {
  if (v === null || v === undefined) return "-";
  if (typeof v === "number") return Number.isInteger(v) ? v : v.toFixed(2);
  return v;
}
