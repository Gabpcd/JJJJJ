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
  for (const methode of ['select', 'eq', 'not', 'order']) {
    builder[methode] = vi.fn(() => builder);
  }
  builder.single = vi.fn(() => Promise.resolve({ data, error: null }));
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
          taux_horaire_base: 25,
          total_brut: 400,
          net_estime: 312,
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
});
