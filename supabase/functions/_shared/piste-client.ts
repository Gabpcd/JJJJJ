/**
 * piste-client.ts — Helper partagé PISTE / Chorus Pro
 *
 * Centralise :
 * - Lecture config env (PISTE_* avec fallback CHORUS_PRO_* legacy)
 * - OAuth2 client_credentials → access_token
 * - Construction headers (Bearer + cpro-account si tech user)
 * - Appels API Chorus Pro génériques
 * - Dépôt de flux Factur-X via /deposer/flux
 * - Consultation statut via /consulter/facture
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
    api: 'https://chorus-pro.gouv.fr',
  },
};

const CHORUS_API_PREFIX = '/cpro/factures/v1';

export function getPisteConfig(): PisteConfig | null {
  const clientId = Deno.env.get('PISTE_CLIENT_ID') ?? Deno.env.get('CHORUS_PRO_CLIENT_ID');
  const clientSecret = Deno.env.get('PISTE_CLIENT_SECRET') ?? Deno.env.get('CHORUS_PRO_CLIENT_SECRET');
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
    apiKey: Deno.env.get('PISTE_API_KEY') ?? undefined,
    techLogin: Deno.env.get('CHORUS_TECH_USER_LOGIN') ?? undefined,
    techPassword: Deno.env.get('CHORUS_TECH_USER_PASSWORD') ?? undefined,
    env,
    isSandbox,
    oauthUrl: urls.oauth,
    apiBaseUrl: urls.api,
  };
}

/** OAuth2 client_credentials → access_token */
export async function getAccessToken(config: PisteConfig): Promise<string> {
  const body = new URLSearchParams({
    grant_type: 'client_credentials',
    client_id: config.clientId,
    client_secret: config.clientSecret,
    scope: 'openid',
  });

  const headers: Record<string, string> = {
    'Content-Type': 'application/x-www-form-urlencoded',
  };
  if (config.apiKey) headers['KeyId'] = config.apiKey;

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
  if (config.techLogin && config.techPassword) {
    headers['cpro-account'] = btoa(`${config.techLogin}:${config.techPassword}`);
  }
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
export async function rechercherStructure(
  config: PisteConfig,
  token: string,
  identifiant: string,
): Promise<{ ok: boolean; found: boolean; structure?: any; data: any }> {
  const result = await chorusProApiCall(
    config, token,
    '/cpro/transverses/v1/rechercherStructure',
    'POST',
    {
      idUtilisateurCourant: 0,
      parametres: {
        nbResultatsMaxParPage: 5,
        numeroPagePourRechercher: 1,
        triSurChamp: 'Identifiant',
        triSensTri: 'Ascendant',
      },
      restreindreStructures: {
        identifiantStructure: identifiant,
        structureActive: true,
      },
      typeRecherche: 'ACTIF',
    },
  );
  const structures = result.data?.listeStructures ?? [];
  return {
    ok: result.ok,
    found: structures.length > 0,
    structure: structures[0] ?? undefined,
    data: result.data,
  };
}
