import { useLayoutEffect, useRef } from 'react';
import { useLocation, useNavigationType } from 'react-router-dom';
import { useAuth } from '@/contexts/AuthContext';

const ONGLETS = new Set([
  '/soignant/tableau-de-bord', '/soignant/recherche-missions', '/soignant/missions',
  '/soignant/mes-gains', '/soignant/mon-compte', '/etablissement/tableau-de-bord',
  '/etablissement/missions', '/etablissement/missions/creer',
  '/etablissement/messagerie', '/etablissement/mon-compte',
]);

type Position = { y: number; auth: boolean };
const formulaire = () => document.querySelector<HTMLElement>('[data-scroll-restoration="auth"]');
const positionCourante = (): Position => {
  const conteneur = formulaire();
  return { y: conteneur?.scrollTop ?? window.scrollY, auth: !!conteneur };
};

/** Retour = position précédente, nouvel écran = haut, onglet = sa dernière position. */
export function ScrollToTop() {
  const { key, pathname } = useLocation();
  const navigation = useNavigationType();
  const { user } = useAuth();
  const positions = useRef(new Map<string, Position>());
  const onglets = useRef(new Map<string, Position>());
  const precedent = useRef<{ pathname: string; position: Position } | null>(null);

  useLayoutEffect(() => {
    positions.current.clear();
    onglets.current.clear();
    precedent.current = null;
  }, [user?.id]);

  useLayoutEffect(() => {
    const previous = window.history.scrollRestoration;
    window.history.scrollRestoration = 'manual';
    const haut: Position = { y: 0, auth: false };
    const target = navigation === 'POP'
      ? positions.current.get(key) ?? haut
      : precedent.current?.pathname === pathname
        ? precedent.current.position
        : ONGLETS.has(pathname) ? onglets.current.get(pathname) ?? haut : haut;
    let dernierePosition = target;
    let restoring = true;
    let contenuObserve: Element | null = null;
    const save = () => { if (!restoring) dernierePosition = positionCourante(); };
    const restore = () => {
      const conteneur = formulaire();
      if (target.auth && !conteneur) return;
      window.scrollTo({ top: conteneur ? 0 : target.y, behavior: 'instant' });
      if (conteneur) {
        const contenu = conteneur.firstElementChild ?? conteneur;
        if (contenuObserve !== contenu) {
          if (contenuObserve) observer.unobserve(contenuObserve);
          observer.observe(contenu);
          contenuObserve = contenu;
        }
        conteneur.scrollTo({ top: target.y, behavior: 'instant' });
      }
      const courante = positionCourante();
      if (Math.abs(courante.y - target.y) < 2) finish();
    };
    // Une route lazy peut d'abord être plus courte que la liste à restaurer.
    // Arrêt dès que la position est atteinte, ou dès une interaction utilisateur.
    const observer = new ResizeObserver(() => { if (restoring) restore(); });
    const finish = () => {
      restoring = false;
      observer.disconnect();
      mutations.disconnect();
      clearTimeout(timeout);
      dernierePosition = positionCourante();
    };
    const timeout = window.setTimeout(finish, 3000);
    // body garde height:100% : sa boîte ne grandit pas avec une liste longue.
    // Observer le contenu effectif permet la reprise après un chargement lazy.
    const racine = document.getElementById('app-route-content') ?? document.body;
    observer.observe(racine);
    // Un formulaire lazy peut remplacer le chargement sans changer la hauteur
    // extérieure (100dvh). Observer aussi son montage, puis sa carte interne.
    const mutations = new MutationObserver(() => { if (restoring) restore(); });
    mutations.observe(racine, { childList: true, subtree: true });
    window.addEventListener('scroll', save, { passive: true });
    document.addEventListener('scroll', save, { passive: true, capture: true });
    window.addEventListener('wheel', finish, { passive: true });
    window.addEventListener('touchstart', finish, { passive: true });
    window.addEventListener('pointerdown', finish, { passive: true });
    window.addEventListener('keydown', finish);
    restore();
    return () => {
      positions.current.set(key, dernierePosition);
      precedent.current = { pathname, position: dernierePosition };
      if (ONGLETS.has(pathname)) onglets.current.set(pathname, dernierePosition);
      // Historique borné en mémoire, aucune donnée utilisateur sur disque.
      if (positions.current.size > 100) positions.current.delete(positions.current.keys().next().value!);
      observer.disconnect();
      mutations.disconnect();
      clearTimeout(timeout);
      window.removeEventListener('scroll', save);
      document.removeEventListener('scroll', save, true);
      window.removeEventListener('wheel', finish);
      window.removeEventListener('touchstart', finish);
      window.removeEventListener('pointerdown', finish);
      window.removeEventListener('keydown', finish);
      window.history.scrollRestoration = previous;
    };
  }, [key, pathname, navigation, user?.id]);
  return null;
}
