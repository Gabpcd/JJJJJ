/**
 * chorus-pro-deposit — Intégration réelle avec l'API PISTE / Chorus Pro
 *
 * API PISTE (Portail Interministériel de Services Transverses pour l'Économie)
 * Doc : https://developer.aife.economie.gouv.fr
 *
 * Flux :
 * 1. OAuth2 client_credentials → access_token
 * 2. POST /cpro/factures/v1/soumettre/flux → dépôt de facture
 * 3. GET /cpro/factures/v1/consulter/flux/{id} → suivi de statut
 *
 * Env vars requises :
 * - PISTE_CLIENT_ID     : client_id PISTE (obtenu sur developer.aife.economie.gouv.fr)
 * - PISTE_CLIENT_SECRET : client_secret PISTE
 * - PISTE_ENV           : "sandbox" (défaut) ou "prod"
 * - CHORUS_TECH_USER_LOGIN / CHORUS_TECH_USER_PASSWORD : compte technique Chorus Pro (header cpro-account)
 *
 * Fallback legacy : CHORUS_PRO_CLIENT_ID / CHORUS_PRO_CLIENT_SECRET / CHORUS_PRO_SANDBOX supportés pour compat.
 *
 * Si les credentials sont absents → mode simulation (SIM-*), identique à l'ancien comportement.
 */

import { createClient } from 'npm:@supabase/supabase-js@2';

/* ── CORS ── */
function getCorsOrigin(req: Request): string {
  const origin = req.headers.get('origin') || '';
  if (
    origin === 'https://jolene.app' ||
    origin === 'https://www.jolene.app' ||
    origin === 'http://localhost:5173' ||
    origin === 'http://localhost:8080'
  ) return origin;
  return 'https://jolene.app';
}

function corsHeaders(req: Request) {
  return {
    'Access-Control-Allow-Origin': getCorsOrigin(req),
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, x-supabase-client-platform, x-supabase-client-platform-version, x-supabase-client-runtime, x-supabase-client-runtime-version',
  };
}

function jsonResponse(req: Request, body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders(req), 'Content-Type': 'application/json' },
  });
}

/* ── PISTE API helpers ── */

const PISTE_URLS = {
  sandbox: {
    oauth: 'https://sandbox-oauth.piste.gouv.fr/api/oauth/token',
    api: 'https://sandbox-api.piste.gouv.fr/cpro/factures/v1',
  },
  prod: {
    oauth: 'https://oauth.piste.gouv.fr/api/oauth/token',
    api: 'https://api.piste.gouv.fr/cpro/factures/v1',
  },
};

function getPisteConfig() {
  // Naming harmonisé PISTE_* (préféré), fallback CHORUS_PRO_* pour compat legacy
  const clientId = Deno.env.get('PISTE_CLIENT_ID') ?? Deno.env.get('CHORUS_PRO_CLIENT_ID');
  const clientSecret = Deno.env.get('PISTE_CLIENT_SECRET') ?? Deno.env.get('CHORUS_PRO_CLIENT_SECRET');
  const env = Deno.env.get('PISTE_ENV');
  // PISTE_ENV='sandbox' => sandbox. Fallback CHORUS_PRO_SANDBOX legacy.
  const isSandbox = env
    ? env === 'sandbox'
    : (Deno.env.get('CHORUS_PRO_SANDBOX') ?? 'true') === 'true';
  const techLogin = Deno.env.get('CHORUS_TECH_USER_LOGIN');
  const techPassword = Deno.env.get('CHORUS_TECH_USER_PASSWORD');

  if (!clientId || !clientSecret) return null;

  return {
    clientId,
    clientSecret,
    techLogin,
    techPassword,
    urls: isSandbox ? PISTE_URLS.sandbox : PISTE_URLS.prod,
    isSandbox,
  };
}

/** Headers d'appel API Chorus Pro (Bearer OAuth + cpro-account si tech user configuré) */
function buildChorusHeaders(config: NonNullable<ReturnType<typeof getPisteConfig>>, token: string): Record<string, string> {
  const headers: Record<string, string> = {
    Authorization: `Bearer ${token}`,
    'Content-Type': 'application/json',
    Accept: 'application/json',
  };
  if (config.techLogin && config.techPassword) {
    headers['cpro-account'] = btoa(`${config.techLogin}:${config.techPassword}`);
  }
  return headers;
}

/** OAuth2 client_credentials → access_token */
async function getAccessToken(config: NonNullable<ReturnType<typeof getPisteConfig>>): Promise<string> {
  const body = new URLSearchParams({
    grant_type: 'client_credentials',
    client_id: config.clientId,
    client_secret: config.clientSecret,
    scope: 'openid',
  });

  const res = await fetch(config.urls.oauth, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: body.toString(),
  });

  if (!res.ok) {
    const text = await res.text();
    throw new Error(`PISTE OAuth failed (${res.status}): ${text}`);
  }

  const data = await res.json();
  return data.access_token;
}

/** Soumettre un flux de facture à Chorus Pro */
async function deposerFlux(
  config: NonNullable<ReturnType<typeof getPisteConfig>>,
  token: string,
  params: {
    numeroFacture: string;
    montantTtc: number;
    siretFournisseur: string;
    siretDestinataire: string;
    codeServiceDestinataire: string;
    dateFacture: string;
    datePrestation: string;
    ligneDesignation: string;
    montantHt: number;
    tauxTva: number;
    montantTva: number;
  },
) {
  // Construction du payload selon la spec PISTE CPPro factures v1
  // Ref: https://developer.aife.economie.gouv.fr/api-catalog/chorus-pro/operations
  const payload = {
    idUtilisateurCourant: 0, // 0 = technique (service account)
    fichierFlux: null, // pas de fichier joint, on utilise le mode structuré
    syntaxeFlux: 'IN_DP_E2_CII_FACTURX', // Format Factur-X / CII
    modeDepot: 'SAISIE_API', // Saisie via API
    // Données de la facture
    coupledePaiement: {
      cadreDeFacturation: {
        codeCadreFacturation: 'A1_FACTURE_FOURNISSEUR',
        codeServiceExecutant: params.codeServiceDestinataire || null,
      },
      destinataire: {
        idDestinataire: params.siretDestinataire,
        typeIdentifiantDestinataire: 'SIRET',
        codeServiceDestinataire: params.codeServiceDestinataire || null,
      },
      fournisseur: {
        idFournisseur: params.siretFournisseur,
        typeIdentifiantFournisseur: 'SIRET',
      },
    },
    references: {
      numeroFacture: params.numeroFacture,
      dateFacture: params.dateFacture, // format YYYY-MM-DD
    },
    montantTotal: {
      montantHtTotal: params.montantHt,
      montantTVA: params.montantTva,
      montantTTC: params.montantTtc,
    },
    lignesPoste: [
      {
        numeroLigne: 1,
        designation: params.ligneDesignation,
        montantHT: params.montantHt,
        tauxTva: params.tauxTva,
        montantTva: params.montantTva,
      },
    ],
  };

  const res = await fetch(`${config.urls.api}/soumettre/facture`, {
    method: 'POST',
    headers: buildChorusHeaders(config, token),
    body: JSON.stringify(payload),
  });

  const responseText = await res.text();
  let responseData: any;
  try {
    responseData = JSON.parse(responseText);
  } catch {
    responseData = { raw: responseText };
  }

  if (!res.ok) {
    console.error('PISTE deposit error:', res.status, responseText);
    throw new Error(
      `Chorus Pro API erreur ${res.status}: ${responseData?.libelleErreur || responseData?.message || responseText}`,
    );
  }

  return {
    identifiantFactureCPP: responseData.identifiantFactureCPP || null,
    numeroFluxDepot: responseData.numeroFluxDepot || responseData.identifiant || `CPR-${Date.now()}`,
    dateTraitement: responseData.dateTraitement || new Date().toISOString(),
  };
}

/** Consulter le statut d'une facture déjà déposée */
async function consulterStatut(
  config: NonNullable<ReturnType<typeof getPisteConfig>>,
  token: string,
  identifiantFactureCPP: string,
) {
  const res = await fetch(`${config.urls.api}/consulter/facture`, {
    method: 'POST',
    headers: buildChorusHeaders(config, token),
    body: JSON.stringify({
      idUtilisateurCourant: 0,
      identifiantFactureCPP: Number(identifiantFactureCPP),
    }),
  });

  if (!res.ok) {
    const text = await res.text();
    console.error('PISTE status error:', res.status, text);
    throw new Error(`Chorus Pro status erreur ${res.status}`);
  }

  const data = await res.json();
  return {
    statutFacture: data.statutFacture || 'INCONNU',
    dateStatut: data.dateStatut || null,
    motifRefus: data.motifRefus || null,
  };
}

/* ── Main handler ── */

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response(null, { headers: corsHeaders(req) });
  }

  try {
    // Auth
    const authHeader = req.headers.get('Authorization');
    if (!authHeader?.startsWith('Bearer ')) {
      return jsonResponse(req, { error: 'Non autorisé' }, 401);
    }

    const supabaseAdmin = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
      { auth: { persistSession: false } },
    );

    const supabaseUser = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_ANON_KEY')!,
      { global: { headers: { Authorization: authHeader } } },
    );

    const token = authHeader.replace('Bearer ', '');
    const { data: userData, error: authError } = await supabaseUser.auth.getUser(token);
    if (authError || !userData?.user) {
      return jsonResponse(req, { error: 'Token invalide' }, 401);
    }

    const userId = userData.user.id;
    const { facture_id, action } = await req.json();

    if (!facture_id || !action) {
      return jsonResponse(req, { error: 'facture_id et action requis' }, 400);
    }

    // Fetch facture
    const { data: facture, error: factError } = await supabaseAdmin
      .from('factures')
      .select('id, numero_facture, montant_ht, montant_ttc, montant_tva, taux_tva, statut, chorus_pro_statut, chorus_pro_id, est_secteur_public, etablissement_id, date_emission, description')
      .eq('id', facture_id)
      .single();

    if (factError || !facture) {
      return jsonResponse(req, { error: 'Facture introuvable' }, 404);
    }

    if (facture.etablissement_id !== userId) {
      return jsonResponse(req, { error: 'Accès interdit' }, 403);
    }

    // Get Chorus Pro config for this etablissement
    const { data: chorusConfig } = await supabaseAdmin
      .from('chorus_pro_config')
      .select('*')
      .eq('etablissement_id', userId)
      .eq('actif', true)
      .maybeSingle();

    // Get etablissement SIRET for fournisseur identification
    const { data: etab } = await supabaseAdmin
      .from('etablissements')
      .select('siret, nom')
      .eq('id', userId)
      .single();

    const pisteConfig = getPisteConfig();
    const isSimulation = !pisteConfig;

    /* ── ACTION: DEPOSER ── */
    if (action === 'deposer') {
      if (!['A_DEPOSER', 'REJETEE'].includes(facture.chorus_pro_statut ?? 'A_DEPOSER')) {
        return jsonResponse(req, {
          error: `Impossible de déposer : statut actuel ${facture.chorus_pro_statut}`,
        }, 400);
      }

      if (isSimulation) {
        const now = new Date().toISOString();
        const fluxId = `SIM-${Date.now()}`;
        await supabaseAdmin
          .from('factures')
          .update({
            chorus_pro_statut: 'DEPOSEE',
            chorus_pro_deposee_le: now,
            chorus_pro_date_depot: now,
            chorus_pro_numero_flux: fluxId,
          })
          .eq('id', facture_id);

        return jsonResponse(req, {
          success: true,
          simulation: true,
          message: 'Mode simulation : facture marquée comme déposée. Configurez PISTE_CLIENT_ID et PISTE_CLIENT_SECRET pour le mode réel (API PISTE).',
          statut: 'DEPOSEE',
          numero_flux: fluxId,
        });
      }

      // Mode réel — appels API PISTE
      if (!chorusConfig) {
        return jsonResponse(req, {
          error: 'Configuration Chorus Pro manquante. Allez dans Paramètres → Chorus Pro pour saisir votre numéro de structure et code service.',
        }, 400);
      }

      if (!etab?.siret) {
        return jsonResponse(req, {
          error: 'SIRET de l\'établissement non renseigné. Complétez votre profil établissement.',
        }, 400);
      }

      console.log(`[chorus-pro] Dépôt facture ${facture.numero_facture} (${pisteConfig.isSandbox ? 'SANDBOX' : 'PROD'})`);

      const accessToken = await getAccessToken(pisteConfig);

      const result = await deposerFlux(pisteConfig, accessToken, {
        numeroFacture: facture.numero_facture,
        montantTtc: Number(facture.montant_ttc) || 0,
        montantHt: Number(facture.montant_ht) || Number(facture.montant_ttc) || 0,
        tauxTva: Number(facture.taux_tva) || 20,
        montantTva: Number(facture.montant_tva) || 0,
        siretFournisseur: etab.siret,
        siretDestinataire: chorusConfig.identifiant_cpro || '',
        codeServiceDestinataire: chorusConfig.code_service || '',
        dateFacture: facture.date_emission || new Date().toISOString().split('T')[0],
        datePrestation: facture.date_emission || new Date().toISOString().split('T')[0],
        ligneDesignation: facture.description || `Facture ${facture.numero_facture} — commission Jolene`,
      });

      const now = new Date().toISOString();
      await supabaseAdmin
        .from('factures')
        .update({
          chorus_pro_statut: 'DEPOSEE',
          chorus_pro_deposee_le: now,
          chorus_pro_date_depot: result.dateTraitement || now,
          chorus_pro_numero_flux: result.numeroFluxDepot,
          chorus_pro_id: result.identifiantFactureCPP?.toString() || null,
        })
        .eq('id', facture_id);

      console.log(`[chorus-pro] Facture ${facture.numero_facture} déposée — flux ${result.numeroFluxDepot}`);

      return jsonResponse(req, {
        success: true,
        simulation: false,
        sandbox: pisteConfig.isSandbox,
        message: pisteConfig.isSandbox
          ? 'Facture déposée sur Chorus Pro (bac à sable)'
          : 'Facture déposée sur Chorus Pro',
        statut: 'DEPOSEE',
        numero_flux: result.numeroFluxDepot,
        identifiant_cpp: result.identifiantFactureCPP,
      });
    }

    /* ── ACTION: STATUT ── */
    if (action === 'statut') {
      if (isSimulation) {
        return jsonResponse(req, {
          success: true,
          simulation: true,
          message: 'Mode simulation : statut lu depuis la base de données.',
          statut: facture.chorus_pro_statut ?? 'A_DEPOSER',
          numero_facture: facture.numero_facture,
        });
      }

      if (!facture.chorus_pro_id) {
        return jsonResponse(req, {
          success: true,
          simulation: false,
          statut: facture.chorus_pro_statut ?? 'A_DEPOSER',
          numero_facture: facture.numero_facture,
          message: 'Pas d\'identifiant Chorus Pro — facture non encore déposée ou dépôt en cours.',
        });
      }

      const accessToken = await getAccessToken(pisteConfig);
      const statusResult = await consulterStatut(pisteConfig, accessToken, facture.chorus_pro_id);

      // Map Chorus Pro statuts to our internal statuts
      const statutMapping: Record<string, string> = {
        DEPOSEE: 'DEPOSEE',
        A_RECYCLER: 'REJETEE',
        REJETEE: 'REJETEE',
        MISE_A_DISPOSITION: 'EN_TRAITEMENT',
        PRISE_EN_COMPTE: 'EN_TRAITEMENT',
        MANDATEE: 'ACCEPTEE',
        MISE_EN_PAIEMENT: 'PAYEE',
        COMPTABILISEE: 'PAYEE',
      };

      const nouveauStatut = statutMapping[statusResult.statutFacture] || facture.chorus_pro_statut || 'DEPOSEE';

      // Update if status changed
      if (nouveauStatut !== facture.chorus_pro_statut) {
        const updateData: any = { chorus_pro_statut: nouveauStatut };
        if (nouveauStatut === 'ACCEPTEE' || nouveauStatut === 'PAYEE') {
          updateData.chorus_pro_date_acceptation = statusResult.dateStatut || new Date().toISOString();
        }
        await supabaseAdmin.from('factures').update(updateData).eq('id', facture_id);
      }

      return jsonResponse(req, {
        success: true,
        simulation: false,
        sandbox: pisteConfig.isSandbox,
        statut: nouveauStatut,
        statut_chorus: statusResult.statutFacture,
        motif_refus: statusResult.motifRefus,
        numero_facture: facture.numero_facture,
      });
    }

    return jsonResponse(req, { error: `Action inconnue: ${action}` }, 400);
  } catch (err) {
    console.error('chorus-pro-deposit error:', err);
    return jsonResponse(req, {
      error: err instanceof Error ? err.message : 'Erreur interne',
    }, 500);
  }
});
