import React from 'react';
import { fireEvent, render, screen } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import InscriptionEtablissement from './InscriptionEtablissement';
import { oublierToutesLesSaisies } from '@/lib/saisieInscriptionEnCours';

vi.mock('@/contexts/AuthContext', () => ({ useAuth: () => ({ inscriptionEtablissement: vi.fn() }) }));
vi.mock('@/contexts/NotificationContext', () => ({ useNotification: () => ({ afficherNotification: vi.fn() }) }));
vi.mock('@/components/AuthLayout', () => ({ AuthLayout: ({ children }: any) => <main>{children}</main> }));
vi.mock('@/components/FooterLegal', () => ({ FooterLegal: () => null }));
vi.mock('@/components/CaptchaTurnstile', () => ({ CaptchaTurnstile: () => null }));
vi.mock('@/integrations/supabase/client', () => ({ SUPABASE_URL: 'http://127.0.0.1:8895', SUPABASE_PUBLISHABLE_KEY: 'fixture-key', supabase: { rpc: vi.fn(async () => ({ data: null, error: null })), functions: { invoke: vi.fn(async () => ({ data: null, error: null })) } } }));

const brouillon = (donnees: Record<string, unknown>) => ({ user_id: 'u-etab', type_compte: 'ETABLISSEMENT' as const, modifie_le: '', donnees });
const v1 = { nom: 'Résidence des Tilleuls', ville: 'Paris', type: 'EHPAD' };
const monter = (donnees: Record<string, unknown>) => render(<MemoryRouter><InscriptionEtablissement parcours={brouillon(donnees)} /></MemoryRouter>);
const nom = () => screen.getByLabelText("Nom de l'établissement *", { exact: true }) as HTMLInputElement;
const ville = () => screen.getByLabelText('Ville *', { exact: true }) as HTMLInputElement;

beforeEach(() => {
  oublierToutesLesSaisies();
  vi.stubGlobal('ResizeObserver', class { observe() {} unobserve() {} disconnect() {} });
});

describe('formulaire établissement — saisie rendue après une page ouverte depuis le formulaire', () => {
  it('rend la saisie au remontage quand le brouillon serveur n’a pas changé', () => {
    const premier = monter(v1);
    fireEvent.change(ville(), { target: { value: 'Lyon' } });
    premier.unmount();
    monter(v1);
    expect(ville()).toHaveValue('Lyon');
  });

  it('une correction enregistrée ailleurs n’est pas écrasée par l’onglet resté ouvert (revue B8 #1137, B1)', () => {
    monter(v1).unmount();
    monter({ ...v1, nom: 'Résidence des Tilleuls — Paris 15' });
    expect(nom()).toHaveValue('Résidence des Tilleuls — Paris 15');
  });

  it('une saisie faite sur un brouillon devenu obsolète cède la place au brouillon serveur', () => {
    const premier = monter(v1);
    fireEvent.change(ville(), { target: { value: 'Lyon' } });
    premier.unmount();
    monter({ ...v1, nom: 'Résidence des Tilleuls — Paris 15' });
    expect(nom()).toHaveValue('Résidence des Tilleuls — Paris 15');
    expect(ville()).toHaveValue('Paris');
  });
});
