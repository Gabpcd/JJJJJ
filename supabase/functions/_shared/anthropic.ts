// Source UNIQUE + appel résilient à l'API Anthropic Messages pour toutes les
// fonctions de vérification IA (documents, identité, RIB, contrats, heures…).
//
// POURQUOI CE MODULE EXISTE
// -------------------------
// Le modèle était codé en dur (`claude-sonnet-4-20250514`) dans 7 fonctions.
// Anthropic a déprécié ce snapshot daté → 404 `not_found_error` à chaque appel
// → TOUTE la vérification IA est tombée en silence (documents bloqués en
// « EN_ATTENTE » indéfiniment). Pour que ça ne se reproduise JAMAIS :
//
//   1. UN SEUL endroit définit le modèle. Par défaut `claude-opus-4-8` (le plus
//      capable — exigé pour la vérification d'identité/fraude).
//   2. Surchargeable SANS REDÉPLOIEMENT via le secret Supabase `ANTHROPIC_MODEL`
//      (et `ANTHROPIC_MODEL_FALLBACKS`, liste séparée par des virgules). Changer
//      le secret au Dashboard suffit — pris en compte au prochain démarrage.
//   3. AUTO-RÉPARATION : si le modèle principal est introuvable (404 = déprécié),
//      on bascule automatiquement sur le modèle de secours suivant et on logge un
//      avertissement. La vérif ne casse plus quand un modèle part en retraite.
//
// IMPORTANT : ne jamais remettre un ID de modèle codé en dur dans une fonction —
// toujours passer par `appelerAnthropic()`.

const MODELE_DEFAUT = 'claude-opus-4-8';
// Ordre de secours (du plus capable au plus léger). PAS de Fable (indisponible
// sur ce compte). Le principal est toujours essayé en premier.
const FALLBACKS_DEFAUT = ['claude-opus-4-8', 'claude-sonnet-4-6', 'claude-haiku-4-5-20251001'];

/** Liste ordonnée des modèles à tenter : principal puis secours, sans doublon. */
export function modelesAnthropic(): string[] {
  const principal = (Deno.env.get('ANTHROPIC_MODEL') || MODELE_DEFAUT).trim();
  const secours = (Deno.env.get('ANTHROPIC_MODEL_FALLBACKS') || FALLBACKS_DEFAUT.join(','))
    .split(',').map((s) => s.trim()).filter(Boolean);
  return [principal, ...secours.filter((m) => m !== principal)];
}

export interface AppelAnthropic {
  apiKey: string;
  system: string;
  /** messages[0].content : string OU tableau (image/PDF + texte) pour la vision. */
  content: unknown;
  maxTokens?: number;
  signal?: AbortSignal;
}

export interface ResultatAnthropic {
  ok: boolean;
  status: number;
  /** JSON parsé de la réponse Anthropic si ok (lire data.content[0].text). */
  data: any;
  /** Corps brut en cas d'erreur (pour log/diagnostic). */
  body: string;
  /** Modèle réellement utilisé (utile pour tracer une bascule de secours). */
  model: string;
}

/**
 * Appelle l'API Anthropic Messages en essayant chaque modèle jusqu'au 1er qui
 * répond. Ne bascule QUE sur un 404 « modèle introuvable » (déprécié) ; toute
 * autre erreur (rate limit, auth, crédits insuffisants) est renvoyée telle
 * quelle, sans la masquer ni gaspiller d'appels.
 */
export async function appelerAnthropic(opts: AppelAnthropic): Promise<ResultatAnthropic> {
  const modeles = modelesAnthropic();
  let dernier: ResultatAnthropic = { ok: false, status: 0, data: null, body: 'aucun modèle configuré', model: '' };
  for (const model of modeles) {
    let res: Response;
    try {
      res = await fetch('https://api.anthropic.com/v1/messages', {
        method: 'POST',
        headers: {
          'x-api-key': opts.apiKey,
          'anthropic-version': '2023-06-01',
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          model,
          max_tokens: opts.maxTokens ?? 1000,
          system: opts.system,
          messages: [{ role: 'user', content: opts.content }],
        }),
        signal: opts.signal,
      });
    } catch (err) {
      // Erreur réseau / abort : ne pas tenter les autres modèles (ce n'est pas
      // un problème de modèle), remonter.
      return { ok: false, status: 0, data: null, body: String(err), model };
    }
    if (res.ok) {
      return { ok: true, status: res.status, data: await res.json(), body: '', model };
    }
    const body = await res.text();
    dernier = { ok: false, status: res.status, data: null, body, model };
    const modeleIntrouvable = res.status === 404 && /not_found|\bmodel\b/i.test(body);
    if (!modeleIntrouvable) return dernier; // vraie erreur métier → on s'arrête
    console.warn(`[anthropic] modèle "${model}" indisponible (404) → bascule sur le modèle de secours suivant`);
  }
  console.error('[anthropic] AUCUN modèle disponible — mettre à jour le secret ANTHROPIC_MODEL / ANTHROPIC_MODEL_FALLBACKS');
  return dernier;
}
