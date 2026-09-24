import React from 'react';
import { act, fireEvent, render, screen, waitFor } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import PageParrainage from './PageParrainage';

const mocks = vi.hoisted(() => ({
  from: vi.fn(), rpc: vi.fn(), clipboard: vi.fn(), toastError: vi.fn(),
  profil: { data: null, error: null } as { data: any; error: unknown },
}));
vi.mock('@/contexts/AuthContext', () => ({ useAuth: () => ({ user: { id: 'parrain-test' } }) }));
vi.mock('@/integrations/supabase/client', () => ({ supabase: { from: mocks.from, rpc: mocks.rpc } }));
vi.mock('@/lib/handleError', () => ({ handleErrorSilent: vi.fn() }));
vi.mock('@/components/LayoutApp', () => ({ LayoutApp: ({ children }: any) => <main>{children}</main> }));
vi.mock('@/components/SEOHead', () => ({ SEOHead: () => null }));
vi.mock('sonner', () => ({ toast: { error: mocks.toastError } }));
vi.mock('qrcode.react', () => ({ QRCodeSVG: ({ value, ...props }: any) => <svg role="img" data-value={value} aria-label={props['aria-label']} /> }));

const afficher = () => render(<MemoryRouter><PageParrainage /></MemoryRouter>);
const lien = 'https://jolene.app/inscription/soignant?ref=JO-ABC123';
function aucunPartagePersonnel() {
  expect(screen.queryByRole('button', { name: /Copier le lien|Copier le code parrainage/ })).not.toBeInTheDocument();
  expect(screen.queryByRole('img', { name: /QR code/ })).not.toBeInTheDocument();
  expect(screen.queryByRole('link', { name: /^(WhatsApp|SMS|Email|LinkedIn)$/ })).not.toBeInTheDocument();
  expect(document.querySelector('[href*="ref="]')).toBeNull();
}

beforeEach(() => {
  vi.clearAllMocks();
  mocks.profil = { data: null, error: null };
  mocks.from.mockImplementation(() => {
    const builder = { select: () => builder, eq: () => builder, maybeSingle: () => Promise.resolve(mocks.profil) };
    return builder;
  });
  mocks.rpc.mockResolvedValue({ data: { filleuls: [] }, error: null });
  mocks.clipboard.mockResolvedValue(undefined);
  Object.defineProperty(navigator, 'clipboard', { configurable: true, value: { writeText: mocks.clipboard } });
});

describe('Parrainage — partage attribuable et états de compte', () => {
  it('ne propose aucun lien personnel pendant le chargement', async () => {
    let terminer!: (value: unknown) => void;
    mocks.rpc.mockReturnValue(new Promise(resolve => { terminer = resolve; }));
    afficher();
    expect(screen.getByRole('status')).toHaveTextContent('Chargement de votre parrainage');
    aucunPartagePersonnel();
    await act(async () => terminer({ data: { filleuls: [] }, error: null }));
  });

  it('explique le compte sans dossier sans générer ni partager de code vide', async () => {
    afficher();
    expect(await screen.findByRole('heading', { name: 'Votre lien de parrainage n’est pas encore disponible' })).toBeInTheDocument();
    aucunPartagePersonnel();
    expect(screen.getByRole('link', { name: 'Explorer les missions' })).toHaveAttribute('href', '/soignant/recherche-missions');
    expect(screen.getByRole('link', { name: 'Préparer mon dossier' })).toHaveAttribute('href', '/soignant/profil');
    expect(mocks.rpc).toHaveBeenCalledTimes(1);
    expect(mocks.rpc).toHaveBeenCalledWith('fn_obtenir_mes_parrainages');
    expect(mocks.clipboard).not.toHaveBeenCalled();
  });

  it('ne partage pas un code composé d’espaces et permet de réessayer', async () => {
    mocks.profil.data = { code_parrainage: '  ', badge_ambassadeur: false };
    afficher();
    expect(await screen.findByRole('heading', { name: 'Votre lien de parrainage n’est pas encore disponible' })).toBeInTheDocument();
    aucunPartagePersonnel();
    expect(screen.getByRole('button', { name: 'Réessayer' })).toBeEnabled();
  });

  it.each(['profil', 'rpc', 'metier'])('distingue une erreur %s d’un état vide, puis restaure les liens au réessai', async (source) => {
    mocks.profil.data = { code_parrainage: 'JO-ABC123' };
    if (source === 'profil') mocks.profil.error = new Error('503');
    if (source === 'rpc') mocks.rpc.mockResolvedValue({ data: null, error: new Error('503') });
    if (source === 'metier') mocks.rpc.mockResolvedValue({ data: { error: 'Accès refusé' }, error: null });
    afficher();
    expect(await screen.findByRole('alert')).toHaveTextContent('Parrainage indisponible');
    aucunPartagePersonnel();
    mocks.profil.error = null;
    mocks.rpc.mockResolvedValue({ data: { filleuls: [] }, error: null });
    fireEvent.click(screen.getByRole('button', { name: 'Réessayer' }));
    expect(await screen.findByRole('button', { name: 'Copier le lien' })).toBeEnabled();
    expect(screen.queryByRole('alert')).not.toBeInTheDocument();
  });

  it('emploie le même code attribué dans la copie, le QR et chaque destination', async () => {
    mocks.profil.data = { code_parrainage: ' JO-ABC123 ', badge_ambassadeur: true };
    afficher();
    fireEvent.click(await screen.findByRole('button', { name: 'Copier le lien' }));
    await waitFor(() => expect(mocks.clipboard).toHaveBeenCalledWith(lien));
    expect(screen.getByRole('img', { name: /QR code/ })).toHaveAttribute('data-value', lien);
    for (const canal of ['WhatsApp', 'SMS', 'Email', 'LinkedIn']) {
      expect(decodeURIComponent(screen.getByRole('link', { name: canal }).getAttribute('href')!)).toContain(lien);
    }
    fireEvent.click(screen.getByRole('button', { name: 'Copier le code parrainage' }));
    await waitFor(() => expect(mocks.clipboard).toHaveBeenCalledWith('JO-ABC123'));
  });

  it('ne confirme pas une copie qui échoue', async () => {
    mocks.profil.data = { code_parrainage: 'JO-ABC123' };
    mocks.clipboard.mockRejectedValue(new Error('Clipboard denied'));
    afficher();
    fireEvent.click(await screen.findByRole('button', { name: 'Copier le lien' }));
    await waitFor(() => expect(mocks.toastError).toHaveBeenCalled());
    expect(screen.queryByRole('button', { name: 'Copié !' })).not.toBeInTheDocument();
  });

  it('conserve les montants et statuts reçus, sans confondre badge, seuil et versement', async () => {
    mocks.profil.data = { code_parrainage: 'JO-ABC123', badge_ambassadeur: false };
    mocks.rpc.mockResolvedValue({ data: { filleuls: [
      { filleul_id: '1', prenom: 'Alice', statut: 'INSCRIT', gmv_cumule_filleul: 320, reste_gmv_avant_prime: 180, seuil_gmv: 500 },
      { filleul_id: '2', prenom: 'Bob', statut: 'VALIDE', premiere_mission_le: '2026-09-01', gmv_cumule_filleul: 500, reste_gmv_avant_prime: 0, seuil_gmv: 500, seuil_atteint: false },
      { filleul_id: '3', prenom: 'Camille', statut: 'VALIDE', prime_versee_le: '2026-09-02', gmv_cumule_filleul: 800, reste_gmv_avant_prime: 0, seuil_gmv: 500 },
    ] }, error: null });
    afficher();
    expect(await screen.findByText('Plus que 180 € de missions avant vos primes')).toBeInTheDocument();
    expect(screen.getByText('Montant de missions atteint — prime non déclenchée')).toBeInTheDocument();
    expect(screen.getByText('💰 Primes versées')).toBeInTheDocument();
    expect(screen.queryByText('✅ Débloqué !')).not.toBeInTheDocument();
  });
});
