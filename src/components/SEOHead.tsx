import { useEffect } from 'react';

interface SEOHeadProps {
  title: string;
  description: string;
  url?: string;
}

export function SEOHead({ title, description, url }: SEOHeadProps) {
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

    setMeta('name', 'description', description);
    setMeta('property', 'og:title', title);
    setMeta('property', 'og:description', description);
    if (url) setMeta('property', 'og:url', url);
    setMeta('property', 'og:type', 'website');
    setMeta('name', 'twitter:title', title);
    setMeta('name', 'twitter:description', description);

    return () => {
      document.title = 'Soin Direct — Staffing médical simplifié';
    };
  }, [title, description, url]);

  return null;
}
