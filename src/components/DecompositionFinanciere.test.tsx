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

  it('ne présente jamais le brut historique net_a_payer comme le net du soignant salarié', () => {
    useModeExerciceMissionMock.mockReturnValue({ mode: null, loading: false, error: null });

    render(
      <DecompositionFinanciere
        mission={{
          ...missionBase,
          type_contrat_applique: 'SALARIE',
          net_a_payer: 444.68,
          net_estime: 346.85,
        }}
        role="SOIGNANT"
      />,
    );

    expect(screen.getByText('Net salarié estimé avant PAS*')).toBeInTheDocument();
    expect(screen.getAllByText(/346,85/).length).toBeGreaterThan(0);
    expect(screen.queryByText(/444,68/)).not.toBeInTheDocument();
    expect(screen.getAllByText(/bulletin officiel/i).length).toBeGreaterThan(0);
  });

  it.each(['ETAB', 'ADMIN'] as const)(
    'présente aussi uniquement net_estime au rôle %s et renvoie au bulletin employeur',
    (role) => {
      useModeExerciceMissionMock.mockReturnValue({ mode: null, loading: false, error: null });

      render(
        <DecompositionFinanciere
          mission={{
            ...missionBase,
            type_contrat_applique: 'SALARIE',
            net_a_payer: 444.68,
            net_estime: 346.85,
          }}
          role={role}
        />,
      );

      expect(screen.getByText('Net salarié estimé avant PAS*')).toBeInTheDocument();
      expect(screen.getAllByText(/346,85/).length).toBeGreaterThan(0);
      expect(screen.queryByText(/444,68/)).not.toBeInTheDocument();
      expect(screen.getByText(/reportez le net à payer du bulletin officiel/i)).toBeInTheDocument();
      expect(screen.queryByText(/bulletin de paie généré par Jolene/i)).not.toBeInTheDocument();
    },
  );

  it('présente un contrat encore indéterminé comme un brut indicatif', () => {
    useModeExerciceMissionMock.mockReturnValue({ mode: null, loading: false, error: new Error('matrice indisponible') });

    render(
      <DecompositionFinanciere
        mission={{ ...missionBase, total_brut: 240, net_a_payer: 187 }}
        role="SOIGNANT"
      />,
    );

    expect(screen.getByText('brut indicatif')).toBeInTheDocument();
    expect(screen.queryByText(/net estimé/i)).not.toBeInTheDocument();
  });

  it('affiche la commission HT, TTC et le taux réellement figé', () => {
    useModeExerciceMissionMock.mockReturnValue({ mode: null, loading: false, error: null });

    render(
      <DecompositionFinanciere
        mission={{
          ...missionBase,
          type_contrat_applique: 'LIBERAL',
          total_brut: 1_200,
          montant_commission_ht: 150,
          montant_commission_tva: 30,
          montant_commission_ttc: 180,
          taux_commission_fige: 12.5,
          taux_commission: 15,
        }}
        role="ETAB"
      />,
    );

    const texteExact = (attendu: string) => (_contenu: string, element: Element | null) =>
      element?.textContent?.replace(/\s+/g, ' ').trim() === attendu;
    expect(screen.getByText(texteExact('180,00 € TTC'))).toBeInTheDocument();
    expect(screen.getByText(texteExact('150,00 € HT + TVA 20 %'))).toBeInTheDocument();
    expect(screen.getByText(texteExact('Calcul : 12.5% × 1 200,00 € honoraires bruts (taux de commission applicable)'))).toBeInTheDocument();
  });
});
