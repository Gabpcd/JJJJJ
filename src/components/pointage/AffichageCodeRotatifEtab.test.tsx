import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { render, screen } from '@testing-library/react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { AffichageCodeRotatifEtab } from './AffichageCodeRotatifEtab';

const mocks = vi.hoisted(() => ({
  from: vi.fn(),
  rpc: vi.fn(),
}));

vi.mock('@/integrations/supabase/client', () => ({
  supabase: { from: mocks.from, rpc: mocks.rpc },
}));

vi.mock('qrcode.react', () => ({
  QRCodeSVG: ({ value }: { value: string }) => <div data-testid="qr-code">{value}</div>,
}));

function creerBuilder(data: unknown, single = false) {
  const builder: Record<string, any> = {};
  for (const methode of ['select', 'eq', 'not', 'order']) {
    builder[methode] = vi.fn(() => builder);
  }
  builder.single = vi.fn(() => Promise.resolve({ data, error: null }));
  builder.then = (resolve: (value: unknown) => unknown, reject: (reason: unknown) => unknown) => (
    Promise.resolve({ data: single ? data : data, error: null }).then(resolve, reject)
  );
  return builder;
}

function renderCode() {
  const queryClient = new QueryClient({
    defaultOptions: { queries: { retry: false } },
  });
  render(
    <QueryClientProvider client={queryClient}>
      <AffichageCodeRotatifEtab missionId="mission-1" />
    </QueryClientProvider>,
  );
  return queryClient;
}

describe('AffichageCodeRotatifEtab — fenêtre du créneau', () => {
  let creneauxBuilder: Record<string, any>;
  let creneaux: unknown[];
  let contrats: unknown[];

  beforeEach(() => {
    vi.useFakeTimers({ toFake: ['Date'] });
    vi.setSystemTime(new Date('2026-07-31T10:00:00+02:00'));
    creneaux = [];
    contrats = [{
      id: 'contrat-1',
      mission_id: 'mission-1',
      statut: 'SIGNE_COMPLET',
      cree_le: '2026-07-01T10:00:00Z',
    }];
    mocks.from.mockReset();
    mocks.rpc.mockReset();
    mocks.rpc.mockResolvedValue({
      data: {
        statut: 'EN_COURS',
        prochain_type_scan: 'OUVERTURE',
        segment_ouvert: false,
        segments: [],
        code_pointage_actif: '123456',
      },
      error: null,
    });
    mocks.from.mockImplementation((table: string) => {
      if (table === 'missions') {
        return creerBuilder({
          id: 'mission-1',
          debut_le: '2026-07-06T08:00:00+02:00',
          fin_le: '2026-08-31T16:00:00+02:00',
        }, true);
      }
      if (table === 'contrats_mission') return creerBuilder(contrats);
      creneauxBuilder = creerBuilder(creneaux);
      return creneauxBuilder;
    });
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  it('masque le code et explique le prochain créneau lorsqu’il est trop tôt', async () => {
    creneaux = [{
      id: 'creneau-1',
      mission_id: 'mission-1',
      debut: '2026-08-31T08:00:00+02:00',
      fin: '2026-08-31T16:00:00+02:00',
      est_pause: false,
      type_creneau: 'PREVISIONNEL',
    }];

    renderCode();

    expect(await screen.findByText('Code masqué hors créneau')).toBeInTheDocument();
    expect(screen.getByText(/créneau 1\/1, le lundi 31 août 2026 à 08:00/i)).toBeInTheDocument();
    expect(screen.queryByText('123 456')).not.toBeInTheDocument();
    expect(screen.queryByTestId('qr-code')).not.toBeInTheDocument();
    expect(creneauxBuilder.eq).toHaveBeenCalledWith('type_creneau', 'PREVISIONNEL');
    expect(creneauxBuilder.eq).toHaveBeenCalledWith('est_pause', false);
  });

  it('affiche le code et la progression pendant le créneau', async () => {
    creneaux = [{
      id: 'creneau-1',
      mission_id: 'mission-1',
      debut: '2026-07-31T08:00:00+02:00',
      fin: '2026-07-31T16:00:00+02:00',
      est_pause: false,
      type_creneau: 'PREVISIONNEL',
    }];

    renderCode();

    expect(await screen.findByText('123 456')).toBeInTheDocument();
    expect(screen.getByText(/Créneau 1\/1 · vendredi 31 juillet 2026 à 08:00 → 16:00/i)).toBeInTheDocument();
    expect(screen.getByTestId('qr-code')).toHaveTextContent('123456');
    expect(screen.queryByText('Code masqué hors créneau')).not.toBeInTheDocument();
  });

  it('laisse toujours visible le code de sortie lorsqu’un segment est déjà ouvert', async () => {
    creneaux = [{
      id: 'creneau-1',
      mission_id: 'mission-1',
      debut: '2026-07-30T08:00:00+02:00',
      fin: '2026-07-30T16:00:00+02:00',
      est_pause: false,
      type_creneau: 'PREVISIONNEL',
    }];
    mocks.rpc.mockResolvedValue({
      data: {
        statut: 'EN_COURS',
        prochain_type_scan: 'FERMETURE',
        segment_ouvert: true,
        segments: [{ id: 'segment-1', debut: '2026-07-31T08:00:00+02:00', fin: null }],
        code_pointage_actif: '654321',
      },
      error: null,
    });

    renderCode();

    expect(await screen.findByText('654 321')).toBeInTheDocument();
    expect(screen.getByText('Segment en cours')).toBeInTheDocument();
    expect(screen.queryByText('Code masqué hors créneau')).not.toBeInTheDocument();
  });

  it('masque le code d’arrivée tant que le contrat n’est pas signé', async () => {
    contrats = [{
      id: 'contrat-1',
      mission_id: 'mission-1',
      statut: 'EN_ATTENTE_SIGNATURES',
      cree_le: '2026-07-01T10:00:00Z',
    }];
    creneaux = [{
      id: 'creneau-1',
      mission_id: 'mission-1',
      debut: '2026-07-31T08:00:00+02:00',
      fin: '2026-07-31T16:00:00+02:00',
      est_pause: false,
      type_creneau: 'PREVISIONNEL',
    }];

    renderCode();

    expect(await screen.findByText('Code masqué — contrat non signé')).toBeInTheDocument();
    expect(screen.getByText(/signé par les deux parties/i)).toBeInTheDocument();
    expect(screen.queryByText('123 456')).not.toBeInTheDocument();
  });

  it('affiche une erreur actionnable si l’état serveur est indisponible', async () => {
    mocks.rpc.mockResolvedValue({ data: null, error: new Error('RPC indisponible') });

    renderCode();

    expect(await screen.findByRole('alert')).toHaveTextContent('Code de pointage indisponible');
    expect(screen.getByRole('button', { name: 'Réessayer' })).toBeInTheDocument();
  });
});
