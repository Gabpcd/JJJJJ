import { render, screen, waitFor } from '@testing-library/react';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { BlocConformite } from './BlocConformite';

const reponses = vi.hoisted(() => ({
  mission: { data: null as unknown, error: null as unknown },
  existantes: { data: [] as unknown[], error: null as unknown },
  creneaux: { data: [] as unknown[], error: null as unknown },
}));
const auth = vi.hoisted(() => ({ user: { id: 'soignant-test' } }));

vi.mock('@/contexts/AuthContext', () => ({
  useAuth: () => auth,
}));

vi.mock('react-router-dom', async () => {
  const original = await vi.importActual<typeof import('react-router-dom')>('react-router-dom');
  return { ...original, useNavigate: () => vi.fn() };
});

vi.mock('@/integrations/supabase/client', () => ({
  supabase: {
    from: () => {
      const builder = {
        select: () => builder,
        eq: () => builder,
        in: () => builder,
        single: () => Promise.resolve(reponses.mission),
        order: () => Promise.resolve(reponses.existantes),
      };
      return builder;
    },
  },
}));

vi.mock('@/lib/mission-creneaux-pagines', () => ({
  chargerCreneauxMissionsPagines: vi.fn(async () => {
    if (reponses.creneaux.error) throw reponses.creneaux.error;
    return reponses.creneaux.data;
  }),
}));

const missionSalariee = {
  debut_le: '2026-07-24T13:00:00+02:00',
  fin_le: '2026-07-24T21:00:00+02:00',
  duree_heures: 8,
  nb_creneaux: 1,
  type_contrat_applique: null,
  choix_contrat_soignant: null,
  type_contrat_recherche: 'SALARIE',
};

describe('BlocConformite — plafond salarié', () => {
  beforeEach(() => {
    reponses.mission = { data: missionSalariee, error: null };
    reponses.existantes = { data: [], error: null };
    reponses.creneaux = {
      data: [{
        mission_id: 'candidate',
        debut: missionSalariee.debut_le,
        fin: missionSalariee.fin_le,
        est_pause: false,
        type_creneau: 'PREVISIONNEL',
      }],
      error: null,
    };
  });

  it('reste fail-closed lorsque la mission ne peut pas être chargée', async () => {
    reponses.mission = { data: null, error: { message: 'indisponible' } };
    const onResultat = vi.fn();

    render(<BlocConformite missionId="candidate" onResultat={onResultat} />);

    expect(await screen.findByText('Vérification indisponible')).toBeInTheDocument();
    expect(onResultat).toHaveBeenCalledWith(false);
    expect(onResultat).not.toHaveBeenCalledWith(true);
  });

  it('ne bloque ni ne compte une mission candidate libérale', async () => {
    reponses.mission = {
      data: { ...missionSalariee, type_contrat_recherche: 'LIBERAL' },
      error: null,
    };
    const onResultat = vi.fn();

    render(<BlocConformite missionId="candidate" onResultat={onResultat} />);

    expect(await screen.findByText(/Cette mission libérale n'entre pas/i)).toBeInTheDocument();
    await waitFor(() => expect(onResultat).toHaveBeenLastCalledWith(true));
  });

  it('exclut une mission existante libérale du total de 48 h', async () => {
    reponses.existantes = {
      data: [{
        id: 'existante-liberale',
        intitule: 'Mission libérale',
        debut_le: '2026-07-20T08:00:00+02:00',
        fin_le: '2026-07-20T16:00:00+02:00',
        duree_heures: 8,
        nb_creneaux: 1,
        statut: 'ASSIGNEE',
        etablissement_id: 'cabinet',
        type_contrat_applique: 'LIBERAL',
        choix_contrat_soignant: 'LIBERAL',
        type_contrat_recherche: 'LIBERAL',
      }],
      error: null,
    };
    reponses.creneaux = {
      data: [
        {
          mission_id: 'candidate',
          debut: missionSalariee.debut_le,
          fin: missionSalariee.fin_le,
          est_pause: false,
          type_creneau: 'PREVISIONNEL',
        },
        {
          mission_id: 'existante-liberale',
          debut: '2026-07-20T08:00:00+02:00',
          fin: '2026-07-20T16:00:00+02:00',
          est_pause: false,
          type_creneau: 'PREVISIONNEL',
        },
      ],
      error: null,
    };
    const onResultat = vi.fn();

    render(<BlocConformite missionId="candidate" onResultat={onResultat} />);

    expect(await screen.findByText('Semaine du 20/07 : 0h + 8h = 8h / 48h')).toBeInTheDocument();
    await waitFor(() => expect(onResultat).toHaveBeenLastCalledWith(true));
  });

  it('laisse ouvrir le choix de contrat pour TOUS malgré un dépassement salarié', async () => {
    const candidateTous = {
      ...missionSalariee,
      fin_le: '2026-07-25T05:00:00+02:00',
      duree_heures: 16,
      type_contrat_recherche: 'TOUS',
    };
    reponses.mission = { data: candidateTous, error: null };
    reponses.existantes = {
      data: [{
        id: 'existante-salariee',
        intitule: 'Mission salariée',
        debut_le: '2026-07-20T00:00:00+02:00',
        fin_le: '2026-07-21T16:00:00+02:00',
        duree_heures: 40,
        nb_creneaux: 1,
        statut: 'ASSIGNEE',
        etablissement_id: 'hopital',
        type_contrat_applique: 'SALARIE',
        choix_contrat_soignant: 'SALARIE',
        type_contrat_recherche: 'TOUS',
      }],
      error: null,
    };
    reponses.creneaux = {
      data: [
        {
          mission_id: 'candidate',
          debut: candidateTous.debut_le,
          fin: candidateTous.fin_le,
          est_pause: false,
          type_creneau: 'PREVISIONNEL',
        },
        {
          mission_id: 'existante-salariee',
          debut: '2026-07-20T00:00:00+02:00',
          fin: '2026-07-21T16:00:00+02:00',
          est_pause: false,
          type_creneau: 'PREVISIONNEL',
        },
      ],
      error: null,
    };
    const onResultat = vi.fn();

    render(<BlocConformite missionId="candidate" onResultat={onResultat} />);

    expect(await screen.findByText('⚠️ Plafond 48h selon le contrat')).toBeInTheDocument();
    expect(screen.getByText(/Dépassement si contrat salarié ; le régime libéral n'est pas concerné/i)).toBeInTheDocument();
    await waitFor(() => expect(onResultat).toHaveBeenLastCalledWith(true));
  });

  it('ne détecte pas de faux chevauchement dans les jours non travaillés d’une période longue', async () => {
    reponses.mission = {
      data: {
        ...missionSalariee,
        debut_le: '2026-07-06T08:00:00+02:00',
        fin_le: '2026-08-31T16:00:00+02:00',
        duree_heures: 16,
        nb_creneaux: 2,
      },
      error: null,
    };
    reponses.existantes = {
      data: [{
        id: 'entre-les-deux',
        intitule: 'Mission du 20 juillet',
        debut_le: '2026-07-20T08:00:00+02:00',
        fin_le: '2026-07-20T16:00:00+02:00',
        duree_heures: 8,
        nb_creneaux: 1,
        statut: 'ASSIGNEE',
        etablissement_id: 'hopital',
        type_contrat_applique: 'SALARIE',
        choix_contrat_soignant: 'SALARIE',
        type_contrat_recherche: 'SALARIE',
      }],
      error: null,
    };
    reponses.creneaux = {
      data: [
        {
          mission_id: 'candidate',
          debut: '2026-07-06T08:00:00+02:00',
          fin: '2026-07-06T16:00:00+02:00',
          est_pause: false,
          type_creneau: 'PREVISIONNEL',
        },
        {
          mission_id: 'candidate',
          debut: '2026-08-31T08:00:00+02:00',
          fin: '2026-08-31T16:00:00+02:00',
          est_pause: false,
          type_creneau: 'PREVISIONNEL',
        },
        {
          mission_id: 'entre-les-deux',
          debut: '2026-07-20T08:00:00+02:00',
          fin: '2026-07-20T16:00:00+02:00',
          est_pause: false,
          type_creneau: 'PREVISIONNEL',
        },
      ],
      error: null,
    };
    const onResultat = vi.fn();

    render(<BlocConformite missionId="candidate" onResultat={onResultat} />);

    expect(await screen.findByText('✅ Pas de chevauchement')).toBeInTheDocument();
    await waitFor(() => expect(onResultat).toHaveBeenLastCalledWith(true));
  });

  it('compare le repos aux heures EFFECTIF d’une mission terminée', async () => {
    reponses.existantes = {
      data: [{
        id: 'terminee',
        intitule: 'Mission terminée',
        debut_le: '2026-07-24T00:00:00+02:00',
        fin_le: '2026-07-24T01:00:00+02:00',
        duree_heures: 1,
        nb_creneaux: 1,
        statut: 'TERMINEE',
        etablissement_id: 'hopital',
        type_contrat_applique: 'SALARIE',
        choix_contrat_soignant: 'SALARIE',
        type_contrat_recherche: 'SALARIE',
      }],
      error: null,
    };
    reponses.creneaux = {
      data: [
        {
          mission_id: 'candidate',
          debut: missionSalariee.debut_le,
          fin: missionSalariee.fin_le,
          est_pause: false,
          type_creneau: 'PREVISIONNEL',
        },
        {
          mission_id: 'terminee',
          debut: '2026-07-24T00:00:00+02:00',
          fin: '2026-07-24T01:00:00+02:00',
          est_pause: false,
          type_creneau: 'PREVISIONNEL',
        },
        {
          mission_id: 'terminee',
          debut: '2026-07-24T04:00:00+02:00',
          fin: '2026-07-24T05:00:00+02:00',
          est_pause: false,
          type_creneau: 'EFFECTIF',
        },
      ],
      error: null,
    };

    render(<BlocConformite missionId="candidate" onResultat={vi.fn()} />);

    expect(await screen.findByText(/Seulement 8.0h de repos après/i)).toBeInTheDocument();
  });
});
