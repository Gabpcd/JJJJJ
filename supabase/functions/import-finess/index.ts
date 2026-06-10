// Import de la base FINESS (établissements de santé, ~270k lignes, AVEC téléphone)
// dans prospects_etablissements. Le fichier officiel data.gouv (~90 Mo) est lu par
// tranches HTTP Range ; la fonction s'auto-relance jusqu'à la fin du fichier.
// Déclenchement : POST { offset?: number } + Authorization Bearer service_role/vault.

import { createClient } from "npm:@supabase/supabase-js@2";

const FICHIER = "https://www.data.gouv.fr/fr/datasets/r/2ce43ade-8d2c-4d1d-81da-ca06c82abc68";
const TRANCHE = 4 * 1024 * 1024;       // 4 Mo par requête Range
const BUDGET_MS = 150_000;             // ~150 s puis auto-relance

// Auth cron : Bearer = service_role (env) ou secret vault sb_secret_* envoyé par
// pg_cron (cf. CLAUDE.md "Auth crons pg_cron"). Plus de secret en dur dans le repo.
let _vaultSecret: string | null = null;
async function bearerAutorise(req: Request): Promise<boolean> {
  const bearer = (req.headers.get("Authorization") || "").replace(/^Bearer\s+/i, "").trim();
  if (!bearer) return false;
  const svc = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || "";
  if (svc && bearer === svc) return true;
  if (_vaultSecret) return bearer === _vaultSecret;
  try {
    const admin = createClient(Deno.env.get("SUPABASE_URL")!, svc, { auth: { persistSession: false } });
    const { data } = await admin.rpc("fn_lire_secret_cron");
    if (data && typeof data === "string") { _vaultSecret = data; return bearer === data; }
  } catch { /* ignore */ }
  return false;
}

// libcategetab / libcategagretab → type Jolene (null = ignoré)
function mapType(libCateg: string, libAgr: string): string | null {
  // On teste les DEUX libellés (catégorie fine + agrégat) — les libellés FINESS
  // n'utilisent pas l'acronyme EHPAD mais « personnes âgées ».
  const s = `${libCateg || ""} ${libAgr || ""}`.toLowerCase();
  if (s.includes("ehpad") || s.includes("personnes âgées") || s.includes("personnes agées") || s.includes("personnes agees")) return "EHPAD";
  if (s.includes("hospitalier") || s.includes("hôpital") || s.includes("hopital") || s.includes("soins de suite") || s.includes("réadaptation")) return "HOPITAL";
  if (s.includes("officine")) return "PHARMACIE";
  if (s.includes("laboratoire")) return "LABO";
  if (s.includes("domicile") || s.includes("ssiad")) return "DOMICILE";
  if (s.includes("handicap") || s.includes("enfance inadaptée") || s.includes("enfance inadaptee")) return "HANDICAP";
  if (s.includes("dialyse")) return "DIALYSE";
  if (s.includes("centre de santé") || s.includes("centre de sante") || s.includes("maison de santé") || s.includes("maison de sante")) return "CENTRE_SANTE";
  return null;
}

Deno.serve(async (req) => {
  try {
    if (!(await bearerAutorise(req))) return new Response(JSON.stringify({ error: "forbidden" }), { status: 403 });
    const { offset = 0 } = await req.json().catch(() => ({}));

    const url = Deno.env.get("SUPABASE_URL")!;
    const admin = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } });

    const debut = Date.now();
    let pos = Number(offset) || 0;
    let totalInsere = 0;
    let done = false;

    while (Date.now() - debut < BUDGET_MS) {
      const r = await fetch(FICHIER, { headers: { Range: `bytes=${pos}-${pos + TRANCHE - 1}` } });
      if (r.status === 416) { done = true; break; }            // au-delà de la fin
      if (!r.ok && r.status !== 206 && r.status !== 200) {
        return new Response(JSON.stringify({ error: `fetch ${r.status}`, offset: pos }), { status: 502 });
      }
      const buf = new Uint8Array(await r.arrayBuffer());
      // Le fichier FINESS est encodé en UTF-8 (vérifié sur les libellés accentués)
      const texte = new TextDecoder("utf-8").decode(buf);
      const finFichier = r.status === 200 || buf.byteLength < TRANCHE;

      // On ne traite que les lignes complètes ; la dernière (partielle) est reportée
      const dernierNL = texte.lastIndexOf("\n");
      if (dernierNL < 0) { pos += buf.byteLength; if (finFichier) done = true; continue; }
      const bloc = texte.slice(0, dernierNL);
      // Avancer du nombre d'OCTETS réellement consommés (UTF-8 multi-octets)
      pos += new TextEncoder().encode(texte.slice(0, dernierNL + 1)).length;

      const lignes = bloc.split("\n");
      const rows: Record<string, unknown>[] = [];
      for (const ligne of lignes) {
        if (!ligne.startsWith("structureet;")) continue;
        const f = ligne.split(";");
        if (f.length < 23) continue;
        const type = mapType(f[19], f[21]);
        if (!type) continue;
        const finess = (f[1] || "").trim();
        if (!/^\d{2}/.test(finess)) continue;   // saute l'en-tête / lignes invalides
        const achemine = (f[15] || "").trim();          // "75014 PARIS"
        const cp = achemine.slice(0, 5);
        const ville = achemine.slice(6).trim();
        const adresse = [f[7], f[8], f[9]].map(s => (s || "").trim()).filter(Boolean).join(" ");
        rows.push({
          finess,
          siret: (f[22] || "").trim() || null,
          nom: ((f[4] || f[3]) || "").trim() || "—",
          type_jolene: type,
          categorie_lib: (f[19] || "").trim() || null,
          telephone: (f[16] || "").trim() || null,
          adresse: adresse || null,
          code_postal: /^\d{5}$/.test(cp) ? cp : null,
          ville: ville || null,
          departement: (f[13] || "").trim().toUpperCase() || null,
        });
      }

      for (let i = 0; i < rows.length; i += 500) {
        const { error } = await admin.from("prospects_etablissements")
          .upsert(rows.slice(i, i + 500), { onConflict: "finess" });
        if (error) return new Response(JSON.stringify({ error: error.message, offset: pos }), { status: 500 });
        totalInsere += Math.min(500, rows.length - i);
      }

      if (finFichier) { done = true; break; }
    }

    if (!done) {
      // Auto-relance pour la suite du fichier — waitUntil garantit que la
      // requête part même après le retour de la réponse.
      const relance = fetch(`${url}/functions/v1/import-finess`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Authorization": `Bearer ${Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")}`,
        },
        body: JSON.stringify({ offset: pos }),
      }).catch(() => {});
      (globalThis as any).EdgeRuntime?.waitUntil?.(relance);
    }

    return new Response(JSON.stringify({ done, next_offset: pos, inseres_cette_passe: totalInsere }), {
      headers: { "Content-Type": "application/json" },
    });
  } catch (e) {
    return new Response(JSON.stringify({ error: (e as Error)?.message || "erreur" }), { status: 500 });
  }
});
