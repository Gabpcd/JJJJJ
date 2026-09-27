import React from 'react';
import { act, fireEvent, render, screen, waitFor } from '@testing-library/react';
import { beforeEach, expect, it, vi } from 'vitest';
import { ChangementMotDePasse } from './ChangementMotDePasse';

const m = vi.hoisted(() => ({ login: vi.fn(), update: vi.fn(), audit: vi.fn(), notifier: vi.fn() }));
vi.mock('@/contexts/AuthContext', () => ({ useAuth: () => ({ user: { id: 'compte-test', email: 'compte@example.invalid' } }) }));
vi.mock('@/contexts/NotificationContext', () => ({ useNotification: () => ({ afficherNotification: m.notifier }) }));
vi.mock('@/integrations/supabase/client', () => ({ supabase: { auth: { signInWithPassword: m.login, updateUser: m.update }, rpc: m.audit } }));
beforeEach(() => { vi.clearAllMocks(); m.login.mockResolvedValue({ error: null }); m.update.mockResolvedValue({ error: null }); m.audit.mockResolvedValue({ error: null }); });
function formulaire() {
  const { container } = render(<ChangementMotDePasse />);
  const inputs = container.querySelectorAll('input');
  ['MotActuel!123456', 'MotNouveau!789Abc', 'MotNouveau!789Abc'].forEach((value, i) => fireEvent.change(inputs[i], { target: { value } }));
  return container.querySelector('form')!;
}
it('ne soumet qu’une modification pendant la vérification et traduit le refus de sécurité', async () => {
  let resolve!: (value: { error: null }) => void;
  m.login.mockReturnValue(new Promise(r => { resolve = r; }));
  m.update.mockResolvedValue({ error: { code: 'weak_password', message: 'Password is known to be weak and easy to guess' } });
  const form = formulaire();
  fireEvent.submit(form); fireEvent.submit(form);
  expect(m.login).toHaveBeenCalledTimes(1);
  await act(async () => resolve({ error: null }));
  await waitFor(() => expect(m.update).toHaveBeenCalledTimes(1));
  expect(m.notifier).toHaveBeenCalledWith(expect.objectContaining({ type: 'erreur', message: expect.not.stringMatching(/Password|weak|guess/) }));
  expect(screen.getByRole('button', { name: 'Modifier mon mot de passe' })).not.toBeDisabled();
  expect(m.audit).not.toHaveBeenCalled();
});
it('une panne réseau ne prétend pas que l’ancien mot de passe est faux et autorise la reprise', async () => {
  m.login.mockResolvedValueOnce({ error: new TypeError('Load failed') });
  const form = formulaire();
  fireEvent.submit(form);
  await waitFor(() => expect(m.notifier).toHaveBeenCalled());
  expect(m.notifier.mock.calls[0][0].message).not.toMatch(/Ancien mot de passe incorrect/);
  expect(m.update).not.toHaveBeenCalled();
  fireEvent.submit(form);
  await waitFor(() => expect(m.notifier).toHaveBeenCalledWith({ type: 'succes', message: 'Mot de passe modifié avec succès.' }));
  expect(m.update).toHaveBeenCalledTimes(1);
});
