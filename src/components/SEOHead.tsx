import { useEffect } from 'react';

interface SEOHeadProps {
  title: string;
  description: string;
  url?: string;
  image?: string;
}

const DEFAULT_OG_IMAGE = 'https://app.soindirect.com/og-default.png';

export function SEOHead({ title, description, url, image }: SEOHeadProps) {
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

    return () => {
      document.title = 'Soin Direct — Staffing médical simplifié';
    };
  }, [title, description, url, image]);

  return null;
}
