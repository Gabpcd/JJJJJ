// Import de la base FINESS (établissements de santé, ~270k lignes, AVEC téléphone)
// dans prospects_etablissements. Le fichier officiel data.gouv (~90 Mo) est lu par
// tranches HTTP Range ; la fonction s'auto-relance jusqu'à la fin du fichier.
// Déclenchement : POST { secret: IMPORT_SECRET, offset?: number }.

import { createClient } from "npm:@supabase/supabase-js@2";

const FICHIER = "https://www.data.gouv.fr/fr/datasets/r/2ce43ade-8d2c-4d1d-81da-ca06c82abc68";
const TRANCHE = 4 * 1024 * 1024;       // 4 Mo par requête Range
const BUDGET_MS = 150_000;             // ~150 s puis auto-relance
const SECRET = "jolene-import-finess-2026";

// libcategetab / libcategagretab → type Jolene (null = ignoré)
function mapType(libCateg: string, libAgr: string): string | null {
  const c = (libCateg || "").toLowerCase();
  const a = (libAgr || "").toLowerCase();
  if (c.includes("ehpad") || a.includes("personnes agées") || a.includes("personnes âgées")) return "EHPAD";
  if (a.includes("hospitalier") || c.includes("centre hospitalier") || c.includes("hôpital") || c.includes("hopital")) return "HOPITAL";
  if (c.includes("officine")) return "PHARMACIE";
  if (c.includes("laboratoire")) return "LABO";
  if (c.includes("domicile") || c.includes("ssiad")) return "DOMICILE";
  if (a.includes("handicap") || c.includes("handicap") || a.includes("enfance inadaptée")) return "HANDICAP";
  if (c.includes("dialyse")) return "DIALYSE";
  if (c.includes("centre de santé") || c.includes("centre de sante") || c.includes("maison de santé")) return "CENTRE_SANTE";
  return null;
}

Deno.serve(async (req) => {
  try {
    const { secret, offset = 0 } = await req.json().catch(() => ({}));
    if (secret !== SECRET) return new Response(JSON.stringify({ error: "forbidden" }), { status: 403 });

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
      // Le fichier FINESS est encodé en ISO-8859-1 (accents)
      const texte = new TextDecoder("iso-8859-1").decode(buf);
      const finFichier = r.status === 200 || buf.byteLength < TRANCHE;

      // On ne traite que les lignes complètes ; la dernière (partielle) est reportée
      const dernierNL = texte.lastIndexOf("\n");
      if (dernierNL < 0) { pos += buf.byteLength; if (finFichier) done = true; continue; }
      const bloc = texte.slice(0, dernierNL);
      // Avancer du nombre d'OCTETS consommés (ISO-8859-1 : 1 char = 1 octet)
      pos += dernierNL + 1;

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
        body: JSON.stringify({ secret: SECRET, offset: pos }),
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
