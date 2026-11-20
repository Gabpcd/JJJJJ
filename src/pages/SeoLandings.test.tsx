import React from 'react';
import { render, screen, cleanup, within } from '@testing-library/react';
import { MemoryRouter, Route, Routes } from 'react-router-dom';
import { afterEach, describe, expect, it, vi } from 'vitest';
import VilleLanding from './VilleLanding';
import ProfessionLanding from './ProfessionLanding';
import VilleProfessionLanding from './VilleProfessionLanding';
import RecruterTypeLanding from './RecruterTypeLanding';
import GuidesIndex from './GuidesIndex';
import GuideArticle from './GuideArticle';
import BarometreRecrutement from './BarometreRecrutement';
import { getProfessionBySlug, getVilleBySlug } from '@/lib/seo-data';
import { GUIDES_SEO } from '@/lib/seo-contenu/guides';
import { jsonLdPage, metaBarometre, metaEtablissement, metaGuide, metaVille, metaVilleMetier, resoudreEtablissement, resoudreGuide, type PageSEO } from '@/lib/seo-routes';

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
/** Testing Library ramène les espaces (insécables compris) à une espace simple dans le DOM : même traitement pour le texte cherché. */
const normaliser = (texte: string) => texte.replace(/\s+/g, ' ').trim();

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
    // Repères locaux : la phrase BMO, la phrase FINESS et un lien vers chacune des deux sources.
    const reperes = screen.getByRole('complementary', { name: 'Repères locaux à Lyon' });
    expect(reperes).toHaveTextContent(/projets de recrutement d’aides-soignants en 2026/);
    expect(reperes).toHaveTextContent(/À Lyon, le répertoire FINESS recense 44 EHPAD/);
    const sources = within(reperes).getAllByRole('link');
    expect(sources.map((a) => a.getAttribute('href'))).toEqual([
      'https://www.data.gouv.fr/datasets/enquete-besoins-en-main-doeuvre-bmo',
      'https://www.data.gouv.fr/datasets/finess-extraction-du-fichier-des-etablissements',
    ]);
    for (const a of sources) expect(a).toHaveAttribute('rel', 'noopener noreferrer');
    // Chaque paragraphe du HTML statique est affiché une seule fois.
    for (const p of metaVilleMetier(getVilleBySlug('lyon')!, getProfessionBySlug('aide-soignant')!).intro.slice(1)) {
      expect(screen.getAllByText(normaliser(p))).toHaveLength(1);
    }
  });

  it('infirmier : donnée BMO « infirmiers et sages-femmes », page indexée', () => {
    ouvrir('/emploi-soignant/lyon/infirmier-ide');
    expect(robots()).toBe('index, follow');
    expect(screen.getByRole('heading', { level: 1 })).toHaveTextContent('Infirmier (IDE) : missions à Lyon');
    expect(screen.getByRole('complementary', { name: 'Repères locaux à Lyon' })).toHaveTextContent(/projets de recrutement d’infirmiers et de sages-femmes en 2026/);
  });

  it('kinésithérapeute : comptes FINESS seuls, aucune mention BMO, page non indexée', () => {
    ouvrir('/emploi-soignant/lyon/kinesitherapeute');
    expect(screen.queryByText(/BMO/)).not.toBeInTheDocument();
    expect(robots()).toBe('noindex, nofollow');
    const reperes = screen.getByRole('complementary', { name: 'Repères locaux à Lyon' });
    expect(reperes).toHaveTextContent(/le répertoire FINESS recense/);
    expect(within(reperes).getAllByRole('link')).toHaveLength(1);
  });

  it('page ville : établissements recensés, lien vers le baromètre et vers la publication d\'une mission', () => {
    ouvrir('/emploi-soignant/le-havre');
    expect(screen.getByRole('heading', { level: 1 })).toHaveTextContent('Missions soignants au Havre');
    const recenses = screen.getByRole('complementary', { name: 'Établissements recensés au Havre' });
    expect(recenses).toHaveTextContent(normaliser(metaVille(getVilleBySlug('le-havre')!).intro[1]));
    expect(within(recenses).getByRole('link', { name: /baromètre 2026/i })).toHaveAttribute('href', '/barometre-recrutement-soignants-2026');
    expect(screen.getByRole('link', { name: 'Publier une mission' })).toHaveAttribute('href', '/recruter-soignants');
  });
});

describe('pages par type d\'établissement, guides et baromètre', () => {
  const ouvrirPage = (chemin: string) => render(
    <MemoryRouter initialEntries={[chemin]}>
      <Routes>
        <Route path="/recruter-soignants/:type" element={<RecruterTypeLanding />} />
        <Route path="/guides" element={<GuidesIndex />} />
        <Route path="/guides/:slug" element={<GuideArticle />} />
        <Route path="/barometre-recrutement-soignants-2026" element={<BarometreRecrutement />} />
      </Routes>
    </MemoryRouter>,
  );
  /** Tout texte du HTML statique (hors premier paragraphe, porté par le hero simulé) doit être affiché. */
  const attendreTextes = (page: PageSEO) => {
    const textes = [
      ...page.intro.slice(1),
      ...(page.sections ?? []).flatMap((s) => [s.titre, ...(s.paragraphes ?? []), ...(s.liste ?? []), ...(s.points ?? []).flatMap((p) => [p.titre, p.texte])]),
      ...(page.faq ?? []).flatMap((f) => [f.q, f.r]),
      ...page.liens.map((l) => l.label),
    ];
    for (const t of textes) expect(screen.getAllByText(normaliser(t)).length, t.slice(0, 60)).toBeGreaterThanOrEqual(1);
  };

  it('type inconnu : noindex et liens vers les types connus', () => {
    ouvrirPage('/recruter-soignants/inconnu');
    expect(robots()).toBe('noindex, nofollow');
    expect(screen.getByRole('link', { name: 'EHPAD' })).toHaveAttribute('href', '/recruter-soignants/ehpad');
  });

  it('EHPAD : tout le texte du HTML statique est affiché, données structurées identiques', () => {
    const meta = metaEtablissement(resoudreEtablissement('ehpad')!);
    ouvrirPage('/recruter-soignants/ehpad');
    expect(robots()).toBe('index, follow');
    expect(document.title).toBe(meta.title);
    expect(document.querySelector('link[rel="canonical"]')).toHaveAttribute('href', 'https://jolene.app/recruter-soignants/ehpad');
    expect(screen.getByRole('heading', { level: 1 })).toHaveTextContent(meta.h1);
    attendreTextes(meta);
    expect(JSON.parse(document.querySelector('script[data-jolene-ld]')!.textContent!)).toEqual(JSON.parse(JSON.stringify(jsonLdPage(meta))));
    expect(screen.getByRole('link', { name: 'Aide-soignant' })).toHaveAttribute('href', '/metier/aide-soignant');
  });

  it('guide inconnu : noindex ; guide connu : texte complet, sources officielles, liste numérotée', () => {
    ouvrirPage('/guides/inconnu');
    expect(robots()).toBe('noindex, nofollow');
    cleanup();
    const meta = metaGuide(resoudreGuide('vacations-etablissement-de-sante')!);
    ouvrirPage('/guides/vacations-etablissement-de-sante');
    expect(robots()).toBe('index, follow');
    expect(document.title).toBe(meta.title);
    attendreTextes(meta);
    const cumul = screen.getByRole('link', { name: /un agent public peut-il cumuler/i });
    expect(cumul).toHaveAttribute('href', 'https://www.service-public.gouv.fr/particuliers/vosdroits/F1648');
    expect(cumul).toHaveAttribute('target', '_blank');
    expect(document.querySelectorAll('ol li').length).toBe(4);
  });

  it('sommaire des guides : un lien par guide', () => {
    ouvrirPage('/guides');
    for (const g of GUIDES_SEO) expect(screen.getByRole('link', { name: g.titre })).toHaveAttribute('href', `/guides/${g.slug}`);
  });

  it('baromètre : tableau accessible, une ligne par département', () => {
    const meta = metaBarometre();
    ouvrirPage('/barometre-recrutement-soignants-2026');
    expect(document.title).toBe(meta.title);
    const tableau = screen.getByRole('table', { name: /Projets de recrutement déclarés pour 2026/ });
    expect(within(tableau).getAllByRole('row')).toHaveLength(1 + meta.sections![1].tableau!.lignes.length);
    expect(within(tableau).getAllByRole('columnheader')).toHaveLength(8);
    expect(within(tableau).getByRole('rowheader', { name: 'Paris (75)' })).toBeInTheDocument();
    // Zone défilante atteignable au clavier (tableau plus large qu'un écran de téléphone).
    expect(tableau.closest('[role="region"]')).toHaveAttribute('tabindex', '0');
  });
});
