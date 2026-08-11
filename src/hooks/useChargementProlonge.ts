import { useCallback, useEffect, useState } from 'react';

export function useChargementProlonge(enCours: boolean, delaiMs = 12_000) {
  const [estProlonge, setEstProlonge] = useState(false);
  const [tentative, setTentative] = useState(0);

  useEffect(() => {
    if (!enCours) {
      setEstProlonge(false);
      return;
    }

    const minuteur = window.setTimeout(() => setEstProlonge(true), delaiMs);
    return () => window.clearTimeout(minuteur);
  }, [delaiMs, enCours, tentative]);

  const reinitialiser = useCallback(() => {
    setEstProlonge(false);
    setTentative((valeur) => valeur + 1);
  }, []);

  return { estProlonge, reinitialiser };
}
