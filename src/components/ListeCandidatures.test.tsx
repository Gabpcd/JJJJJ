import { fireEvent, render, screen, waitFor } from '@testing-library/react';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { ListeCandidatures } from './ListeCandidatures';

const mocks = vi.hoisted(() => ({
  from: vi.fn(),
  rpc: vi.fn(),
}));

vi.mock('@/integrations/supabase/client', () => ({
  supabase: { from: mocks.from, rpc: mocks.rpc },
}));

function builderCandidatures(resultat: { data: unknown; error: unknown }) {
  const builder: Record<string, any> = {};
  builder.select = vi.fn(() => builder);
  builder.eq = vi.fn(() => builder);
  builder.order = vi.fn(() => Promise.resolve(resultat));
  return builder;
}

function builderPlanning(resultat: { data: unknown; error: unknown }) {
  const builder: Record<string, any> = {};
  builder.select = vi.fn(() => builder);
  builder.eq = vi.fn(() => builder);
  builder.order = vi.fn(() => Promise.resolve(resultat));
  return builder;
}

const creneaux = [
  {
    id: 'creneau-nuit',
    debut: '2026-07-30T20:00:00+02:00',
    fin: '2026-07-31T06:00:00+02:00',
    est_pause: false,
    type_creneau: 'PREVISIONNEL',
  },
];

describe('ListeCandidatures — confirmation établissement', () => {
  let resultatCandidatures: { data: unknown; error: unknown };
  let resultatsPlanning: Array<{ data: unknown; error: unknown }>;

  beforeEach(() => {
    mocks.from.mockReset();
    mocks.rpc.mockReset();
    resultatCandidatures = {
      data: [{ id: 'cand-1', soignant_id: 'sg-1', message: null, statut: 'EN_ATTENTE', cree_le: '2026-07-01T10:00:00Z' }],
      error: null,
    };
    resultatsPlanning = [
      { data: creneaux, error: null },
      { data: creneaux, error: null },
    ];
    mocks.from.mockImplementation((table: string) => {
      if (table === 'mission_creneaux') {
        return builderPlanning(resultatsPlanning.shift() ?? { data: creneaux, error: null });
      }
      return builderCandidatures(resultatCandidatures);
    });
    mocks.rpc.mockImplementation((nom: string) => {
      if (nom === 'fn_soignant_pour_etablissement') {
        return Promise.resolve({
          data: { id: 'sg-1', prenom: 'Marie', nom: 'Lefèvre', profession: 'IDE', total_missions_terminees: 0 },
          error: null,
        });
      }
      return Promise.resolve({ data: { success: true }, error: null });
    });
  });

  it('affiche le planning exact avant de déclencher l’acceptation', async () => {
    render(
      <ListeCandidatures
        missionId="mission-1"
        missionIntitule="Garde de nuit"
        missionCreneaux={creneaux}
        missionNbCreneaux={1}
        missionProfession="IDE"
        onAccepted={vi.fn()}
        onError={vi.fn()}
        onSuccess={vi.fn()}
      />,
    );

    fireEvent.click(await screen.findByRole('button', { name: 'Accepter cette candidature' }));

    expect(mocks.rpc).not.toHaveBeenCalledWith('fn_traiter_candidature_planning_v1', expect.anything());
    expect(await screen.findByRole('heading', { name: 'Confirmer l’acceptation' })).toBeInTheDocument();
    expect(screen.getByText('jeudi 30 juillet 2026')).toBeInTheDocument();
    expect(screen.getByText(/20:00 → ven\. 31 juil\. · 06:00/)).toBeInTheDocument();

    fireEvent.click(screen.getByRole('button', { name: 'Confirmer et assigner' }));
    await waitFor(() => expect(mocks.rpc).toHaveBeenCalledWith('fn_traiter_candidature_planning_v1', {
      p_candidature_id: 'cand-1',
      p_decision: 'ACCEPTEE',
      p_creneaux_confirmes: [{
        debut: '2026-07-30T20:00:00+02:00',
        fin: '2026-07-31T06:00:00+02:00',
      }],
      p_motif: null,
    }));
  });

  it('affiche une erreur de chargement au lieu d’un faux état vide', async () => {
    resultatCandidatures = { data: null, error: { message: 'Réseau indisponible' } };

    render(
      <ListeCandidatures
        missionId="mission-1"
        missionCreneaux={creneaux}
        missionNbCreneaux={1}
        onAccepted={vi.fn()}
        onError={vi.fn()}
        onSuccess={vi.fn()}
      />,
    );

    expect(await screen.findByRole('alert')).toHaveTextContent('Impossible de charger les candidatures');
    expect(screen.queryByText('En attente de candidats')).not.toBeInTheDocument();
  });

  it('bloque l’acceptation tant que le planning est incomplet', async () => {
    render(
      <ListeCandidatures
        missionId="mission-1"
        missionCreneaux={[]}
        missionNbCreneaux={1}
        onAccepted={vi.fn()}
        onError={vi.fn()}
        onSuccess={vi.fn()}
      />,
    );

    expect(await screen.findByRole('alert')).toHaveTextContent('Planning détaillé à confirmer avant toute acceptation');
    expect(screen.getByRole('button', { name: 'Accepter cette candidature' })).toBeDisabled();
  });

  it('bloque une liste partielle par rapport au nombre contractuel de créneaux', async () => {
    render(
      <ListeCandidatures
        missionId="mission-1"
        missionCreneaux={creneaux}
        missionNbCreneaux={2}
        onAccepted={vi.fn()}
        onError={vi.fn()}
        onSuccess={vi.fn()}
      />,
    );

    expect(await screen.findByRole('alert')).toHaveTextContent('2 créneaux attendus, 1 chargé');
    expect(screen.getByRole('button', { name: 'Accepter cette candidature' })).toBeDisabled();
  });

  it('exige une nouvelle confirmation lorsque le planning change dans la boîte de dialogue', async () => {
    const planningModifie = [{
      ...creneaux[0],
      debut: '2026-07-30T21:00:00+02:00',
      fin: '2026-07-31T07:00:00+02:00',
    }];
    resultatsPlanning = [
      { data: creneaux, error: null },
      { data: planningModifie, error: null },
      { data: planningModifie, error: null },
    ];

    render(
      <ListeCandidatures
        missionId="mission-1"
        missionCreneaux={creneaux}
        missionNbCreneaux={1}
        onAccepted={vi.fn()}
        onError={vi.fn()}
        onSuccess={vi.fn()}
      />,
    );

    fireEvent.click(await screen.findByRole('button', { name: 'Accepter cette candidature' }));
    expect(await screen.findByRole('heading', { name: 'Confirmer l’acceptation' })).toBeInTheDocument();
    fireEvent.click(screen.getByRole('button', { name: 'Confirmer et assigner' }));

    expect(await screen.findByRole('alert')).toHaveTextContent('Le planning a changé depuis l’ouverture');
    expect(screen.getByText(/21:00 → ven\. 31 juil\. · 07:00/)).toBeInTheDocument();
    expect(mocks.rpc).not.toHaveBeenCalledWith('fn_traiter_candidature_planning_v1', expect.anything());

    await waitFor(() => expect(screen.getByRole('button', { name: 'Confirmer et assigner' })).toBeEnabled());
    fireEvent.click(screen.getByRole('button', { name: 'Confirmer et assigner' }));
    await waitFor(() => expect(mocks.rpc).toHaveBeenCalledWith(
      'fn_traiter_candidature_planning_v1',
      expect.objectContaining({
        p_decision: 'ACCEPTEE',
        p_creneaux_confirmes: [{
          debut: '2026-07-30T21:00:00+02:00',
          fin: '2026-07-31T07:00:00+02:00',
        }],
      }),
    ));
  });

  it('utilise aussi le wrapper établissement pour refuser sans planning confirmé', async () => {
    render(
      <ListeCandidatures
        missionId="mission-1"
        missionCreneaux={creneaux}
        missionNbCreneaux={1}
        onAccepted={vi.fn()}
        onError={vi.fn()}
        onSuccess={vi.fn()}
      />,
    );

    fireEvent.click(await screen.findByRole('button', { name: 'Refuser cette candidature' }));
    await waitFor(() => expect(mocks.rpc).toHaveBeenCalledWith('fn_traiter_candidature_planning_v1', {
      p_candidature_id: 'cand-1',
      p_decision: 'REFUSEE',
      p_creneaux_confirmes: null,
      p_motif: 'Refusé par l\'établissement',
    }));
  });
});
