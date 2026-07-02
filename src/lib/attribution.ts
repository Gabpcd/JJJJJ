/**
 * Attribution d'acquisition — capture la source d'arrivée (UTM, referrer, code
 * parrainage) dès la PREMIÈRE page visitée et la persiste jusqu'à l'inscription.
 *
 * Modèle : "premier contact significatif". On stocke la première source porteuse
 * d'un signal (UTM, ref, ou referrer externe). Une arrivée purement directe ne
 * verrouille rien (un contact ultérieur via une campagne deviendra l'attribution).
 *
 * Bonus : mirrore le code ?ref= dans le sessionStorage existant utilisé par le
 * flux parrainage — ce qui corrige le bug "code parrainage perdu sur la homepage"
 * (le code n'était capté que sur la page d'inscription elle-même).
 */

const KEY = 'jolene.attribution';

export interface Attribution {
  utm_source?: string;
  utm_medium?: string;
  utm_campaign?: string;
  utm_content?: string;
  utm_term?: string;
  referrer?: string;
  ref_code?: string;
  captured_at?: string;
}

function refSessionKey(ref: string): string {
  return /^ETB-/i.test(ref) ? 'jolene.parrainage_etab_code' : 'jolene.parrainage_code';
}

export function captureAttribution(): void {
  if (typeof window === 'undefined') return;
  try {
    const params = new URLSearchParams(window.location.search);
    // 7f : ?parrain= est l'alias utilisé par les emails avis-parrainage.
    const ref = params.get('ref') || params.get('parrain') || undefined;

    // Mirror du code parrainage dans le sessionStorage existant (depuis N'IMPORTE
    // quelle page d'entrée, pas seulement la page d'inscription).
    if (ref) {
      try {
        const k = refSessionKey(ref);
        if (!sessionStorage.getItem(k)) sessionStorage.setItem(k, ref);
      } catch { /* ignore */ }
    }

    const existing = localStorage.getItem(KEY);
    if (existing) {
      // Première source déjà verrouillée — on complète juste le code parrainage
      // s'il apparaît plus tard et n'était pas encore connu.
      if (ref) {
        const data: Attribution = JSON.parse(existing);
        if (!data.ref_code) {
          data.ref_code = ref;
          localStorage.setItem(KEY, JSON.stringify(data));
        }
      }
      return;
    }

    const utm = {
      utm_source: params.get('utm_source') || undefined,
      utm_medium: params.get('utm_medium') || undefined,
      utm_campaign: params.get('utm_campaign') || undefined,
      utm_content: params.get('utm_content') || undefined,
      utm_term: params.get('utm_term') || undefined,
    };
    const hasUtm = Object.values(utm).some(Boolean);
    const referrerExterne =
      document.referrer && !document.referrer.includes(window.location.host)
        ? document.referrer
        : undefined;

    // Arrivée purement directe → on ne verrouille rien.
    if (!hasUtm && !ref && !referrerExterne) return;

    const data: Attribution = {
      ...utm,
      ref_code: ref,
      referrer: referrerExterne,
      captured_at: new Date().toISOString(),
    };
    localStorage.setItem(KEY, JSON.stringify(data));
  } catch {
    /* ignore — l'attribution ne doit jamais bloquer la navigation */
  }
}

export function getAttribution(): Attribution {
  if (typeof window === 'undefined') return {};
  try {
    return JSON.parse(localStorage.getItem(KEY) || '{}');
  } catch {
    return {};
  }
}
