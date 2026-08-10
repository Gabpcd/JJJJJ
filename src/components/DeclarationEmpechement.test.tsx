import React from 'react';
import { fireEvent, render, screen, waitFor } from '@testing-library/react';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { DeclarationEmpechement } from './DeclarationEmpechement';

const mocks = vi.hoisted(() => ({
  rpc: vi.fn(),
  success: vi.fn(),
  warning: vi.fn(),
  error: vi.fn(),
}));

vi.mock('@/integrations/supabase/client', () => ({ supabase: { rpc: mocks.rpc } }));
vi.mock('sonner', () => ({
  toast: { success: mocks.success, warning: mocks.warning, error: mocks.error },
}));

describe('DeclarationEmpechement — parcours frontend sans donnée de santé', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mocks.rpc.mockResolvedValue({ data: { success: true, depassement: false }, error: null });
  });

  it('demande seulement les dates et une attestation puis prévient le backend', async () => {
    const onDeclare = vi.fn();
    render(<DeclarationEmpechement missionId="mission-1" onDeclare={onDeclare} />);

    fireEvent.click(screen.getByRole('button', { name: /Je ne peux pas assurer cette mission/i }));
    expect(screen.getByText(/Aucun justificatif ni motif/i)).toBeInTheDocument();
    expect(screen.queryByLabelText(/motif/i)).not.toBeInTheDocument();
    expect(screen.queryByLabelText(/justificatif/i)).not.toBeInTheDocument();

    fireEvent.change(screen.getByLabelText('Indisponible du *'), { target: { value: '2026-08-20' } });
    fireEvent.change(screen.getByLabelText('au *'), { target: { value: '2026-08-21' } });
    fireEvent.click(screen.getByRole('checkbox'));
    fireEvent.click(screen.getByRole('button', { name: 'Déclarer' }));

    await waitFor(() => expect(mocks.rpc).toHaveBeenCalledWith(
      'fn_declarer_empechement_imperieux',
      { p_mission_id: 'mission-1', p_indispo_debut: '2026-08-20', p_indispo_fin: '2026-08-21' },
    ));
    expect(onDeclare).toHaveBeenCalledTimes(1);
    expect(mocks.success).toHaveBeenCalledWith(expect.stringMatching(/établissement est prévenu/i));
  });
});
