import React from 'react';
import { act, cleanup, fireEvent, render, screen, waitFor, within } from '@testing-library/react';
import { afterEach, beforeAll, beforeEach, describe, expect, it, vi } from 'vitest';
import { LitigeResolutionModal } from './LitigeResolutionModal';
import type { LitigeEnrichi } from './types';

const { rpc, invoke, facture, resolved, toastError, toastSuccess, logError } = vi.hoisted(() => ({
  rpc: vi.fn(), invoke: vi.fn(), facture: vi.fn(), resolved: vi.fn(),
  toastError: vi.fn(), toastSuccess: vi.fn(), logError: vi.fn(),
}));
vi.mock('@/integrations/supabase/client', () => ({ supabase: {
  rpc, functions: { invoke }, from: () => ({ select: () => ({ eq: () => ({ maybeSingle: facture }) }) }),
} }));
vi.mock('@/lib/logger', () => ({ logger: { error: logError } }));
vi.mock('sonner', () => ({ toast: { error: toastError, success: toastSuccess } }));
vi.mock('./LitigesSimilairesPanel', () => ({ LitigesSimilairesPanel: () => null }));

const decision = 'Décision fictive sans changement financier.';
const litige = (contrat = 'LIBERAL', id = 'litige-a'): LitigeEnrichi => ({
  id, motif: `Litige ${id}`, statut: 'REVUE_ADMIN', cree_le: '2026-09-28T12:00:00Z',
  reponse: null, resolution: null, resolu_le: null, soignant_id: 'soignant',
  etablissement_id: 'etablissement', mission_id: 'mission', initie_par: 'SYSTEME',
  mission: { id: 'mission', intitule: 'Mission fictive', profession_requise: 'IDE', service: null,
    debut_le: '2026-09-28T08:00:00Z', fin_le: '2026-09-28T16:00:00Z', statut: 'TERMINEE',
    duree_heures: 8, taux_horaire_base: 30, taux_horaire_base_fige: 30, taux_rist_plafonne: null,
    rist_plafond_applique: false, type_contrat_applique: contrat },
});
const props = (dossier = litige(), open = true) => ({ litige: dossier, open, onOpenChange: vi.fn(), onResolved: resolved });
async function remplir() {
  fireEvent.change(screen.getByRole('textbox', { name: 'Résolution' }), { target: { value: decision } });
  fireEvent.keyDown(screen.getByRole('combobox', { name: 'En faveur de' }), { key: 'ArrowDown' });
  fireEvent.click(screen.getByRole('option', { name: 'Neutre' }));
  await waitFor(() => expect(screen.getByRole('combobox', { name: 'En faveur de' })).toHaveFocus());
  return screen.getByRole('button', { name: 'Valider la résolution' });
}
function attente<T>() {
  let terminer!: (value: T) => void;
  const promise = new Promise<T>(resolve => { terminer = resolve; });
  return { promise, terminer };
}

beforeAll(() => {
  // Radix Select utilise ces API de navigateur absentes de jsdom.
  HTMLElement.prototype.hasPointerCapture = () => false;
  HTMLElement.prototype.scrollIntoView = () => {};
});
beforeEach(() => { vi.resetAllMocks(); });
afterEach(cleanup);

describe('Résolution — retours dans le dialogue', () => {
  it.each(['SALARIE', 'LIBERAL'])('%s : ouvre et ferme l’information sans résoudre ni fermer le litige', async contrat => {
    const initialProps = props(litige(contrat));
    render(<LitigeResolutionModal {...initialProps} />);
    const heures = screen.getByRole('spinbutton', { name: 'Ajuster les heures' });
    fireEvent.change(heures, { target: { value: '9' } });
    const information = screen.getByRole('button', { name: 'Information sur les cotisations sociales' });
    expect(information).toHaveAttribute('aria-expanded', 'false');
    fireEvent.click(information);
    const panneau = await screen.findByRole('dialog', { name: 'Information sur les cotisations sociales' });
    expect(information).toHaveAttribute('aria-expanded', 'true');
    expect(information).toHaveAttribute('aria-controls', panneau.id);
    expect(panneau).toHaveAccessibleDescription();
    // Safari refocalise le dialogue avant de délivrer le clic sur le déclencheur.
    fireEvent.focus(screen.getByRole('dialog', { name: 'Résoudre le litige' }));
    expect(panneau).toBeInTheDocument();
    fireEvent.click(information);
    await waitFor(() => expect(panneau).not.toBeInTheDocument());
    fireEvent.click(information);
    const panneauRouvert = await screen.findByRole('dialog', { name: 'Information sur les cotisations sociales' });
    fireEvent.click(within(panneauRouvert).getByRole('button', { name: 'Fermer l’information' }));
    await waitFor(() => expect(panneauRouvert).not.toBeInTheDocument());
    expect(information).toHaveFocus();
    fireEvent.click(information);
    await screen.findByRole('dialog', { name: 'Information sur les cotisations sociales' });
    fireEvent.keyDown(document, { key: 'Escape' });
    await waitFor(() => expect(information).toHaveAttribute('aria-expanded', 'false'));
    expect(information).toHaveFocus();
    expect(screen.getByRole('dialog', { name: 'Résoudre le litige' })).toBeVisible();
    expect(heures).toHaveValue(9);
    expect(initialProps.onOpenChange).not.toHaveBeenCalled();
    expect(rpc).not.toHaveBeenCalled();
    expect(invoke).not.toHaveBeenCalled();
    expect(resolved).not.toHaveBeenCalled();
  });

  it.each(['SALARIE', 'LIBERAL'])('%s : refus accessible, saisie conservée et réessai immédiat sans toast', async contrat => {
    rpc.mockResolvedValueOnce({ data: { success: false, error: 'Administrateur requis.' }, error: null })
      .mockResolvedValueOnce({ data: { success: true, action_financiere: 'AUCUNE' }, error: null });
    render(<LitigeResolutionModal {...props(litige(contrat))} />);
    const bouton = await remplir();
    fireEvent.click(bouton);
    const alerte = await screen.findByRole('alert');
    expect(within(screen.getByRole('dialog')).getByRole('alert')).toBe(alerte);
    expect(alerte).toHaveTextContent('Administrateur requis.');
    expect(alerte).toHaveFocus();
    expect(bouton).toHaveAccessibleDescription('Administrateur requis.');
    expect(screen.getByRole('textbox', { name: 'Résolution' })).toHaveValue(decision);
    expect(bouton).toBeEnabled();
    fireEvent.click(bouton);
    expect(await screen.findByRole('status')).toHaveTextContent('Litige résolu avec succès.');
    expect(screen.queryByRole('alert')).not.toBeInTheDocument();
    expect(bouton).toBeDisabled();
    fireEvent.click(bouton);
    expect(rpc).toHaveBeenCalledTimes(2);
    expect(rpc).toHaveBeenLastCalledWith('fn_admin_resoudre_litige_intelligent', {
      p_litige_id: 'litige-a', p_resolution: decision, p_en_faveur_de: 'NEUTRE',
      p_ajuster_heures: undefined, p_ajuster_taux: undefined, p_action_financiere: 'AUTO',
    });
    expect(resolved).toHaveBeenCalledTimes(1);
    expect(toastError).not.toHaveBeenCalled();
    expect(toastSuccess).not.toHaveBeenCalled();
  });

  it('verrouille les clics simultanés et ignore une réponse tardive du dossier précédent', async () => {
    const requete = attente<{ data: { success: boolean }; error: null }>();
    rpc.mockReturnValueOnce(requete.promise);
    const initialProps = props();
    const { rerender } = render(<LitigeResolutionModal {...initialProps} />);
    const bouton = await remplir();
    act(() => { bouton.click(); bouton.click(); });
    expect(rpc).toHaveBeenCalledTimes(1);
    expect(bouton).toBeDisabled();
    expect(screen.getAllByRole('button', { name: 'Fermer' })[0]).toBeDisabled();
    fireEvent.keyDown(document, { key: 'Escape' });
    expect(initialProps.onOpenChange).not.toHaveBeenCalled();
    rerender(<LitigeResolutionModal {...props(litige('SALARIE', 'litige-b'))} />);
    expect(screen.getByRole('textbox', { name: 'Résolution' })).toHaveValue('');
    expect(screen.getByRole('combobox', { name: 'En faveur de' })).toHaveTextContent('Choisir...');
    await act(async () => { requete.terminer({ data: { success: true }, error: null }); });
    expect(screen.queryByRole('status')).not.toBeInTheDocument();
    expect(screen.queryByRole('alert')).not.toBeInTheDocument();
    expect(resolved).not.toHaveBeenCalled();
    rpc.mockResolvedValueOnce({ data: { success: true }, error: null });
    fireEvent.click(await remplir());
    await screen.findByRole('status');
    expect(rpc).toHaveBeenLastCalledWith('fn_admin_resoudre_litige_intelligent', expect.objectContaining({ p_litige_id: 'litige-b' }));
  });

  it('efface saisie et refus à la réouverture du même dossier', async () => {
    rpc.mockResolvedValue({ data: { error: 'Refus fictif.' }, error: null });
    const dossier = litige();
    const { rerender } = render(<LitigeResolutionModal {...props(dossier)} />);
    fireEvent.click(await remplir());
    await screen.findByRole('alert');
    rerender(<LitigeResolutionModal {...props(dossier, false)} />);
    rerender(<LitigeResolutionModal {...props(dossier)} />);
    expect(screen.getByRole('textbox', { name: 'Résolution' })).toHaveValue('');
    expect(screen.queryByRole('alert')).not.toBeInTheDocument();
    expect(screen.queryByRole('status')).not.toBeInTheDocument();
  });

  it.each([null, { success: false }])('ne confirme pas une réponse incomplète %j', async data => {
    rpc.mockResolvedValue({ data, error: null });
    render(<LitigeResolutionModal {...props()} />);
    const bouton = await remplir();
    fireEvent.click(bouton);
    expect(await screen.findByRole('alert')).toHaveTextContent('La résolution n’a pas été confirmée.');
    expect(screen.queryByTestId('result-json')).not.toBeInTheDocument();
    expect(screen.queryByRole('status')).not.toBeInTheDocument();
    expect(bouton).toBeEnabled();
    expect(resolved).not.toHaveBeenCalled();
  });

  it('garde le détail technique Supabase dans le logger et affiche un refus français réessayable', async () => {
    const transport = { message: 'TypeError: Failed to fetch', code: 'NETWORK_ERROR' };
    rpc.mockResolvedValueOnce({ data: null, error: transport })
      .mockResolvedValueOnce({ data: { success: true }, error: null });
    render(<LitigeResolutionModal {...props()} />);
    const bouton = await remplir();
    fireEvent.click(bouton);
    expect(await screen.findByRole('alert')).toHaveTextContent('Erreur lors de la résolution.');
    expect(screen.queryByText(/Failed to fetch/)).not.toBeInTheDocument();
    expect(logError).toHaveBeenCalledWith('fn_admin_resoudre_litige_intelligent error', transport);
    expect(bouton).toBeEnabled();
    fireEvent.click(bouton);
    await screen.findByRole('status');
    expect(rpc).toHaveBeenCalledTimes(2);
  });

  it('libère le formulaire après rejet transport et accepte un nouvel essai', async () => {
    rpc.mockRejectedValueOnce(new Error('Transport fictif indisponible'))
      .mockResolvedValueOnce({ data: { success: true }, error: null });
    render(<LitigeResolutionModal {...props()} />);
    const bouton = await remplir();
    fireEvent.click(bouton);
    expect(await screen.findByRole('alert')).toHaveTextContent('Erreur lors de la résolution.');
    expect(logError).toHaveBeenCalledWith('LitigeResolutionModal resolution error', expect.any(Error));
    expect(screen.queryByText('Transport fictif indisponible')).not.toBeInTheDocument();
    expect(bouton).toBeEnabled();
    fireEvent.click(bouton);
    await screen.findByRole('status');
    expect(rpc).toHaveBeenCalledTimes(2);
  });

  it('affiche le refus de sécurisation du paiement sans lancer la résolution financière', async () => {
    facture.mockResolvedValue({ data: { id: 'facture', numero_facture: 'F-RECETTE', statut: 'EMISE',
      montant_ht: 240, montant_tva: 0, montant_ttc: 240, taux_tva: 0, quantite_heures_snapshot: 8, taux_horaire_snapshot: 30 }, error: null });
    rpc.mockResolvedValue({ data: { success: true, montant_ttc: 240 }, error: null });
    invoke.mockResolvedValue({ data: { error: 'refus', message: 'Paiement en cours : réessayez.' }, error: null });
    render(<LitigeResolutionModal {...props({ ...litige(), facture_id: 'facture' })} />);
    await screen.findByText('Facture exacte à corriger : F-RECETTE');
    fireEvent.click(await remplir());
    expect(await screen.findByRole('alert')).toHaveTextContent('Paiement en cours : réessayez.');
    expect(rpc).toHaveBeenCalledTimes(1);
    expect(rpc).toHaveBeenCalledWith('fn_admin_solde_correction_facture_honoraires', { p_facture_id: 'facture' });
    expect(invoke).toHaveBeenCalledWith('expire-invoice-checkout-for-dispute', { body: { litige_id: 'litige-a' } });
    expect(resolved).not.toHaveBeenCalled();
    expect(screen.getByRole('button', { name: 'Valider la résolution' })).toBeEnabled();
  });
});
