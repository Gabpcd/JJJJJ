import { createClient } from "npm:@supabase/supabase-js@2";

// Prospection d'établissements de santé (démarchage B2B) — interroge en direct
// l'API publique recherche-entreprises.api.gouv.fr (open data, sans clé) par
// département + catégorie. Renvoie nom + adresse + SIRET. Le téléphone/email n'est
// pas fourni par cette API : le frontend propose des liens Pages Jaunes/Google
// pré-remplis (1 clic) pour récupérer les coordonnées. Réservé ADMIN_PLATEFORME.

function getCorsOrigin(req: Request): string {
  const o = req.headers.get("origin") || "";
  if (["https://jolene.app", "https://app.jolene.app", "https://www.jolene.app", "http://localhost:5173", "http://localhost:8080"].includes(o)) return o;
  return "https://jolene.app";
}
function cors(req: Request) {
  return { "Access-Control-Allow-Origin": getCorsOrigin(req), "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type", "Content-Type": "application/json" };
}

// Catégories ciblables → codes NAF (établissements employeurs de soignants)
const NAF: Record<string, string[]> = {
  EHPAD: ["87.10A", "87.10B", "87.30A"],
  HOPITAL: ["86.10Z"],
  PHARMACIE: ["47.73Z"],
  HANDICAP: ["87.20A", "87.20B", "88.10A", "88.10B", "88.10C"],
  CABINET_MEDICAL: ["86.21Z", "86.22A", "86.22B", "86.22C"],
  CABINET_DENTAIRE: ["86.23Z"],
  LABO: ["86.90B"],
  AUTRE_SANTE: ["86.90A", "86.90D", "86.90E", "86.90F"],
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: cors(req) });
  try {
    const auth = req.headers.get("Authorization");
    if (!auth?.startsWith("Bearer ")) return new Response(JSON.stringify({ error: "Non autorisé" }), { status: 401, headers: cors(req) });
    const token = auth.replace("Bearer ", "");
    const url = Deno.env.get("SUPABASE_URL")!;
    const admin = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } });
    const authClient = createClient(url, Deno.env.get("SUPABASE_ANON_KEY")!);
    const { data: { user } } = await authClient.auth.getUser(token);
    if (!user) return new Response(JSON.stringify({ error: "Token invalide" }), { status: 401, headers: cors(req) });
    const { data: u } = await admin.auth.admin.getUserById(user.id);
    if ((u?.user?.app_metadata as any)?.role !== "ADMIN_PLATEFORME") {
      return new Response(JSON.stringify({ error: "Accès admin requis" }), { status: 403, headers: cors(req) });
    }

    const { departement, categorie, page } = await req.json().catch(() => ({}));
    const dep = String(departement || "").trim();
    if (!/^(2A|2B|\d{1,3})$/.test(dep)) return new Response(JSON.stringify({ error: "Département invalide (ex. 75, 2A, 971)" }), { status: 400, headers: cors(req) });
    const nafCodes = NAF[categorie] || NAF.EHPAD;
    const p = Math.min(Math.max(Number(page) || 1, 1), 20);

    // L'API accepte activite_principale en liste séparée par virgules.
    const apiUrl = `https://recherche-entreprises.api.gouv.fr/search?activite_principale=${encodeURIComponent(nafCodes.join(","))}&departement=${encodeURIComponent(dep)}&etat_administratif=A&per_page=25&page=${p}&mtm_campaign=jolene`;
    const r = await fetch(apiUrl, { headers: { Accept: "application/json" } });
    if (!r.ok) return new Response(JSON.stringify({ error: "API entreprises indisponible", status: r.status }), { status: 502, headers: cors(req) });
    const data = await r.json();

    const resultats = (data.results || []).map((e: any) => {
      const s = e.siege || {};
      const adresse = [s.numero_voie, s.type_voie, s.libelle_voie].filter(Boolean).join(" ")
        || s.adresse || "";
      return {
        nom: e.nom_complet || e.nom_raison_sociale || "—",
        siret: s.siret || null,
        adresse,
        code_postal: s.code_postal || null,
        ville: s.libelle_commune || null,
        naf: s.activite_principale || e.activite_principale || null,
        nb_etablissements: e.nombre_etablissements_ouverts || null,
      };
    });

    return new Response(JSON.stringify({
      resultats,
      total: data.total_results ?? resultats.length,
      page: p,
      total_pages: data.total_pages ?? 1,
    }), { headers: cors(req) });
  } catch (e: any) {
    return new Response(JSON.stringify({ error: e?.message || "Erreur interne" }), { status: 500, headers: cors(req) });
  }
});
