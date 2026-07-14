/**
 * Sprint 10-A v3 PR 2 — Filtre anti-leak messagerie (logique pure)
 *
 * Détection des coordonnées de contact externe dans le contenu d'un message.
 * Fichier sans imports Deno-spécifiques pour être importable depuis :
 *  - supabase/functions/messagerie-validate/index.ts (Deno edge function)
 *  - e2e/flows/messagerie-anti-leak.spec.ts (tests Playwright Node)
 *
 * Décision produit Gabrielle (option DUR) :
 *   AUCUNE exception pour téléphones fixes étab ou emails pro.
 *   Tout échange de coordonnées interdit, peu importe origine.
 *   Exception URL : domaine jolene.app et sous-domaines uniquement.
 */

export type DetectedType = "TELEPHONE" | "EMAIL" | "URL" | "HANDLE" | "KEYWORD";

export interface DetectionResult {
  blocked: boolean;
  type?: DetectedType;
  match?: string;
}

/**
 * Détection anti-leak — retourne le PREMIER pattern trouvé.
 * Ordre de priorité : téléphones > emails > URLs > handles > keywords.
 */
export function detecterLeak(content: string): DetectionResult {
  const lower = content.toLowerCase();

  // ─── 1. TÉLÉPHONES FR (mobile + fixe + international + spéciaux) ─────
  const telFR = /(?:(?:\+|00)33|0)\s*[1-9](?:[\s.-]*\d{2}){4}/g;
  const matchTelFR = content.match(telFR);
  if (matchTelFR && matchTelFR.length > 0) {
    return { blocked: true, type: "TELEPHONE", match: matchTelFR[0] };
  }

  const telSpecialFR = /\b(?:08\d{2}|36\d{2}|39\d{2})[\s.-]?\d{0,6}/g;
  const matchSpecial = content.match(telSpecialFR);
  if (matchSpecial && matchSpecial.length > 0) {
    return { blocked: true, type: "TELEPHONE", match: matchSpecial[0] };
  }

  const telIntl = /(?:\+|00)(?:[\s.-]*\d){7,15}\b/g;
  const matchIntl = content.match(telIntl);
  if (matchIntl && matchIntl.length > 0) {
    return { blocked: true, type: "TELEPHONE", match: matchIntl[0] };
  }

  // 7e-1 : « zéro six / zéro sept » en toutes lettres (contournement courant)
  const zeroSix = /\bz[ée]ro\s*(?:six|sept)\b/i;
  const matchZeroSix = content.match(zeroSix);
  if (matchZeroSix) {
    return { blocked: true, type: "TELEPHONE", match: matchZeroSix[0] };
  }

  // ─── 2. EMAILS (RFC 5322 simplifié, TOUS domaines) ──────────────────
  const email = /[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}/g;
  const matchEmail = content.match(email);
  if (matchEmail && matchEmail.length > 0) {
    return { blocked: true, type: "EMAIL", match: matchEmail[0] };
  }

  // ─── 3. URLS (sauf jolene.app et sous-domaines) ──────────────────────
  const urlHttp = /https?:\/\/[^\s]+/gi;
  const matchHttp = content.match(urlHttp);
  if (matchHttp) {
    for (const url of matchHttp) {
      if (!isJoleneUrl(url)) {
        return { blocked: true, type: "URL", match: url };
      }
    }
  }

  const domain = /\b(?!jolene\.app\b)[a-z0-9-]+\.(?:fr|com|net|org|eu|io|app|co|info|biz|pro|me|tv|us|uk|de|es|it|be|ch|ca)\b/gi;
  const matchDomain = content.match(domain);
  if (matchDomain) {
    for (const d of matchDomain) {
      if (!isJoleneUrl(d)) {
        return { blocked: true, type: "URL", match: d };
      }
    }
  }

  const www = /www\.[a-z0-9.-]+\.[a-z]{2,}/gi;
  const matchWww = content.match(www);
  if (matchWww) {
    for (const w of matchWww) {
      if (!isJoleneUrl(w)) {
        return { blocked: true, type: "URL", match: w };
      }
    }
  }

  // ─── 4. HANDLES RÉSEAUX SOCIAUX (@nom + contexte) ───────────────────
  const reseauxKeywords = ["instagram", "twitter", "tiktok", "linkedin", "facebook", "snapchat", " x ", "insta", "snap"];
  const hasReseauContext = reseauxKeywords.some((k) => lower.includes(k));
  if (hasReseauContext) {
    const handle = /@[a-zA-Z0-9._]{2,}/g;
    const matchHandle = content.match(handle);
    if (matchHandle && matchHandle.length > 0) {
      return { blocked: true, type: "HANDLE", match: matchHandle[0] };
    }
  }

  // ─── 5. MOTS-CLÉS CONTACT EXTERNE ────────────────────────────────────
  const motsCles = [
    "whatsapp", "signal", "telegram", "messenger", "viber", "imessage",
    "skype", "facetime", "appelle-moi", "appelle moi", "écris-moi",
    "écris moi", "dm me", "dm-moi", "dm moi",
    "mon numéro", "mon numero", "mon mail", "mon email",
    "envoie-moi un sms", "envoie moi un sms", "envoie-moi un mail",
    "tu peux me joindre", "ma ligne directe", "mon perso",
    "hors plateforme", "hors-plateforme", "hors de la plateforme",
    "calendly", "doctolib",
    "en dehors de jolene", "en privé", "en prive",
  ];
  for (const mot of motsCles) {
    if (lower.includes(mot)) {
      return { blocked: true, type: "KEYWORD", match: mot };
    }
  }

  return { blocked: false };
}

export function isJoleneUrl(url: string): boolean {
  const valeur = url.trim().replace(/[),.;!?]+$/g, '');
  try {
    const parsed = new URL(
      /^[a-z][a-z\d+.-]*:\/\//i.test(valeur)
        ? valeur
        : `https://${valeur}`,
    );
    const hostname = parsed.hostname.toLowerCase().replace(/\.$/, '');
    return hostname === 'jolene.app' || hostname.endsWith('.jolene.app');
  } catch {
    return false;
  }
}

/**
 * Normalisation du texte brut. Les clients React rendent `contenu` comme un
 * nœud texte (aucun HTML/Markdown), donc encoder ou retirer `<` altérerait des
 * messages légitimes comme « 1 < 2 ». PostgreSQL interdit seulement NUL.
 */
export function sanitizeContent(content: string): string {
  return content
    .split(String.fromCharCode(0)).join("")
    .replace(/\r\n?/g, "\n")
    .trim();
}
