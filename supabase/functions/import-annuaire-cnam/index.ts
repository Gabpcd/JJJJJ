// Import Annuaire Santé CNAM (ps-infospratiques.csv, ~183 Mo) → prospects_soignants.
// Professionnels LIBÉRAUX conventionnés avec téléphone de cabinet. Layout (sans
// en-tête, séparateur ;) : 0=civilité 1=nom 2=prénom 3=enseigne 4=complément
// 5=voie 6=lieu-dit 7=CP 8=ville 9=téléphone 10=code profession.
// Nomenclature dérivée empiriquement via mode sample : 18/19=DENTISTE, 39=IDE,
// 43=KINE, 45=MEDECIN, 57=ORTHOPHONISTE, 61=PEDICURE_PODOLOGUE, 62=PHARMACIEN,
// 71=SAGE_FEMME. Le fichier duplique 1 ligne par plage horaire → dédup par clé.
// Modes : {mode:'sample', offset?} | {offset?, code_map} = import auto-relancé.
// Auth : Bearer service_role/vault.

import { createClient } from "npm:@supabase/supabase-js@2";

const FICHIER = "https://static.data.gouv.fr/resources/annuaire-sante-de-la-cnam-deprecie/20260201-001039/ps-infospratiques.csv";
const TRANCHE = 4 * 1024 * 1024;
const BUDGET_MS = 150_000;

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

Deno.serve(async (req) => {
  try {
    if (!(await bearerAutorise(req))) return new Response(JSON.stringify({ error: "forbidden" }), { status: 403 });
    const { mode, offset = 0, code_map } = await req.json().catch(() => ({}));

    if (mode === "sample") {
      const pos = Number(offset) || 0;
      const r = await fetch(FICHIER, { headers: { Range: `bytes=${pos}-${pos + 10 * 1024 * 1024 - 1}` } });
      const texte = new TextDecoder("utf-8").decode(new Uint8Array(await r.arrayBuffer()));
      const st: Record<string, { n: number; f: number; ex: string }> = {};
      for (const ligne of texte.split("\n").slice(1, -1)) {
        const f = ligne.split(";");
        if (f.length < 15) continue;
        const code = (f[10] || "").trim();
        if (!code) continue;
        const s = st[code] ??= { n: 0, f: 0, ex: "" };
        s.n++;
        if ((f[0] || "").trim() === "F") s.f++;
        const ens = ((f[3] || "") + " " + (f[4] || "")).trim();
        if (!s.ex && ens.length > 3) s.ex = ens.slice(0, 35);
      }
      return new Response(JSON.stringify(st));
    }

    const mapEff: Record<string, string> = (code_map && typeof code_map === "object") ? code_map : {};
    if (Object.keys(mapEff).length === 0) return new Response(JSON.stringify({ error: "code_map requis" }), { status: 400 });
    const url = Deno.env.get("SUPABASE_URL")!;
    const admin = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } });
    const debut = Date.now();
    let pos = Number(offset) || 0;
    let totalInsere = 0;
    let done = false;

    while (Date.now() - debut < BUDGET_MS) {
      const r = await fetch(FICHIER, { headers: { Range: `bytes=${pos}-${pos + TRANCHE - 1}` } });
      if (r.status === 416) { done = true; break; }
      if (!r.ok && r.status !== 206 && r.status !== 200) {
        return new Response(JSON.stringify({ error: `fetch ${r.status}`, offset: pos }), { status: 502 });
      }
      const buf = new Uint8Array(await r.arrayBuffer());
      const texte = new TextDecoder("utf-8").decode(buf);
      const finFichier = r.status === 200 || buf.byteLength < TRANCHE;

      const dernierNL = texte.lastIndexOf("\n");
      if (dernierNL < 0) { pos += buf.byteLength; if (finFichier) done = true; continue; }
      const bloc = texte.slice(0, dernierNL);
      pos += new TextEncoder().encode(texte.slice(0, dernierNL + 1)).length;

      const vus = new Set<string>();
      const rows: Record<string, unknown>[] = [];
      for (const ligne of bloc.split("\n")) {
        const f = ligne.split(";");
        if (f.length < 15) continue;
        const profession = mapEff[(f[10] || "").trim()];
        if (!profession) continue;
        const nom = (f[1] || "").trim();
        const prenom = (f[2] || "").trim();
        const cp = (f[7] || "").trim();
        if (!nom || !/^\d{5}$/.test(cp)) continue;
        const cle = (nom + "|" + prenom + "|" + cp + "|" + profession).toLowerCase().slice(0, 220);
        if (vus.has(cle)) continue;
        vus.add(cle);
        const tel = (f[9] || "").replace(/\D/g, "");
        rows.push({
          cle, nom, prenom, profession,
          enseigne: ((f[3] || "").trim() || (f[4] || "").trim()) || null,
          telephone: tel.length >= 9 ? tel : null,
          adresse: [f[4], f[5], f[6]].map((s) => (s || "").trim()).filter(Boolean).join(" ") || null,
          code_postal: cp, ville: (f[8] || "").trim() || null,
          departement: cp.slice(0, 2),
        });
      }

      for (let i = 0; i < rows.length; i += 500) {
        const { error } = await admin.from("prospects_soignants")
          .upsert(rows.slice(i, i + 500), { onConflict: "cle", ignoreDuplicates: true });
        if (error) return new Response(JSON.stringify({ error: error.message, offset: pos }), { status: 500 });
        totalInsere += Math.min(500, rows.length - i);
      }

      if (finFichier) { done = true; break; }
    }

    if (!done) {
      const relance = fetch(`${url}/functions/v1/import-annuaire-cnam`, {
        method: "POST",
        headers: { "Content-Type": "application/json", "Authorization": `Bearer ${Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")}` },
        body: JSON.stringify({ offset: pos, code_map: mapEff }),
      }).catch(() => {});
      (globalThis as any).EdgeRuntime?.waitUntil?.(relance);
    }

    return new Response(JSON.stringify({ done, next_offset: pos, inseres_cette_passe: totalInsere }));
  } catch (e) {
    return new Response(JSON.stringify({ error: (e as Error)?.message || "erreur" }), { status: 500 });
  }
});
