import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { act, cleanup, fireEvent, render, screen, waitFor, within } from '@testing-library/react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { PointageRotatifSoignant } from './PointageRotatifSoignant';

// Vrais bouton, Dialog, ScannerQRPointage et envoi de pointage ; transports simulés.
const mocks = vi.hoisted(() => ({
  rpc: vi.fn(), native: vi.fn(), scannerNatif: vi.fn(), position: vi.fn(),
  succes: vi.fn(), erreur: vi.fn(), camera: vi.fn(), trackStop: vi.fn(),
  start: vi.fn(), stop: vi.fn(), clear: vi.fn(),
  decoded: null as null | ((text: string) => Promise<void>),
}));
vi.mock('@/integrations/supabase/client', () => ({ supabase: { rpc: mocks.rpc, from: vi.fn() } }));
vi.mock('@/components/NotationRapide', () => ({ SheetNotationRapide: () => null }));
vi.mock('@/lib/platform', () => ({ isNative: mocks.native, obtenirPosition: mocks.position }));
vi.mock('@/lib/camera', () => ({ scannerQr: mocks.scannerNatif }));
vi.mock('@/lib/terminal', () => ({ genererIdTerminal: () => 'terminal-qr-simulation' }));
vi.mock('sonner', () => ({ toast: { success: mocks.succes, error: mocks.erreur } }));
vi.mock('html5-qrcode', () => ({
  Html5Qrcode: class {
    start(...args: unknown[]) {
      mocks.decoded = args[2] as typeof mocks.decoded;
      return mocks.start(...args);
    }
    getState() { return 2; }
    stop() { return mocks.stop(); }
    clear() { return mocks.clear(); }
  },
}));

const initial = { statut: 'ASSIGNEE', prochain_type_scan: 'OUVERTURE', segment_ouvert: false, segments: [] };
const apres = { statut: 'EN_COURS', prochain_type_scan: 'FERMETURE', segment_ouvert: true,
  segments: [{ id: 'segment-1', debut: new Date().toISOString(), fin: null }] };
const clients: QueryClient[] = [];
const mutations = () => mocks.rpc.mock.calls.filter(([name]) => name === 'fn_scanner_code_pointage');
const cameraStream = () => ({ getTracks: () => [{ stop: mocks.trackStop }] });

async function afficher() {
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  clients.push(client);
  const vue = render(<QueryClientProvider client={client}>
    <PointageRotatifSoignant missionId="mission-qr" consentementGPS={false} />
  </QueryClientProvider>);
  await screen.findByRole('button', { name: 'QR' });
  return vue;
}

async function ouvrir() {
  fireEvent.click(screen.getByRole('button', { name: 'QR' }));
  const dialog = await screen.findByRole('dialog', { name: 'Scanner le QR de pointage' });
  await waitFor(() => expect(mocks.start).toHaveBeenCalledTimes(1));
  return dialog;
}

describe('Pointage — QR web depuis le vrai bouton', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mocks.decoded = null;
    mocks.native.mockReturnValue(false);
    mocks.scannerNatif.mockReset();
    mocks.start.mockReset().mockResolvedValue(null);
    mocks.stop.mockReset().mockResolvedValue(undefined);
    mocks.clear.mockReset().mockResolvedValue(undefined);
    mocks.camera.mockReset().mockResolvedValue(cameraStream());
    Object.defineProperty(navigator, 'mediaDevices', { configurable: true, value: { getUserMedia: mocks.camera } });
    let pointe = false;
    mocks.rpc.mockReset().mockImplementation(async (name: string) => {
      if (name === 'fn_scanner_code_pointage') {
        pointe = true;
        return { data: { type_scan_effectue: 'OUVERTURE' }, error: null };
      }
      return { data: pointe ? apres : initial, error: null };
    });
  });
  afterEach(() => { cleanup(); clients.splice(0).forEach(client => client.clear()); });

  it('ouvre le scanner sans second clic et annule sans pointage en arrêtant la caméra', async () => {
    await afficher();
    const dialog = await ouvrir();
    expect(within(dialog).queryByRole('button', { name: '📷 Scanner le QR code' })).not.toBeInTheDocument();
    expect(mocks.scannerNatif).not.toHaveBeenCalled();
    expect(mocks.camera).toHaveBeenCalledWith({ video: { facingMode: { ideal: 'environment' } }, audio: false });
    fireEvent.click(within(dialog).getByRole('button', { name: 'Annuler le scan QR' }));
    await waitFor(() => expect(screen.queryByRole('dialog')).not.toBeInTheDocument());
    await waitFor(() => expect(mocks.stop).toHaveBeenCalledTimes(1));
    await act(async () => { await mocks.decoded?.('654321'); });
    expect(mutations()).toHaveLength(0);
    expect(mocks.clear).toHaveBeenCalledTimes(1);
    expect(screen.getByRole('button', { name: 'QR' })).toHaveFocus();
    expect(screen.getByRole('textbox', { name: 'Code de pointage à 6 chiffres' })).toBeEnabled();
  });

  it('envoie une seule mutation malgré deux détections et la relecture arrivée → départ', async () => {
    await afficher(); await ouvrir();
    const decode = mocks.decoded!;
    await act(async () => { await Promise.all([decode('654321'), decode('654321')]); });
    expect(mutations()).toEqual([['fn_scanner_code_pointage', { p_code: '654321', p_metadata: { id_terminal: 'terminal-qr-simulation' } }]]);
    expect(await screen.findByText('Pointage enregistré — segment ouvert')).toBeVisible();
    await waitFor(() => expect(screen.queryByRole('dialog')).not.toBeInTheDocument(), { timeout: 2500 });
    expect(screen.getByRole('button', { name: 'Pointer mon départ / pause' })).toBeInTheDocument();
    expect(mocks.start).toHaveBeenCalledTimes(1);
    expect(mocks.position).not.toHaveBeenCalled();
    await act(async () => { await decode('654321'); });
    expect(mutations()).toHaveLength(1);
  });

  it('ignore les QR malformés, garde la caméra ouverte puis accepte les six chiffres', async () => {
    await afficher(); await ouvrir();
    for (const texte of ['https://exemple.invalid/654321', '1234567', 'ab1234', '123 456']) {
      await act(async () => { await mocks.decoded?.(texte); });
    }
    expect(screen.getByRole('alert')).toHaveTextContent('QR non reconnu. Saisissez le code à 6 chiffres.');
    expect(mutations()).toHaveLength(0);
    expect(mocks.stop).not.toHaveBeenCalled();
    await act(async () => { await mocks.decoded?.('654321'); });
    expect(mutations()).toHaveLength(1);
  });

  it('refus caméra : explique le refus et conserve la saisie manuelle après fermeture', async () => {
    mocks.camera.mockRejectedValue(new DOMException('Permission denied', 'NotAllowedError'));
    await afficher();
    fireEvent.click(screen.getByRole('button', { name: 'QR' }));
    expect(await screen.findByRole('alert')).toHaveTextContent('Accès à la caméra refusé');
    expect(mocks.start).not.toHaveBeenCalled();
    expect(mutations()).toHaveLength(0);
    fireEvent.click(screen.getByRole('button', { name: 'Annuler le scan QR' }));
    fireEvent.change(screen.getByRole('textbox', { name: 'Code de pointage à 6 chiffres' }), { target: { value: '654321' } });
    fireEvent.click(screen.getByRole('button', { name: 'Pointer mon arrivée' }));
    await waitFor(() => expect(mutations()).toHaveLength(1));
  });

  it('ferme pendant la permission puis arrête le flux tardif sans démarrer de lecteur', async () => {
    let autoriser!: (stream: ReturnType<typeof cameraStream>) => void;
    mocks.camera.mockImplementation(() => new Promise(resolve => { autoriser = resolve; }));
    await afficher();
    fireEvent.click(screen.getByRole('button', { name: 'QR' }));
    await waitFor(() => expect(mocks.camera).toHaveBeenCalledTimes(1));
    fireEvent.click(screen.getByRole('button', { name: 'Annuler le scan QR' }));
    await act(async () => { autoriser(cameraStream()); });
    expect(mocks.trackStop).toHaveBeenCalledTimes(1);
    expect(mocks.start).not.toHaveBeenCalled();
    expect(mutations()).toHaveLength(0);
    expect(screen.queryByRole('dialog')).not.toBeInTheDocument();
  });

  it('ferme pendant le démarrage du lecteur et le stoppe dès que sa promesse se termine', async () => {
    let demarrer!: () => void;
    mocks.start.mockImplementation(() => new Promise<void>(resolve => { demarrer = resolve; }));
    await afficher(); await ouvrir();
    fireEvent.click(screen.getByRole('button', { name: 'Annuler le scan QR' }));
    await act(async () => { demarrer(); });
    await waitFor(() => expect(mocks.stop).toHaveBeenCalledTimes(1));
    await act(async () => { await mocks.decoded?.('654321'); });
    expect(mocks.clear).toHaveBeenCalledTimes(1);
    expect(mutations()).toHaveLength(0);
  });

  it('conserve le message serveur du code expiré et ne rejoue pas le scan', async () => {
    mocks.rpc.mockImplementation(async (name: string) => name === 'fn_scanner_code_pointage'
      ? { data: null, error: { message: 'Code de pointage invalide ou expiré.' } }
      : { data: initial, error: null });
    await afficher(); await ouvrir();
    await act(async () => { await mocks.decoded?.('654321'); await mocks.decoded?.('654321'); });
    expect(screen.getByRole('dialog')).toHaveTextContent('Code de pointage invalide ou expiré. Demande le code actuel à l’établissement.');
    expect(mutations()).toHaveLength(1);
    expect(mocks.succes).not.toHaveBeenCalled();
  });

  it('conserve le scanner natif et son code sans ouvrir le lecteur web', async () => {
    mocks.native.mockReturnValue(true);
    mocks.scannerNatif.mockResolvedValue({ text: '654321', source: 'native', format: 'QR_CODE' });
    await afficher();
    fireEvent.click(screen.getByRole('button', { name: 'QR' }));
    await waitFor(() => expect(mutations()).toHaveLength(1));
    expect(screen.queryByRole('dialog')).not.toBeInTheDocument();
    expect(mocks.camera).not.toHaveBeenCalled();
    expect(mocks.start).not.toHaveBeenCalled();
  });

  for (const code of ['CANCELLED', 'PERMISSION_DENIED']) {
    it(`conserve l’échec natif ${code} sans mutation ni ouverture web`, async () => {
      mocks.native.mockReturnValue(true);
      mocks.scannerNatif.mockRejectedValue(Object.assign(new Error(code), { code }));
      await afficher();
      fireEvent.click(screen.getByRole('button', { name: 'QR' }));
      await waitFor(() => expect(mocks.erreur).toHaveBeenCalledWith('Scan impossible. Saisissez le code manuellement.'));
      expect(mutations()).toHaveLength(0);
      expect(screen.queryByRole('dialog')).not.toBeInTheDocument();
      expect(mocks.camera).not.toHaveBeenCalled();
      expect(screen.getByRole('button', { name: 'QR' })).toBeEnabled();
    });
  }
});
