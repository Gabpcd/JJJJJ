import React from 'react';
import { cleanup, fireEvent, render, screen, waitFor, within } from '@testing-library/react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { AvoirsList, type AvoirEnrichi } from './AvoirsList';

const mocks = vi.hoisted(() => ({
  rows: [] as AvoirEnrichi[],
  from: vi.fn(),
  rpc: vi.fn(),
  download: vi.fn(),
  error: vi.fn(),
  success: vi.fn(),
  selects: [] as string[],
}));
vi.mock('@/integrations/supabase/client', () => ({ supabase: { from: mocks.from, rpc: mocks.rpc } }));
vi.mock('@/lib/facture-honoraires-pdf', () => ({ telechargerFactureHonorairesPDF: mocks.download }));
vi.mock('@/lib/logger', () => ({ logger: { error: vi.fn() } }));
vi.mock('sonner', () => ({ toast: { error: mocks.error, success: mocks.success } }));

const avoir: AvoirEnrichi = {
  id: 'avoir-synthetique', numero_facture: 'AV-SYNTHETIQUE-001', type_document: 'AVOIR',
  statut: 'EMISE', mode_remboursement: 'VIREMENT_MANUEL', montant_ht: 60,
  montant_tva: 12, montant_ttc: 72, date_emission: '2026-10-01T10:00:00Z',
  date_remboursement: null, reference_remboursement: null, soignant_id: 'soignant-synthetique',
  etablissement_id: 'etablissement-synthetique', litige_id: null,
  facture_precedente_id: 'facture-origine-synthetique',
};

async function ouvrir() {
  fireEvent.click(await screen.findByRole('button', { name: 'Confirmer remboursement avoir AV-SYNTHETIQUE-001' }));
  return within(await screen.findByRole('dialog'));
}

beforeEach(() => {
  vi.clearAllMocks();
  mocks.rows = [{ ...avoir }];
  mocks.selects = [];
  mocks.download.mockResolvedValue(undefined);
  mocks.rpc.mockImplementation(async (name, args) => {
    if (name !== 'fn_confirmer_remboursement_avoir') throw new Error('RPC inattendue');
    mocks.rows = [{ ...avoir, statut: 'REMBOURSE', date_remboursement: '2026-10-04T16:00:00Z', reference_remboursement: args.p_reference_virement }];
    return { data: { ok: true }, error: null };
  });
  mocks.from.mockImplementation((table: string) => {
    const data = table === 'factures_honoraires' ? mocks.rows
      : table === 'soignants' ? [{ id: avoir.soignant_id, prenom: 'Camille', nom: 'Synthétique' }]
      : table === 'etablissements' ? [{ id: avoir.etablissement_id, nom: 'Établissement synthétique' }]
      : null;
    if (data === null) throw new Error('Lecture inattendue');
    const response = Promise.resolve({ data, error: null });
    const builder = {
      select: (columns: string) => { mocks.selects.push(columns); return builder; },
      eq: () => builder, order: () => builder, limit: () => builder, in: () => builder,
      then: response.then.bind(response),
    };
    return builder;
  });
});
afterEach(cleanup);

describe('AvoirsList — déclaration opérateur et pièces existantes', () => {
  it('relie les deux documents exacts sans opération financière ni attestation implicite', async () => {
    render(<AvoirsList />);
    const dialog = await ouvrir();
    expect(dialog.getByText('Camille Synthétique')).toBeVisible();
    expect(dialog.getByText('Établissement synthétique')).toBeVisible();
    expect(dialog.getByText(/ne désignent pas à elles seules le bénéficiaire bancaire/)).toBeVisible();
    expect(dialog.getByText(/Jolene ne vérifie pas automatiquement le virement/)).toBeVisible();
    fireEvent.click(dialog.getByRole('button', { name: 'Consulter l’avoir' }));
    fireEvent.click(dialog.getByRole('button', { name: 'Consulter la facture d’origine' }));
    await waitFor(() => expect(mocks.download.mock.calls).toEqual([[avoir.id], [avoir.facture_precedente_id]]));
    expect(mocks.selects[0].split(', ')).toContain('facture_precedente_id');
    expect(dialog.getByRole('checkbox')).not.toBeChecked();
    expect(dialog.getByRole('button', { name: /Confirmer 72,00/ })).toBeDisabled();
    expect(mocks.rpc).not.toHaveBeenCalled();
  });

  it('préserve les deux gardes et la RPC existante, puis relit le statut déclaré', async () => {
    const onChanged = vi.fn();
    render(<AvoirsList onChanged={onChanged} />);
    const dialog = await ouvrir();
    const confirm = dialog.getByRole('button', { name: /Confirmer 72,00/ });
    fireEvent.change(dialog.getByRole('textbox', { name: 'Référence virement' }), { target: { value: ' VIR-SYNTHETIQUE-001 ' } });
    expect(confirm).toBeDisabled();
    fireEvent.click(confirm);
    expect(mocks.rpc).not.toHaveBeenCalled();
    fireEvent.click(dialog.getByRole('checkbox', { name: /Je confirme avoir vérifié les pièces, le bénéficiaire bancaire et la preuve/ }));
    fireEvent.change(dialog.getByRole('textbox'), { target: { value: 'x' } });
    expect(confirm).toBeDisabled();
    fireEvent.change(dialog.getByRole('textbox'), { target: { value: ' VIR-SYNTHETIQUE-001 ' } });
    expect(confirm).toBeEnabled();
    fireEvent.click(confirm);
    await waitFor(() => expect(onChanged).toHaveBeenCalledOnce());
    expect(mocks.rpc.mock.calls).toEqual([['fn_confirmer_remboursement_avoir', { p_avoir_id: avoir.id, p_reference_virement: 'VIR-SYNTHETIQUE-001' }]]);
    expect(screen.queryByRole('dialog')).not.toBeInTheDocument();
    fireEvent.click(screen.getByRole('button', { name: /Historique/ }));
    expect(screen.getByText('Remboursé', { exact: true })).toBeVisible();
  });

  it('ne fabrique pas de facture d’origine et conserve la vérification externe existante', async () => {
    mocks.rows[0].facture_precedente_id = null;
    render(<AvoirsList />);
    const dialog = await ouvrir();
    expect(dialog.queryByRole('button', { name: 'Consulter la facture d’origine' })).not.toBeInTheDocument();
    expect(dialog.getByText(/Facture d’origine non reliée/)).toBeVisible();
    fireEvent.click(dialog.getByRole('button', { name: 'Consulter l’avoir' }));
    expect(mocks.download).toHaveBeenCalledWith(avoir.id);
    fireEvent.change(dialog.getByRole('textbox'), { target: { value: 'VIR-EXTERNE-SYNTHETIQUE' } });
    fireEvent.click(dialog.getByRole('checkbox'));
    expect(dialog.getByRole('button', { name: /Confirmer 72,00/ })).toBeEnabled();
    expect(mocks.rpc).not.toHaveBeenCalled();
  });

  it('une fermeture exige une nouvelle déclaration sans reprendre la référence saisie', async () => {
    render(<AvoirsList />);
    let dialog = await ouvrir();
    fireEvent.change(dialog.getByRole('textbox'), { target: { value: 'VIR-SYNTHETIQUE' } });
    fireEvent.click(dialog.getByRole('checkbox'));
    fireEvent.click(dialog.getByRole('button', { name: 'Annuler' }));
    dialog = await ouvrir();
    expect(dialog.getByRole('textbox')).toHaveValue('');
    expect(dialog.getByRole('checkbox')).not.toBeChecked();
    expect(dialog.getByRole('button', { name: /Confirmer 72,00/ })).toBeDisabled();
    expect(mocks.rpc).not.toHaveBeenCalled();
  });

  it('conserve le refus serveur et ne transforme pas une erreur en remboursement', async () => {
    mocks.rpc.mockResolvedValue({ data: { error: 'Refus métier synthétique' }, error: null });
    render(<AvoirsList />);
    const dialog = await ouvrir();
    fireEvent.change(dialog.getByRole('textbox'), { target: { value: 'VIR-SYNTHETIQUE' } });
    fireEvent.click(dialog.getByRole('checkbox'));
    fireEvent.click(dialog.getByRole('button', { name: /Confirmer 72,00/ }));
    await waitFor(() => expect(mocks.error).toHaveBeenCalledWith('Refus métier synthétique'));
    expect(screen.getByRole('dialog')).toBeVisible();
    expect(mocks.rows[0].statut).toBe('EMISE');
    expect(mocks.success).not.toHaveBeenCalled();
  });
});
