import { render, screen } from '@testing-library/react';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { DecompositionFinanciere } from './DecompositionFinanciere';

const useModeExerciceMissionMock = vi.fn();

vi.mock('@/hooks/useModeExerciceMission', () => ({
  useModeExerciceMission: (...args: unknown[]) => useModeExerciceMissionMock(...args),
}));

const missionBase = {
  profession_requise: 'IDE',
  type_contrat_applique: null,
  type_contrat_recherche: 'TOUS',
  statut: 'OUVERTE',
  duree_heures: 8,
  taux_horaire_base: 30,
  total_brut: 240,
  net_estime: 187,
  montant_ifm: 0,
  montant_icp: 0,
};

describe('DecompositionFinanciere avant attribution', () => {
  beforeEach(() => {
    useModeExerciceMissionMock.mockReset();
  });

  it('interroge la matrice avec la profession de la mission et affiche le salarié pour le public', () => {
    useModeExerciceMissionMock.mockReturnValue({ mode: null, loading: true, error: null });

    render(
      <DecompositionFinanciere
        mission={missionBase}
        etablissement={{ type: 'HOPITAL_PUBLIC', est_secteur_public: true }}
        role="SOIGNANT"
      />,
    );

    expect(useModeExerciceMissionMock).toHaveBeenCalledWith('IDE', 'HOPITAL_PUBLIC', true);
    expect(screen.getByText('Contrat salarié (CDD)')).toBeInTheDocument();
    expect(screen.queryByText(/selon le contrat retenu/i)).not.toBeInTheDocument();
    expect(screen.queryByText(/Type de contrat à définir/i)).not.toBeInTheDocument();
  });

  it('affiche le salarié quand la matrice retourne NON_PROPOSE', () => {
    useModeExerciceMissionMock.mockReturnValue({
      mode: {
        niveau: 'NON_PROPOSE',
        categorie: 'prive',
        source_libelle: 'Mission proposée en salarié.',
        source_force: 'CONFORMITE_JOLENE',
        source_url: null,
      },
      loading: false,
      error: null,
    });

    render(
      <DecompositionFinanciere
        mission={missionBase}
        etablissement={{ type: 'CLINIQUE_PRIVEE', est_secteur_public: false }}
        role="SOIGNANT"
      />,
    );

    expect(useModeExerciceMissionMock).toHaveBeenCalledWith('IDE', 'CLINIQUE_PRIVEE', false);
    expect(screen.getByText('Contrat salarié (CDD)')).toBeInTheDocument();
    expect(screen.queryByText(/selon le contrat retenu/i)).not.toBeInTheDocument();
  });

  it('affiche le libéral seulement pour une mission LIBERAL explicitement autorisée', () => {
    useModeExerciceMissionMock.mockReturnValue({
      mode: {
        niveau: 'AUTORISE',
        categorie: 'cabinet_liberal',
        source_libelle: 'Exercice libéral proposé.',
        source_force: 'CONFORMITE_JOLENE',
        source_url: null,
      },
      loading: false,
      error: null,
    });

    render(
      <DecompositionFinanciere
        mission={{ ...missionBase, type_contrat_recherche: 'LIBERAL' }}
        etablissement={{ type: 'CABINET_LIBERAL', est_secteur_public: false }}
        role="SOIGNANT"
      />,
    );

    expect(screen.getByText('Contrat libéral')).toBeInTheDocument();
  });

  it('masque le wording générique pendant la résolution privée', () => {
    useModeExerciceMissionMock.mockReturnValue({ mode: null, loading: true, error: null });

    render(
      <DecompositionFinanciere
        mission={missionBase}
        etablissement={{ type: 'CLINIQUE_PRIVEE', est_secteur_public: false }}
        role="SOIGNANT"
      />,
    );

    expect(screen.getByText(/Vérification du mode d'exercice/i)).toBeInTheDocument();
    expect(screen.queryByText(/selon le contrat retenu/i)).not.toBeInTheDocument();
  });
});
