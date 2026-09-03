import React from 'react';
import { render, screen } from '@testing-library/react';
import { MemoryRouter, Route, Routes } from 'react-router-dom';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import DetailPresencesMission from './DetailPresencesMission';

const mocks = vi.hoisted(() => ({
  from: vi.fn(),
  rpc: vi.fn(),
}));

vi.mock('@/integrations/supabase/client', () => ({
  supabase: { from: mocks.from, rpc: mocks.rpc },
}));

vi.mock('@/contexts/AuthContext', () => ({
  useAuth: () => ({ user: { id: 'admin-1' } }),
}));

vi.mock('@/components/LayoutApp', () => ({
  LayoutApp: ({ children }: { children: React.ReactNode }) => <>{children}</>,
}));

vi.mock('@/components/LayoutAdmin', () => ({
  LayoutAdmin: ({ children }: { children: React.ReactNode }) => <>{children}</>,
}));

vi.mock('@/components/ChargementPage', () => ({ ChargementPage: () => <p>Chargement</p> }));
vi.mock('@/components/pointage/AffichageCodeRotatifEtab', () => ({ AffichageCodeRotatifEtab: () => null }));
vi.mock('@/hooks/usePageTitle', () => ({ usePageTitle: vi.fn() }));

function creerBuilder(data: unknown) {
  const builder: Record<string, any> = {};
  for (const methode of ['select', 'eq', 'neq', 'not', 'order', 'limit']) {
    builder[methode] = vi.fn(() => builder);
  }
  builder.single = vi.fn(() => Promise.resolve({ data, error: null }));
  builder.maybeSingle = vi.fn(() => Promise.resolve({ data: Array.isArray(data) ? data[0] ?? null : data, error: null }));
  builder.then = (resolve: (value: unknown) => unknown, reject: (reason: unknown) => unknown) => (
    Promise.resolve({ data, error: null }).then(resolve, reject)
  );
  return builder;
}

describe('DetailPresencesMission — planning prévisionnel', () => {
  let creneauxBuilder: Record<string, any>;

  beforeEach(() => {
    vi.useFakeTimers({ toFake: ['Date'] });
    vi.setSystemTime(new Date('2026-07-31T14:30:00+02:00'));
    mocks.from.mockReset();
    mocks.rpc.mockReset();
    mocks.rpc.mockResolvedValue({
      data: {
        heures_reelles: 999,
        heures_planifiees: 16,
        duree_pause_minutes: 0,
        alerte_teleportation: false,
      },
      error: null,
    });

    mocks.from.mockImplementation((table: string) => {
      if (table === 'missions') {
        return creerBuilder({
          id: 'mission-1',
          intitule: 'Mission IDE longue',
          service: 'Médecine',
          debut_le: '2026-07-31T08:00:00+02:00',
          fin_le: '2026-08-31T16:00:00+02:00',
          duree_heures: 16,
          statut: 'EN_COURS',
          taux_horaire_base: 25,
          total_brut: 400,
          net_estime: 312,
          type_contrat_applique: 'SALARIE',
          soignant_assigne_id: 'soignant-1',
          etablissement_id: 'etablissement-1',
        });
      }
      if (table === 'presences') {
        return creerBuilder([{
          id: 'presence-1',
          mission_id: 'mission-1',
          pointage_arrivee_le: '2026-07-06T08:00:00+02:00',
          pointage_depart_le: '2026-08-31T16:00:00+02:00',
          duree_nette_min: 999999,
          duree_pause_min: 0,
          perimetre_gps_valide: true,
          distance_etablissement_m: null,
          alerte_teleportation: false,
          valide_par_etablissement: false,
        }]);
      }
      if (table === 'mission_creneaux') {
        creneauxBuilder = creerBuilder([
          {
            id: 'creneau-1',
            mission_id: 'mission-1',
            debut: '2026-07-31T08:00:00+02:00',
            fin: '2026-07-31T16:00:00+02:00',
            est_pause: false,
            type_creneau: 'PREVISIONNEL',
          },
          {
            id: 'creneau-2',
            mission_id: 'mission-1',
            debut: '2026-08-31T08:00:00+02:00',
            fin: '2026-08-31T16:00:00+02:00',
            est_pause: false,
            type_creneau: 'PREVISIONNEL',
          },
          {
            id: 'effectif-1',
            mission_id: 'mission-1',
            debut: '2026-07-31T08:00:00+02:00',
            fin: '2026-07-31T14:00:00+02:00',
            est_pause: false,
            type_creneau: 'EFFECTIF',
          },
        ]);
        return creneauxBuilder;
      }
      if (table === 'soignants') {
        return creerBuilder({
          id: 'soignant-1',
          prenom: 'Marie',
          nom: 'Lefèvre',
          profession: 'IDE',
          numero_rpps: '1234',
        });
      }
      return creerBuilder([]);
    });
  });

  afterEach(() => vi.useRealTimers());

  it('calcule le travail depuis EFFECTIF sans signaler de déficit avant le dernier prévu', async () => {
    render(
      <MemoryRouter initialEntries={['/etablissement/presences/mission/mission-1']}>
        <Routes>
          <Route path="/etablissement/presences/mission/:id" element={<DetailPresencesMission />} />
        </Routes>
      </MemoryRouter>,
    );

    expect(await screen.findByRole('heading', { name: 'Mission IDE longue' })).toBeInTheDocument();
    expect(screen.getByText(/Progression : 0\/2 créneaux/i)).toBeInTheDocument();
    expect(screen.getByText(/Créneau planifié 1 \/ 2/i)).toBeInTheDocument();
    expect(screen.getByText(/Bilan après l’échéance de 16:00/i)).toBeInTheDocument();
    expect(screen.getByText(/Aucun déficit n’est signalé avant cette échéance/i)).toBeInTheDocument();
    expect(screen.getByText('Heures réelles').parentElement).toHaveTextContent('6h');
    expect(screen.getByRole('heading', { name: /Détail des créneaux travaillés \(1 segment\)/i })).toBeInTheDocument();
    expect(screen.queryByText(/999h/i)).not.toBeInTheDocument();
    expect(screen.queryByText(/Heures réelles inférieures à 90% du planifié/i)).not.toBeInTheDocument();
    expect(creneauxBuilder.eq).toHaveBeenCalledWith('est_pause', false);
    expect(creneauxBuilder.eq).not.toHaveBeenCalledWith('type_creneau', 'PREVISIONNEL');
  });

  it('donne à l’admin un chemin visible et audité pour régulariser les heures', async () => {
    vi.setSystemTime(new Date('2026-09-03T14:30:00+02:00'));
    render(
      <MemoryRouter initialEntries={['/admin/presences/mission/mission-1']}>
        <Routes>
          <Route
            path="/admin/presences/mission/:id"
            element={<DetailPresencesMission role="ADMIN_PLATEFORME" />}
          />
        </Routes>
      </MemoryRouter>,
    );

    expect(await screen.findByRole('heading', { name: 'Mission IDE longue' })).toBeInTheDocument();
    expect(screen.getByRole('region', { name: /Intervention admin sur les présences/i })).toHaveTextContent(
      '16 h planifiées contre 6 h pointées',
    );
    expect(screen.getByRole('button', { name: /Intervenir sur les heures ou le paiement/i })).toBeInTheDocument();
    expect(screen.getByText(/toute correction financière reste confirmée séparément/i)).toBeInTheDocument();
    expect(screen.getByText('Brut simulé avec compléments')).toBeInTheDocument();
  });

  it('ne présente jamais un faux net salarié pour une mission libérale', async () => {
    vi.setSystemTime(new Date('2026-09-03T14:30:00+02:00'));
    mocks.from.mockImplementation((table: string) => {
      if (table === 'missions') {
        return creerBuilder({
          id: 'mission-1',
          intitule: 'Mission IDE longue',
          debut_le: '2026-07-31T08:00:00+02:00',
          fin_le: '2026-08-31T16:00:00+02:00',
          duree_heures: 16,
          taux_horaire_base: 25,
          total_brut: 400,
          net_estime: 312,
          type_contrat_applique: 'LIBERAL',
          soignant_assigne_id: 'soignant-1',
          etablissement_id: 'etablissement-1',
        });
      }
      if (table === 'presences') return creerBuilder([]);
      if (table === 'mission_creneaux') {
        return creerBuilder([
          { id: 'prevu-1', mission_id: 'mission-1', debut: '2026-07-31T08:00:00+02:00', fin: '2026-07-31T16:00:00+02:00', est_pause: false, type_creneau: 'PREVISIONNEL' },
          { id: 'prevu-2', mission_id: 'mission-1', debut: '2026-08-31T08:00:00+02:00', fin: '2026-08-31T16:00:00+02:00', est_pause: false, type_creneau: 'PREVISIONNEL' },
          { id: 'effectif-1', mission_id: 'mission-1', debut: '2026-07-31T08:00:00+02:00', fin: '2026-07-31T16:00:00+02:00', est_pause: false, type_creneau: 'EFFECTIF' },
        ]);
      }
      if (table === 'soignants') return creerBuilder({ id: 'soignant-1', prenom: 'Marie', nom: 'Lefèvre' });
      return creerBuilder([]);
    });

    render(
      <MemoryRouter initialEntries={['/soignant/presences/mission/mission-1']}>
        <Routes>
          <Route path="/soignant/presences/mission/:id" element={<DetailPresencesMission role="SOIGNANT" />} />
        </Routes>
      </MemoryRouter>,
    );

    expect(await screen.findByRole('heading', { name: 'Mission IDE longue' })).toBeInTheDocument();
    expect(screen.getByText('Taux d’honoraires')).toBeInTheDocument();
    expect(screen.getByText('Honoraires selon heures retenues').parentElement).toHaveTextContent('200,00');
    expect(screen.getByText('Total honoraires mission').parentElement).toHaveTextContent('400,00');
    expect(screen.queryByText(/Net salarié estimé/i)).not.toBeInTheDocument();
    expect(screen.queryByText(/312,00/)).not.toBeInTheDocument();
  });

  it('rend deux jours et plusieurs pauses sans les additionner aux heures travaillées', async () => {
    vi.setSystemTime(new Date('2026-09-03T14:30:00+02:00'));
    const planifies = [
      { id: 'prevu-1', mission_id: 'mission-1', debut: '2026-08-30T08:00:00+02:00', fin: '2026-08-30T16:00:00+02:00', est_pause: false, type_creneau: 'PREVISIONNEL' },
      { id: 'prevu-2', mission_id: 'mission-1', debut: '2026-08-31T08:00:00+02:00', fin: '2026-08-31T16:00:00+02:00', est_pause: false, type_creneau: 'PREVISIONNEL' },
    ];
    const segments = ['2026-08-30', '2026-08-31'].flatMap((jour, jourIndex) => [
      { id: `effectif-${jourIndex}-1`, mission_id: 'mission-1', debut: `${jour}T08:00:00+02:00`, fin: `${jour}T10:00:00+02:00`, est_pause: false, type_creneau: 'EFFECTIF' },
      { id: `effectif-${jourIndex}-2`, mission_id: 'mission-1', debut: `${jour}T10:30:00+02:00`, fin: `${jour}T12:30:00+02:00`, est_pause: false, type_creneau: 'EFFECTIF' },
      { id: `effectif-${jourIndex}-3`, mission_id: 'mission-1', debut: `${jour}T13:15:00+02:00`, fin: `${jour}T16:00:00+02:00`, est_pause: false, type_creneau: 'EFFECTIF' },
    ]);

    mocks.from.mockImplementation((table: string) => {
      if (table === 'missions') {
        return creerBuilder({
          id: 'mission-1',
          intitule: 'Mission IDE avec pauses',
          debut_le: planifies[0].debut,
          fin_le: planifies[1].fin,
          duree_heures: 16,
          taux_horaire_base: 25,
          total_brut: 400,
          net_estime: 312,
          type_contrat_applique: 'SALARIE',
          soignant_assigne_id: 'soignant-1',
          etablissement_id: 'etablissement-1',
        });
      }
      if (table === 'presences') return creerBuilder([{ id: 'presence-1', valide_par_etablissement: false }]);
      if (table === 'mission_creneaux') return creerBuilder([...planifies, ...segments]);
      if (table === 'soignants') return creerBuilder({ id: 'soignant-1', prenom: 'Marie', nom: 'Lefèvre' });
      return creerBuilder([]);
    });

    render(
      <MemoryRouter initialEntries={['/etablissement/presences/mission/mission-1']}>
        <Routes>
          <Route path="/etablissement/presences/mission/:id" element={<DetailPresencesMission />} />
        </Routes>
      </MemoryRouter>,
    );

    expect(await screen.findByRole('heading', { name: 'Mission IDE avec pauses' })).toBeInTheDocument();
    expect(screen.getByText(/2 dates planifiées · 30 août 2026 → 31 août 2026/i)).toBeInTheDocument();
    expect(screen.getByRole('heading', { name: /6 segments/i })).toBeInTheDocument();
    expect(screen.getAllByText(/reprise après interruption/i)).toHaveLength(4);
    expect(screen.getAllByText(/Pause \/ interruption depuis le segment précédent/i)).toHaveLength(4);
    expect(screen.getAllByText('0h30')).toHaveLength(2);
    expect(screen.getAllByText('0h45')).toHaveLength(2);
    expect(screen.getByText('Heures réelles').parentElement).toHaveTextContent('13,5h');
    expect(screen.getByText('Heures travaillées fermées').parentElement).toHaveTextContent('13h30');
    expect(screen.getByText('Pauses / interruptions').parentElement).toHaveTextContent('150 min');
    expect(screen.queryByText('Retard')).not.toBeInTheDocument();
    expect(screen.queryByText('Départ anticipé')).not.toBeInTheDocument();
  });

  it('présente comme définitive une mission clôturée avant la fin du planning', async () => {
    vi.setSystemTime(new Date('2026-09-03T21:30:00+02:00'));
    mocks.from.mockImplementation((table: string) => {
      if (table === 'missions') {
        return creerBuilder({
          id: 'mission-1',
          intitule: 'Mission clôturée après arbitrage',
          debut_le: '2026-09-03T19:00:00+02:00',
          fin_le: '2026-09-04T19:00:00+02:00',
          duree_heures: 0.21,
          statut: 'TERMINEE',
          taux_horaire_base: 30,
          taux_rist_plafonne: 25,
          rist_plafond_applique: true,
          total_brut: 5.25,
          montant_ifm: 0.53,
          montant_icp: 0.53,
          net_estime: 4.92,
          type_contrat_applique: 'SALARIE',
          soignant_assigne_id: 'soignant-1',
          etablissement_id: 'etablissement-1',
        });
      }
      if (table === 'presences') {
        return creerBuilder([{
          id: 'presence-1',
          mission_id: 'mission-1',
          heures_ajustees_litige: 0.21,
          valide_par_etablissement: false,
        }]);
      }
      if (table === 'mission_creneaux') {
        return creerBuilder([
          { id: 'prevu-1', mission_id: 'mission-1', debut: '2026-09-03T19:00:00+02:00', fin: '2026-09-03T20:00:00+02:00', est_pause: false, type_creneau: 'PREVISIONNEL' },
          { id: 'prevu-2', mission_id: 'mission-1', debut: '2026-09-04T07:00:00+02:00', fin: '2026-09-04T19:00:00+02:00', est_pause: false, type_creneau: 'PREVISIONNEL' },
          { id: 'effectif-1', mission_id: 'mission-1', debut: '2026-09-03T19:00:00+02:00', fin: '2026-09-03T19:12:36+02:00', est_pause: false, type_creneau: 'EFFECTIF' },
        ]);
      }
      if (table === 'soignants') return creerBuilder({ id: 'soignant-1', prenom: 'Marie', nom: 'Lefèvre' });
      return creerBuilder([]);
    });

    render(
      <MemoryRouter initialEntries={['/soignant/presences/mission/mission-1']}>
        <Routes>
          <Route path="/soignant/presences/mission/:id" element={<DetailPresencesMission role="SOIGNANT" />} />
        </Routes>
      </MemoryRouter>,
    );

    expect(await screen.findByRole('heading', { name: 'Mission clôturée après arbitrage' })).toBeInTheDocument();
    expect(screen.getByText(/Mission clôturée · 1\/2 créneaux initialement prévus étaient échus/i)).toBeInTheDocument();
    expect(screen.getByText(/Les créneaux futurs ne sont plus à effectuer/i)).toBeInTheDocument();
    expect(screen.getByText('✅ Relevé clôturé après arbitrage')).toBeInTheDocument();
    expect(screen.getByText('Taux horaire brut retenu').parentElement).toHaveTextContent('25,00');
    expect(screen.getByText('Taux horaire brut retenu').parentElement).toHaveTextContent('Demandé : 30,00');
    expect(screen.getByText('Base brute retenue').parentElement).toHaveTextContent('5,25');
    expect(screen.getByText('Brut simulé avec compléments').parentElement).toHaveTextContent('6,31');
    expect(screen.queryByText(/prochain :/i)).not.toBeInTheDocument();
    expect(screen.queryByText('Mission en cours')).not.toBeInTheDocument();
    expect(screen.queryByText(/Heures réelles inférieures à 90% du planifié/i)).not.toBeInTheDocument();
    expect(screen.getByRole('button', { name: /Voir la simulation de paie détaillée/i })).toBeInTheDocument();
  });
});
