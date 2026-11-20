import { lazy } from 'react';
import { Route, Routes } from 'react-router-dom';

const RecruterTypeLanding = lazy(() => import('./RecruterTypeLanding'));
const GuidesIndex = lazy(() => import('./GuidesIndex'));
const GuideArticle = lazy(() => import('./GuideArticle'));
const BarometreRecrutement = lazy(() => import('./BarometreRecrutement'));
const NotFound = lazy(() => import('./NotFound'));

/**
 * Routes publiques de contenu (stratégie SEO) et page 404, montées par la route « * » de
 * `src/App.tsx`.
 *
 * Elles vivent ici, et non dans App.tsx, parce que `docs/mobile-swift/PARITE_ETABLISSEMENT.md`
 * cite le NUMÉRO DE LIGNE de chaque route établissement d'App.tsx (garde
 * `tests/node/contrats-etablissement-ios.node.mjs`, et CI iOS relancée à chaque modification de
 * ce document). Ajouter une route de contenu ici ne décale aucune de ces lignes.
 *
 * Routes descendantes d'une route « * » : leurs chemins sont relatifs à la racine, sans « / »
 * initial. Une route déclarée dans App.tsx reste prioritaire (elle ne passe jamais par ici).
 * Les pages restent chargées à la demande, sous le `Suspense` d'App.tsx.
 */
export default function RoutesPubliques() {
  return (
    <Routes>
      <Route path="recruter-soignants/:type" element={<RecruterTypeLanding />} />
      <Route path="guides" element={<GuidesIndex />} />
      <Route path="guides/:slug" element={<GuideArticle />} />
      <Route path="barometre-recrutement-soignants-2026" element={<BarometreRecrutement />} />
      <Route path="*" element={<NotFound />} />
    </Routes>
  );
}
