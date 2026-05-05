import { useEffect, useMemo, useState } from "react";
import {
  AreaChart,
  Area,
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
      {/* GLOBAL STICKY NAVBAR */}
      <header className="top-bar">
        <div className="brand">
          <h1>SkyLens Analytics</h1>
          <p>Aviation Intelligence Dashboard</p>
        </div>
        <div className="global-controls">
          <div className="control-group">
            <label>Airline</label>
            <input 
              value={airlineCode} 
              onChange={(e) => setAirlineCode(e.target.value.toUpperCase())} 
              maxLength={2}
            />
          </div>
          <div className="control-group">
            <label>Origin</label>
            <input 
              value={origin} 
              onChange={(e) => setOrigin(e.target.value.toUpperCase())} 
              maxLength={3}
            />
          </div>
          <div className="control-group">
            <label>Dest</label>
            <input 
              value={destination} 
              onChange={(e) => setDestination(e.target.value.toUpperCase())} 
              maxLength={3}
            />
          </div>
        </div>
      </header>

      {hasErrors && (
        <div className="global-alert">
          <strong>Lỗi Kết Nối:</strong> Đảm bảo Database & Backend đã được deploy hoàn chỉnh. Bấm "Retry" ở khối bị lỗi.
        </div>
      )}

      {/* DASHBOARD GRID */}
      <main className="dashboard-grid">
        
        {/* ROW 1: 4 KPI CARDS FOR AIRLINE (Col span 3 each) */}
        <div className="card col-span-3">
          <h2 className="card-title">Flights Tracked</h2>
          <DataState {...score}>
            {score.data && (
              <>
                <div className="kpi-value">{score.data.total_flights?.toLocaleString() || 0}</div>
                <div className="kpi-sub">Total operational records</div>
              </>
            )}
          </DataState>
        </div>

        <div className="card col-span-3">
          <h2 className="card-title">Performance Score</h2>
          <DataState {...score}>
            {score.data && (
              <>
                <div className="kpi-value kpi-neutral">{fmt(score.data.performance_score)}</div>
                <div className="kpi-sub">Out of 100 points</div>
              </>
            )}
          </DataState>
        </div>

        <div className="card col-span-3">
          <h2 className="card-title">On-time Reliability</h2>
          <DataState {...score}>
            {score.data && (
              <>
                <div className={`kpi-value ${score.data.on_time_pct >= 80 ? 'kpi-good' : 'kpi-warning'}`}>
                  {fmt(score.data.on_time_pct)}%
                </div>
                <div className="kpi-sub">Arrival delay &le; 15 mins</div>
              </>
            )}
          </DataState>
        </div>

        <div className="card col-span-3">
          <h2 className="card-title">Cancellation Rate</h2>
          <DataState {...score}>
            {score.data && (
              <>
                <div className={`kpi-value ${score.data.cancellation_rate < 3 ? 'kpi-good' : 'kpi-bad'}`}>
                  {fmt(score.data.cancellation_rate)}%
                </div>
                <div className="kpi-sub">Industry target: &lt; 3%</div>
              </>
            )}
          </DataState>
        </div>

        {/* ROW 2: CHART (Span 8) + ROUTE KPI (Span 4) */}
        <div className="card col-span-8">
          <h2 className="card-title">Delay Trend ({airlineCode})</h2>
          <DataState {...trend}>
            <div className="chart-container">
              <ResponsiveContainer width="100%" height="100%">
                <AreaChart data={trend.data} margin={{ top: 10, right: 10, left: -20, bottom: 0 }}>
                  <defs>
                    <linearGradient id="colorDelay" x1="0" y1="0" x2="0" y2="1">
                      <stop offset="5%" stopColor="#0ea5e9" stopOpacity={0.3}/>
                      <stop offset="95%" stopColor="#0ea5e9" stopOpacity={0}/>
                    </linearGradient>
                  </defs>
                  <CartesianGrid strokeDasharray="3 3" stroke="#334155" vertical={false} />
                  <XAxis dataKey="month" stroke="#94a3b8" tick={{fill: '#94a3b8', fontSize: 12}} tickMargin={10} />
                  <YAxis stroke="#94a3b8" tick={{fill: '#94a3b8', fontSize: 12}} />
                  <Tooltip 
                    contentStyle={{ backgroundColor: 'rgba(15, 23, 42, 0.9)', borderColor: '#334155', borderRadius: '8px' }}
                    itemStyle={{ color: '#f8fafc' }}
                  />
                  <Area 
                    type="monotone" 
                    dataKey="avg_arr_delay" 
                    name="Avg Delay (min)" 
                    stroke="#0ea5e9" 
                    strokeWidth={3}
                    fillOpacity={1} 
                    fill="url(#colorDelay)" 
                  />
                </AreaChart>
              </ResponsiveContainer>
            </div>
          </DataState>
        </div>

        <div className="card col-span-4">
          <h2 className="card-title">Route Deep Dive: {origin} &rarr; {destination}</h2>
          <DataState {...routeKPI}>
            {routeKPI.data && (
              <div style={{display: 'flex', flexDirection: 'column', gap: '20px', height: '100%', justifyContent: 'center'}}>
                <div>
                  <div className="kpi-sub" style={{marginBottom: '4px'}}>Total Route Flights</div>
                  <div className="kpi-value" style={{fontSize: '28px'}}>{routeKPI.data.total_flights?.toLocaleString()}</div>
                </div>
                <div>
                  <div className="kpi-sub" style={{marginBottom: '4px'}}>Route On-time %</div>
                  <div className="kpi-value kpi-good" style={{fontSize: '28px'}}>{fmt(routeKPI.data.on_time_pct)}%</div>
                </div>
                <div>
                  <div className="kpi-sub" style={{marginBottom: '4px'}}>Avg Route Delay</div>
                  <div className="kpi-value kpi-bad" style={{fontSize: '28px'}}>{fmt(routeKPI.data.avg_arr_delay_min)} min</div>
                </div>
              </div>
            )}
          </DataState>
        </div>

        {/* ROW 3: MAP (Span 12) */}
        <div className="card col-span-12">
          <h2 className="card-title">Network Heatmap (Top 20 Routes)</h2>
          <DataState {...routes}>
            <div className="map-container">
              <MapContainer center={mapCenter} zoom={4.5} scrollWheelZoom={false}>
                {/* DARK THEME CARTODB TILELAYER */}
                <TileLayer
                  attribution='&copy; <a href="https://carto.com/">CartoDB</a>'
                  url="https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png"
                />
                {routes.data.map((r, idx) => (
                  <Polyline
                    key={`${r.origin}-${r.destination}-${idx}`}
                    positions={[
                      [r.origin_lat, r.origin_lon],
                      [r.dest_lat, r.dest_lon]
                    ]}
                    pathOptions={{ color: "#0ea5e9", weight: Math.max(1, (r.total_flights / 5000) * 3), opacity: 0.6 }}
                  >
                    <Popup className="dark-popup">
                      <strong>{r.origin} ({r.origin_city}) &rarr; {r.destination} ({r.dest_city})</strong>
                      <br />
                      Flights: {r.total_flights?.toLocaleString()}
                      <br />
                      Avg Delay: {fmt(r.avg_arr_delay)} min
                    </Popup>
                  </Polyline>
                ))}
              </MapContainer>
            </div>
          </DataState>
        </div>

        {/* ROW 4: RANKING TABLE (Span 8) + QUALITY (Span 4) */}
        <div className="card col-span-8">
          <h2 className="card-title">Top Carrier Leaderboard</h2>
          <DataState {...ranking}>
            <RankingTable rows={ranking.data} />
          </DataState>
        </div>

        <div className="card col-span-4">
          <h2 className="card-title">System Health (Data Quality)</h2>
          <DataState {...quality}>
            <QualityTable rows={quality.data} />
          </DataState>
        </div>

      </main>
    </div>
  );
}

// ================= UI COMPONENTS =================

function DataState({ loading, error, reload, children }) {
  if (loading) return (
    <div className="state-container">
      <div className="loader"></div>
      <div style={{color: 'var(--text-muted)', fontSize: '13px'}}>Loading data...</div>
    </div>
  );
  if (error) return (
    <div className="state-container">
      <div className="error-text">{error}</div>
      <button className="btn-retry" onClick={reload}>Retry Connection</button>
    </div>
  );
  return children;
}

function RankingTable({ rows = [] }) {
  return (
    <div className="table-container">
      <table>
        <thead>
          <tr>
            <th>Rank</th>
            <th>Carrier</th>
            <th>Score</th>
            <th>On-time</th>
            <th>Flights</th>
          </tr>
        </thead>
        <tbody>
          {rows.map((row, idx) => (
            <tr key={idx}>
              <td><span className="badge badge-rank">#{row.rank}</span></td>
              <td>
                <div style={{fontWeight: 600, color: 'var(--text-main)'}}>{row.airline_code}</div>
                <div style={{fontSize: '12px', color: 'var(--text-muted)'}}>{row.airline_name}</div>
              </td>
              <td><span className="badge badge-score">{fmt(row.performance_score)}</span></td>
              <td>{fmt(row.on_time_pct)}%</td>
              <td style={{color: 'var(--text-muted)'}}>{row.total_flights?.toLocaleString()}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

function QualityTable({ rows = [] }) {
  return (
    <div className="table-container">
      <table>
        <thead>
          <tr>
            <th>Metric Check</th>
            <th>Impact</th>
          </tr>
        </thead>
        <tbody>
          {rows.map((row, idx) => {
            const isErrorMetric = row.metric_name !== 'total_rows' && row.metric_value > 0;
            return (
              <tr key={idx}>
                <td style={{textTransform: 'capitalize'}}>
                  {row.metric_name.replace(/_/g, ' ')}
                </td>
                <td>
                  <div style={{color: isErrorMetric ? 'var(--accent-warning)' : 'var(--text-main)', fontWeight: 600}}>
                    {row.metric_value?.toLocaleString()}
                  </div>
                  {row.metric_percent !== null && (
                    <div style={{fontSize: '12px', color: 'var(--text-muted)'}}>
                      {fmt(row.metric_percent)}%
                    </div>
                  )}
                </td>
              </tr>
            );
          })}
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
