import { useLayoutEffect, useRef } from 'react';
import { useLocation, useNavigationType } from 'react-router-dom';
import { useAuth } from '@/contexts/AuthContext';

const ONGLETS = new Set([
  '/soignant/tableau-de-bord', '/soignant/recherche-missions', '/soignant/missions',
  '/soignant/mes-gains', '/soignant/mon-compte', '/etablissement/tableau-de-bord',
  '/etablissement/missions', '/etablissement/missions/creer',
  '/etablissement/messagerie', '/etablissement/mon-compte',
]);

/** Retour = position précédente, nouvel écran = haut, onglet = sa dernière position. */
export function ScrollToTop() {
  const { key, pathname } = useLocation();
  const navigation = useNavigationType();
  const { user } = useAuth();
  const positions = useRef(new Map<string, number>());
  const onglets = useRef(new Map<string, number>());

  useLayoutEffect(() => {
    positions.current.clear();
    onglets.current.clear();
  }, [user?.id]);

  useLayoutEffect(() => {
    const previous = window.history.scrollRestoration;
    window.history.scrollRestoration = 'manual';
    const target = navigation === 'POP'
      ? positions.current.get(key) ?? 0
      : ONGLETS.has(pathname) ? onglets.current.get(pathname) ?? 0 : 0;
    let lastY = target;
    let restoring = true;
    const save = () => { if (!restoring) lastY = window.scrollY; };
    const restore = () => {
      window.scrollTo({ top: target, behavior: 'instant' });
      if (Math.abs(window.scrollY - target) < 2) finish();
    };
    // Une route lazy peut d'abord être plus courte que la liste à restaurer.
    // Arrêt dès que la position est atteinte, ou dès une interaction utilisateur.
    const observer = new ResizeObserver(() => { if (restoring) restore(); });
    const finish = () => {
      restoring = false;
      observer.disconnect();
      clearTimeout(timeout);
      lastY = window.scrollY;
    };
    const timeout = window.setTimeout(finish, 3000);
    // body garde height:100% : sa boîte ne grandit pas avec une liste longue.
    // Observer le contenu effectif permet la reprise après un chargement lazy.
    observer.observe(document.getElementById('app-route-content') ?? document.body);
    window.addEventListener('scroll', save, { passive: true });
    window.addEventListener('wheel', finish, { passive: true });
    window.addEventListener('touchstart', finish, { passive: true });
    window.addEventListener('pointerdown', finish, { passive: true });
    restore();
    return () => {
      positions.current.set(key, lastY);
      if (ONGLETS.has(pathname)) onglets.current.set(pathname, lastY);
      // Historique borné en mémoire, aucune donnée utilisateur sur disque.
      if (positions.current.size > 100) positions.current.delete(positions.current.keys().next().value!);
      observer.disconnect();
      clearTimeout(timeout);
      window.removeEventListener('scroll', save);
      window.removeEventListener('wheel', finish);
      window.removeEventListener('touchstart', finish);
      window.removeEventListener('pointerdown', finish);
      window.history.scrollRestoration = previous;
    };
  }, [key, pathname, navigation, user?.id]);
  return null;
}
