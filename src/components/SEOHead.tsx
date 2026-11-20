import { useEffect } from 'react';

interface SEOHeadProps {
  title: string;
  description: string;
  url?: string;
  image?: string;
  jsonLd?: Record<string, unknown> | Record<string, unknown>[];
  noIndex?: boolean;
}

const DEFAULT_OG_IMAGE = 'https://jolene.app/og-default.png';

/** Sélecteur du script de données structurées de la page (posé par le HTML statique ou par ce composant). */
const SELECTEUR_LD = 'script[data-jolene-ld]';

export function SEOHead({ title, description, url, image, jsonLd, noIndex = false }: SEOHeadProps) {
  // Sérialisé hors de l'effet : un objet recréé à chaque rendu ne relance pas l'effet si son contenu est le même.
  const ld = jsonLd && (!Array.isArray(jsonLd) || jsonLd.length > 0) ? JSON.stringify(jsonLd) : null;

  useEffect(() => {
    document.title = title;

    const setMeta = (attr: string, key: string, content: string) => {
      let el = document.querySelector(`meta[${attr}="${key}"]`) as HTMLMetaElement | null;
      if (!el) {
        el = document.createElement('meta');
        el.setAttribute(attr, key);
        document.head.appendChild(el);
      }
      el.setAttribute('content', content);
    };

    const ogImage = image || DEFAULT_OG_IMAGE;

    setMeta('name', 'description', description);
    setMeta('property', 'og:title', title);
    setMeta('property', 'og:description', description);
    setMeta('property', 'og:image', ogImage);
    setMeta('property', 'og:type', 'website');
    if (url) setMeta('property', 'og:url', url);
    setMeta('name', 'twitter:card', 'summary_large_image');
    setMeta('name', 'twitter:title', title);
    setMeta('name', 'twitter:description', description);
    setMeta('name', 'twitter:image', ogImage);
    setMeta('name', 'robots', noIndex ? 'noindex, nofollow' : 'index, follow');

    let canonical = document.querySelector('link[rel="canonical"]') as HTMLLinkElement | null;
    if (!canonical) {
      canonical = document.createElement('link');
      canonical.rel = 'canonical';
      document.head.appendChild(canonical);
    }
    canonical.href = url || `https://jolene.app${window.location.pathname}`;

    // Données structurées : un seul script par page. Celui du HTML statique (même attribut)
    // est repris tel quel ; une page sans données structurées retire celui de la page précédente.
    let ldScript = document.querySelector(SELECTEUR_LD) as HTMLScriptElement | null;
    if (ld) {
      if (!ldScript) {
        ldScript = document.createElement('script');
        ldScript.type = 'application/ld+json';
        ldScript.setAttribute('data-jolene-ld', 'true');
        document.head.appendChild(ldScript);
      }
      ldScript.textContent = ld;
    } else if (ldScript) {
      ldScript.remove();
      ldScript = null;
    }

    return () => {
      document.title = 'Jolene Santé — Missions soignants & remplacements vérifiés';
      document.querySelector(SELECTEUR_LD)?.remove();
    };
  }, [title, description, url, image, ld, noIndex]);

  return null;
}
