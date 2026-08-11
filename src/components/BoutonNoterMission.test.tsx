import React from 'react';
import { act, fireEvent, render, screen } from '@testing-library/react';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { BoutonNoterMission } from './BoutonNoterMission';

const mocks = vi.hoisted(() => ({
  maybeSingle: vi.fn(),
  handleErrorSilent: vi.fn(),
}));

vi.mock('@/integrations/supabase/client', () => {
  const creerBuilder = () => {
    const builder: Record<string, any> = {};
    for (const methode of ['select', 'eq']) builder[methode] = () => builder;
    builder.maybeSingle = mocks.maybeSingle;
    return builder;
  };

  return {
    supabase: {
      from: vi.fn(() => creerBuilder()),
    },
  };
});

vi.mock('@/lib/handleError', () => ({
  handleErrorSilent: mocks.handleErrorSilent,
}));

vi.mock('@/components/ModalNoterMission', () => ({
  ModalNoterMission: ({ onClose }: { onClose: () => void }) => (
    <div role="dialog">
      Formulaire de notation
      <button type="button" onClick={onClose}>Fermer</button>
    </div>
  ),
}));

describe('BoutonNoterMission', () => {
  beforeEach(() => {
    mocks.maybeSingle.mockReset();
    mocks.handleErrorSilent.mockReset();
  });

  it('garde le CTA visible et utilisable pendant une vérification lente', async () => {
    let terminerVerification!: (resultat: unknown) => void;
    mocks.maybeSingle.mockReturnValueOnce(new Promise((resolve) => {
      terminerVerification = resolve;
    }));

    render(
      <BoutonNoterMission
        missionId="mission-1"
        sens="SOIGNANT_VERS_ETAB"
      />,
    );

    const bouton = screen.getByRole('button', { name: "Noter l'établissement" });
    expect(bouton).toBeVisible();
    expect(bouton).toHaveAttribute('aria-busy', 'true');

    fireEvent.click(bouton);
    expect(screen.getByRole('dialog')).toHaveTextContent('Formulaire de notation');

    await act(async () => {
      terminerVerification({ data: null, error: null });
    });
  });

  it('ne masque pas le CTA si la vérification distante échoue', async () => {
    mocks.maybeSingle.mockResolvedValueOnce({
      data: null,
      error: new Error('réseau indisponible'),
    });

    render(
      <BoutonNoterMission
        missionId="mission-2"
        sens="SOIGNANT_VERS_ETAB"
      />,
    );

    expect(await screen.findByRole('button', { name: "Noter l'établissement" })).toBeVisible();
    expect(await screen.findByRole('status')).toHaveTextContent("L'éligibilité sera contrôlée à l'envoi");
    expect(mocks.handleErrorSilent).toHaveBeenCalledOnce();
  });

  it('affiche la confirmation quand la mission a déjà été notée', async () => {
    mocks.maybeSingle.mockResolvedValueOnce({ data: { id: 'notation-1' }, error: null });

    render(
      <BoutonNoterMission
        missionId="mission-3"
        sens="SOIGNANT_VERS_ETAB"
      />,
    );

    expect(await screen.findByText('Notation envoyée')).toBeVisible();
    expect(screen.queryByRole('button', { name: "Noter l'établissement" })).not.toBeInTheDocument();
  });
});
