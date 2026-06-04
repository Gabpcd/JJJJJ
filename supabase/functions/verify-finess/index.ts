// verify-finess — Vérification FINESS établissement via l'API FHIR Annuaire Santé
// (ressource Organization). Même gateway / même clé ESANTE_FHIR_API_KEY que verify-rpps.
// Confirme l'existence de la structure + récupère raison sociale / adresse / type.
// NOTE PHASE 1 : fonction de validation API. Recherche par identifier valeur seule
// (FHIR matche la valeur tous systèmes) + remonte les systèmes d'identifiant trouvés
// pour diagnostic. Dégradation gracieuse si clé absente ou API indisponible.

function corsHeaders(req: Request): Record<string, string> {
  const origin = req.headers.get('origin') || '';
  const allowed =
    origin === 'https://jolene.app' || origin === 'https://app.jolene.app' ||
    origin === 'https://www.jolene.app' || origin === 'http://localhost:5173' ||
    origin === 'http://localhost:8080';
  return {
    'Access-Control-Allow-Origin': allowed ? origin : 'https://jolene.app',
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
  };
}

async function fetchWithTimeout(url: string, init: RequestInit, ms: number): Promise<Response> {
  const controller = new AbortController();
  const t = setTimeout(() => controller.abort(), ms);
  try {
    return await fetch(url, { ...init, signal: controller.signal });
  } finally {
    clearTimeout(t);
  }
}

const GATEWAY = 'https://gateway.api.esante.gouv.fr/fhir/v2/Organization';

Deno.serve(async (req) => {
  const cors = corsHeaders(req);
  if (req.method === 'OPTIONS') return new Response(null, { headers: cors });

  const json = (status: number, body: unknown) =>
    new Response(JSON.stringify(body), { status, headers: { ...cors, 'Content-Type': 'application/json' } });

  try {
    const apiKey = Deno.env.get('ESANTE_FHIR_API_KEY') || '';
    const body = await req.json().catch(() => ({}));

    if (body?.warm === true) {
      return json(200, { warm: true, configured: !!apiKey, endpoint: GATEWAY });
    }

    if (!apiKey) {
      return json(200, { ok: false, fhir_indisponible: true, source: 'ESANTE_FHIR_API_KEY non configurée' });
    }

    // Mode debug : inspecter la structure réelle de quelques Organization
    if (body?.debug === true) {
      const url = `${GATEWAY}?_count=${encodeURIComponent(String(body.count || 2))}`;
      const r = await fetchWithTimeout(url, { headers: { 'Accept': 'application/fhir+json', 'ESANTE-API-KEY': apiKey } }, 9000);
      const txt = await r.text();
      return json(200, { debug: true, http: r.status, body: txt.slice(0, 6000) });
    }

    const finess = String(body?.finess || '').replace(/\D/g, '').trim();
    if (!finess || finess.length < 9) {
      return json(400, { ok: false, error: 'FINESS invalide (9 chiffres attendus).' });
    }

    // Recherche par identifier (valeur seule → matche tous systèmes)
    const url = `${GATEWAY}?identifier=${encodeURIComponent(finess)}`;
    const r = await fetchWithTimeout(url, { headers: { 'Accept': 'application/fhir+json', 'ESANTE-API-KEY': apiKey } }, 9000);
    if (!r.ok) {
      const errBody = await r.text();
      return json(200, { ok: false, fhir_indisponible: true, http: r.status, detail: errBody.slice(0, 500) });
    }
    const bundle = await r.json();
    if (!bundle.entry || bundle.entry.length === 0) {
      return json(200, { ok: true, trouve: false });
    }
    const org = bundle.entry[0].resource;
    const identifiers = (org.identifier || []).map((i: any) => ({ system: i.system, value: i.value }));
    const adresse = org.address?.[0]
      ? { ligne: org.address[0].line?.join(' '), ville: org.address[0].city, cp: org.address[0].postalCode }
      : null;
    const types = (org.type || []).flatMap((t: any) => (t.coding || []).map((c: any) => ({ code: c.code, display: c.display, system: c.system })));

    return json(200, {
      ok: true,
      trouve: true,
      nom: org.name || null,
      actif: org.active !== false,
      adresse,
      types,
      identifiers,
      partOf: org.partOf?.display || org.partOf?.reference || null,
      // Diagnostic : y a-t-il un contact/telecom nominatif ?
      telecom: (org.telecom || []).map((t: any) => ({ system: t.system, value: t.value })),
      contact: (org.contact || []).map((c: any) => ({ name: c.name?.text, purpose: c.purpose?.coding?.[0]?.code })),
    });
  } catch (e) {
    return json(200, { ok: false, fhir_indisponible: true, source: 'Erreur appel FHIR', detail: String(e).slice(0, 300) });
  }
});
