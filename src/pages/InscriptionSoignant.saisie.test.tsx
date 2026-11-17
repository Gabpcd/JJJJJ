import React from 'react';
import { fireEvent, render, screen, waitFor } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import InscriptionSoignant from './InscriptionSoignant';
import { oublierToutesLesSaisies, reprendreSaisie } from '@/lib/saisieInscriptionEnCours';

vi.mock('@/contexts/AuthContext', () => ({ useAuth: () => ({ inscriptionSoignant: vi.fn() }) }));
vi.mock('@/contexts/NotificationContext', () => ({ useNotification: () => ({ afficherNotification: vi.fn() }) }));
vi.mock('@/hooks/useTypesExerciceAutorises', () => ({ useTypesExerciceAutorises: () => ({ typesAutorises: ['SALARIE'], uniqueType: 'SALARIE', loading: false, indisponible: false }) }));
vi.mock('@/components/AuthLayout', () => ({ AuthLayout: ({ children }: any) => <main>{children}</main> }));
vi.mock('@/components/inscription/ApercuMarche', () => ({ ApercuMarche: () => null }));
// Double de Supabase : le brouillon serveur fusionne comme fn_enregistrer_parcours_inscription
// (donnees || p_donnees) et renvoie la ligne entière ; l'envoi du profil échoue.
const sb = vi.hoisted(() => ({ serveur: { donnees: {} as Record<string, unknown> } }));
vi.mock('@/integrations/supabase/client', () => ({
  SUPABASE_URL: 'http://127.0.0.1:8895',
  SUPABASE_PUBLISHABLE_KEY: 'fixture-key',
  supabase: {
    rpc: async (nom: string, args: { p_donnees?: Record<string, unknown> }) => {
      if (nom !== 'fn_enregistrer_parcours_inscription') return { data: null, error: null };
      sb.serveur.donnees = { ...sb.serveur.donnees, ...args.p_donnees };
      return { data: { user_id: 'u-saisie', type_compte: 'SOIGNANT', modifie_le: '', donnees: { ...sb.serveur.donnees } }, error: null };
    },
    auth: { getSession: async () => ({ data: { session: { access_token: 'fixture', user: { id: 'u-saisie', email: 'u@example.invalid' } } } }), refreshSession: async () => ({ error: null }) },
    functions: { invoke: async () => ({ data: { ok: false, code: 'RPPS_API_UNAVAILABLE', message: 'Annuaire Santé temporairement indisponible. Votre saisie est conservée.' }, error: null }) },
  },
}));

const brouillon = (donnees: Record<string, unknown>) => ({ user_id: 'u-saisie', type_compte: 'SOIGNANT' as const, modifie_le: '', donnees });
const v1 = { prenom: 'Camille', nom: 'Recette', profession: 'IDE', telephone: '0100000000', dateNaissance: '1990-01-01', typesContrat: ['SALARIE'] };
const monter = (donnees: Record<string, unknown>) => { sb.serveur.donnees = { ...donnees }; return render(<MemoryRouter><InscriptionSoignant parcours={brouillon(donnees)} /></MemoryRouter>); };
const prenom = () => screen.getByLabelText(/^Prénom \*/) as HTMLInputElement;
const nom = () => screen.getByLabelText(/^Nom \*/) as HTMLInputElement;
const telephone = () => screen.getByLabelText(/^Téléphone \*/) as HTMLInputElement;

beforeEach(() => {
  oublierToutesLesSaisies();
  vi.stubGlobal('ResizeObserver', class { observe() {} unobserve() {} disconnect() {} });
});

describe('formulaire soignant — saisie rendue après une page ouverte depuis le formulaire', () => {
  it('rend la saisie au remontage quand le brouillon serveur n’a pas changé', () => {
    const premier = monter(v1);
    fireEvent.change(prenom(), { target: { value: 'Camille-Anne' } });
    premier.unmount();
    monter(v1);
    expect(prenom()).toHaveValue('Camille-Anne');
  });

  it('un brouillon corrigé ailleurs l’emporte sur l’onglet resté ouvert (revue B8 #1137, B1)', () => {
    monter(v1).unmount();
    // Correction faite ailleurs (autre appareil), enregistrée côté serveur.
    monter({ ...v1, nom: 'Recette-Martin', prenom: 'Camila' });
    expect(nom()).toHaveValue('Recette-Martin');
    expect(prenom()).toHaveValue('Camila');
  });

  it('une saisie faite sur un brouillon devenu obsolète cède la place au brouillon serveur', () => {
    const premier = monter(v1);
    fireEvent.change(prenom(), { target: { value: 'Camille-Anne' } });
    premier.unmount();
    monter({ ...v1, nom: 'Recette-Martin' });
    expect(nom()).toHaveValue('Recette-Martin');
    expect(prenom()).toHaveValue('Camille');
  });

  it('après un envoi refusé, une correction survit au retour (revue B8 n°2 #1137, m1)', async () => {
    const premier = monter(v1);
    fireEvent.click(screen.getByRole('button', { name: 'Enregistrer mon profil' }));
    expect(await screen.findByText(/Votre saisie est conservée/)).toBeVisible();
    // Le brouillon serveur porte maintenant la saisie envoyée (écrite avant l'envoi).
    expect(sb.serveur.donnees).toMatchObject({ telephone: '0100000000', rpps: '' });
    fireEvent.change(telephone(), { target: { value: '0200000000' } });
    premier.unmount();
    monter(sb.serveur.donnees);
    expect(telephone()).toHaveValue('0200000000');
  });

  it('« Enregistrer et continuer plus tard » laisse le brouillon serveur seul porter la saisie', async () => {
    monter(v1);
    fireEvent.change(prenom(), { target: { value: 'Camille-Anne' } });
    fireEvent.click(screen.getByRole('button', { name: 'Enregistrer et continuer plus tard' }));
    await waitFor(() => expect(sb.serveur.donnees).toMatchObject({ prenom: 'Camille-Anne' }));
    await waitFor(() => expect(reprendreSaisie(brouillon(sb.serveur.donnees)).depuisOnglet).toBe(false));
  });

  it('une saisie annulée par l’utilisateur ne ressort pas au retour', () => {
    const premier = monter(v1);
    fireEvent.change(prenom(), { target: { value: 'Camille-Anne' } });
    fireEvent.change(prenom(), { target: { value: 'Camille' } });
    premier.unmount();
    monter(v1);
    expect(prenom()).toHaveValue('Camille');
  });
});
