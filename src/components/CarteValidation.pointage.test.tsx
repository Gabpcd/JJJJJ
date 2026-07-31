import { render, screen } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { CarteValidation } from './CarteValidation';

vi.mock('./BadgeCertification', () => ({ BadgeCertification: () => null }));
vi.mock('./PanneauContestation', () => ({ PanneauContestation: () => null }));
vi.mock('./FilDiscussionLitige', () => ({ FilDiscussionLitige: () => null }));
vi.mock('./presence/BadgesAntiTrichePresence', () => ({ BadgesAntiTrichePresence: () => null }));
vi.mock('./NotationRapide', () => ({
  EtoilesNotation: () => null,
  DetailCriteres: () => null,
}));

const previsionnels = [
  {
    id: 'prev-1',
    debut: '2026-07-06T08:00:00+02:00',
    fin: '2026-07-06T16:00:00+02:00',
    est_pause: false,
    type_creneau: 'PREVISIONNEL',
  },
  {
    id: 'prev-2',
    debut: '2026-07-31T08:00:00+02:00',
    fin: '2026-07-31T16:00:00+02:00',
    est_pause: false,
    type_creneau: 'PREVISIONNEL',
  },
  {
    id: 'prev-3',
    debut: '2026-08-31T08:00:00+02:00',
    fin: '2026-08-31T16:00:00+02:00',
    est_pause: false,
    type_creneau: 'PREVISIONNEL',
  },
];

function creerPresence(creneaux: any[]) {
  return {
    id: 'presence-1',
    mission_id: 'mission-1',
    soignant_id: 'soignant-1',
    // Valeurs legacy volontairement étalées sur deux mois : elles ne doivent
    // jamais être interprétées comme du temps travaillé.
    pointage_arrivee_le: '2026-07-06T08:00:00+02:00',
    pointage_depart_le: '2026-08-31T16:00:00+02:00',
    distance_etablissement_m: null,
    perimetre_gps_valide: true,
    alerte_teleportation: false,
    valide_par_etablissement: false,
    missions: {
      intitule: 'Mission IDE longue',
      debut_le: '2026-07-06T08:00:00+02:00',
      fin_le: '2026-08-31T16:00:00+02:00',
      duree_heures: 24,
      etablissement_id: 'etablissement-1',
      creneaux,
    },
    soignants: { prenom: 'Marie', nom: 'Lefèvre', profession: 'IDE' },
  };
}

function renderCarte(creneaux: any[]) {
  render(
    <MemoryRouter>
      <CarteValidation
        presence={creerPresence(creneaux)}
        onValider={vi.fn()}
        onContester={vi.fn()}
      />
    </MemoryRouter>,
  );
}

afterEach(() => vi.useRealTimers());

describe('CarteValidation — créneaux effectifs multi-jours', () => {
  it('additionne les EFFECTIF fermés et bloque la validation entre deux shifts', () => {
    vi.useFakeTimers({ toFake: ['Date'] });
    vi.setSystemTime(new Date('2026-07-31T17:00:00+02:00'));

    renderCarte([
      ...previsionnels,
      { id: 'eff-1', debut: '2026-07-06T08:00:00+02:00', fin: '2026-07-06T16:00:00+02:00', est_pause: false, type_creneau: 'EFFECTIF' },
      { id: 'eff-2', debut: '2026-07-31T08:00:00+02:00', fin: '2026-07-31T14:00:00+02:00', est_pause: false, type_creneau: 'EFFECTIF' },
    ]);

    expect(screen.getByText(/Prévu · 3 créneaux/i)).toBeInTheDocument();
    expect(screen.getByText(/Réel · 2 segments terminés/i)).toBeInTheDocument();
    expect(screen.getByText(/14h00 travaillées/i)).toBeInTheDocument();
    expect(screen.getByText(/validation après le dernier créneau, le 31\/08\/2026 à 16:00/i)).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: /valider/i })).not.toBeInTheDocument();
  });

  it('permet la validation après le dernier prévu et calcule l’écart exact', () => {
    vi.useFakeTimers({ toFake: ['Date'] });
    vi.setSystemTime(new Date('2026-09-01T09:00:00+02:00'));

    renderCarte([
      ...previsionnels,
      { id: 'eff-1', debut: '2026-07-06T08:00:00+02:00', fin: '2026-07-06T16:00:00+02:00', est_pause: false, type_creneau: 'EFFECTIF' },
      { id: 'eff-2', debut: '2026-07-31T08:00:00+02:00', fin: '2026-07-31T14:00:00+02:00', est_pause: false, type_creneau: 'EFFECTIF' },
      { id: 'eff-3', debut: '2026-08-31T08:00:00+02:00', fin: '2026-08-31T16:00:00+02:00', est_pause: false, type_creneau: 'EFFECTIF' },
    ]);

    expect(screen.getByText('Écart : -120 min')).toBeInTheDocument();
    expect(screen.getByRole('button', { name: /noter pour valider/i })).toBeInTheDocument();
  });

  it('bloque encore la validation si un EFFECTIF reste ouvert', () => {
    vi.useFakeTimers({ toFake: ['Date'] });
    vi.setSystemTime(new Date('2026-09-01T09:00:00+02:00'));

    renderCarte([
      ...previsionnels,
      { id: 'eff-1', debut: '2026-07-06T08:00:00+02:00', fin: '2026-07-06T16:00:00+02:00', est_pause: false, type_creneau: 'EFFECTIF' },
      { id: 'eff-ouvert', debut: '2026-08-31T08:00:00+02:00', fin: null, est_pause: false, type_creneau: 'EFFECTIF' },
    ]);

    expect(screen.getByText(/Pointage en cours : la validation sera disponible/i)).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: /valider/i })).not.toBeInTheDocument();
  });
});
