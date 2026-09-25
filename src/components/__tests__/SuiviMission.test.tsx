import { act, cleanup, fireEvent, render, screen } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { SuiviMission } from '../SuiviMission';

const banc = vi.hoisted(() => ({
  userId: 'soignant',
  lire: vi.fn(),
  permission: vi.fn(),
}));
vi.mock('@/contexts/AuthContext', () => ({ useAuth: () => ({ user: { id: banc.userId } }) }));
vi.mock('@/integrations/supabase/client', () => ({ supabase: {
  from: (table: string) => {
    let missionId: string;
    const requete = {
      select: () => requete,
      eq: (_: string, valeur: string) => { missionId = valeur; return requete; },
      order: () => requete, limit: () => requete,
      abortSignal: (signal: AbortSignal) => banc.lire(table, missionId, signal),
    };
    return requete;
  },
  rpc: (_: string, body: unknown) => ({ abortSignal: (signal: AbortSignal) => banc.permission(body, signal) }),
} }));
const mission = { id: 'mission-a', etablissement_id: 'etab', soignant_assigne_id: 'soignant', statut: 'ASSIGNEE', type_contrat_applique: 'LIBERAL' };
const reponse = (data: unknown[]) => Promise.resolve({ data, error: null });
function vue(id = mission.id, role: 'SOIGNANT' | 'ADMIN_ETABLISSEMENT' = 'SOIGNANT') {
  return <MemoryRouter><SuiviMission mission={{ ...mission, id }} role={role} /></MemoryRouter>;
}
function ouvrirDetail() { fireEvent.click(screen.getByRole('button', { name: 'Afficher le détail du suivi' })); }
beforeEach(() => { banc.userId = 'soignant'; banc.lire.mockReset().mockImplementation(() => reponse([])); banc.permission.mockReset(); });
afterEach(() => { cleanup(); vi.useRealTimers(); });

describe('SuiviMission : lectures bornées et isolées', () => {
  it('une réponse ancienne ne remplace pas le contrat de la nouvelle mission', async () => {
    let finirAncienne!: (value: unknown) => void;
    banc.lire.mockImplementation((table, missionId) => {
      if (table === 'presences' && missionId === 'mission-a') return new Promise(resolve => { finirAncienne = resolve; });
      if (table === 'contrats_mission') return reponse([{ id: `contrat-${missionId}`, statut: 'SIGNE_COMPLET', signature_soignant: true, signature_etablissement: true }]);
      return reponse([]);
    });
    const { rerender } = render(vue());
    rerender(vue('mission-b'));
    ouvrirDetail();
    const contrat = await screen.findByRole('link', { name: 'Consulter le contrat' });
    expect(contrat).toHaveAttribute('href', '/contrat/contrat-mission-b');
    await act(async () => finirAncienne({ data: [], error: null }));
    expect(screen.getByRole('link', { name: 'Consulter le contrat' })).toHaveAttribute('href', '/contrat/contrat-mission-b');
    const ancienSignal = banc.lire.mock.calls.find(c => c[1] === 'mission-a')?.[2] as AbortSignal;
    expect(ancienSignal.aborted).toBe(true);
  });

  it('une lecture qui ne répond pas devient indisponible après 10 s, sans rester bloquée', async () => {
    vi.useFakeTimers();
    banc.lire.mockImplementation((table) => table === 'presences' ? new Promise(() => {}) : reponse([]));
    render(vue());
    await act(async () => { await Promise.resolve(); });
    expect(screen.getByRole('button', { name: 'Actualiser le suivi' })).toBeDisabled();
    await act(async () => { await vi.advanceTimersByTimeAsync(10_001); });
    expect(screen.getByRole('alert')).toHaveTextContent('Une partie du suivi n’a pas pu être chargée.');
    ouvrirDetail();
    expect(screen.getByTestId('suivi-heures')).toHaveTextContent('Information indisponible');
    expect(screen.getByRole('button', { name: 'Actualiser le suivi' })).toBeEnabled();
    expect((banc.lire.mock.calls[0][2] as AbortSignal).aborted).toBe(true);
  });

  it('refuse toute lecture financière si les permissions concernent un autre établissement', async () => {
    banc.userId = 'gestionnaire';
    banc.permission.mockResolvedValue({ error: null, data: { success: true, etablissement_id: 'autre-etab', permissions: { paiement: true } } });
    render(vue(mission.id, 'ADMIN_ETABLISSEMENT'));
    await screen.findByRole('alert');
    expect(banc.lire.mock.calls.map(c => c[0])).toEqual(['contrats_mission', 'presences']);
    expect(screen.queryByRole('link', { name: 'Consulter les finances' })).not.toBeInTheDocument();
  });

  it('ne lit aucune donnée privée après changement vers un soignant non assigné', async () => {
    banc.lire.mockImplementation(table => table === 'contrats_mission'
      ? reponse([{ id: 'contrat-prive', statut: 'SIGNE_COMPLET', signature_soignant: true, signature_etablissement: true }]) : reponse([]));
    const { rerender } = render(vue());
    ouvrirDetail();
    await screen.findByRole('link', { name: 'Consulter le contrat' });
    const avant = banc.lire.mock.calls.length;
    banc.userId = 'autre-soignant'; rerender(vue());
    expect(screen.queryByRole('link', { name: 'Consulter le contrat' })).not.toBeInTheDocument();
    expect(banc.lire).toHaveBeenCalledTimes(avant);
    expect(screen.getByText('Accès limité à certaines informations du suivi.')).toBeVisible();
    ouvrirDetail();
    expect(screen.getByTestId('suivi-contrat')).toHaveTextContent('Accès limité');
  });

  it('reste replié par défaut et ouvre/ferme les étapes sans relancer les lectures', async () => {
    render(vue());
    await act(async () => { await Promise.resolve(); });
    const bouton = screen.getByRole('button', { name: 'Afficher le détail du suivi' });
    expect(bouton).toHaveAttribute('aria-expanded', 'false');
    expect(document.getElementById(bouton.getAttribute('aria-controls')!)).not.toBeVisible();
    expect(screen.getByRole('list', { name: 'Repères du suivi' }).children).toHaveLength(6);
    expect(screen.queryByRole('link', { name: 'Voir les présences' })).not.toBeInTheDocument();
    const appels = banc.lire.mock.calls.length;
    fireEvent.click(bouton);
    expect(bouton).toHaveAttribute('aria-expanded', 'true');
    expect(screen.getByRole('link', { name: 'Voir les présences' })).toBeVisible();
    fireEvent.click(screen.getByRole('button', { name: 'Masquer le détail du suivi' }));
    expect(bouton).toHaveAttribute('aria-expanded', 'false');
    expect(banc.lire).toHaveBeenCalledTimes(appels);
  });

  it('garde litige et erreur visibles dans le résumé replié sans confirmer le règlement', async () => {
    banc.lire.mockResolvedValue({ data: null, error: new Error('panne simulée') });
    render(<MemoryRouter><SuiviMission mission={mission} role="SOIGNANT" litigeActif /></MemoryRouter>);
    await screen.findByRole('alert');
    expect(screen.getByRole('status')).toHaveTextContent('Un litige est en cours');
    expect(screen.getByRole('button', { name: 'Afficher le détail du suivi' })).toHaveAttribute('aria-expanded', 'false');
    expect(screen.queryByText('Réception enregistrée')).not.toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Actualiser le suivi' })).toBeEnabled();
  });
});
