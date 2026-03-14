import { useEffect } from 'react';

export function usePageTitle(title: string) {
  useEffect(() => {
    document.title = `${title} — Soin Direct`;
    return () => { document.title = 'Soin Direct — Staffing médical simplifié'; };
  }, [title]);
}
