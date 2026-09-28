import { act, cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { PanneauxHealthcheck } from './PanneauxHealthcheck';

const mocks = vi.hoisted(() => ({
  invoke: vi.fn(), from: vi.fn(), getSession: vi.fn(), fetch: vi.fn(),
  success: vi.fn(), warning: vi.fn(), error: vi.fn(), unknown: [] as string[],
}));
vi.mock('@/integrations/supabase/client', () => ({
  SUPABASE_URL: 'http://127.0.0.1:8891',
  supabase: { from: mocks.from, auth: { getSession: mocks.getSession }, functions: { invoke: mocks.invoke } },
}));
vi.mock('@/contexts/AuthContext', () => ({ useAuth: () => ({ user: null }) }));
vi.mock('sonner', () => ({ toast: { success: mocks.success, warning: mocks.warning, error: mocks.error } }));

const warmResponses: Record<string, unknown> = {
  'stripe-config-health': { authenticated: true, livemode: true, mode: 'live', production_ready: true },
  'send-sms': { warm: true },
  'verify-document': { configured: true, reachable: true, model: 'fixture' },
  'send-email': { warm: true },
  'psc-authorize': { configured: true },
  'test-piste-credentials': { success: true, diagnostics: [{ step: 'OAuth', status: 'OK' }] },
  'verify-rpps': { configured: true },
  'verify-finess': { configured: true },
};

beforeEach(() => {
  vi.clearAllMocks(); mocks.unknown.length = 0;
  vi.stubGlobal('fetch', mocks.fetch);
  mocks.fetch.mockImplementation(async (url: string, options: { method?: string }) => {
    if (url !== 'http://127.0.0.1:8891/functions/v1/health-check' || options.method !== 'HEAD') {
      mocks.unknown.push(`fetch ${options.method} ${url}`);
      throw new Error('Appel non simulé');
    }
    return { status: 200 };
  });
  mocks.from.mockImplementation((table: string) => {
    if (table !== 'health_check') { mocks.unknown.push(`table ${table}`); throw new Error('Table non simulée'); }
    return { select: (colonnes: string) => {
      expect(colonnes).toBe('id');
      return { limit: async (nombre: number) => { expect(nombre).toBe(1); return { data: [], error: null }; } };
    } };
  });
  mocks.getSession.mockResolvedValue({ data: { session: { user: { id: 'admin-fixture' } } }, error: null });
});
afterEach(() => { cleanup(); vi.unstubAllGlobals(); });

const cas = [
  {
    nom: 'demande acceptée avec SID', data: { success: true, sid: 'SM00000000000000000000000000000001' }, toast: 'success',
    message: 'Demande acceptée par le fournisseur · référence SM00000000000000000000000000000001. La réception sur le téléphone reste à confirmer.',
  },
  {
    nom: 'demande ignorée malgré un SID', data: { success: true, skipped: true, sid: 'SM00000000000000000000000000000001' }, toast: 'error',
    message: 'Aucun SMS envoyé : le service a ignoré cette demande.',
  },
  {
    nom: 'résultat pending malgré un SID', data: { success: true, pending: true, sid: 'SM00000000000000000000000000000001' }, toast: 'warning',
    message: 'Le résultat de l’envoi reste à confirmer. Ne relancez pas le test immédiatement.',
  },
  {
    nom: 'service non configuré', data: { configured: false }, toast: 'error',
    message: 'Le service SMS n’est pas configuré.',
  },
  {
    nom: 'demande refusée', data: { success: false, error: 'Destinataire refusé pour ce test.' }, toast: 'error',
    message: 'Destinataire refusé pour ce test.',
  },
  {
    nom: 'réponse inconnue', data: { message: 'fixture inconnue' }, toast: 'warning',
    message: 'Réponse du service non reconnue : aucun envoi confirmé.',
  },
] as const;

describe('PanneauxHealthcheck — résultat du bouton Tester SMS', () => {
  it.each(cas)('$nom : affiche le résultat réel et ne prétend pas une réception', async ({ data, toast, message }) => {
    let repondre!: (reponse: { data: unknown; error: null }) => void;
    const reponseSms = new Promise<{ data: unknown; error: null }>(resolve => { repondre = resolve; });
    mocks.invoke.mockImplementation((fonction: string, options: { body: Record<string, unknown> }) => {
      if (fonction === 'send-sms' && options.body.type === 'TEST_ADMIN') return reponseSms;
      if (!(fonction in warmResponses)) { mocks.unknown.push(`function ${fonction}`); throw new Error('Fonction non simulée'); }
      const corpsAttendu = ['stripe-config-health', 'test-piste-credentials'].includes(fonction)
        ? {} : fonction === 'verify-document' ? { warm: true, probe: true } : { warm: true };
      expect(options.body).toEqual(corpsAttendu);
      return Promise.resolve({ data: warmResponses[fonction], error: null });
    });
    render(<PanneauxHealthcheck />);
    await waitFor(() => expect(screen.getByRole('button', { name: 'Revérifier' })).toBeEnabled());
    const bouton = screen.getByRole('button', { name: 'Tester SMS' });
    expect(bouton).toBeDisabled();
    fireEvent.change(screen.getByRole('textbox', { name: 'Numéro de téléphone pour le SMS de test' }), { target: { value: ' +330100000000 ' } });
    fireEvent.click(bouton);
    expect(screen.getByRole('button', { name: 'Envoi…' })).toBeDisabled();
    fireEvent.click(screen.getByRole('button', { name: 'Envoi…' }));
    const envois = mocks.invoke.mock.calls.filter(([nom, options]) => nom === 'send-sms' && options.body.type === 'TEST_ADMIN');
    expect(envois).toHaveLength(1);
    expect(envois[0][1].body).toEqual({ telephone: '+330100000000', type: 'TEST_ADMIN', contenu: expect.stringMatching(/^Test SMS Jolene depuis Statut système à /) });
    await act(async () => { repondre({ data, error: null }); });
    expect(screen.getByText(message, { exact: true })).toBeVisible();
    expect(screen.getByRole('button', { name: 'Tester SMS' })).toBeEnabled();
    const resultat = screen.getByText(message, { exact: true }).parentElement;
    if (toast === 'success') {
      expect(resultat).toHaveClass('text-success');
      expect(mocks.success).toHaveBeenCalledWith('Demande de SMS acceptée — réception à confirmer');
      expect(mocks.warning).not.toHaveBeenCalled(); expect(mocks.error).not.toHaveBeenCalled();
    } else {
      expect(resultat).not.toHaveClass('text-success');
      expect(mocks.success).not.toHaveBeenCalled();
      expect(mocks[toast]).toHaveBeenCalledWith(message);
    }
    expect(screen.queryByText(/^SMS (envoyé|reçu)/i)).not.toBeInTheDocument();
    expect(mocks.unknown).toEqual([]);
  });
});
