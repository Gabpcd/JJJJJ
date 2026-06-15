import { useEffect } from 'react';

interface SEOHeadProps {
  title: string;
  description: string;
  url?: string;
  image?: string;
  jsonLd?: Record<string, any> | Record<string, any>[];
}

const DEFAULT_OG_IMAGE = 'https://jolene.app/og-default.png';

export function SEOHead({ title, description, url, image, jsonLd }: SEOHeadProps) {
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
  }, [title, description, url, image, jsonLd]);

  return null;
}
