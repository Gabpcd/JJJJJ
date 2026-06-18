import { createClient } from 'npm:@supabase/supabase-js@2';
import { verifyTurnstileToken } from '../_shared/verify-turnstile.ts';
import { errorResponse, safeStringifyError } from '../_shared/errors.ts';
import { colonnesAttribution } from '../_shared/attribution.ts';

function getCorsOrigin(req: Request): string {
  const origin = req.headers.get("origin") || "";
  if (
    origin === "https://jolene.app" ||
    origin === "https://app.jolene.app" ||
    origin === "https://www.jolene.app" ||
    origin === "http://localhost:5173" ||
    origin === "http://localhost:8080"
  ) {
    return origin;
  }
  return "https://jolene.app";
}

function corsHeaders(req: Request) {
  return {
    'Access-Control-Allow-Origin': getCorsOrigin(req),
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, x-supabase-client-platform, x-supabase-client-platform-version, x-supabase-client-runtime, x-supabase-client-runtime-version',
  };
}

// M7: Rate limiting - 5 requests per IP per 10 minutes
const rateLimitMap = new Map<string, { count: number; resetAt: number }>();
const RATE_LIMIT = 5;
const RATE_WINDOW_MS = 10 * 60 * 1000;

function checkRateLimit(ip: string): boolean {
  const now = Date.now();
  const entry = rateLimitMap.get(ip);
  if (!entry || now > entry.resetAt) {
    rateLimitMap.set(ip, { count: 1, resetAt: now + RATE_WINDOW_MS });
    return true;
  }
  if (entry.count >= RATE_LIMIT) return false;
  entry.count++;
  return true;
}

// Vérification FINESS via FHIR Annuaire Santé (même source que verify-finess) —
// inline ici pour pouvoir croiser raison sociale FINESS ↔ SIRET ↔ nom AVANT l'insert.
const FINESS_GATEWAY = 'https://gateway.api.esante.gouv.fr/fhir/v2/Organization';
const FINESS_SYSTEM = 'https://finess.esante.gouv.fr';
async function queryFinessInscription(finess: string, apiKey: string): Promise<{ trouve: boolean; raison_sociale?: string | null; actif?: boolean; categorie?: string | null; secteur?: string | null; est_public?: boolean } | null> {
  try {
    const identifier = `${FINESS_SYSTEM}|${finess}`;
    const url = `${FINESS_GATEWAY}?identifier=${encodeURIComponent(identifier)}`;
    const controller = new AbortController();
    const t = setTimeout(() => controller.abort(), 9000);
    const r = await fetch(url, { headers: { 'Accept': 'application/fhir+json', 'ESANTE-API-KEY': apiKey }, signal: controller.signal });
    clearTimeout(t);
    if (!r.ok) return null;
    const bundle = await r.json();
    if (!bundle.entry || bundle.entry.length === 0) return { trouve: false };
    const org = bundle.entry[0].resource;
    let categorie: string | null = null, secteur: string | null = null;
    for (const ty of org.type || []) {
      for (const c of ty.coding || []) {
        const sys = String(c.system || '');
        if (sys.includes('TRE_R66-CategorieEtablissement') && !categorie) categorie = c.display;
        if (sys.includes('TRE_R02-SecteurActivite') && !secteur) secteur = c.display;
      }
    }
    return { trouve: true, raison_sociale: org.name || null, actif: org.active !== false, categorie, secteur, est_public: /public/i.test(secteur || '') };
  } catch { return null; }
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
  if (req.method === 'OPTIONS') {
    return new Response(null, { headers: corsHeaders(req) });
  }

  const cors = corsHeaders(req);

  // M7: Rate limiting
  const clientIp = req.headers.get('x-forwarded-for')?.split(',')[0]?.trim() || 'unknown';
  if (!checkRateLimit(clientIp)) {
    return errorResponse(cors, 429, 'RATE_LIMITED', 'Trop de tentatives. Réessayez dans quelques minutes.');
  }

  const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY')!;
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;

  // 1. Authenticate caller via JWT
  const authHeader = req.headers.get('Authorization');
  if (!authHeader) {
    return errorResponse(cors, 401, 'UNAUTHORIZED', 'Non authentifié.');
  }

  const token = authHeader.replace('Bearer ', '');
  const supabaseAuth = createClient(supabaseUrl, anonKey);
  const { data: { user }, error: authError } = await supabaseAuth.auth.getUser(token);
  if (authError || !user) {
    return errorResponse(cors, 401, 'INVALID_TOKEN', 'Session invalide. Reconnectez-vous et réessayez.');
  }

  try {
    const body = await req.json();
    const { nom, siret, finess, type, adresse_rue, adresse_ville, adresse_code_postal,
      adresse_departement, telephone_contact, email_contact, adresse_lat, adresse_lng,
      numero_licence, turnstileToken } = body;

    // Captcha anti-bot Cloudflare Turnstile (no-op tant que TURNSTILE_SECRET_KEY non configurée)
    const captcha = await verifyTurnstileToken(turnstileToken, clientIp);
    if (!captcha.success) {
      return errorResponse(cors, 403, 'CAPTCHA_FAILED', captcha.error || 'Vérification anti-bot échouée. Rafraîchissez la page.');
    }

    // Validate required fields
    if (!nom || !siret || !type || !adresse_ville) {
      return errorResponse(cors, 400, 'MISSING_REQUIRED_FIELDS', 'Champs obligatoires manquants.', { champs_manquants: [!nom && 'nom', !siret && 'siret', !type && 'type', !adresse_ville && 'adresse_ville'].filter(Boolean) });
    }

    // Luhn validation
    if (!/^\d{14}$/.test(siret) || /^0+$/.test(siret)) {
      return errorResponse(cors, 400, 'SIRET_FORMAT_INVALID', 'Le SIRET doit contenir 14 chiffres.');
    }
    {
      let sum = 0;
      for (let i = 0; i < 14; i++) {
        let d = parseInt(siret[i], 10);
        if (i % 2 === 0) { d *= 2; if (d > 9) d -= 9; }
        sum += d;
      }
      if (sum % 10 !== 0) {
        return errorResponse(cors, 400, 'SIRET_CHECKSUM_INVALID', 'SIRET invalide (checksum incorrecte).');
      }
    }

    const supabaseAdmin = createClient(supabaseUrl, serviceRoleKey, { auth: { persistSession: false } });

    // 2a. Verify SIRET against INSEE registry
    let siretVerification: any = null;
    try {
      const rechercheUrl = `https://recherche-entreprises.api.gouv.fr/search?q=${siret}&mtm_campaign=jolene`;
      const verifyResp = await fetch(rechercheUrl, { headers: { 'Accept': 'application/json' } });
      if (verifyResp.ok) {
        const verifyData = await verifyResp.json();
        const results = verifyData.results || [];
        let matching: any = null;
        let matchingEtab: any = null;
        for (const r of results) {
          if (r.matching_etablissements) {
            for (const e of r.matching_etablissements) {
              if (e.siret === siret) { matching = r; matchingEtab = e; break; }
            }
          }
          if (matching) break;
          if (r.siege?.siret === siret) { matching = r; matchingEtab = r.siege; break; }
        }
        if (matching) {
          const NAF_SANTE = ['86.10Z','86.21Z','86.22A','86.22B','86.22C','86.23Z','86.90A','86.90B','86.90C','86.90D','86.90E','86.90F','87.10A','87.10B','87.10C','87.20A','87.20B','87.30A','87.30B','87.90A','87.90B','88.10A','88.10B','88.10C','47.73Z'];
          const codeNaf = matchingEtab?.activite_principale || matching.activite_principale || '';
          const nafNorm = codeNaf.length === 5 ? `${codeNaf.slice(0,2)}.${codeNaf.slice(2)}` : codeNaf;
          const estActif = matchingEtab?.etat_administratif === 'A';
          const estSante = NAF_SANTE.includes(nafNorm);
          const catJuridique = matching.nature_juridique || '';
          const estPublic = catJuridique.startsWith('7') || catJuridique.startsWith('4');

          siretVerification = {
            raison_sociale: matching.nom_raison_sociale || matching.nom_complet || null,
            est_actif: estActif,
            est_sante: estSante,
            est_public: estPublic,
            code_naf: codeNaf,
            categorie_juridique: catJuridique,
            // Dirigeants (personnes physiques/morales) renvoyés par l'API INSEE —
            // sert au match auto identité↔titulaire pour les petites structures (Phase 3).
            dirigeants: Array.isArray((matching as any).dirigeants) ? (matching as any).dirigeants : null,
          };
        }
      }
    } catch (verifyErr) {
      console.warn('SIRET verification failed (non-blocking):', verifyErr);
    }

    // Cohérence nom déclaré ↔ raison sociale SIRET (anti-usurpation : on refuse
    // qu'un SIRET sans rapport avec l'établissement passe en auto-vérifié).
    const normNom = (s: string | null | undefined) => (s || '')
      .toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '')
      .replace(/\b(sas|sasu|sarl|sa|eurl|sci|scp|selarl|selas|snc|gie|association|asso|groupe|clinique|centre|hopital|ehpad|cabinet|pharmacie|ste|societe)\b/g, '')
      .replace(/[^a-z0-9]+/g, ' ').trim();
    const compareNoms = (a: string | null | undefined, b: string | null | undefined): 'OK' | 'PARTIEL' | 'INCOHERENT' | null => {
      const na = normNom(a), nb = normNom(b);
      if (!na || !nb) return null;
      if (na === nb) return 'OK';
      if (na.includes(nb) || nb.includes(na)) return 'PARTIEL';
      const sa = new Set(na.split(' ').filter((w) => w.length >= 3));
      const sb = new Set(nb.split(' ').filter((w) => w.length >= 3));
      if ([...sa].some((w) => sb.has(w))) return 'PARTIEL';
      return 'INCOHERENT';
    };
    // Vérification FINESS (si fourni) via l'Annuaire Santé + croisement
    // nom ↔ raison sociale SIRET ↔ raison sociale FINESS.
    let finessResult: Awaited<ReturnType<typeof queryFinessInscription>> = null;
    const finessApiKey = Deno.env.get('ESANTE_FHIR_API_KEY') || '';
    if (finess && /^\d{9}$/.test(finess) && finessApiKey) {
      finessResult = await queryFinessInscription(finess, finessApiKey);
    }
    const finessRs = finessResult?.trouve ? (finessResult.raison_sociale ?? null) : null;
    const finessVerifie = !!(finessResult?.trouve && finessResult.actif);

    const cohParts = [
      compareNoms(nom, siretVerification?.raison_sociale),
      finessRs ? compareNoms(nom, finessRs) : null,
      (siretVerification?.raison_sociale && finessRs) ? compareNoms(siretVerification.raison_sociale, finessRs) : null,
    ].filter((v): v is 'OK' | 'PARTIEL' | 'INCOHERENT' => v !== null);
    const coherenceIdentite: 'OK' | 'PARTIEL' | 'INCOHERENT' | null =
      cohParts.includes('INCOHERENT') ? 'INCOHERENT'
      : cohParts.includes('PARTIEL') ? 'PARTIEL'
      : cohParts.length > 0 ? 'OK' : null;

    // Auto-vérifié uniquement si SIRET actif + secteur santé + identités cohérentes
    // (nom ↔ SIRET ↔ FINESS). Toute incohérence → EN_ATTENTE + revue admin.
    const autoVerifie = siretVerification?.est_actif && siretVerification?.est_sante
      && coherenceIdentite !== 'INCOHERENT';
    const statutVerification = autoVerifie ? 'VERIFIE' : 'EN_ATTENTE';

    // 2. Insert into etablissements table
    const insertPayload = {
      id: user.id,
      nom,
      siret,
      finess: finess || null,
      finess_verifie: finessVerifie || false,
      finess_verifie_le: finessVerifie ? new Date().toISOString() : null,
      finess_raison_sociale: finessRs,
      finess_categorie: finessResult?.categorie ?? null,
      finess_secteur: finessResult?.secteur ?? null,
      finess_est_public: finessResult?.est_public ?? null,
      type,
      adresse_rue: adresse_rue || 'Non renseigné',
      adresse_ville,
      adresse_code_postal: adresse_code_postal || '00000',
      adresse_departement: adresse_departement || null,
      email_contact: email_contact || user.email,
      telephone_contact: telephone_contact || null,
      adresse_lat: adresse_lat || null,
      adresse_lng: adresse_lng || null,
      siret_verifie: autoVerifie || false,
      siret_verifie_le: autoVerifie ? new Date().toISOString() : null,
      siret_est_actif: siretVerification?.est_actif ?? null,
      siret_code_naf: siretVerification?.code_naf ?? null,
      siret_raison_sociale: siretVerification?.raison_sociale ?? null,
      siret_categorie_juridique: siretVerification?.categorie_juridique ?? null,
      dirigeants: siretVerification?.dirigeants ?? null,
      est_secteur_public: siretVerification?.est_public ?? false,
      coherence_identite: coherenceIdentite,
      statut_verification: statutVerification,
      peut_publier_missions: autoVerifie || false,
      ...colonnesAttribution(body.attribution, req),
    };

    const { error: insertError } = await supabaseAdmin
      .from('etablissements')
      .insert(insertPayload);

    if (insertError) {
      console.error('INSERT etablissements échoué', insertError.code || safeStringifyError(insertError));
      const msg = insertError.message || '';
      if (msg.includes('duplicate key') && msg.includes('siret')) {
        return errorResponse(cors, 409, 'SIRET_ALREADY_REGISTERED', 'Ce numéro SIRET est déjà enregistré.');
      }
      // Compensation : nettoyer le user Auth pour qu'un retry ne se heurte pas
      // à "User already registered".
      try {
        await supabaseAdmin.auth.admin.deleteUser(user.id);
      } catch (cleanupErr) {
        console.error('[register-etablissement] Cleanup Auth user échoué:', safeStringifyError(cleanupErr));
      }
      return errorResponse(cors, 500, 'INTERNAL_ERROR', 'Erreur lors de la création du profil établissement. Réessayez dans quelques minutes.');
    }

    // 3. Set app_metadata role — server-side, no client involvement
    const { error: claimsError } = await supabaseAdmin.auth.admin.updateUserById(user.id, {
      app_metadata: { role: 'ADMIN_ETABLISSEMENT', etablissement_id: user.id },
    });

    if (claimsError) {
      console.error('set-user-claims échoué', claimsError.code || safeStringifyError(claimsError));
      await supabaseAdmin.from('etablissements').delete().eq('id', user.id);
      try {
        await supabaseAdmin.auth.admin.deleteUser(user.id);
      } catch (cleanupErr) {
        console.error('[register-etablissement] Cleanup Auth user échoué (claims):', safeStringifyError(cleanupErr));
      }
      return errorResponse(cors, 500, 'INTERNAL_ERROR', 'Erreur lors de la configuration du compte. Réessayez dans quelques minutes.');
    }

    // 4. Audit inscription + CGU + L1: CGV consent
    await supabaseAdmin.from('journaux_audit').insert({
      acteur_id: user.id,
      type_acteur: 'ADMIN_ETABLISSEMENT',
      action: 'INSCRIPTION',
      type_ressource: 'etablissement',
      id_ressource: user.id,
      details: { evenement: 'inscription', type },
      navigateur_acteur: body.navigateur || null,
    });

    await supabaseAdmin.from('journaux_audit').insert({
      acteur_id: user.id,
      type_acteur: 'ADMIN_ETABLISSEMENT',
      action: 'RGPD_CONSENTEMENT_DONNE',
      type_ressource: 'etablissement',
      id_ressource: user.id,
      details: { type: 'inscription', cgu: true, confidentialite: true, cgv: true },
      navigateur_acteur: body.navigateur || null,
    });

    // 5. Email bienvenue (best-effort — ne bloque pas l'inscription)
    try {
      await supabaseAdmin.functions.invoke('send-email', {
        body: {
          type: 'BIENVENUE_ETABLISSEMENT',
          destinataire_id: user.id,
          data: {
            nom_etablissement: String(nom).slice(0, 200),
            type_etablissement: type,
            lien_dashboard: 'https://jolene.app/etablissement',
          },
        },
      });
    } catch (emailErr) {
      console.warn('[register-etablissement] Email bienvenue non envoyé (best-effort):', emailErr);
    }

    // 6. Planifier la série onboarding J0/J1/J3/J7 (best-effort)
    try {
      await supabaseAdmin.rpc('fn_planifier_serie_onboarding', {
        p_utilisateur_id: user.id,
        p_serie: 'ETAB_ONBOARDING',
      });
    } catch (serieErr) {
      console.warn('[register-etablissement] Planification série onboarding échouée (best-effort):', serieErr);
    }

    return new Response(JSON.stringify({ ok: true, success: true, etablissement_id: user.id, auto_verifie: autoVerifie, statut_verification: statutVerification, coherence_identite: coherenceIdentite, siret_raison_sociale: siretVerification?.raison_sociale ?? null }), {
      status: 200,
      headers: { ...cors, 'Content-Type': 'application/json' },
    });
  } catch (err) {
    console.error('register-etablissement error:', safeStringifyError(err));
    return errorResponse(cors, 500, 'INTERNAL_ERROR', 'Erreur serveur. Notre équipe a été notifiée. Réessayez dans quelques minutes.');
  }
});
