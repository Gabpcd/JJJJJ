import { useEffect } from 'react';

export function usePageTitle(title: string) {
  useEffect(() => {
    document.title = `${title} — Jolene`;
    return () => { document.title = 'Jolene — Staffing médical simplifié'; };
  }, [title]);
}
