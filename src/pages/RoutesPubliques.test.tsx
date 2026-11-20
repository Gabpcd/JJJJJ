import React, { Suspense } from 'react';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { render, screen, cleanup, waitFor } from '@testing-library/react';
import { MemoryRouter, Route, Routes } from 'react-router-dom';
import { afterEach, describe, expect, it, vi } from 'vitest';
import RoutesPubliques from './RoutesPubliques';
import { toutesLesRoutesSeo } from '@/lib/seo-routes';

vi.mock('@/components/SEOPageLayout', () => ({
  SEOPageLayout: ({ heroTitle, children }: any) => <div><h1>{heroTitle}</h1>{children}</div>,
}));

/** Même montage que src/App.tsx : une route déclarée, puis « * » qui délègue à RoutesPubliques. */
const ouvrir = (chemin: string) => render(
  <MemoryRouter initialEntries={[chemin]}>
    <Suspense fallback={<p>chargement</p>}>
      <Routes>
        <Route path="/recruter-soignants" element={<h1>Pilier déclaré dans App.tsx</h1>} />
        <Route path="*" element={<RoutesPubliques />} />
      </Routes>
    </Suspense>
  </MemoryRouter>,
);
const robots = () => document.querySelector('meta[name="robots"]')?.getAttribute('content');

afterEach(() => { cleanup(); document.head.innerHTML = ''; });

describe('routes publiques montées sous « * »', () => {
  it.each([
    ['/recruter-soignants/ehpad', 'Remplacer un soignant en EHPAD'],
    ['/guides', 'Guides du remplacement en santé'],
    ['/guides/premiere-mission-de-remplacement', 'Première mission de remplacement : la check-list du soignant'],
    ['/barometre-recrutement-soignants-2026', 'Baromètre 2026 du recrutement de soignants, département par département'],
  ])('%s affiche sa page, indexable', async (chemin, h1) => {
    ouvrir(chemin);
    expect(await screen.findByRole('heading', { level: 1, name: h1 })).toBeInTheDocument();
    // SEOHead écrit ces balises dans un effet : le titre peut être affiché avant qu'elles soient posées.
    await waitFor(() => expect(robots()).toBe('index, follow'));
    await waitFor(() => expect(document.querySelector('link[rel="canonical"]')).toHaveAttribute('href', `https://jolene.app${chemin}`));
  });

  it('une URL inconnue affiche la page 404, en noindex', async () => {
    ouvrir('/adresse-inconnue/sous-chemin');
    expect(await screen.findByRole('heading', { level: 1, name: '404' })).toBeInTheDocument();
    await waitFor(() => expect(robots()).toBe('noindex, nofollow'));
  });

  it('une route déclarée dans App.tsx reste prioritaire', async () => {
    ouvrir('/recruter-soignants');
    expect(await screen.findByRole('heading', { level: 1, name: 'Pilier déclaré dans App.tsx' })).toBeInTheDocument();
  });

  it('chaque page statique de contenu a sa route, ici ou dans App.tsx', () => {
    const lire = (f: string) => readFileSync(path.resolve(__dirname, '../..', f), 'utf8');
    const app = lire('src/App.tsx');
    const publiques = lire('src/pages/RoutesPubliques.tsx');
    const motifs = [...app.matchAll(/<Route path="([^"*]+)"/g)].map((m) => m[1])
      .concat([...publiques.matchAll(/<Route path="([^"*]+)"/g)].map((m) => `/${m[1]}`));
    const correspond = (motif: string, chemin: string) => new RegExp(`^${motif.replace(/:[^/]+/g, '[^/]+')}$`).test(chemin);
    for (const page of toutesLesRoutesSeo()) {
      expect(motifs.some((m) => correspond(m, page.path)), page.path).toBe(true);
    }
    // App.tsx ne déclare aucune de ces routes : ses numéros de ligne sont cités par docs/mobile-swift/PARITE_ETABLISSEMENT.md.
    expect(app).not.toMatch(/<Route path="\/(guides|barometre|recruter-soignants\/:type)/);
    expect(app).toContain('<Route path="*" element={<RoutesPubliques />} />');
  });
});
