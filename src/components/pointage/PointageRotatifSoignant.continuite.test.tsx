import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { act, fireEvent, render, screen, waitFor } from '@testing-library/react';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { PointageRotatifSoignant } from './PointageRotatifSoignant';
const mocks = vi.hoisted(() => ({ rpc: vi.fn(), succes: vi.fn(), erreur: vi.fn() }));
vi.mock('@/integrations/supabase/client', () => ({ supabase: { rpc: mocks.rpc, from: vi.fn() } }));
vi.mock('@/components/NotationRapide', () => ({ SheetNotationRapide: () => null }));
vi.mock('@/lib/terminal', () => ({ genererIdTerminal: () => 'terminal-simulation' }));
vi.mock('sonner', () => ({ toast: { success: mocks.succes, error: mocks.erreur } }));
const etat = { statut: 'ASSIGNEE', prochain_type_scan: 'OUVERTURE', segment_ouvert: false, segments: [] };
function afficher() {
  const queryClient = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  render(<QueryClientProvider client={queryClient}><PointageRotatifSoignant missionId="mission-a" consentementGPS={false} /></QueryClientProvider>);
  return queryClient;
}
describe('Pointage — lecture après mutation', () => {
  beforeEach(() => { mocks.rpc.mockReset(); mocks.succes.mockReset(); mocks.erreur.mockReset(); });
  it('ne permet pas un deuxième scan avant d’avoir relu le nouvel état serveur', async () => {
    let lecture = 0;
    let resoudre!: (value: any) => void;
    mocks.rpc.mockImplementation((nom: string) => {
      if (nom === 'fn_scanner_code_pointage') return Promise.resolve({ data: { success: true, type_scan_effectue: 'OUVERTURE' }, error: null });
      if (lecture++ === 0) return Promise.resolve({ data: etat, error: null });
      return new Promise(resolve => { resoudre = resolve; });
    });
    const client = afficher();
    const code = await screen.findByRole('textbox', { name: 'Code de pointage à 6 chiffres' });
    fireEvent.change(code, { target: { value: '654321' } });
    fireEvent.click(screen.getByRole('button', { name: 'Pointer mon arrivée' }));
    await waitFor(() => expect(lecture).toBe(2));
    fireEvent.change(code, { target: { value: '654322' } });
    expect(screen.getByRole('button', { name: 'Pointer mon arrivée' })).toBeDisabled();
    await act(async () => resoudre({ data: { ...etat, statut: 'EN_COURS', segment_ouvert: true, prochain_type_scan: 'FERMETURE', segments: [{ id: 's1', debut: '2026-09-25T07:00:00Z', fin: null }] }, error: null }));
    expect(await screen.findByRole('button', { name: 'Pointer mon départ / pause' })).toBeEnabled();
    expect(mocks.rpc.mock.calls.filter(([nom]) => nom === 'fn_scanner_code_pointage')).toHaveLength(1);
    client.clear();
  });

  it('ignore la réponse du pointage quand on quitte cette mission', async () => {
    let resoudre!: (value: any) => void;
    mocks.rpc.mockImplementation((nom: string) => nom === 'fn_scanner_code_pointage'
      ? new Promise(resolve => { resoudre = resolve; })
      : Promise.resolve({ data: etat, error: null }));
    const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
    const vue = render(<QueryClientProvider client={client}><PointageRotatifSoignant missionId="mission-a" consentementGPS={false} /></QueryClientProvider>);
    fireEvent.change(await screen.findByRole('textbox', { name: 'Code de pointage à 6 chiffres' }), { target: { value: '654321' } });
    fireEvent.click(screen.getByRole('button', { name: 'Pointer mon arrivée' }));
    vue.unmount();
    await act(async () => resoudre({ data: { type_scan_effectue: 'OUVERTURE' }, error: null }));
    expect(mocks.succes).not.toHaveBeenCalled();
    expect(mocks.erreur).not.toHaveBeenCalled();
    expect(mocks.rpc.mock.calls.filter(([nom]) => nom === 'fn_etat_pointage_mission')).toHaveLength(1);
    client.clear();
  });
});
