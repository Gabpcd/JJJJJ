import { render, screen } from '@testing-library/react';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { SectionEvenementsScore } from './SectionEvenementsScore';

const { rpc } = vi.hoisted(() => ({ rpc: vi.fn() }));

vi.mock('@/integrations/supabase/client', () => ({
  supabase: { rpc },
}));

vi.mock('@/components/score/ModaleReclamationScore', () => ({
  ModaleReclamationScore: () => null,
}));

describe('SectionEvenementsScore', () => {
  beforeEach(() => {
    rpc.mockResolvedValue({ data: { events: [] }, error: null });
  });

  it('vouvoie un établissement', async () => {
    render(<SectionEvenementsScore type="ETAB" />);

    expect(await screen.findByText(/impactant votre score/i)).toBeInTheDocument();
    expect(screen.getByText(/Vous pourrez contester/i)).toBeInTheDocument();
    expect(screen.queryByText(/ton score/i)).not.toBeInTheDocument();
  });

  it('conserve le tutoiement côté soignant', async () => {
    render(<SectionEvenementsScore type="SOIGNANT" />);

    expect(await screen.findByText(/impactant ton score/i)).toBeInTheDocument();
    expect(screen.getByText(/Tu pourras contester/i)).toBeInTheDocument();
  });
});
