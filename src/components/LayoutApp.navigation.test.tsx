import { lazy } from 'react';
import { act, fireEvent, render, screen } from '@testing-library/react';
import { MemoryRouter, Routes, Route, Link, useNavigate } from 'react-router-dom';
import { describe, expect, it, vi } from 'vitest';
import { AppShell, LayoutApp } from './LayoutApp';

vi.mock('@/components/BarreNavigation', () => ({ BarreNavigation: () => <nav aria-label="Onglets"><Link to="/a">Accueil</Link><Link to="/b">Explorer</Link><Link to="/swipe">Swipe</Link></nav> }));
vi.mock('@/components/DemandePermissionPush', () => ({ DemandePermissionPush: () => null }));
vi.mock('@/components/BandeauHorsLigne', () => ({ BandeauHorsLigne: () => null }));
vi.mock('@/components/SyncHorsLigne', () => ({ SyncHorsLigne: () => null }));
vi.mock('@/components/BandeauInstallerPWA', () => ({ BandeauInstallerPWA: () => null }));
vi.mock('@/components/BandeauOnboardingEtab', () => ({ BandeauOnboardingEtab: () => null }));
vi.mock('@/lib/firebase', () => ({ ecouterMessagesForeground: vi.fn(() => vi.fn()) }));

function Back() { const navigate = useNavigate(); return <button onClick={() => navigate(-1)}>Retour</button>; }
const Page = ({ name, pleinEcran = false }: { name: string; pleinEcran?: boolean }) => <LayoutApp role="SOIGNANT" pleinEcran={pleinEcran}><h1>{name}</h1></LayoutApp>;

describe('navigation avec cadre persistant', () => {
  it('conserve la même navigation pendant le chargement lazy puis le retour, avec un seul main', async () => {
    let resolve!: (value: { default: () => JSX.Element }) => void;
    const SlowPage = lazy(() => new Promise<{ default: () => JSX.Element }>(r => { resolve = r; }));
    render(<MemoryRouter initialEntries={['/a']}><Back /><Routes><Route element={<AppShell role="SOIGNANT" />}>
      <Route path="/a" element={<Page name="Accueil soignant" />} />
      <Route path="/b" element={<SlowPage />} />
    </Route></Routes></MemoryRouter>);
    const navigation = screen.getByRole('navigation');
    fireEvent.click(screen.getByRole('link', { name: 'Explorer' }));
    expect(await screen.findByRole('status')).toBeVisible();
    expect(screen.getByRole('navigation')).toBe(navigation);
    await act(async () => resolve({ default: () => <Page name="Missions disponibles" /> }));
    expect(screen.getByRole('heading', { name: 'Missions disponibles' })).toBeVisible();
    expect(screen.getAllByRole('main')).toHaveLength(1);
    expect(screen.getByRole('navigation')).toBe(navigation);
    fireEvent.click(screen.getByRole('button', { name: 'Retour' }));
    expect(screen.getByRole('heading', { name: 'Accueil soignant' })).toBeVisible();
    expect(screen.getByRole('navigation')).toBe(navigation);
  });

  it('réserve la hauteur du deck puis rétablit le défilement sans remonter la navigation', async () => {
    render(<MemoryRouter initialEntries={['/a']}><Routes><Route element={<AppShell role="SOIGNANT" />}>
      <Route path="/a" element={<Page name="Accueil" />} />
      <Route path="/swipe" element={<Page name="Carte" pleinEcran />} />
    </Route></Routes></MemoryRouter>);
    const navigation = screen.getByRole('navigation');
    fireEvent.click(screen.getByRole('link', { name: 'Swipe' }));
    expect(screen.getByRole('main')).toHaveClass('overflow-hidden');
    fireEvent.click(screen.getByRole('link', { name: 'Accueil' }));
    expect(screen.getByRole('main')).not.toHaveClass('overflow-hidden');
    expect(screen.getByRole('navigation')).toBe(navigation);
  });
});
