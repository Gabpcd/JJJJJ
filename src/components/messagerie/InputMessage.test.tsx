import { act, fireEvent, render, screen, waitFor } from '@testing-library/react';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { InputMessage } from './InputMessage';

const mocks = vi.hoisted(() => ({
  envoyer: vi.fn(),
  rpc: vi.fn(),
  haptic: vi.fn(),
}));

vi.mock('@/lib/messagerieEnvoi', () => ({
  envoyerMessageAvecAntiFuite: mocks.envoyer,
}));

vi.mock('@/integrations/supabase/client', () => ({
  supabase: { rpc: mocks.rpc },
}));

vi.mock('@/lib/haptics', () => ({
  hapticImpact: mocks.haptic,
}));

describe('InputMessage — validation atomique', () => {
  beforeEach(() => {
    mocks.envoyer.mockReset();
    mocks.rpc.mockReset();
    mocks.haptic.mockReset();
    mocks.rpc.mockResolvedValue({ data: null, error: null });
  });

  it('ouvre la modale sur un refus HTTP et conserve le message à corriger', async () => {
    mocks.envoyer.mockResolvedValue({
      success: false,
      error: 'ANTI_LEAK_REFUSE',
      detectedType: 'TELEPHONE',
    });
    render(<InputMessage conversationId="conversation-1" />);

    const input = screen.getByRole('textbox', { name: 'Saisir un message' });
    fireEvent.change(input, {
      target: { value: 'Appelez-moi au 06 12 34 56 78' },
    });
    fireEvent.click(screen.getByRole('button', { name: 'Envoyer le message' }));

    expect(await screen.findByText('Pour votre sécurité')).toBeInTheDocument();
    expect(screen.getByText(
      'Les numéros de téléphone ne peuvent pas être échangés via la messagerie Jolene.',
    )).toBeInTheDocument();
    expect(input).toHaveValue('Appelez-moi au 06 12 34 56 78');
    expect(mocks.envoyer).toHaveBeenCalledTimes(1);
  });

  it('efface le texte uniquement après le succès de l’unique appel Edge', async () => {
    const onSent = vi.fn();
    mocks.envoyer.mockResolvedValue({ success: true, messageId: 'message-1' });
    render(
      <InputMessage conversationId="conversation-1" onSent={onSent} />,
    );

    const input = screen.getByRole('textbox', { name: 'Saisir un message' });
    fireEvent.change(input, { target: { value: 'A & B et 1 < 2' } });
    fireEvent.click(screen.getByRole('button', { name: 'Envoyer le message' }));

    await waitFor(() => expect(input).toHaveValue(''));
    expect(mocks.envoyer).toHaveBeenCalledTimes(1);
    expect(mocks.envoyer).toHaveBeenCalledWith(
      'conversation-1',
      'A & B et 1 < 2',
    );
    expect(onSent).toHaveBeenCalledWith('message-1');
  });

  it('ne lance jamais deux envois dans le même tick', async () => {
    let terminer!: (resultat: { success: boolean }) => void;
    mocks.envoyer.mockReturnValueOnce(new Promise(resolve => { terminer = resolve; }));
    render(<InputMessage conversationId="conversation-1" />);

    const input = screen.getByRole('textbox', { name: 'Saisir un message' });
    fireEvent.change(input, { target: { value: 'Bonjour' } });
    act(() => {
      fireEvent.keyDown(input, { key: 'Enter', shiftKey: false });
      fireEvent.keyDown(input, { key: 'Enter', shiftKey: false });
    });

    expect(mocks.envoyer).toHaveBeenCalledTimes(1);
    terminer({ success: true, messageId: 'message-1' } as any);
    await waitFor(() => expect(input).toHaveValue(''));
  });

  it("n'envoie pas pendant la composition IME", () => {
    render(<InputMessage conversationId="conversation-1" />);
    const input = screen.getByRole('textbox', { name: 'Saisir un message' });
    fireEvent.change(input, { target: { value: 'Bonjour' } });
    fireEvent.keyDown(input, {
      key: 'Enter',
      shiftKey: false,
      isComposing: true,
    });

    expect(mocks.envoyer).not.toHaveBeenCalled();
  });
});
