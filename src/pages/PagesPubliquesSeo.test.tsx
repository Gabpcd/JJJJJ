import React, { useEffect } from 'react';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { render, screen, cleanup, fireEvent } from '@testing-library/react';
import { Link, MemoryRouter, Route, Routes, useLocation } from 'react-router-dom';
import { afterEach, describe, expect, it, vi } from 'vitest';
import NotFound from './NotFound';
import Tarifs from './Tarifs';
import APropos from './APropos';
import DevenirSoignant from './DevenirSoignant';
import RecruterSoignants from './RecruterSoignants';
import { jsonLdPage, metaDevenirSoignant, metaInstitutionnelle, metaRecruterSoignants } from '@/lib/seo-routes';

vi.mock('@/components/SEOPageLayout', () => ({
  SEOPageLayout: ({ heroTitle, heroSubtitle, children }: any) => (
    <div><h1>{heroTitle}</h1><p data-testid="accroche">{heroSubtitle}</p>{children}</div>
  ),
}));

const ouvrir = (element: React.ReactElement) => render(<MemoryRouter>{element}</MemoryRouter>);
const robots = () => document.querySelector('meta[name="robots"]')?.getAttribute('content');
const canonical = () => document.querySelector('link[rel="canonical"]')?.getAttribute('href');
const donneesStructurees = () => JSON.parse(document.querySelector('script[data-jolene-ld]')!.textContent!);

afterEach(() => { cleanup(); document.head.innerHTML = ''; });

describe('page introuvable', () => {
  it('n\'est jamais indexable', () => {
    ouvrir(<NotFound />);
    expect(robots()).toBe('noindex, nofollow');
    expect(document.title).toBe('Page introuvable — Jolene');
    expect(screen.getByRole('heading', { level: 1, name: '404' })).toBeInTheDocument();
    expect(screen.getByRole('link', { name: /Retour à l'accueil/ })).toHaveAttribute('href', '/');
  });

  it('reste en noindex d\'une URL inconnue à une autre, sans rechargement', () => {
    // Même mécanique que RouteMeta (src/App.tsx) : à chaque changement de chemin, robots repasse à « index, follow ».
    function RemiseAZero() {
      const { pathname } = useLocation();
      useEffect(() => {
        let meta = document.querySelector('meta[name="robots"]');
        if (!meta) { meta = document.createElement('meta'); meta.setAttribute('name', 'robots'); document.head.appendChild(meta); }
        meta.setAttribute('content', 'index, follow');
      }, [pathname]);
      return null;
    }
    render(
      <MemoryRouter initialEntries={['/inconnue-1']}>
        <RemiseAZero />
        <Link to="/inconnue-2">suivante</Link>
        <Routes><Route path="*" element={<NotFound />} /></Routes>
      </MemoryRouter>,
    );
    expect(robots()).toBe('noindex, nofollow');
    fireEvent.click(screen.getByRole('link', { name: 'suivante' }));
    expect(robots()).toBe('noindex, nofollow');
    expect(canonical()).toBe('https://jolene.app/inconnue-2');
  });
});

describe('pages publiques : la page rendue et le HTML statique disent la même chose', () => {
  it('/tarifs : titre, canonical, H1, accroche et données structurées de seo-routes', () => {
    const meta = metaInstitutionnelle('tarifs');
    ouvrir(<Tarifs />);
    expect(document.title).toBe(meta.title);
    expect(canonical()).toBe('https://jolene.app/tarifs');
    expect(robots()).toBe('index, follow');
    expect(screen.getByRole('heading', { level: 1 })).toHaveTextContent(meta.h1);
    for (const texte of meta.intro) expect(screen.getByText(texte)).toBeInTheDocument();
    // Carte de prix : intitulé, taux HT, taux TTC et lignes « inclus » du HTML statique, tous affichés.
    expect(meta.sections![0].titre).toBe('Commission Jolene');
    expect(meta.sections![0].paragraphes).toEqual(['15 % HT', 'soit 18 % TTC avec TVA à 20 %']);
    for (const texte of [meta.sections![0].titre, ...meta.sections![0].paragraphes!, ...meta.sections![0].liste!]) expect(screen.getByText(texte)).toBeInTheDocument();
    expect(donneesStructurees()).toEqual(JSON.parse(JSON.stringify(jsonLdPage(meta))));
  });

  it('/a-propos : H1 et deux premiers paragraphes de seo-routes', () => {
    const meta = metaInstitutionnelle('a-propos');
    ouvrir(<APropos />);
    expect(document.title).toBe(meta.title);
    expect(screen.getByRole('heading', { level: 1 })).toHaveTextContent(meta.h1);
    expect(screen.getByTestId('accroche')).toHaveTextContent(meta.intro[0]);
    expect(screen.getByText(meta.intro[1])).toBeInTheDocument();
  });

  it('/devenir-soignant : aucune promesse de volume, FAQ identique à la FAQ déclarée', () => {
    const meta = metaDevenirSoignant();
    ouvrir(<DevenirSoignant />);
    expect(document.title).toBe(meta.title);
    expect(screen.getByTestId('accroche')).toHaveTextContent(meta.intro[0]);
    expect(screen.getByTestId('accroche').textContent).not.toMatch(/centaines/);
    for (const f of meta.faq!) expect(screen.getByText(f.q)).toBeInTheDocument();
    const faq = donneesStructurees().find((b: { '@type': string }) => b['@type'] === 'FAQPage');
    expect(faq.mainEntity.map((q: { name: string }) => q.name)).toEqual(meta.faq!.map((f) => f.q));
  });

  it('/recruter-soignants : FAQ affichée = FAQ déclarée', () => {
    const meta = metaRecruterSoignants();
    ouvrir(<RecruterSoignants />);
    expect(screen.getByRole('heading', { level: 1 })).toHaveTextContent(meta.h1);
    for (const f of meta.faq!) {
      expect(screen.getByText(f.q)).toBeInTheDocument();
      expect(screen.getByText(f.r)).toBeInTheDocument();
    }
  });
});

describe('gardes de source', () => {
  const lire = (fichier: string) => readFileSync(path.resolve(__dirname, '../..', fichier), 'utf8');

  it('une page dont SEOHead pose le titre n\'appelle pas usePageTitle (qui le remplaçait après montage)', () => {
    for (const page of ['PageAccueil', 'Tarifs', 'APropos', 'PageContact', 'InfirmiereLiberal', 'Telecharger', 'DevenirSoignant', 'RecruterSoignants', 'NotFound']) {
      expect(lire(`src/pages/${page}.tsx`), page).not.toContain('usePageTitle');
    }
  });

  it('public/sitemap.xml ne liste aucune route que l\'application rend en noindex', () => {
    const app = lire('src/App.tsx');
    const prefixes = /const ROUTES_NOINDEX = \[([\s\S]*?)\];/.exec(app)![1].match(/'[^']+'/g)!.map((p) => p.slice(1, -1));
    expect(prefixes).toContain('/inscription');
    const urls = [...lire('public/sitemap.xml').matchAll(/<loc>https:\/\/jolene\.app([^<]*)<\/loc>/g)].map((m) => m[1] || '/');
    expect(urls.length).toBeGreaterThan(5);
    for (const u of urls) {
      expect(prefixes.some((p) => u === p || u.startsWith(`${p}/`)), u).toBe(false);
    }
  });
});
