// Relais météo de l'appli Élevage d'ALB (fonction Supabase « meteo », déjà installée sur le projet).
// Prévisions : MET Norway (api.met.no), données CC BY 4.0. Communes : geo.api.gouv.fr (licence ouverte Etalab).
// MET Norway demande d'identifier l'appli (User-Agent) et de passer par un serveur pour les applis web : c'est le rôle de cette fonction.
const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const UA = "ElevageALB/1.0 https://github.com/enguerranddelaferte-tech/elevage-d-alb";
const cache = new Map<string, { exp: number; body: string; lm?: string }>();

function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), { status, headers: { ...CORS, "Content-Type": "application/json" } });
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json({ error: "Méthode non autorisée" }, 405);
  let b: Record<string, unknown> = {};
  try { b = await req.json(); } catch { return json({ error: "Requête invalide" }, 400); }

  try {
    if (b.type === "communes") {
      let url: string;
      if (b.lat != null && b.lon != null) {
        const la = Number(b.lat), lo = Number(b.lon);
        if (!isFinite(la) || !isFinite(lo)) return json({ error: "Position invalide" }, 400);
        url = `https://geo.api.gouv.fr/communes?lat=${la.toFixed(4)}&lon=${lo.toFixed(4)}&fields=nom,centre,codesPostaux,departement&limit=1`;
      } else {
        const q = String(b.q ?? "").trim().slice(0, 60);
        if (q.length < 2) return json([]);
        url = /^\d{5}$/.test(q)
          ? `https://geo.api.gouv.fr/communes?codePostal=${q}&fields=nom,centre,codesPostaux,departement&limit=8`
          : `https://geo.api.gouv.fr/communes?nom=${encodeURIComponent(q)}&fields=nom,centre,codesPostaux,departement&boost=population&limit=8`;
      }
      const r = await fetch(url, { headers: { "User-Agent": UA } });
      if (!r.ok) return json({ error: `Recherche de commune indisponible (${r.status})` }, 502);
      return json(await r.json());
    }

    const lat = Number(b.lat), lon = Number(b.lon);
    if (!isFinite(lat) || !isFinite(lon) || Math.abs(lat) > 90 || Math.abs(lon) > 180) return json({ error: "Position invalide" }, 400);
    const key = `${lat.toFixed(4)},${lon.toFixed(4)}`;
    const hit = cache.get(key);
    if (hit && hit.exp > Date.now()) return new Response(hit.body, { headers: { ...CORS, "Content-Type": "application/json" } });

    const headers: Record<string, string> = { "User-Agent": UA };
    if (hit?.lm) headers["If-Modified-Since"] = hit.lm;
    const r = await fetch(`https://api.met.no/weatherapi/locationforecast/2.0/compact?lat=${lat.toFixed(4)}&lon=${lon.toFixed(4)}`, { headers });
    let body: string;
    if (r.status === 304 && hit) body = hit.body;
    else if (r.ok) body = await r.text();
    else return json({ error: `Prévisions indisponibles (${r.status})` }, 502);
    const expHeader = r.headers.get("Expires");
    const exp = expHeader ? Date.parse(expHeader) : NaN;
    cache.set(key, { body, exp: isFinite(exp) ? exp : Date.now() + 30 * 60000, lm: r.headers.get("Last-Modified") ?? hit?.lm });
    return new Response(body, { headers: { ...CORS, "Content-Type": "application/json" } });
  } catch (e) {
    return json({ error: "Service météo injoignable", detail: String(e) }, 502);
  }
});
