// Enrichissement emails + téléphones des prospects depuis l'Annuaire Santé
// (API FHIR ANS, clé ESANTE_FHIR_API_KEY déjà configurée — même API que
// verify-rpps). Étabs : Organization par FINESS (match exact). Soignants :
// Practitioner par nom+prénom — on n'enrichit QUE si le match est non ambigu
// (1 seul résultat), jamais de donnée devinée. email/telephone remplis
// UNIQUEMENT s'ils sont vides (une saisie manuelle n'est jamais écrasée).
// enrichi_le posé dans tous les cas pour avancer par tranches relançables.
// Réservé ADMIN_PLATEFORME.

import { createClient } from "npm:@supabase/supabase-js@2";
import { verifyAdminOrServiceRole } from "../_shared/admin-auth.ts";
import { corsHeaders } from "../_shared/cors.ts";

const FHIR_BASE = "https://gateway.api.esante.gouv.fr/fhir/v2";

interface Telecoms { email: string | null; telephone: string | null }

/** Extrait le premier email et téléphone d'une liste telecom FHIR. */
function extraireTelecom(telecom: any[] | undefined, acc: Telecoms): Telecoms {
  for (const t of telecom ?? []) {
    const v = String(t?.value ?? "").trim();
    if (!v) continue;
    if (!acc.email && t.system === "email" && /^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(v)) acc.email = v.toLowerCase();
    if (!acc.telephone && (t.system === "phone" || t.system === "sms")) acc.telephone = v.replace(/[^\d+]/g, "");
  }
  return acc;
}

async function fhir(path: string, apiKey: string): Promise<any | null> {
  const ctrl = new AbortController();
  const timer = setTimeout(() => ctrl.abort(), 8000);
  try {
    const r = await fetch(`${FHIR_BASE}${path}`, {
      headers: { "Accept": "application/fhir+json", "ESANTE-API-KEY": apiKey },
      signal: ctrl.signal,
    });
    if (!r.ok) return null;
    return await r.json();
  } catch {
    return null;
  } finally {
    clearTimeout(timer);
  }
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders(req) });
  try {
    // Auth standard : JWT admin OU service_role/sb_secret_* (fallback vault
    // géré par le helper — piège pg_cron documenté CLAUDE.md)
    const authResult = await verifyAdminOrServiceRole(req);
    if (!authResult.ok) {
      return new Response(JSON.stringify({ error: authResult.error }), { status: authResult.status, headers: corsHeaders(req) });
    }
    const url = Deno.env.get("SUPABASE_URL")!;
    const admin = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } });

    const apiKey = Deno.env.get("ESANTE_FHIR_API_KEY") || "";
    if (!apiKey) return new Response(JSON.stringify({ error: "ESANTE_FHIR_API_KEY non configurée." }), { status: 500, headers: corsHeaders(req) });

    const { cible, departement, limite } = await req.json().catch(() => ({}));
    if (!["ETABLISSEMENT", "SOIGNANT"].includes(cible)) {
      return new Response(JSON.stringify({ error: "cible invalide (ETABLISSEMENT|SOIGNANT)" }), { status: 400, headers: corsHeaders(req) });
    }
    const table = cible === "ETABLISSEMENT" ? "prospects_etablissements" : "prospects_soignants";
    const pk = cible === "ETABLISSEMENT" ? "finess" : "cle";
    const max = Math.min(Number(limite) || 40, 60);

    // Ordre alphabétique par nom : l'enrichissement suit l'ordre de navigation
    // de l'admin (la liste prospection est triée par nom) → la page 1 se remplit
    // en premier, l'admin voit les emails apparaître là où il regarde.
    let q = admin.from(table).select("*").is("enrichi_le", null).order("nom", { ascending: true }).limit(max);
    if (departement) q = q.eq("departement", String(departement).toUpperCase());
    const { data: prospects, error: qErr } = await q;
    if (qErr) return new Response(JSON.stringify({ error: qErr.message }), { status: 500, headers: corsHeaders(req) });
    if (!prospects?.length) {
      return new Response(JSON.stringify({ success: true, traites: 0, emails: 0, telephones: 0, restants: 0, message: "Tous les prospects ont déjà été passés à l'Annuaire." }), { headers: corsHeaders(req) });
    }

    let traites = 0; let emails = 0; let telephones = 0; let ambigus = 0;
    for (const p of prospects as any[]) {
      const acc: Telecoms = { email: null, telephone: null };

      if (cible === "ETABLISSEMENT") {
        // Match exact par identifiant FINESS — aucune ambiguïté possible
        const bundle = await fhir(`/Organization?identifier=${encodeURIComponent(p.finess)}`, apiKey);
        for (const entry of bundle?.entry ?? []) {
          extraireTelecom(entry?.resource?.telecom, acc);
          for (const c of entry?.resource?.contact ?? []) extraireTelecom(c?.telecom, acc);
          if (acc.email && acc.telephone) break;
        }
      } else {
        // Match par nom + prénom — on n'accepte QUE le match non ambigu
        const nom = String(p.nom ?? "").trim();
        const prenom = String(p.prenom ?? "").trim();
        if (nom && prenom) {
          const bundle = await fhir(`/Practitioner?family=${encodeURIComponent(nom)}&given=${encodeURIComponent(prenom)}`, apiKey);
          const entries = bundle?.entry ?? [];
          if (entries.length === 1) {
            const pract = entries[0].resource;
            extraireTelecom(pract?.telecom, acc);
            if (!acc.email || !acc.telephone) {
              // Les telecom (dont boîtes MSSanté) sont souvent sur PractitionerRole
              const roles = await fhir(`/PractitionerRole?practitioner=${encodeURIComponent(pract.id)}`, apiKey);
              for (const entry of roles?.entry ?? []) {
                extraireTelecom(entry?.resource?.telecom, acc);
                if (acc.email && acc.telephone) break;
              }
            }
          } else if (entries.length > 1) {
            ambigus++;
          }
        }
      }

      const patch: Record<string, unknown> = { enrichi_le: new Date().toISOString() };
      if (acc.email && !p.email) { patch.email = acc.email; emails++; }
      if (acc.telephone && !p.telephone) { patch.telephone = acc.telephone; telephones++; }
      await admin.from(table).update(patch).eq(pk, p[pk]);
      traites++;
      await new Promise((res) => setTimeout(res, 200));
    }

    const { count: restants } = await admin.from(table)
      .select(pk, { count: "exact", head: true }).is("enrichi_le", null);

    return new Response(JSON.stringify({ success: true, traites, emails, telephones, ambigus, restants: restants ?? 0 }), { headers: corsHeaders(req) });
  } catch (e) {
    return new Response(JSON.stringify({ error: (e as Error)?.message || "Erreur interne" }), { status: 500, headers: corsHeaders(req) });
  }
});
