import { useEffect } from 'react';

interface SEOHeadProps {
  title: string;
  description: string;
  url?: string;
  image?: string;
  jsonLd?: Record<string, any> | Record<string, any>[];
  noIndex?: boolean;
}

const DEFAULT_OG_IMAGE = 'https://jolene.app/og-default.png';

export function SEOHead({ title, description, url, image, jsonLd, noIndex = false }: SEOHeadProps) {
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

    // JSON-LD structured data
    let ldScript: HTMLScriptElement | null = null;
    if (jsonLd) {
      ldScript = document.querySelector('script[data-jolene-ld]') as HTMLScriptElement | null;
      if (!ldScript) {
        ldScript = document.createElement('script');
        ldScript.type = 'application/ld+json';
        ldScript.setAttribute('data-jolene-ld', 'true');
        document.head.appendChild(ldScript);
      }
      ldScript.textContent = JSON.stringify(jsonLd);
    }

    return () => {
      document.title = 'Jolene Santé — Missions soignants & remplacements vérifiés';
      if (ldScript) ldScript.remove();
    };
  }, [title, description, url, image, jsonLd, noIndex]);

  return null;
}
