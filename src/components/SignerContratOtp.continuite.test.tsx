import { act, fireEvent, render, screen, waitFor } from '@testing-library/react';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { SignerContratOtp } from './SignerContratOtp';

const mocks = vi.hoisted(() => ({ rpc: vi.fn(), notifier: vi.fn() }));
vi.mock('@/integrations/supabase/client', () => ({ supabase: { rpc: mocks.rpc } }));
vi.mock('@/contexts/NotificationContext', () => ({ useNotification: () => ({ afficherNotification: mocks.notifier }) }));
const sms = { data: { success: true, telephone_masked: 'numéro fictif', sms_restants: 2, expire_dans_minutes: 10 }, error: null };
const consentement = () => screen.getByRole('checkbox', { name: /J'ai lu l'intégralité du contrat/ });
const recevoir = () => screen.getByRole('button', { name: 'Recevoir le code SMS pour signer' });

describe('Signature OTP — continuité du contrat affiché', () => {
  beforeEach(() => { mocks.rpc.mockReset(); mocks.notifier.mockReset(); });

  it('redemande le consentement et un code lorsque le contrat affiché change', async () => {
    mocks.rpc.mockResolvedValue(sms);
    const { rerender } = render(<SignerContratOtp contratId="contrat-a" hashDocument="hash-a" />);
    fireEvent.click(consentement()); fireEvent.click(recevoir());
    fireEvent.change(await screen.findByRole('textbox', { name: 'Code SMS à 6 chiffres' }), { target: { value: '123456' } });
    rerender(<SignerContratOtp contratId="contrat-b" hashDocument="hash-b" />);
    expect(consentement()).not.toBeChecked();
    expect(screen.queryByRole('textbox', { name: 'Code SMS à 6 chiffres' })).not.toBeInTheDocument();
    expect(recevoir()).toBeDisabled();
    expect(mocks.rpc).toHaveBeenCalledTimes(1);
  });

  it('ignore la réponse du précédent document si son hash change pendant l’envoi', async () => {
    let resoudre!: (value: typeof sms) => void;
    mocks.rpc.mockReturnValue(new Promise(resolve => { resoudre = resolve; }));
    const { rerender } = render(<SignerContratOtp contratId="contrat-a" hashDocument="hash-a" />);
    fireEvent.click(consentement()); fireEvent.click(recevoir());
    rerender(<SignerContratOtp contratId="contrat-a" hashDocument="hash-b" />);
    await act(async () => resoudre(sms));
    expect(screen.queryByRole('textbox', { name: 'Code SMS à 6 chiffres' })).not.toBeInTheDocument();
    expect(consentement()).not.toBeChecked();
    expect(mocks.notifier).not.toHaveBeenCalled();
  });

  it('bloque tout nouvel envoi et signature après un refus pour document modifié', async () => {
    mocks.rpc.mockResolvedValueOnce(sms).mockResolvedValue({ data: { success: false, error_code: 'HASH_DOCUMENT_CHANGE' }, error: null });
    render(<SignerContratOtp contratId="contrat-a" hashDocument="hash-a" />);
    fireEvent.click(consentement()); fireEvent.click(recevoir());
    fireEvent.change(await screen.findByRole('textbox', { name: 'Code SMS à 6 chiffres' }), { target: { value: '123456' } });
    fireEvent.click(screen.getByRole('button', { name: 'Signer' }));
    await waitFor(() => expect(screen.getByText('Le contrat a été modifié depuis votre chargement. Rechargez la page avant de signer.')).toBeInTheDocument());
    expect(screen.getByRole('button', { name: 'Signer' })).toBeDisabled();
    expect(screen.getByRole('button', { name: 'Renvoyer le code' })).toBeDisabled();
    expect(mocks.rpc).toHaveBeenCalledTimes(2);
  });

  it.each(['envoi', 'signature'])('traduit le refus JWT pendant %s sans prétendre signer', async (etape) => {
    const onSigne = vi.fn();
    if (etape === 'signature') mocks.rpc.mockResolvedValueOnce(sms);
    mocks.rpc.mockResolvedValue({ data: null, error: { code: 'PGRST301', message: 'JWT expired' } });
    render(<SignerContratOtp contratId="contrat-a" hashDocument="hash-a" onSigne={onSigne} />);
    fireEvent.click(consentement()); fireEvent.click(recevoir());
    if (etape === 'signature') {
      fireEvent.change(await screen.findByRole('textbox', { name: 'Code SMS à 6 chiffres' }), { target: { value: '123456' } });
      fireEvent.click(screen.getByRole('button', { name: 'Signer' }));
    }
    await waitFor(() => expect(mocks.notifier).toHaveBeenLastCalledWith({
      type: 'erreur', message: 'Votre session a expiré ou n’est plus valide. Reconnectez-vous puis réessayez.',
    }));
    expect(onSigne).not.toHaveBeenCalled();
  });
});
