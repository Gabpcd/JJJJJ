import { fireEvent, render, screen, within } from '@testing-library/react';
import { MemoryRouter } from 'react-router-dom';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import AdminContrats from './AdminContrats';

// Liste admin des contrats : un contrat salarié (CDD, CDDU, VACATION) signé sans
// numéro DPAE est « ⏳ À déclarer », porte le badge « DPAE manquante » et reste
// dans la file « À traiter ». Le remplacement libéral reste « Non requise ».
// DPAE obligatoire pour tout salarié : C. trav. art. L.1221-10 ; CDD d'usage = CDD,
// art. L.1242-2 3° et D.1242-1. Décision du 08/11/2026.
const m = vi.hoisted(() => ({ rpc: vi.fn() }));
vi.mock('@/hooks/usePageTitle', () => ({ usePageTitle: vi.fn() }));
vi.mock('@/components/LayoutAdmin', () => ({ LayoutAdmin: ({ children }: any) => <main>{children}</main> }));
vi.mock('@/components/admin/ChargementAdmin', () => ({ ChargementAdmin: () => <p>Chargement admin</p> }));
vi.mock('@/integrations/supabase/client', () => ({ supabase: { rpc: m.rpc } }));

const A_TRAITER = 'À traiter (signatures en attente, DPAE manquantes)';
const HISTORIQUE = 'Historique (signés, annulés, expirés)';
const ligne = (type: string, extra: Record<string, unknown> = {}) => ({
  id: `contrat-${type}`, numero_contrat: `SIM-ADMIN-${type}`, mission_id: `mission-${type}`, mission_intitule: `Mission fictive ${type}`,
  soignant_id: 'soignant-fictif', soignant_nom: 'Camille Recette', etablissement_id: 'etab-fictif', etablissement_nom: 'Clinique Simulation',
  type_contrat: type, statut: 'SIGNE_COMPLET', hash_court: null, signature_soignant: true, signature_etablissement: true,
  signature_soignant_le: '2026-09-24T12:00:00Z', signature_etablissement_le: '2026-09-24T12:00:00Z', mode_signature: 'OTP',
  dpae_effectuee: false, dpae_numero: null, cree_le: '2026-09-24T12:00:00Z', ...extra,
});

beforeEach(() => {
  m.rpc.mockReset();
  m.rpc.mockResolvedValue({ data: { success: true, total: 4, contrats: [
    ligne('CDDU'), ligne('VACATION'), ligne('REMPLACEMENT_LIBERAL'),
    ligne('CDD', { dpae_effectuee: true, dpae_numero: 'SIM2026DPAE01' }),
  ] }, error: null });
});

const largeurInitiale = window.innerWidth;
afterEach(() => { Object.defineProperty(window, 'innerWidth', { configurable: true, writable: true, value: largeurInitiale }); });

async function afficher(largeur: number) {
  Object.defineProperty(window, 'innerWidth', { configurable: true, writable: true, value: largeur });
  render(<MemoryRouter><AdminContrats /></MemoryRouter>);
  const aTraiter = await screen.findByRole('region', { name: A_TRAITER });
  expect(m.rpc).toHaveBeenCalledWith('fn_admin_lister_contrats', expect.objectContaining({ p_filtre_statut: null }));
  return aTraiter;
}

const element = (zone: HTMLElement, numero: string) => {
  const cellule = within(zone).getByText(numero);
  return (cellule.closest('tr') ?? cellule.closest('[role="listitem"]')) as HTMLElement;
};

describe.each([['ordinateur', 1440], ['iphone', 390]])('liste admin des contrats (%s)', (_format, largeur) => {
  it('garde CDDU et VACATION signés sans numéro dans « À traiter », DPAE à déclarer', async () => {
    const aTraiter = await afficher(largeur);
    for (const type of ['CDDU', 'VACATION']) {
      const contrat = element(aTraiter, `SIM-ADMIN-${type}`);
      expect(within(contrat).getByText('DPAE manquante')).toBeInTheDocument();
      expect(within(contrat).getByText('⏳ À déclarer')).toBeInTheDocument();
      expect(within(contrat).queryByText('Non requise')).not.toBeInTheDocument();
    }
    expect(within(aTraiter).getAllByText('DPAE manquante')).toHaveLength(2);
    expect(within(aTraiter).queryByText('SIM-ADMIN-REMPLACEMENT_LIBERAL')).not.toBeInTheDocument();
    expect(within(aTraiter).queryByText('SIM-ADMIN-CDD')).not.toBeInTheDocument();
  });

  it('range le remplacement libéral en historique, DPAE non requise', async () => {
    await afficher(largeur);
    const historique = screen.getByRole('region', { name: HISTORIQUE });
    fireEvent.click(within(historique).getByRole('button', { name: /Historique \(signés, annulés, expirés\)/ }));
    const liberal = element(historique, 'SIM-ADMIN-REMPLACEMENT_LIBERAL');
    expect(within(liberal).getByText('Non requise')).toBeInTheDocument();
    expect(within(liberal).queryByText('DPAE manquante')).not.toBeInTheDocument();
    expect(within(liberal).queryByText('⏳ À déclarer')).not.toBeInTheDocument();
    const cddDeclare = element(historique, 'SIM-ADMIN-CDD');
    expect(within(cddDeclare).getByText('Validée · SIM2026D…')).toBeInTheDocument();
  });
});
