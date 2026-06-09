// Helper d'attribution d'acquisition partagé par register-soignant /
// register-etablissement. Extrait les colonnes brutes (UTM, referrer, code
// parrainage) depuis le body d'inscription + le header Referer. La
// classification en canal (SEO/SOCIAL/PAID/…) est faite par le trigger DB
// fn_trg_classifier_acquisition (source de vérité unique).

export interface AttributionInput {
  utm_source?: string | null;
  utm_medium?: string | null;
  utm_campaign?: string | null;
  utm_content?: string | null;
  utm_term?: string | null;
  referrer?: string | null;
  ref_code?: string | null;
}

function clean(v: unknown, max = 255): string | null {
  if (typeof v !== "string") return null;
  const s = v.trim();
  return s ? s.slice(0, max) : null;
}

export function colonnesAttribution(
  attribution: AttributionInput | undefined | null,
  req: Request,
): Record<string, string | null> {
  const a = attribution || {};
  const referrer = clean(a.referrer, 2000) || clean(req.headers.get("referer"), 2000);
  return {
    utm_source: clean(a.utm_source),
    utm_medium: clean(a.utm_medium),
    utm_campaign: clean(a.utm_campaign),
    utm_content: clean(a.utm_content),
    utm_term: clean(a.utm_term),
    http_referrer: referrer,
    ref_capture: clean(a.ref_code, 32),
  };
}
