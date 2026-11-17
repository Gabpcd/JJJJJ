import React from 'react';
import { fireEvent, render, screen } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import InscriptionSoignant from './InscriptionSoignant';
import { oublierToutesLesSaisies } from '@/lib/saisieInscriptionEnCours';

vi.mock('@/contexts/AuthContext', () => ({ useAuth: () => ({ inscriptionSoignant: vi.fn() }) }));
vi.mock('@/contexts/NotificationContext', () => ({ useNotification: () => ({ afficherNotification: vi.fn() }) }));
vi.mock('@/hooks/useTypesExerciceAutorises', () => ({ useTypesExerciceAutorises: () => ({ typesAutorises: ['SALARIE'], uniqueType: 'SALARIE', loading: false, indisponible: false }) }));
vi.mock('@/components/AuthLayout', () => ({ AuthLayout: ({ children }: any) => <main>{children}</main> }));
vi.mock('@/components/inscription/ApercuMarche', () => ({ ApercuMarche: () => null }));
vi.mock('@/integrations/supabase/client', () => ({ SUPABASE_URL: 'http://127.0.0.1:8895', SUPABASE_PUBLISHABLE_KEY: 'fixture-key', supabase: {} }));

const brouillon = (donnees: Record<string, unknown>) => ({ user_id: 'u-saisie', type_compte: 'SOIGNANT' as const, modifie_le: '', donnees });
const v1 = { prenom: 'Camille', nom: 'Recette', profession: 'IDE', telephone: '0100000000', dateNaissance: '1990-01-01', typesContrat: ['SALARIE'] };
const monter = (donnees: Record<string, unknown>) => render(<MemoryRouter><InscriptionSoignant parcours={brouillon(donnees)} /></MemoryRouter>);
const prenom = () => screen.getByLabelText(/^Prénom \*/) as HTMLInputElement;
const nom = () => screen.getByLabelText(/^Nom \*/) as HTMLInputElement;

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

  it('ouvrir le formulaire sans rien saisir ne fige pas le brouillon (revue B8 #1137, B1)', () => {
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

  it('une saisie annulée par l’utilisateur ne ressort pas au retour', () => {
    const premier = monter(v1);
    fireEvent.change(prenom(), { target: { value: 'Camille-Anne' } });
    fireEvent.change(prenom(), { target: { value: 'Camille' } });
    premier.unmount();
    monter(v1);
    expect(prenom()).toHaveValue('Camille');
  });
});
