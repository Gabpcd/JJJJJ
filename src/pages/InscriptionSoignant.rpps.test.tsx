import React from 'react';
import { act, fireEvent, render, screen, waitFor } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import InscriptionSoignant, { RPPS_VERIFICATION_TIMEOUT_MS } from './InscriptionSoignant';

const mocks = vi.hoisted(() => ({ finaliser: vi.fn(), fetch: vi.fn() }));
vi.mock('@/contexts/AuthContext', () => ({ useAuth: () => ({ inscriptionSoignant: vi.fn() }) }));
vi.mock('@/contexts/NotificationContext', () => ({ useNotification: () => ({ afficherNotification: vi.fn() }) }));
vi.mock('@/hooks/useTypesExerciceAutorises', () => ({ useTypesExerciceAutorises: () => ({ typesAutorises: ['SALARIE'], uniqueType: 'SALARIE', loading: false, indisponible: false }) }));
vi.mock('@/components/AuthLayout', () => ({ AuthLayout: ({ children }: any) => <main>{children}</main> }));
vi.mock('@/components/inscription/ApercuMarche', () => ({ ApercuMarche: () => null }));
vi.mock('@/integrations/supabase/client', () => ({ SUPABASE_URL: 'http://127.0.0.1:8895', SUPABASE_PUBLISHABLE_KEY: 'fixture-key', supabase: {} }));
vi.mock('@/lib/inscriptionProgressive', async importOriginal => ({ ...await importOriginal<typeof import('@/lib/inscriptionProgressive')>(), finaliserProfil: mocks.finaliser }));

const trouve = (professionCorrespond: boolean) => ({ ok: true, json: async () => ({ trouve: true, prenom: 'Camille', nom_api: 'Recette', profession_api: professionCorrespond ? 'IDE' : 'Médecin', profession_correspond: professionCorrespond }) });
const afficher = () => render(<MemoryRouter><InscriptionSoignant parcours={{ user_id: 'fixture', type_compte: 'SOIGNANT', modifie_le: '', donnees: { prenom: 'Camille', nom: 'Recette', profession: 'IDE', telephone: '0100000000', dateNaissance: '1990-01-01', typesContrat: ['SALARIE'] } }} /></MemoryRouter>);

beforeEach(() => {
  vi.clearAllMocks();
  vi.stubGlobal('fetch', mocks.fetch);
  vi.stubGlobal('ResizeObserver', class { observe() {} unobserve() {} disconnect() {} });
});
afterEach(() => { vi.unstubAllGlobals(); vi.useRealTimers(); });

describe('RPPS — la confirmation correspond aux informations actuellement saisies', () => {
  it('signale une profession incompatible sans annoncer de vérification réussie ni finaliser', async () => {
    mocks.fetch.mockResolvedValue(trouve(false));
    afficher();
    fireEvent.change(screen.getByPlaceholderText(/^11 chiffres/), { target: { value: '10000000000' } });
    expect(await screen.findByText(/Ce RPPS correspond à la profession/)).toBeVisible();
    expect(screen.queryByText(/RPPS vérifié dans l’Annuaire Santé/)).not.toBeInTheDocument();
    fireEvent.click(screen.getByRole('button', { name: 'Enregistrer mon profil' }));
    expect(await screen.findByText(/Vérifiez les informations suivantes : cohérence du RPPS/)).toBeVisible();
    expect(mocks.finaliser).not.toHaveBeenCalled();
  });

  it('retire l’ancien succès dès le changement de numéro et attend le nouveau résultat', async () => {
    let repondre!: (value: ReturnType<typeof trouve>) => void;
    mocks.fetch.mockResolvedValueOnce(trouve(true)).mockImplementationOnce(() => new Promise(resolve => { repondre = resolve; }));
    afficher();
    const numero = screen.getByPlaceholderText(/^11 chiffres/);
    fireEvent.change(numero, { target: { value: '10000000000' } });
    expect(await screen.findByText(/RPPS vérifié dans l’Annuaire Santé/)).toBeVisible();
    fireEvent.change(numero, { target: { value: '10000000001' } });
    expect(screen.queryByText(/RPPS vérifié dans l’Annuaire Santé/)).not.toBeInTheDocument();
    expect(screen.getByRole('status')).toHaveTextContent('Vérification en cours');
    expect(screen.getByRole('button', { name: 'Enregistrer mon profil' })).toBeDisabled();
    await waitFor(() => expect(mocks.fetch).toHaveBeenCalledTimes(2));
    await act(async () => { repondre(trouve(true)); });
    expect(await screen.findByText(/RPPS vérifié dans l’Annuaire Santé/)).toBeVisible();
    expect(screen.getByRole('button', { name: 'Enregistrer mon profil' })).toBeEnabled();
    expect(mocks.finaliser).not.toHaveBeenCalled();
  });

  it('sort d’une requête bloquée avec le repli annuaire indisponible, sans fausse vérification', async () => {
    vi.useFakeTimers();
    mocks.fetch.mockImplementation((_url, options) => new Promise((_resolve, reject) => {
      options.signal.addEventListener('abort', () => reject(new DOMException('Aborted', 'AbortError')), { once: true });
    }));
    afficher();
    fireEvent.change(screen.getByPlaceholderText(/^11 chiffres/), { target: { value: '10000000000' } });
    expect(screen.getByRole('button', { name: 'Enregistrer mon profil' })).toBeDisabled();
    await act(async () => { await vi.advanceTimersByTimeAsync(500 + RPPS_VERIFICATION_TIMEOUT_MS); });
    expect(screen.getByText(/Format RPPS valide. La vérification auprès de l'Annuaire Santé sera effectuée/)).toBeVisible();
    expect(screen.queryByText(/RPPS vérifié dans l’Annuaire Santé/)).not.toBeInTheDocument();
    expect(screen.queryByRole('status')).not.toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Enregistrer mon profil' })).toBeEnabled();
    expect(mocks.finaliser).not.toHaveBeenCalled();
  });
});
