import { createClient } from 'npm:@supabase/supabase-js@2.99.2';
import { applyRateLimit, getClientIp } from '../_shared/rate-limit.ts';
import { corsHeaders, jsonResponse, preflightResponse } from '../_shared/cors.ts';

async function fingerprint(value: string): Promise<string> {
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(value));
  return [...new Uint8Array(digest)].slice(0, 16)
    .map((octet) => octet.toString(16).padStart(2, '0')).join('');
}

const NAF_SANTE = new Set([
  '86.10Z','86.21Z','86.22A','86.22B','86.22C','86.23Z',
  '86.90A','86.90B','86.90C','86.90D','86.90E','86.90F',
  '87.10A','87.10B','87.10C','87.20A','87.20B',
  '87.30A','87.30B','87.90A','87.90B',
  '88.10A','88.10B','88.10C',
  '47.73Z',
]);

const PREFIXES_PUBLIC = ['7', '4'];

function estSecteurPublic(categorieJuridique: string): boolean {
  if (!categorieJuridique) return false;
  return PREFIXES_PUBLIC.some(p => categorieJuridique.startsWith(p));
}

function estNafSante(codeNaf: string): boolean {
  if (!codeNaf) return false;
  const normalized = codeNaf.length === 5 ? `${codeNaf.slice(0, 2)}.${codeNaf.slice(2)}` : codeNaf;
  return NAF_SANTE.has(normalized);
}

interface VerificationResult {
  statut: 'VERIFIE' | 'ALERTE' | 'INTROUVABLE';
  raison_sociale: string | null;
  est_actif: boolean;
  est_sante: boolean;
  est_public: boolean;
  code_naf: string | null;
  libelle_naf: string | null;
  categorie_juridique: string | null;
  message: string;
  // Dirigeants INSEE (match auto identité↔titulaire, Phase 3).
  dirigeants?: unknown[] | null;
}

function findMatchingEtablissement(results: any[], siret: string): { matching: any; matchingEtab: any } {
  for (const r of results) {
    if (r.matching_etablissements) {
      for (const e of r.matching_etablissements) {
        if (e.siret === siret) return { matching: r, matchingEtab: e };
      }
    }
    if (r.siege?.siret === siret) return { matching: r, matchingEtab: r.siege };
  }
  return { matching: null, matchingEtab: null };
}

function buildResult(matching: any, matchingEtab: any): VerificationResult {
  if (!matching) {
    return {
      statut: 'INTROUVABLE', raison_sociale: null, est_actif: false,
      est_sante: false, est_public: false, code_naf: null,
      libelle_naf: null, categorie_juridique: null,
      message: 'SIRET introuvable dans le registre INSEE',
    };
  }

  const raisonSociale = matching.nom_raison_sociale || matching.nom_complet || null;
  const codeNaf = matchingEtab?.activite_principale || matching.activite_principale || null;
  const libelleNaf = matchingEtab?.libelle_activite_principale || matching.libelle_activite_principale || null;
  const catJuridique = matching.nature_juridique || null;
  const dirigeants = Array.isArray(matching.dirigeants) ? matching.dirigeants : null;
  const estActif = matchingEtab?.etat_administratif === 'A';
  const sante = estNafSante(codeNaf);
  const secteurPublic = estSecteurPublic(catJuridique);

  if (!estActif) {
    return {
      statut: 'INTROUVABLE', raison_sociale: raisonSociale, est_actif: false,
      est_sante: sante, est_public: secteurPublic, code_naf: codeNaf,
      libelle_naf: libelleNaf, categorie_juridique: catJuridique, dirigeants,
      message: 'Établissement fermé ou radié',
    };
  }

  if (sante) {
    return {
      statut: 'VERIFIE', raison_sociale: raisonSociale, est_actif: true,
      est_sante: true, est_public: secteurPublic, code_naf: codeNaf,
      libelle_naf: libelleNaf, categorie_juridique: catJuridique, dirigeants,
      message: `SIRET vérifié — ${raisonSociale} — Établissement de santé actif`,
    };
  }

  return {
    statut: 'ALERTE', raison_sociale: raisonSociale, est_actif: true,
    est_sante: false, est_public: secteurPublic, code_naf: codeNaf,
    libelle_naf: libelleNaf, categorie_juridique: catJuridique,
    message: `SIRET valide mais activité non-santé (${libelleNaf || codeNaf}) — Vérification manuelle requise`,
  };
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return preflightResponse(req);
  }
  if (req.method !== 'POST') return jsonResponse(req, { error: 'Methode non autorisee' }, 405);

  // Rate-limit IP : 20 vérifs SIRET/min/IP (API INSEE quota partagé).
  const clientIp = getClientIp(req);
  if (applyRateLimit('verify-siret', clientIp, { max: 20, windowMs: 60_000 })) {
    return new Response(JSON.stringify({ ok: false, code: 'RATE_LIMITED', error: 'Trop de vérifications. Réessayez dans 1 minute.' }), {
      status: 429,
      headers: { ...corsHeaders(req), 'Content-Type': 'application/json' },
    });
  }

  try {
    // Lecture publique : la recherche SIRET interroge le registre ouvert
    // recherche-entreprises.api.gouv.fr (données publiques), exactement comme
    // verify-finess. Aucune session n'est requise — la page d'inscription appelle
    // cette fonction AVANT que le compte n'existe (avec la clé anon). On ne gate
    // donc PAS la lecture : seule l'écriture en base (plus bas) exige une
    // autorisation (service-role ou membre PROPRIETAIRE/ADMIN_GROUPE). La fonction
    // est protégée contre l'abus par le rate-limit IP (20/min) défini au-dessus.
    const body = await req.json().catch(() => null) as Record<string, unknown> | null;
    if (!body || Array.isArray(body)) return jsonResponse(req, { error: 'Corps JSON invalide' }, 400);
    const siret = typeof body.siret === 'string' ? body.siret.trim() : '';
    const etablissement_id = typeof body.etablissement_id === 'string' ? body.etablissement_id : null;
    if (!siret || !/^\d{14}$/.test(siret)) {
      return new Response(JSON.stringify({ ok: false, code: 'SIRET_INVALID', error: 'SIRET invalide' }), {
        status: 400,
        headers: { ...corsHeaders(req), 'Content-Type': 'application/json' },
      });
    }

    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || '';
    const supabaseUrl = Deno.env.get('SUPABASE_URL') || '';
    if (!serviceRoleKey || !supabaseUrl) return jsonResponse(req, { error: 'Service indisponible' }, 503);
    const authHeader = req.headers.get('Authorization') || '';
    const tokenVal = authHeader.startsWith('Bearer ') ? authHeader.slice(7) : '';
    if (tokenVal !== serviceRoleKey) {
      const admin = createClient(supabaseUrl, serviceRoleKey, { auth: { persistSession: false } });
      const { data: allowed, error: rateError } = await admin.rpc('fn_verifier_rate_limit', {
        p_cle: await fingerprint(clientIp === 'unknown'
          ? `unknown|${(req.headers.get('user-agent') || '').slice(0, 160)}`
          : clientIp),
        p_action: 'edge_verify_siret',
        p_max_tentatives: 60,
        p_fenetre_secondes: 600,
      });
      if (rateError) return jsonResponse(req, { error: 'Service temporairement indisponible' }, 503);
      if (allowed !== true) return jsonResponse(req, { code: 'RATE_LIMITED', error: 'Quota de verification atteint' }, 429);
    }

    let result: VerificationResult;

    try {
      const rechercheUrl = `https://recherche-entreprises.api.gouv.fr/search?q=${siret}&mtm_campaign=jolene`;
      const response = await fetch(rechercheUrl, {
        headers: { 'Accept': 'application/json' },
        signal: AbortSignal.timeout(8_000),
      });

      if (!response.ok) {
        result = buildResult(null, null);
      } else {
        const data = await response.json();
        const { matching, matchingEtab } = findMatchingEtablissement(data.results || [], siret);
        result = buildResult(matching, matchingEtab);
      }
    } catch (fetchErr) {
      console.error('API recherche-entreprises error:', fetchErr);
      result = {
        statut: 'ALERTE', raison_sociale: null, est_actif: false,
        est_sante: false, est_public: false, code_naf: null,
        libelle_naf: null, categorie_juridique: null,
        message: 'Service de vérification temporairement indisponible — Vérification manuelle requise',
      };
    }

    // Écriture en base : UNIQUEMENT si SIRET vérifié + etablissement_id fourni
    // + appelant autorisé. Autorisé = service-role (inscription server-side, crons)
    // OU membre PROPRIETAIRE/ADMIN_GROUPE de cet établissement (UI de vérification).
    // À l'inscription publique il n'y a PAS d'etablissement_id → on ne fait que lire,
    // donc la vérification anti-usurpation côté serveur reste intacte.
    if (result.statut === 'VERIFIE' && etablissement_id) {
      let autorise = false;
      if (tokenVal && serviceRoleKey && tokenVal === serviceRoleKey) {
        autorise = true; // service-role
      } else if (tokenVal) {
        try {
          const userClient = createClient(supabaseUrl, Deno.env.get('SUPABASE_ANON_KEY')!, {
            global: { headers: { Authorization: authHeader } },
          });
          const { data: { user } } = await userClient.auth.getUser();
          if (user) {
            const adminCheck = createClient(supabaseUrl, serviceRoleKey);
            const { data: membre } = await adminCheck.from('membres_etablissement')
              .select('role').eq('etablissement_id', etablissement_id).eq('user_id', user.id)
              .eq('actif', true).maybeSingle();
            autorise = (!!membre && ['PROPRIETAIRE', 'ADMIN_GROUPE'].includes((membre as Record<string, string>).role))
              || user.id === etablissement_id;
          }
        } catch { /* non autorisé → on se contente de renvoyer la lecture */ }
      }

      if (autorise) {
        try {
          const supabaseAdmin = createClient(
            supabaseUrl,
            serviceRoleKey,
            { auth: { persistSession: false } }
          );
          await supabaseAdmin.from('etablissements').update({
            siret_verifie: true,
            siret_verifie_le: new Date().toISOString(),
            siret_est_actif: result.est_actif,
            siret_code_naf: result.code_naf,
            siret_raison_sociale: result.raison_sociale,
            siret_categorie_juridique: result.categorie_juridique,
            dirigeants: result.dirigeants ?? null,
            est_secteur_public: result.est_public,
            statut_verification: 'VERIFIE',
          }).eq('id', etablissement_id).eq('siret', siret);
          console.log(`SIRET vérifié → etablissement ${etablissement_id} mis à jour`);
        } catch (updateErr) {
          console.error('Erreur update etablissement après vérification SIRET:', updateErr);
        }
      }
    }

    return new Response(JSON.stringify({ ok: true, ...result }), {
      status: 200,
      headers: { ...corsHeaders(req), 'Content-Type': 'application/json' },
    });
  } catch (err) {
    console.error('verify-siret error:', err);
    return new Response(JSON.stringify({ ok: false, code: 'INTERNAL_ERROR', error: 'Erreur interne' }), {
      status: 500,
      headers: { ...corsHeaders(req), 'Content-Type': 'application/json' },
    });
  }
});
