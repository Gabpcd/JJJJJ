import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { render, screen } from '@testing-library/react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { PointageRotatifSoignant } from './PointageRotatifSoignant';

const mocks = vi.hoisted(() => ({ rpc: vi.fn() }));

vi.mock('@/integrations/supabase/client', () => ({
  supabase: {
    rpc: mocks.rpc,
    from: vi.fn(),
  },
}));

vi.mock('@/components/NotationRapide', () => ({
  SheetNotationRapide: () => null,
}));

function renderPointage() {
  const queryClient = new QueryClient({
    defaultOptions: { queries: { retry: false } },
  });
  render(
    <QueryClientProvider client={queryClient}>
      <PointageRotatifSoignant missionId="mission-1" consentementGPS={false} />
    </QueryClientProvider>,
  );
}

describe('PointageRotatifSoignant — jours civils Europe/Paris', () => {
  beforeEach(() => {
    vi.useFakeTimers({ toFake: ['Date'] });
    vi.setSystemTime(new Date('2026-07-31T14:00:00+02:00'));
    mocks.rpc.mockReset();
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  it('reste exact sans planning après un segment du même jour et affiche les heures de Paris sous UTC', async () => {
    mocks.rpc.mockResolvedValue({
      data: {
        statut: 'EN_COURS',
        prochain_type_scan: 'OUVERTURE',
        segment_ouvert: false,
        segments: [
          { id: 'veille', debut: '2026-07-30T06:00:00.000Z', fin: '2026-07-30T14:00:00.000Z' },
          { id: 'matin', debut: '2026-07-31T06:00:00.000Z', fin: '2026-07-31T10:00:00.000Z' },
        ],
      },
      error: null,
    });

    renderPointage();

    expect(await screen.findByRole('button', { name: 'Pointer mon arrivée / ma reprise' })).toBeInTheDocument();
    expect(screen.getByText(/30 juil\. · 08h00 → 16h00/)).toBeInTheDocument();
    expect(screen.getByText(/31 juil\. · 08h00 → 12h00/)).toBeInTheDocument();
  });

  it('propose une arrivée lorsque le dernier segment appartient à la veille à Paris', async () => {
    mocks.rpc.mockResolvedValue({
      data: {
        statut: 'EN_COURS',
        prochain_type_scan: 'OUVERTURE',
        segment_ouvert: false,
        segments: [
          { id: 'veille', debut: '2026-07-30T06:00:00.000Z', fin: '2026-07-30T14:00:00.000Z' },
        ],
      },
      error: null,
    });

    renderPointage();

    expect(await screen.findByRole('button', { name: "Pointer mon arrivée" })).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: 'Pointer mon arrivée / ma reprise' })).not.toBeInTheDocument();
  });
});
