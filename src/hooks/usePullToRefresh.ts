import { useEffect, useRef, useState } from 'react';

/**
 * Pull-to-refresh maison (Lot 6b.3) — geste natif attendu d'une app store.
 *
 * Le pull-to-refresh NAVIGATEUR est volontairement tué globalement
 * (body { overscroll-behavior-y: none } — il rechargeait toute la SPA).
 * Ce hook réimplémente le geste au niveau produit : tirer vers le bas quand la
 * page est déjà en haut (window.scrollY === 0) déclenche un refetch des
 * données, sans recharger l'app.
 *
 * Usage :
 *   const { pullDistance, refreshing } = usePullToRefresh(async () => { await refetch(); });
 *   <IndicateurPullToRefresh distance={pullDistance} refreshing={refreshing} />
 */
const SEUIL_DECLENCHEMENT = 70; // px de tirage pour déclencher
const TIRAGE_MAX = 110; // résistance : on n'affiche jamais plus que ça

export function usePullToRefresh(onRefresh: () => Promise<unknown>) {
  const [pullDistance, setPullDistance] = useState(0);
  const [refreshing, setRefreshing] = useState(false);
  const startY = useRef<number | null>(null);
  const pulling = useRef(false);
  const refreshingRef = useRef(false);
  const onRefreshRef = useRef(onRefresh);
  onRefreshRef.current = onRefresh;

  useEffect(() => {
    const onTouchStart = (e: TouchEvent) => {
      if (refreshingRef.current) return;
      // Uniquement quand la PAGE est en haut : sinon c'est un scroll normal.
      if (window.scrollY > 0) return;
      // Pas de pull si le geste démarre dans un conteneur scrollable interne
      // qui n'est pas lui-même en haut (modales, listes imbriquées).
      const cible = e.target as HTMLElement | null;
      const scrollable = cible?.closest('[data-no-ptr], [role="dialog"]');
      if (scrollable) return;
      startY.current = e.touches[0].clientY;
      pulling.current = true;
    };

    const onTouchMove = (e: TouchEvent) => {
      if (!pulling.current || startY.current === null) return;
      const delta = e.touches[0].clientY - startY.current;
      if (delta <= 0 || window.scrollY > 0) {
        setPullDistance(0);
        return;
      }
      // Résistance progressive (÷2) plafonnée
      setPullDistance(Math.min(TIRAGE_MAX, delta / 2));
    };

    const onTouchEnd = () => {
      if (!pulling.current) return;
      pulling.current = false;
      startY.current = null;
      setPullDistance((d) => {
        if (d >= SEUIL_DECLENCHEMENT && !refreshingRef.current) {
          refreshingRef.current = true;
          setRefreshing(true);
          void Promise.resolve(onRefreshRef.current()).finally(() => {
            refreshingRef.current = false;
            setRefreshing(false);
          });
        }
        return 0;
      });
    };

    window.addEventListener('touchstart', onTouchStart, { passive: true });
    window.addEventListener('touchmove', onTouchMove, { passive: true });
    window.addEventListener('touchend', onTouchEnd, { passive: true });
    return () => {
      window.removeEventListener('touchstart', onTouchStart);
      window.removeEventListener('touchmove', onTouchMove);
      window.removeEventListener('touchend', onTouchEnd);
    };
  }, []);

  return { pullDistance, refreshing };
}

export default usePullToRefresh;
