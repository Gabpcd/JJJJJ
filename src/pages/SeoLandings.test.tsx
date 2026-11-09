import React from 'react';
import { render, screen, cleanup } from '@testing-library/react';
import { MemoryRouter, Route, Routes } from 'react-router-dom';
import { afterEach, describe, expect, it, vi } from 'vitest';
import VilleLanding from './VilleLanding';
import ProfessionLanding from './ProfessionLanding';
import VilleProfessionLanding from './VilleProfessionLanding';

vi.mock('@/components/MissionsPubliquesSEO', () => ({ MissionsPubliquesSEO: () => null }));
vi.mock('@/components/SEOPageLayout', () => ({
  SEOPageLayout: ({ heroTitle, ctaHref, children }: any) => (
    <div><h1>{heroTitle}</h1><a data-testid="cta" href={ctaHref}>cta</a>{children}</div>
  ),
}));

function ouvrir(chemin: string) {
  return render(
    <MemoryRouter initialEntries={[chemin]}>
      <Routes>
        <Route path="/emploi-soignant/:ville" element={<VilleLanding />} />
        <Route path="/emploi-soignant/:ville/:profession" element={<VilleProfessionLanding />} />
        <Route path="/metier/:profession" element={<ProfessionLanding />} />
      </Routes>
    </MemoryRouter>,
  );
}
const robots = () => document.querySelector('meta[name="robots"]')?.getAttribute('content');

afterEach(() => { cleanup(); document.head.innerHTML = ''; });

describe('pages SEO : slug inconnu = noindex', () => {
  it('ville inconnue', () => {
    ouvrir('/emploi-soignant/ville-qui-nexiste-pas');
    expect(robots()).toBe('noindex, nofollow');
    expect(screen.getByRole('link', { name: 'Paris' })).toHaveAttribute('href', '/emploi-soignant/paris');
  });

  it('métier inconnu', () => {
    ouvrir('/metier/metier-inconnu');
    expect(robots()).toBe('noindex, nofollow');
    expect(document.querySelector('a[href="/metier/infirmier-ide"]')).not.toBeNull();
  });

  it('ville × métier hors périmètre ou inconnue', () => {
    ouvrir('/emploi-soignant/paris/pharmacien');
    expect(robots()).toBe('noindex, nofollow');
    expect(document.querySelector('a[href="/emploi-soignant/paris/infirmier-ide"]')).not.toBeNull();
    cleanup();
    ouvrir('/emploi-soignant/inconnue/medecin');
    expect(robots()).toBe('noindex, nofollow');
  });

  it('ville connue hors périmètre ville × métier : liens vers la page ville et les pages métier, jamais vers des pages non référencées', () => {
    ouvrir('/emploi-soignant/bourges/infirmier-ide');
    expect(robots()).toBe('noindex, nofollow');
    const hrefs = [...document.querySelectorAll('a')].map((a) => a.getAttribute('href'));
    expect(hrefs).toContain('/emploi-soignant/bourges');
    expect(hrefs).toContain('/metier/infirmier-ide');
    expect(hrefs.filter((h) => h?.startsWith('/emploi-soignant/bourges/'))).toEqual([]);
  });
});

describe('pages SEO connues', () => {
  it('ville connue : indexable', () => {
    ouvrir('/emploi-soignant/lyon');
    expect(robots()).toBe('index, follow');
    expect(document.title).toBe('Missions soignants à Lyon | Jolene Santé');
    expect(document.querySelector('a[href="/emploi-soignant/lyon/aide-soignant"]')).not.toBeNull();
  });

  it('ville × métier : indexable, canonical, CTA avec UTM organiques', () => {
    ouvrir('/emploi-soignant/lyon/aide-soignant');
    expect(robots()).toBe('index, follow');
    expect(document.title).toBe('Aide-soignant à Lyon : missions et remplacements | Jolene Santé');
    expect(screen.getByRole('heading', { level: 1 })).toHaveTextContent('Aide-soignant : missions à Lyon');
    expect(document.querySelector('link[rel="canonical"]')).toHaveAttribute('href', 'https://jolene.app/emploi-soignant/lyon/aide-soignant');
    const url = new URL(screen.getByTestId('cta').getAttribute('href')!, 'https://jolene.app');
    expect(url.pathname).toBe('/inscription/soignant');
    expect(Object.fromEntries(url.searchParams)).toEqual({
      profession: 'AS',
      ville: 'Lyon',
      utm_source: 'seo',
      utm_medium: 'organic',
      utm_campaign: 'seo-ville-metier',
      utm_content: 'lyon-aide-soignant',
    });
    expect(screen.getByText(/Enquête BMO 2026, France Travail \(données ouvertes/)).toBeInTheDocument();
  });

  it('ville × métier sans donnée BMO (IDE) : aucune mention BMO, page non indexée', () => {
    ouvrir('/emploi-soignant/lyon/infirmier-ide');
    expect(screen.queryByText(/BMO/)).not.toBeInTheDocument();
    expect(robots()).toBe('noindex, nofollow');
    expect(screen.getByRole('heading', { level: 1 })).toHaveTextContent('Infirmier (IDE) : missions à Lyon');
  });
});
