/**
 * piste-client.ts — Helper partagé PISTE / Chorus Pro
 *
 * Centralise :
 * - Lecture config env (PISTE_* avec fallback CHORUS_PRO_* legacy)
 * - OAuth2 client_credentials → access_token
 * - Construction headers (Bearer + cpro-account si tech user)
 * - Appels API Chorus Pro génériques
 * - Dépôt de flux Factur-X via /deposer/flux
 * - Consultation statut via /consulter/facture, /consulter/fournisseur
 * - Consultation historique via /consulter/historique
 * - Compte rendu détaillé via /consulterCR, /consulterCRDetaille
 * - Recherche structures + services via /structures/v1/*
 *
 * Env vars attendues :
 * - PISTE_CLIENT_ID (fallback CHORUS_PRO_CLIENT_ID)
 * - PISTE_CLIENT_SECRET (fallback CHORUS_PRO_CLIENT_SECRET)
 * - PISTE_ENV ('sandbox' | 'prod', défaut 'sandbox')
 * - CHORUS_TECH_USER_LOGIN / CHORUS_TECH_USER_PASSWORD (optionnel, header cpro-account)
 * - PISTE_API_KEY (optionnel)
 */

export interface PisteConfig {
  clientId: string;
  clientSecret: string;
  apiKey?: string;
  techLogin?: string;
  techPassword?: string;
  env: 'sandbox' | 'prod';
  oauthUrl: string;
  apiBaseUrl: string;
  isSandbox: boolean;
}

const PISTE_URLS = {
  sandbox: {
    oauth: 'https://sandbox-oauth.piste.gouv.fr/api/oauth/token',
    api: 'https://sandbox-api.piste.gouv.fr',
  },
  prod: {
    oauth: 'https://oauth.piste.gouv.fr/api/oauth/token',
    api: 'https://api.piste.gouv.fr',
  },
};

const CHORUS_API_PREFIX = '/cpro/factures/v1';

export function getPisteConfig(): PisteConfig | null {
  // trim() défensif : un espace/retour à la ligne collé dans un secret Supabase
  // produit un 401 silencieux côté PISTE/Chorus (header cpro-account corrompu).
  const clientId = (Deno.env.get('PISTE_CLIENT_ID') ?? Deno.env.get('CHORUS_PRO_CLIENT_ID'))?.trim();
  const clientSecret = (Deno.env.get('PISTE_CLIENT_SECRET') ?? Deno.env.get('CHORUS_PRO_CLIENT_SECRET'))?.trim();
  if (!clientId || !clientSecret) return null;

  const envRaw = Deno.env.get('PISTE_ENV');
  const isSandbox = envRaw
    ? envRaw === 'sandbox'
    : (Deno.env.get('CHORUS_PRO_SANDBOX') ?? 'true') === 'true';
  const env: 'sandbox' | 'prod' = isSandbox ? 'sandbox' : 'prod';
  const urls = isSandbox ? PISTE_URLS.sandbox : PISTE_URLS.prod;

  return {
    clientId,
    clientSecret,
    apiKey: Deno.env.get('PISTE_API_KEY')?.trim() ?? undefined,
    techLogin: Deno.env.get('CHORUS_TECH_USER_LOGIN')?.trim() ?? undefined,
    techPassword: Deno.env.get('CHORUS_TECH_USER_PASSWORD')?.trim() ?? undefined,
    env,
    isSandbox,
    oauthUrl: urls.oauth,
    apiBaseUrl: urls.api,
  };
}

/** OAuth2 client_credentials → access_token
 *
 * Note PROD : oauth.piste.gouv.fr est un endpoint séparé de l'API Manager
 * Gravitee. Le header `KeyId` est requis sur les endpoints API métier
 * (api.piste.gouv.fr) mais N'EST PAS attendu sur l'OAuth lui-même. Certains
 * plans PISTE rejettent les requêtes OAuth contenant `KeyId` (observé après
 * recréation d'app prod le 2026-05-05 → 401 invalid_client). On garde donc
 * l'OAuth strictement minimal.
 */
export async function getAccessToken(config: PisteConfig): Promise<string> {
  // Scope OAuth configurable via env var PISTE_OAUTH_SCOPE.
  // Quand l'AIFE débloquera l'application avec des scopes opérationnels
  // spécifiques (ex: "openid profile deposerFluxFacture rechercherStructure"),
  // il suffira de définir PISTE_OAUTH_SCOPE dans Supabase Edge Functions Secrets
  // sans modifier le code. Voir docs/CHORUS-PRO-BASCULE-PROD.md.
  const scope = Deno.env.get('PISTE_OAUTH_SCOPE') || 'openid';
  const body = new URLSearchParams({
    grant_type: 'client_credentials',
    client_id: config.clientId,
    client_secret: config.clientSecret,
    scope,
  });

  const headers: Record<string, string> = {
    'Content-Type': 'application/x-www-form-urlencoded',
    Accept: 'application/json',
  };

  const res = await fetch(config.oauthUrl, {
    method: 'POST',
    headers,
    body: body.toString(),
    signal: AbortSignal.timeout(15000),
  });

  if (!res.ok) {
    const text = await res.text();
    throw new Error(`PISTE OAuth failed (${res.status}): ${text.slice(0, 300)}`);
  }

  const data = await res.json();
  if (!data.access_token) throw new Error(`PISTE OAuth sans access_token : ${JSON.stringify(data).slice(0, 200)}`);
  return data.access_token;
}

/** Headers API Chorus Pro (Bearer + KeyId + cpro-account si tech user) */
export function buildChorusHeaders(config: PisteConfig, token: string): Record<string, string> {
  const headers: Record<string, string> = {
    Authorization: `Bearer ${token}`,
    'Content-Type': 'application/json',
    Accept: 'application/json',
  };
  if (config.apiKey) headers['KeyId'] = config.apiKey;
  // PAS de header cpro-account : en raccordement API de type
  // UTILISATEUR_APPLICATION_INTERNE, l'application PISTE est liée à la structure
  // et Chorus rejette (401) toute requête portant ce header. Diagnostic 10/06/2026 :
  // Bearer seul → 400 fonctionnel (auth OK) ; avec cpro-account → 401.
  return headers;
}

/** Appel générique API Chorus Pro avec logs + timeout */
export async function chorusProApiCall(
  config: PisteConfig,
  token: string,
  endpoint: string,
  method: 'GET' | 'POST',
  body?: unknown,
): Promise<{ status: number; ok: boolean; data: any; raw: string; pisteRequestId?: string }> {
  const url = endpoint.startsWith('http') ? endpoint : `${config.apiBaseUrl}${endpoint}`;
  const start = Date.now();
  const res = await fetch(url, {
    method,
    headers: buildChorusHeaders(config, token),
    body: body ? JSON.stringify(body) : undefined,
    signal: AbortSignal.timeout(30000),
  });
  const raw = await res.text();
  let data: any;
  try { data = JSON.parse(raw); } catch { data = { raw }; }
  const duration = Date.now() - start;
  const pisteRequestId = res.headers.get('x-piste-request-id') ?? undefined;
  console.log(`[piste] ${method} ${endpoint} → ${res.status} in ${duration}ms ${pisteRequestId ? '(reqId=' + pisteRequestId + ')' : ''}`);
  return { status: res.status, ok: res.ok, data, raw, pisteRequestId };
}

/**
 * Dépôt d'un flux Factur-X (XML + PDF embarqué ou XML seul) via /deposer/flux.
 * Accepte le fichier encodé en base64.
 *
 * @param fichierBase64 — XML Factur-X ou PDF/A-3 avec XML embarqué, base64-encodé
 * @param nomFichier — nom du fichier (ex. 'F-2026-001.xml' ou '.pdf')
 */
export async function deposerFlux(
  config: PisteConfig,
  token: string,
  params: {
    fichierBase64: string;
    nomFichier: string;
    syntaxeFlux?: string; // défaut 'IN_DP_E2_CII_FACTURX'
  },
): Promise<{ ok: boolean; status: number; data: any; raw: string; identifiantFluxDepot?: string; pisteRequestId?: string }> {
  const payload = {
    idUtilisateurCourant: 0,
    fichierFlux: params.fichierBase64,
    nomFichier: params.nomFichier,
    syntaxeFlux: params.syntaxeFlux ?? 'IN_DP_E2_CII_FACTURX',
  };

  const result = await chorusProApiCall(
    config, token,
    `${CHORUS_API_PREFIX}/deposer/flux`,
    'POST',
    payload,
  );

  const identifiantFluxDepot = result.data?.numeroFluxDepot
    ?? result.data?.identifiantFluxDepot
    ?? result.data?.identifiant
    ?? undefined;

  return { ...result, identifiantFluxDepot };
}

/**
 * Consulter le statut d'une facture déposée via son identifiantFactureCPP
 */
export async function consulterFacture(
  config: PisteConfig,
  token: string,
  identifiantFactureCPP: string | number,
): Promise<{ ok: boolean; status: number; data: any; raw: string; statutFacture?: string; dateStatut?: string; motifRefus?: string }> {
  const result = await chorusProApiCall(
    config, token,
    `${CHORUS_API_PREFIX}/consulter/facture`,
    'POST',
    {
      idUtilisateurCourant: 0,
      identifiantFactureCPP: Number(identifiantFactureCPP),
    },
  );

  return {
    ...result,
    statutFacture: result.data?.statutFacture,
    dateStatut: result.data?.dateStatut,
    motifRefus: result.data?.motifRefus,
  };
}

/**
 * Consulter l'historique d'un flux déposé via son numeroFluxDepot
 * Utile pour sync-chorus-status (retourne le statut traitement + identifiantFactureCPP final)
 */
export async function consulterFlux(
  config: PisteConfig,
  token: string,
  numeroFluxDepot: string,
): Promise<{ ok: boolean; status: number; data: any; raw: string }> {
  return chorusProApiCall(
    config, token,
    `${CHORUS_API_PREFIX}/consulter/flux`,
    'POST',
    {
      idUtilisateurCourant: 0,
      numeroFluxDepot,
    },
  );
}

/**
 * Rechercher une structure Chorus Pro par identifiant (SIRET/numéro structure).
 * Retourne la structure trouvée ou null si introuvable.
 */
// ═══════════════════════════════════════════════════════════════════════
// P1 — Consultation détaillée factures
// ═══════════════════════════════════════════════════════════════════════

/**
 * Consulter le détail complet d'une facture émise (point de vue fournisseur).
 * Retourne : cadre de facturation, destinataire, fournisseur, lignes de poste,
 * pièces jointes, montants, statut, references, coordonnées bancaires,
 * numéro de mandat DGFiP, pièce précédente/suivante.
 */
export async function consulterFactureFournisseur(
  config: PisteConfig,
  token: string,
  identifiantFactureCPP: string | number,
): Promise<{ ok: boolean; data: any }> {
  return chorusProApiCall(
    config, token,
    `${CHORUS_API_PREFIX}/consulter/fournisseur`,
    'POST',
    { idUtilisateurCourant: 0, identifiantFactureCPP: Number(identifiantFactureCPP) },
  );
}

/**
 * Historique complet d'une facture : statuts successifs avec dates et
 * utilisateurs, actions utilisateurs, événements complémentaires.
 */
export async function consulterHistoriqueFacture(
  config: PisteConfig,
  token: string,
  identifiantFactureCPP: string | number,
): Promise<{ ok: boolean; data: any }> {
  return chorusProApiCall(
    config, token,
    `${CHORUS_API_PREFIX}/consulter/historique`,
    'POST',
    { idUtilisateurCourant: 0, identifiantFactureCPP: Number(identifiantFactureCPP) },
  );
}

/**
 * Compte rendu d'un flux (PDF base64). Preuve officielle de réception.
 * Retourne `fichierCR` (base64), `etatCourantFlux`, `dateDepotFlux`.
 */
export async function consulterCR(
  config: PisteConfig,
  token: string,
  numeroFluxDepot: string,
): Promise<{ ok: boolean; data: any; fichierCR?: string; etatCourant?: string }> {
  const result = await chorusProApiCall(
    config, token,
    '/cpro/transverses/v1/consulterCR',
    'POST',
    { idUtilisateurCourant: 0, numeroFluxDepot },
  );
  return {
    ...result,
    fichierCR: result.data?.fichierCR,
    etatCourant: result.data?.etatCourantFlux,
  };
}

/**
 * Compte rendu détaillé d'un flux : retourne les erreurs par demande de
 * paiement (listeErreurDP) et erreurs techniques (listeErreurTechnique).
 * Indispensable pour comprendre pourquoi un flux est rejeté.
 */
export async function consulterCRDetaille(
  config: PisteConfig,
  token: string,
  numeroFluxDepot: string,
): Promise<{ ok: boolean; data: any; erreurs?: any[]; erreursTechniques?: any[] }> {
  const result = await chorusProApiCall(
    config, token,
    '/cpro/transverses/v1/consulterCRDetaille',
    'POST',
    { idUtilisateurCourant: 0, numeroFluxDepot },
  );
  return {
    ...result,
    erreurs: result.data?.listeErreurDP ?? [],
    erreursTechniques: result.data?.listeErreurTechnique ?? [],
  };
}

/**
 * Rechercher les factures émises par le fournisseur (recherche batch).
 * Filtres : statut, dates, SIRET destinataire, montants, numéro flux.
 */
export async function rechercherFacturesFournisseur(
  config: PisteConfig,
  token: string,
  filtres: {
    dateDepotDebut?: string;
    dateDepotFin?: string;
    statutCourant?: string;
    identifiantDestinataire?: string;
    nbResultatsMax?: number;
    pageNumero?: number;
  } = {},
): Promise<{ ok: boolean; data: any; factures?: any[]; nbResultats?: number }> {
  const result = await chorusProApiCall(
    config, token,
    `${CHORUS_API_PREFIX}/rechercher/fournisseur`,
    'POST',
    {
      idUtilisateurCourant: 0,
      parametres: {
        nbResultatsMaxParPage: filtres.nbResultatsMax ?? 50,
        numeroPagePourRechercher: filtres.pageNumero ?? 1,
        triSurChamp: 'DateDepot',
        triSensTri: 'Descendant',
      },
      ...(filtres.dateDepotDebut ? { dateDepotDebut: filtres.dateDepotDebut } : {}),
      ...(filtres.dateDepotFin ? { dateDepotFin: filtres.dateDepotFin } : {}),
      ...(filtres.statutCourant ? { statutCourant: filtres.statutCourant } : {}),
      ...(filtres.identifiantDestinataire ? { identifiantDestinataire: filtres.identifiantDestinataire } : {}),
    },
  );
  return {
    ...result,
    factures: result.data?.listeFactures ?? [],
    nbResultats: result.data?.parametres?.nbResultatsGlobal,
  };
}

// ═══════════════════════════════════════════════════════════════════════
// P2 — Validation structures + services
// ═══════════════════════════════════════════════════════════════════════

/**
 * Consulter le détail + paramétrage d'une structure Chorus Pro.
 * Retourne : codeServiceDoitEtreRenseigne, statutMiseEnPaiementNestPasRemonte,
 * raison sociale, adresse, SIRET, type identifiant, statut.
 */
export async function consulterStructure(
  config: PisteConfig,
  token: string,
  identifiantStructure: string,
): Promise<{ ok: boolean; data: any; codeServiceObligatoire?: boolean; designation?: string }> {
  const result = await chorusProApiCall(
    config, token,
    '/cpro/structures/v1/consulter',
    'POST',
    { idUtilisateurCourant: 0, identifiantStructure },
  );
  return {
    ...result,
    codeServiceObligatoire: result.data?.parametrage?.codeServiceDoitEtreRenseigne === true,
    designation: result.data?.designationStructure,
  };
}

/**
 * Rechercher les services d'une structure (codes service valides).
 * Retourne la liste paginée des services (code, nom, statut, actif).
 */
export async function rechercherServicesStructure(
  config: PisteConfig,
  token: string,
  identifiantStructure: string,
): Promise<{ ok: boolean; data: any; services?: Array<{ code: string; nom: string; actif: boolean }> }> {
  const result = await chorusProApiCall(
    config, token,
    '/cpro/structures/v1/rechercher/services',
    'POST',
    {
      idUtilisateurCourant: 0,
      identifiantStructure,
      parametres: {
        nbResultatsMaxParPage: 100,
        numeroPagePourRechercher: 1,
        triSurChamp: 'CodeService',
        triSensTri: 'Ascendant',
      },
    },
  );
  const raw = result.data?.listeServices ?? [];
  return {
    ...result,
    services: raw.map((s: any) => ({
      code: s.codeService ?? s.code,
      nom: s.nomService ?? s.libelle ?? s.nom,
      actif: s.serviceActif !== false && s.actif !== false,
    })),
  };
}

/**
 * Consulter le détail d'un service spécifique d'une structure.
 */
export async function consulterService(
  config: PisteConfig,
  token: string,
  identifiantStructure: string,
  codeService: string,
): Promise<{ ok: boolean; data: any; actif?: boolean; nom?: string }> {
  const result = await chorusProApiCall(
    config, token,
    '/cpro/structures/v1/consulter/service',
    'POST',
    { idUtilisateurCourant: 0, identifiantStructure, codeService },
  );
  return {
    ...result,
    actif: result.data?.serviceActif !== false,
    nom: result.data?.nomService ?? result.data?.libelle,
  };
}

// ═══════════════════════════════════════════════════════════════════════
// Existant — Recherche structure (inchangé)
// ═══════════════════════════════════════════════════════════════════════

export async function rechercherStructure(
  config: PisteConfig,
  token: string,
  identifiant: string,
): Promise<{ ok: boolean; found: boolean; structure?: any; data: any; status: number }> {
  // Chemin vérifié en prod le 11/06/2026 : /cpro/structures/v1/rechercher répond
  // (l'ancien /cpro/transverses/v1/rechercherStructure → 403 route inconnue).
  // Deux formats de corps tentés (nouveau puis legacy) — l'API renvoie 400 sur
  // le mauvais format, pas d'effet de bord (lecture seule).
  let result = await chorusProApiCall(
    config, token,
    '/cpro/structures/v1/rechercher',
    'POST',
    {
      structure: {
        identifiantStructure: identifiant,
        typeIdentifiantStructure: 'SIRET',
      },
    },
  );
  if (!result.ok) {
    result = await chorusProApiCall(
      config, token,
      '/cpro/structures/v1/rechercher',
      'POST',
      {
        parametres: { nbResultatsMaxParPage: 5, numeroPagePourRechercher: 1 },
        restreindreStructures: { identifiantStructure: identifiant, structureActive: true },
        typeRecherche: 'ACTIF',
      },
    );
  }
  const structures = result.data?.listeStructures ?? [];
  return {
    ok: result.ok,
    found: structures.length > 0,
    structure: structures[0] ?? undefined,
    data: result.data,
    status: result.status,
  };
}
