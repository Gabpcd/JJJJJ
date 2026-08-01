import React from 'react';
import { act, fireEvent, render, screen, waitFor, within } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { FormulaireMission } from './FormulaireMission';

type ReponseRpc = { data: unknown; error: unknown };

class ResizeObserverMock {
  observe() {}
  unobserve() {}
  disconnect() {}
}

vi.stubGlobal('ResizeObserver', ResizeObserverMock);
Element.prototype.scrollIntoView = vi.fn();

const mocks = vi.hoisted(() => ({
  rpc: vi.fn(),
  afficherNotification: vi.fn(),
  recapData: null as Record<string, unknown> | null,
}));

vi.mock('@/contexts/AuthContext', () => ({
  useAuth: () => ({ user: { id: 'etablissement-test', email: 'etab-test@jolene.app' } }),
}));

vi.mock('@/contexts/NotificationContext', () => ({
  useNotification: () => ({ afficherNotification: mocks.afficherNotification }),
}));

vi.mock('@/integrations/supabase/client', () => ({
  supabase: {
    rpc: mocks.rpc,
    from: vi.fn(() => {
      throw new Error('Aucune lecture de table attendue dans ce parcours de création.');
    }),
  },
}));

vi.mock('@/components/WarningRist', () => ({ WarningRist: () => null }));
vi.mock('@/components/EncartCommissionDegressif', () => ({ EncartCommissionDegressif: () => null }));
vi.mock('@/components/mission/ModalRecapMission', () => ({
  ModalRecapMission: ({ data, onConfirmer }: { data: Record<string, unknown>; onConfirmer: () => void }) => {
    mocks.recapData = data;
    return (
      <div role="dialog" aria-label="Récapitulatif avant publication">
        <p>Récapitulatif avant publication</p>
        <p>{String(data.intitule)}</p>
        <p>{String(data.profession)}</p>
        <button type="button" onClick={onConfirmer}>Confirmer la publication</button>
      </div>
    );
  },
}));

function promesseControlee<T>() {
  let resolve!: (value: T) => void;
  const promise = new Promise<T>((res) => {
    resolve = res;
  });
  return { promise, resolve };
}

const etablissementComplet = {
  id: 'etablissement-test',
  type: 'CLINIQUE_PRIVEE',
  est_secteur_public: false,
  rist_plafond_actif: false,
  taux_commission_negocie: 15,
  tolerance_gps_metres: 100,
  siret: '12345678901234',
  contrat_service_signe: true,
};

async function remplirChampsEtPlanning() {
  act(() => {
    fireEvent.change(screen.getByLabelText('Intitulé *'), {
      target: { value: 'IDE — test conservation du formulaire' },
    });
    fireEvent.change(screen.getByLabelText('Description'), {
      target: { value: 'Description conservée pendant la vérification.' },
    });
    fireEvent.change(screen.getByLabelText('Service'), {
      target: { value: 'Soins continus' },
    });
    fireEvent.change(screen.getByLabelText('Taux horaire brut * (€/h)'), {
      target: { value: '32' },
    });
    fireEvent.change(screen.getByLabelText('Première date affichée *'), {
      target: { value: '2099-08-03' },
    });
    fireEvent.change(screen.getByLabelText('Dernière date affichée *'), {
      target: { value: '2099-08-03' },
    });
  });
  const toutesLesDates = await screen.findByRole('button', { name: 'Toutes les dates' });
  act(() => fireEvent.click(toutesLesDates));
  await waitFor(() => {
    expect(within(screen.getByTestId('jour-planning-2099-08-03')).getByRole('checkbox')).toBeChecked();
  });
}

function verifierValeursConservees() {
  expect(screen.getByLabelText('Intitulé *')).toHaveValue('IDE — test conservation du formulaire');
  expect(screen.getByLabelText('Description')).toHaveValue('Description conservée pendant la vérification.');
  expect(screen.getByLabelText('Service')).toHaveValue('Soins continus');
  expect(screen.getByLabelText('Taux horaire brut * (€/h)')).toHaveValue(32);
  expect(screen.getByLabelText('Première date affichée *')).toHaveValue('2099-08-03');
  expect(screen.getByLabelText('Dernière date affichée *')).toHaveValue('2099-08-03');
  expect(within(screen.getByTestId('jour-planning-2099-08-03')).getByRole('checkbox')).toBeChecked();
  expect(document.getElementById('mission-profession')).toHaveTextContent(/Infirmier.*IDE/i);
}

async function choisirIde() {
  const profession = document.getElementById('mission-profession');
  expect(profession).not.toBeNull();
  act(() => fireEvent.click(profession!));
  const optionIde = await screen.findByTestId('profession-option-IDE');
  act(() => fireEvent.click(optionIde));
}

describe('FormulaireMission — parcours de création critique', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mocks.recapData = null;
  });

  it('conserve les champs et le planning pendant une RPC lente puis publie après le récapitulatif', async () => {
    const etablissement = promesseControlee<ReponseRpc>();
    const modeExercice = promesseControlee<ReponseRpc>();
    mocks.rpc.mockImplementation((fonction: string) => {
      if (fonction === 'fn_mon_etablissement_complet') {
        return etablissement.promise;
      }
      if (fonction === 'fn_mode_exercice') return modeExercice.promise;
      if (fonction === 'fn_creer_mission_multi_jours_v2') {
        return Promise.resolve({ data: { success: true, mission_id: 'mission-test-creee' }, error: null });
      }
      throw new Error(`RPC inattendue : ${fonction}`);
    });

    render(
      <MemoryRouter initialEntries={['/etablissement/missions/creer']}>
        <FormulaireMission />
      </MemoryRouter>,
    );

    await waitFor(() => expect(mocks.rpc).toHaveBeenCalledWith('fn_mon_etablissement_complet'));
    await act(async () => {
      etablissement.resolve({ data: etablissementComplet, error: null });
      await etablissement.promise;
    });
    await remplirChampsEtPlanning();
    await choisirIde();

    expect(await screen.findByText("Vérification du mode d'exercice…")).toBeInTheDocument();
    verifierValeursConservees();

    await act(async () => {
      modeExercice.resolve({
        data: {
          niveau: 'NON_PROPOSE',
          categorie: 'prive',
          source_libelle: 'Mission proposée en salarié.',
          source_force: 'CONFORMITE_JOLENE',
          source_url: null,
        },
        error: null,
      });
      await modeExercice.promise;
    });

    await waitFor(() => expect(screen.queryByText("Vérification du mode d'exercice…")).not.toBeInTheDocument());
    verifierValeursConservees();
    expect(screen.getByRole('radio', { name: /Salarié/i })).toBeChecked();

    const publier = screen.getByRole('button', { name: /Publier la mission/ });
    expect(publier).toBeEnabled();
    fireEvent.click(publier);

    expect(await screen.findByRole('dialog', { name: 'Récapitulatif avant publication' })).toBeInTheDocument();
    expect(mocks.recapData).toMatchObject({
      intitule: 'IDE — test conservation du formulaire',
      description: 'Description conservée pendant la vérification.',
      profession: 'IDE',
      service: 'Soins continus',
      tauxHoraire: 32,
      contratPreference: 'SALARIE',
      dureeHeures: 12,
    });

    fireEvent.click(screen.getByRole('button', { name: 'Confirmer la publication' }));
    await waitFor(() => {
      expect(mocks.rpc).toHaveBeenCalledWith('fn_creer_mission_multi_jours_v2', expect.objectContaining({
        p_intitule: 'IDE — test conservation du formulaire',
        p_profession_requise: 'IDE',
        p_service: 'Soins continus',
        p_taux_horaire_base: 32,
        p_type_contrat_recherche: 'SALARIE',
        p_creneaux: [expect.objectContaining({
          debut: expect.stringContaining('2099-08-03'),
          fin: expect.stringContaining('2099-08-03'),
        })],
      }));
    });
  });

  it('conserve les valeurs et atteint le récapitulatif si la matrice répond en erreur', async () => {
    const etablissement = promesseControlee<ReponseRpc>();
    const modeExercice = promesseControlee<ReponseRpc>();
    mocks.rpc.mockImplementation((fonction: string) => {
      if (fonction === 'fn_mon_etablissement_complet') {
        return etablissement.promise;
      }
      if (fonction === 'fn_mode_exercice') return modeExercice.promise;
      throw new Error(`RPC inattendue : ${fonction}`);
    });

    render(
      <MemoryRouter initialEntries={['/etablissement/missions/creer']}>
        <FormulaireMission />
      </MemoryRouter>,
    );

    await waitFor(() => expect(mocks.rpc).toHaveBeenCalledWith('fn_mon_etablissement_complet'));
    await act(async () => {
      etablissement.resolve({ data: etablissementComplet, error: null });
      await etablissement.promise;
    });
    await remplirChampsEtPlanning();
    await choisirIde();

    await act(async () => {
      modeExercice.resolve({ data: null, error: { message: 'Matrice indisponible pour le test' } });
      await modeExercice.promise;
    });
    expect(await screen.findByRole('alert')).toHaveTextContent('Impossible de vérifier le mode libéral');
    verifierValeursConservees();

    const publier = screen.getByRole('button', { name: /Publier la mission/ });
    expect(publier).toBeEnabled();
    fireEvent.click(publier);
    expect(await screen.findByRole('dialog', { name: 'Récapitulatif avant publication' })).toBeInTheDocument();
  });
});
