const API_BASE = import.meta.env.VITE_API_BASE || "http://localhost:8080";

async function getJSON(path) {
  const res = await fetch(`${API_BASE}${path}`);
  if (!res.ok) {
    const body = await res.text();
    throw new Error(`Request failed (${res.status}): ${body}`);
  }
  return res.json();
}

export const api = {
  ranking: () => getJSON("/api/overview/ranking"),
  airlineScore: (code = "AA") =>
    getJSON(`/api/overview/airline-score?airline_code=${encodeURIComponent(code)}`),
  topRoutes: (limit = 20) => getJSON(`/api/routes/top?limit=${limit}`),
  routeKPI: (origin = "JFK", destination = "LAX") =>
    getJSON(
      `/api/routes/kpi?origin=${encodeURIComponent(origin)}&destination=${encodeURIComponent(destination)}`
    ),
  trend: (code = "AA") =>
    getJSON(`/api/trends/monthly?airline_code=${encodeURIComponent(code)}`),
  quality: () => getJSON("/api/quality/summary")
};
