import { render, screen } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { describe, expect, it, vi } from 'vitest';
import DashboardSoignant from './DashboardSoignant';

const missionAVenir = {
  id: 'mission-a-venir',
  intitule: 'Mission de nuit',
  statut: 'ASSIGNEE',
  debut_le: '2030-01-01T00:00:00.000Z',
  fin_le: '2030-01-31T23:00:00.000Z',
  debut_affiche: '2030-01-10T20:00:00.000Z',
  fin_affichee: '2030-01-11T08:00:00.000Z',
  planning_indisponible: false,
  duree_creneau_heures: 12,
  nb_creneaux_planifies: 2,
  index_prochain_creneau: 2,
  creneaux: [{
    id: 'creneau-a-venir',
    debut: '2030-01-10T20:00:00.000Z',
    fin: '2030-01-11T08:00:00.000Z',
    est_pause: false,
    type_creneau: 'PREVISIONNEL',
  }],
  etablissements: { nom: 'Clinique Jolene', adresse_ville: 'Paris' },
};

const missionOuverte = {
  id: 'mission-ouverte',
  intitule: 'Renfort IDE',
  debut_le: '2030-02-01T00:00:00.000Z',
  fin_le: '2030-02-28T23:00:00.000Z',
  debut_affiche: '2030-02-10T08:00:00.000Z',
  fin_affichee: '2030-02-10T20:00:00.000Z',
  planning_indisponible: false,
  duree_creneau_heures: 12,
  duree_planifiee_heures: 12,
  nb_creneaux_planifies: 1,
  index_prochain_creneau: 1,
  taux_horaire_base: 30,
  etab_nom: 'Hôpital Jolene',
};

// Garder la même référence entre les renders : le composant synchronise les
// propositions reçues par React Query dans un état local.
const dashboardData = {
  profil: {
    prenom: 'Marie',
    nom: 'Lefèvre',
    profession: 'IDE',
    tous_documents_valides: true,
    identite_verifiee: true,
    total_missions_terminees: 1,
    heures_cumulees: 12,
    type_exercice: 'LIBERAL',
  },
  mes_missions: [missionAVenir],
  missions_ouvertes: [missionOuverte],
  documents: [],
  propositions: [],
  heures_semaine: 0,
  heures_totales_terminees: 12,
  missions_oubliees_count: 0,
  gains_mois: { net_total: 234, brut_total: 300, nb_missions: 1 },
  gains_missions: [{
    id: 'mission-terminee',
    type_contrat_applique: 'SALARIE',
    type_contrat_recherche: 'SALARIE',
    total_brut: 300,
    net_a_payer: 300,
    net_estime: 234,
  }],
  hasStripeConnect: true,
};

vi.mock('@tanstack/react-query', () => ({
  useQuery: () => ({
    isLoading: false,
    data: dashboardData,
  }),
  useQueryClient: () => ({ resetQueries: vi.fn() }),
}));

vi.mock('@/components/LayoutApp', () => ({
  LayoutApp: ({ children }: { children: React.ReactNode }) => <>{children}</>,
}));

vi.mock('@/components/dashboard/ChecklistActivation', () => ({
  ChecklistActivation: () => null,
  useActivationSoignant: () => ({ visible: false }),
}));

vi.mock('@/hooks/useAppliquerParrainage', () => ({ useAppliquerParrainage: () => undefined }));
vi.mock('@/components/mascotte/Mascotte', () => ({ Mascotte: () => null }));
vi.mock('@/components/BadgeRPPS', () => ({ BadgeRPPS: () => null }));
vi.mock('@/components/BandeauGraceDocuments', () => ({ BandeauGraceDocuments: () => null }));
vi.mock('@/components/profil-soignant/BandeauCompletionProfil', () => ({ BandeauCompletionProfil: () => null }));
vi.mock('@/components/BandeauEvaluationsEnAttente', () => ({ BandeauEvaluationsEnAttente: () => null }));
vi.mock('@/components/NoteNetEstime', () => ({ NoteNetEstime: () => null }));
vi.mock('@/components/SyncCalendrier', () => ({
  BoutonAjouterCalendrier: () => <button type="button">Agenda</button>,
}));
vi.mock('@/components/SectionErrorBoundary', () => ({
  SectionErrorBoundary: ({ children }: { children: React.ReactNode }) => <>{children}</>,
}));
vi.mock('@/contexts/AuthContext', () => ({ useAuth: () => ({ user: { id: 'soignant-test' } }) }));
vi.mock('@/integrations/supabase/client', () => ({
  supabase: { rpc: vi.fn(), from: vi.fn() },
}));

describe('DashboardSoignant — cartes accessibles', () => {
  it('utilise des liens pour les missions et un bouton pour les gains', async () => {
    render(
      <MemoryRouter>
        <DashboardSoignant />
      </MemoryRouter>,
    );

    expect(await screen.findByRole('link', { name: 'Voir la mission Mission de nuit' }))
      .toHaveAttribute('href', '/soignant/missions/mission-a-venir');
    expect(screen.getByRole('link', { name: 'Voir la mission Renfort IDE' }))
      .toHaveAttribute('href', '/soignant/missions/mission-ouverte');
    expect(screen.getByText(/jeudi 10 janv\. · 21h00 → 09h00/i)).toBeInTheDocument();
    expect(screen.getByText(/dimanche 10 févr\. · 09h00 → 21h00/i)).toBeInTheDocument();
    expect(screen.queryByText(/mardi 1 janv\./i)).not.toBeInTheDocument();
    expect(screen.getByRole('button', { name: /Ce mois : 234,00\s*€ net salarié estimé/i })).toHaveAttribute('type', 'button');
  });
});
