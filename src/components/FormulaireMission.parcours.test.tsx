vi.mock('@/hooks/useRole', () => ({ useRole: () => ({ parcours: null }) }));
import React from 'react';
import { act, cleanup, fireEvent, render, screen, waitFor, within } from '@testing-library/react';
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
  user: { id: 'etablissement-test', email: 'etab-test@jolene.app' },
}));

vi.mock('@/contexts/AuthContext', () => ({
  useAuth: () => ({ user: mocks.user }),
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
  statut_verification: 'VERIFIE',
  peut_publier_missions: true,
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
    fireEvent.change(screen.getByLabelText(/Taux horaire (?:proposé|brut|des honoraires)/i), {
      target: { value: '32' },
    });
    fireEvent.input(screen.getByLabelText('Première date affichée *'), {
      target: { value: '2099-08-03' },
    });
    fireEvent.input(screen.getByLabelText('Dernière date affichée *'), {
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
  expect(screen.getByLabelText(/Taux horaire (?:proposé|brut|des honoraires)/i)).toHaveValue(32);
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
      if (fonction === 'fn_param_bool') return Promise.resolve({ data: false, error: null });
      if (fonction === 'fn_mon_etablissement_complet') {
        return etablissement.promise;
      }
      if (fonction === 'fn_mode_exercice') return modeExercice.promise;
      if (fonction === 'fn_creer_mission_multi_jours_v4') {
        return Promise.resolve({ data: { success: true, mission_id: 'mission-test-creee' }, error: null });
      }
      throw new Error(`RPC inattendue : ${fonction}`);
    });

    render(
      <MemoryRouter initialEntries={['/etablissement/missions/creer']}>
        <FormulaireMission />
      </MemoryRouter>,
    );

    expect(screen.getByText(/Choisissez d’abord la profession/)).toBeInTheDocument();
    expect(screen.queryByText(/Nature TVA prévue/)).not.toBeInTheDocument();
    expect(screen.queryByRole('radio', { name: /^Salarié/i })).not.toBeInTheDocument();

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
    act(() => fireEvent.click(screen.getByRole('radio', { name: /Soin à finalité thérapeutique/i })));
    verifierValeursConservees();
    expect(screen.getByRole('radio', { name: /Tous profils/i })).toBeChecked();
    expect(screen.getByRole('radio', { name: /^Libéral/i })).toBeEnabled();
    expect(screen.queryByText(/salariat recommandé/i)).not.toBeInTheDocument();

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
      contratPreference: 'TOUS',
      natureTvaPrestation: 'SOIN_THERAPEUTIQUE_EXONERE',
      dureeHeures: 12,
    });

    fireEvent.click(screen.getByRole('button', { name: 'Confirmer la publication' }));
    await waitFor(() => {
      expect(mocks.rpc).toHaveBeenCalledWith('fn_creer_mission_multi_jours_v4', expect.objectContaining({
        p_accepte_internes: false,
        p_intitule: 'IDE — test conservation du formulaire',
        p_profession_requise: 'IDE',
        p_service: 'Soins continus',
        p_taux_horaire_base: 32,
        p_type_contrat_recherche: 'TOUS',
        p_nature_tva_prestation: 'SOIN_THERAPEUTIQUE_EXONERE',
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
      if (fonction === 'fn_param_bool') return Promise.resolve({ data: false, error: null });
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

  it('explique le verrou de vérification sans afficher le code serveur brut', async () => {
    mocks.rpc.mockImplementation((fonction: string) => {
      if (fonction === 'fn_param_bool') return Promise.resolve({ data: false, error: null });
      if (fonction === 'fn_mon_etablissement_complet') {
        return Promise.resolve({ data: etablissementComplet, error: null });
      }
      if (fonction === 'fn_mode_exercice') {
        return Promise.resolve({
          data: {
            niveau: 'NON_PROPOSE',
            categorie: 'prive',
            source_libelle: 'Mission proposée en salarié.',
            source_force: 'CONFORMITE_JOLENE',
            source_url: null,
          },
          error: null,
        });
      }
      if (fonction === 'fn_creer_mission_multi_jours_v4') {
        return Promise.resolve({
          data: {
            success: false,
            error: 'ETABLISSEMENT_NON_VERIFIE',
            message: "Votre établissement doit être vérifié avant de publier une mission.",
          },
          error: null,
        });
      }
      throw new Error(`RPC inattendue : ${fonction}`);
    });

    render(
      <MemoryRouter initialEntries={['/etablissement/missions/creer']}>
        <FormulaireMission />
      </MemoryRouter>,
    );

    await waitFor(() => expect(mocks.rpc).toHaveBeenCalledWith('fn_mon_etablissement_complet'));
    await remplirChampsEtPlanning();
    await choisirIde();
    await waitFor(() => expect(screen.queryByText("Vérification du mode d'exercice…")).not.toBeInTheDocument());
    fireEvent.click(screen.getByRole('radio', { name: /Soin à finalité thérapeutique/i }));

    fireEvent.click(screen.getByRole('button', { name: /Publier la mission/ }));
    await act(async () => {
      fireEvent.click(await screen.findByRole('button', { name: 'Confirmer la publication' }));
    });

    await waitFor(() => {
      expect(mocks.afficherNotification).toHaveBeenCalledWith({
        type: 'erreur',
        message: "Votre établissement doit être vérifié avant de publier une mission.",
      });
    });
    expect(screen.queryByRole('dialog', { name: 'Récapitulatif avant publication' })).not.toBeInTheDocument();
    expect(await screen.findByRole('alert')).toHaveTextContent(
      "Votre établissement doit être vérifié avant de publier une mission.",
    );
    expect(screen.getByRole('link', { name: /Terminer la vérification/ })).toHaveAttribute(
      'href',
      '/etablissement/activer',
    );
    expect(screen.queryByText('ETABLISSEMENT_NON_VERIFIE')).not.toBeInTheDocument();
  });

  it('refuse un taux salarié sous le plancher lu au serveur avec le message exact, accepte le plancher', async () => {
    let plancher = 12.31;
    let annonce = true;
    const appels: Record<string, unknown>[] = [];
    let refusServeur = false;
    mocks.rpc.mockImplementation((fonction: string, params?: Record<string, unknown>) => {
      if (fonction === 'fn_param_bool') {
        expect(params).toEqual({ p_cle: 'taux_horaire_minimum_salarie', p_defaut: false });
        return Promise.resolve({ data: annonce, error: null });
      }
      if (fonction === 'fn_taux_horaire_minimum_salarie') return Promise.resolve({ data: plancher, error: null });
      if (fonction === 'fn_mon_etablissement_complet') return Promise.resolve({ data: etablissementComplet, error: null });
      if (fonction === 'fn_mode_exercice') {
        return Promise.resolve({
          data: { niveau: 'NON_PROPOSE', categorie: 'prive', source_libelle: 'Mission proposée en salarié.',
            source_force: 'CONFORMITE_JOLENE', source_url: null },
          error: null,
        });
      }
      if (fonction === 'fn_creer_mission_multi_jours_v4') {
        appels.push(params ?? {});
        if (refusServeur) {
          return Promise.resolve({ data: null, error: { code: 'P0001', hint: 'TAUX_HORAIRE_SOUS_MINIMUM_SALARIE',
            message: "Le taux horaire doit être d'au moins 12,31 €/h." } });
        }
        return Promise.resolve({ data: { success: true, mission_id: 'mission-test-creee' }, error: null });
      }
      throw new Error(`RPC inattendue : ${fonction}`);
    });

    const { unmount } = render(
      <MemoryRouter initialEntries={['/etablissement/missions/creer']}>
        <FormulaireMission />
      </MemoryRouter>,
    );
    await waitFor(() => expect(mocks.rpc).toHaveBeenCalledWith('fn_taux_horaire_minimum_salarie'));
    await waitFor(() => expect(mocks.rpc).toHaveBeenCalledWith('fn_mon_etablissement_complet'));
    await remplirChampsEtPlanning();
    await choisirIde();
    await waitFor(() => expect(screen.queryByText("Vérification du mode d'exercice…")).not.toBeInTheDocument());
    fireEvent.click(screen.getByRole('radio', { name: /Soin à finalité thérapeutique/i }));

    const champ = screen.getByLabelText(/Taux horaire (?:proposé|brut|des honoraires)/i);
    const publier = () => screen.getByRole('button', { name: /Publier la mission/ });
    act(() => fireEvent.change(champ, { target: { value: '12.30' } }));
    expect(screen.getByRole('alert')).toHaveTextContent(/^Le taux horaire doit être d'au moins 12,31 €\/h\.$/);
    expect(champ).toHaveAttribute('aria-invalid', 'true');
    expect(champ).toHaveAttribute('min', '12.31');
    expect(publier()).toBeDisabled();

    // Mission libérale : non concernée.
    act(() => fireEvent.click(screen.getByRole('radio', { name: /^Libéral/i })));
    expect(screen.queryByText(/au moins 12,31/)).not.toBeInTheDocument();
    expect(champ).toHaveAttribute('min', '0.01');
    act(() => fireEvent.click(screen.getByRole('radio', { name: /Tous profils/i })));
    expect(screen.getByRole('alert')).toHaveTextContent("Le taux horaire doit être d'au moins 12,31 €/h.");

    act(() => fireEvent.change(champ, { target: { value: '12.31' } }));
    expect(screen.queryByText(/au moins 12,31/)).not.toBeInTheDocument();
    expect(publier()).toBeEnabled();
    fireEvent.click(publier());
    expect(await screen.findByRole('dialog', { name: 'Récapitulatif avant publication' })).toBeInTheDocument();
    expect(mocks.recapData).toMatchObject({ tauxHoraire: 12.31, contratPreference: 'TOUS' });

    // Refus du serveur (verrou différé) : message affiché tel quel.
    refusServeur = true;
    await act(async () => {
      fireEvent.click(screen.getByRole('button', { name: 'Confirmer la publication' }));
    });
    await waitFor(() => expect(mocks.afficherNotification).toHaveBeenCalledWith({
      type: 'erreur', message: "Le taux horaire doit être d'au moins 12,31 €/h.",
    }));
    expect(appels).toHaveLength(1);
    expect(appels[0]).toMatchObject({ p_taux_horaire_base: 12.31, p_type_contrat_recherche: 'TOUS' });
    unmount();

    // Paramètre serveur relevé : le formulaire suit la valeur lue, pas le repli.
    plancher = 12.5;
    render(
      <MemoryRouter initialEntries={['/etablissement/missions/creer']}>
        <FormulaireMission />
      </MemoryRouter>,
    );
    await waitFor(() => expect(mocks.rpc).toHaveBeenCalledWith('fn_mon_etablissement_complet'));
    const champ2 = screen.getByLabelText(/Taux horaire (?:proposé|brut|des honoraires)/i);
    act(() => fireEvent.change(champ2, { target: { value: '12.31' } }));
    expect(await screen.findByText("Le taux horaire doit être d'au moins 12,50 €/h.")).toBeInTheDocument();
    cleanup();

    // Paramètre non annoncé (base sans la migration) : repli 12,31, la RPC de lecture n'est pas appelée.
    annonce = false;
    mocks.rpc.mockClear();
    render(
      <MemoryRouter initialEntries={['/etablissement/missions/creer']}>
        <FormulaireMission />
      </MemoryRouter>,
    );
    await waitFor(() => expect(mocks.rpc).toHaveBeenCalledWith('fn_param_bool', expect.anything()));
    await waitFor(() => expect(mocks.rpc).toHaveBeenCalledWith('fn_mon_etablissement_complet'));
    const champ3 = screen.getByLabelText(/Taux horaire (?:proposé|brut|des honoraires)/i);
    act(() => fireEvent.change(champ3, { target: { value: '12.30' } }));
    expect(await screen.findByText("Le taux horaire doit être d'au moins 12,31 €/h.")).toBeInTheDocument();
    expect(mocks.rpc).not.toHaveBeenCalledWith('fn_taux_horaire_minimum_salarie');
  });
});
