import { useEffect, useState, type SetStateAction } from 'react';
import { useQueryClient } from '@tanstack/react-query';

export type VueExploration = 'swipe' | 'liste' | 'carte';
export type HoraireExploration = 'TOUS' | 'JOUR' | 'NUIT' | 'WEEKEND';

interface EtatExploration {
  vue: VueExploration;
  profession: string;
  rayonKm: number;
  tauxMin: number;
  typeContrat: string;
  urgentesOnly: boolean;
  horaire: HoraireExploration;
  villeRecherche: string;
  nbAffiche: number;
  profilApplique: boolean;
}

function vueInitiale(userId?: string): VueExploration {
  try {
    const value = new URLSearchParams(window.location.search).get('vue')
      || localStorage.getItem(`jolene_missions_view_pref:${userId}`)
      || localStorage.getItem('jolene_missions_view_pref');
    if (value === 'liste' || value === 'carte') return value;
  } catch { /* Stockage indisponible : le mode Swipe reste accessible. */ }
  return 'swipe';
}

/** État de navigation en mémoire seulement, effacé avec le cache à la déconnexion. */
export function useMemoireExploration(userId?: string) {
  const queryClient = useQueryClient();
  const key = ['explorer-navigation', userId];
  const [etat, setEtat] = useState<EtatExploration>(() => {
    const precedent = queryClient.getQueryData<EtatExploration>(key);
    const vueUrl = new URLSearchParams(window.location.search).get('vue');
    if (precedent) {
      return vueUrl === 'swipe' || vueUrl === 'liste' || vueUrl === 'carte'
        ? { ...precedent, vue: vueUrl }
        : precedent;
    }
    return {
      vue: vueInitiale(userId), profession: '', rayonKm: 50, tauxMin: 0,
      typeContrat: 'TOUS', urgentesOnly: false, horaire: 'TOUS',
      villeRecherche: '', nbAffiche: 20, profilApplique: false,
    };
  });

  useEffect(() => {
    if (!userId) return;
    // Contrairement aux résultats métier, une préférence de navigation ne doit
    // pas disparaître après quelques minutes passées sur un autre écran.
    // AuthContext vide toujours ce cache à la déconnexion.
    queryClient.setQueryDefaults(['explorer-navigation'], { gcTime: Infinity });
    queryClient.setQueryData(['explorer-navigation', userId], etat);
  }, [queryClient, userId, etat]);

  function modifier<K extends keyof EtatExploration>(champ: K, value: SetStateAction<EtatExploration[K]>) {
    setEtat((precedent) => ({
      ...precedent,
      [champ]: typeof value === 'function'
        ? (value as (ancienne: EtatExploration[K]) => EtatExploration[K])(precedent[champ])
        : value,
    }));
  }

  return { etat, setEtat, modifier };
}
