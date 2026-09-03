import { render, screen, waitFor } from '@testing-library/react';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { CertificatSignature } from './CertificatSignature';

const { order, from } = vi.hoisted(() => {
  const orderMock = vi.fn();
  const eq = vi.fn(() => ({ order: orderMock }));
  const select = vi.fn(() => ({ eq }));
  return { order: orderMock, from: vi.fn(() => ({ select })) };
});

vi.mock('@/integrations/supabase/client', () => ({
  supabase: { from },
}));

describe('CertificatSignature sans preuve OTP', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    order.mockResolvedValue({ data: [], error: null });
  });

  it('ne contredit pas le statut de signature dans le résumé du contrat', async () => {
    const { container } = render(<CertificatSignature contratId="contrat-test" />);

    await waitFor(() => expect(order).toHaveBeenCalled());
    expect(container).toBeEmptyDOMElement();
    expect(screen.queryByText(/aucune signature enregistrée/i)).not.toBeInTheDocument();
  });

  it('précise l’absence de preuve OTP sur la vue de détail', async () => {
    render(<CertificatSignature contratId="contrat-test" variant="detail" />);

    expect(await screen.findByText(/aucune preuve OTP détaillée/i)).toBeInTheDocument();
  });
});
