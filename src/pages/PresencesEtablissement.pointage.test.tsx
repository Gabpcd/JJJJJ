import React from 'react';
import { render, screen } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import PresencesEtablissement from './PresencesEtablissement';

const mocks = vi.hoisted(() => ({
  from: vi.fn(),
  rpc: vi.fn(),
  chargerCreneaux: vi.fn(),
}));

vi.mock('@/integrations/supabase/client', () => ({
  supabase: { from: mocks.from, rpc: mocks.rpc },
}));

vi.mock('@/lib/mission-creneaux-pagines', () => ({
  chargerCreneauxMissionsPagines: mocks.chargerCreneaux,
}));

vi.mock('@/hooks/useEtablissementScope', () => ({
  useEtablissementScope: () => ({
    user: { id: 'admin-1' },
    etablissementId: 'etablissement-1',
  }),
}));

vi.mock('@/contexts/NotificationContext', () => ({
  useNotification: () => ({ afficherNotification: vi.fn() }),
}));

vi.mock('@/components/LayoutApp', () => ({
  LayoutApp: ({ children }: { children: React.ReactNode }) => <>{children}</>,
}));

vi.mock('@/components/ChargementPage', () => ({ ChargementPage: () => <p>Chargement</p> }));
vi.mock('@/hooks/usePageTitle', () => ({ usePageTitle: vi.fn() }));
vi.mock('@/components/NotationRapide', () => ({
  envoyerNotationRapide: vi.fn(),
  EtoilesNotation: () => null,
}));

vi.mock('@/components/CarteValidation', () => ({
  CarteValidation: ({ presence }: { presence: any }) => (
    <p>{presence.missions.intitule} · {presence.missions.creneaux.length} créneaux chargés</p>
  ),
}));

vi.mock('@/components/ui/TableOuCartes', () => ({
  TableOuCartes: ({ donnees, renduCarte, etatVide }: {
    donnees: any[];
    renduCarte: (donnee: any) => React.ReactNode;
    etatVide: React.ReactNode;
  }) => <>{donnees.length > 0
    ? donnees.map((donnee) => <React.Fragment key={donnee.id}>{renduCarte(donnee)}</React.Fragment>)
    : etatVide}</>,
}));

function creerBuilder(data: unknown, error: unknown = null) {
  const builder: Record<string, any> = {};
  for (const methode of ['select', 'eq', 'not', 'order', 'in']) {
    builder[methode] = vi.fn(() => builder);
  }
  builder.then = (resolve: (value: unknown) => unknown, reject: (reason: unknown) => unknown) => (
    Promise.resolve({ data, error }).then(resolve, reject)
  );
  return builder;
}

const previsionnels = [
  {
    id: 'prev-1',
    mission_id: 'mission-1',
    debut: '2026-07-06T08:00:00+02:00',
    fin: '2026-07-06T16:00:00+02:00',
    est_pause: false,
    type_creneau: 'PREVISIONNEL',
  },
  {
    id: 'prev-2',
    mission_id: 'mission-1',
    debut: '2026-08-31T08:00:00+02:00',
    fin: '2026-08-31T16:00:00+02:00',
    est_pause: false,
    type_creneau: 'PREVISIONNEL',
  },
];

describe('PresencesEtablissement — statut multi-créneaux', () => {
  let creneauxData: any[];

  beforeEach(() => {
    vi.useFakeTimers({ toFake: ['Date'] });
    creneauxData = [
      ...previsionnels,
      {
        id: 'eff-1',
        mission_id: 'mission-1',
        debut: '2026-07-06T08:00:00+02:00',
        fin: '2026-07-06T16:00:00+02:00',
        est_pause: false,
        type_creneau: 'EFFECTIF',
      },
    ];
    mocks.from.mockReset();
    mocks.rpc.mockReset();
    mocks.chargerCreneaux.mockReset();
    mocks.chargerCreneaux.mockImplementation(async () => creneauxData);
    mocks.rpc.mockResolvedValue({
      data: [{ id: 'soignant-1', prenom: 'Marie', nom: 'Lefèvre', profession: 'IDE' }],
      error: null,
    });
    mocks.from.mockImplementation((table: string) => {
      if (table === 'presences') {
        return creerBuilder([{
          id: 'presence-1',
          mission_id: 'mission-1',
          soignant_id: 'soignant-1',
          pointage_arrivee_le: '2026-07-06T08:00:00+02:00',
          pointage_depart_le: '2026-07-06T16:00:00+02:00',
          perimetre_gps_valide: true,
          alerte_teleportation: false,
          valide_par_etablissement: false,
          missions: {
            id: 'mission-1',
            intitule: 'Mission IDE longue',
            debut_le: '2026-07-06T08:00:00+02:00',
            fin_le: '2026-08-31T16:00:00+02:00',
            duree_heures: 16,
            nb_creneaux: 2,
            etablissement_id: 'etablissement-1',
          },
        }]);
      }
      if (table === 'litiges') return creerBuilder([]);
      return creerBuilder([]);
    });
  });

  afterEach(() => vi.useRealTimers());

  it('reste « en cours » entre deux shifts malgré un départ legacy renseigné', async () => {
    vi.setSystemTime(new Date('2026-07-31T12:00:00+02:00'));

    render(<MemoryRouter><PresencesEtablissement /></MemoryRouter>);

    expect(await screen.findByRole('tab', { name: 'À valider: 0 présences' })).toBeInTheDocument();
    expect(screen.getByRole('tab', { name: 'En cours: 1 présences' })).toBeInTheDocument();
    expect(mocks.chargerCreneaux).toHaveBeenCalledWith(
      ['mission-1'],
      { exclurePauses: true },
    );
  });

  it('passe « à valider » seulement après le dernier prévu', async () => {
    vi.setSystemTime(new Date('2026-09-01T12:00:00+02:00'));

    render(<MemoryRouter><PresencesEtablissement /></MemoryRouter>);

    expect(await screen.findByRole('tab', { name: 'À valider: 1 présences' })).toBeInTheDocument();
    expect(screen.getByRole('tab', { name: 'En cours: 0 présences' })).toBeInTheDocument();
  });

  it('reste « en cours » après l’échéance si un EFFECTIF est ouvert', async () => {
    vi.setSystemTime(new Date('2026-09-01T12:00:00+02:00'));
    creneauxData.push({
      id: 'eff-ouvert',
      mission_id: 'mission-1',
      debut: '2026-08-31T08:00:00+02:00',
      fin: null,
      est_pause: false,
      type_creneau: 'EFFECTIF',
    });

    render(<MemoryRouter><PresencesEtablissement /></MemoryRouter>);

    expect(await screen.findByRole('tab', { name: 'À valider: 0 présences' })).toBeInTheDocument();
    expect(screen.getByRole('tab', { name: 'En cours: 1 présences' })).toBeInTheDocument();
  });

  it('reste « en cours » si un des créneaux attendus manque après l’échéance', async () => {
    vi.setSystemTime(new Date('2026-09-01T12:00:00+02:00'));
    creneauxData = creneauxData.filter((creneau) => creneau.id !== 'prev-2');

    render(<MemoryRouter><PresencesEtablissement /></MemoryRouter>);

    expect(await screen.findByRole('tab', { name: 'À valider: 0 présences' })).toBeInTheDocument();
    expect(screen.getByRole('tab', { name: 'En cours: 1 présences' })).toBeInTheDocument();
  });

  it('conserve le repli compatible d’une mission ponctuelle historique', async () => {
    vi.setSystemTime(new Date('2026-09-01T12:00:00+02:00'));
    creneauxData = [{
      id: 'eff-ponctuel',
      mission_id: 'mission-1',
      debut: '2026-07-06T08:00:00+02:00',
      fin: '2026-07-06T16:00:00+02:00',
      est_pause: false,
      type_creneau: 'EFFECTIF',
    }];

    // Le mock de mission couvre ici plus de 24 h, donc on remplace la période
    // au niveau de la réponse présence pour simuler l'ancien format ponctuel.
    const originalImplementation = mocks.from.getMockImplementation();
    mocks.from.mockImplementation((table: string) => {
      if (table === 'presences') {
        return creerBuilder([{
          id: 'presence-1', mission_id: 'mission-1', soignant_id: 'soignant-1',
          pointage_arrivee_le: '2026-07-06T08:00:00+02:00',
          pointage_depart_le: '2026-07-06T16:00:00+02:00',
          perimetre_gps_valide: true, alerte_teleportation: false,
          valide_par_etablissement: false,
          missions: {
            id: 'mission-1', intitule: 'Mission IDE ponctuelle',
            debut_le: '2026-07-06T08:00:00+02:00',
            fin_le: '2026-07-06T16:00:00+02:00', duree_heures: 8,
            etablissement_id: 'etablissement-1',
          },
        }]);
      }
      return originalImplementation!(table);
    });

    render(<MemoryRouter><PresencesEtablissement /></MemoryRouter>);

    expect(await screen.findByRole('tab', { name: 'À valider: 1 présences' })).toBeInTheDocument();
  });

  it('affiche une erreur explicite au lieu d’un faux état vide', async () => {
    const originalImplementation = mocks.from.getMockImplementation();
    mocks.from.mockImplementation((table: string) => (
      table === 'presences'
        ? creerBuilder(null, { message: 'Réseau indisponible' })
        : originalImplementation!(table)
    ));

    render(<MemoryRouter><PresencesEtablissement /></MemoryRouter>);

    expect(await screen.findByRole('alert')).toHaveTextContent('Impossible de charger les présences');
    expect(screen.queryByText('Aucune présence à valider')).not.toBeInTheDocument();
  });

  it('affiche une erreur explicite si le planning des présences est indisponible', async () => {
    mocks.chargerCreneaux.mockRejectedValueOnce(new Error('Planning indisponible'));

    render(<MemoryRouter><PresencesEtablissement /></MemoryRouter>);

    expect(await screen.findByRole('alert')).toHaveTextContent('Impossible de charger les présences');
    expect(screen.queryByRole('tab', { name: /En cours/ })).not.toBeInTheDocument();
    expect(screen.queryByText('Aucune présence à valider')).not.toBeInTheDocument();
  });
});
