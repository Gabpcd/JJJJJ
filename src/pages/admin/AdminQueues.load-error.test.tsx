import React from 'react';
import { fireEvent, render, screen, waitFor } from '@testing-library/react';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import AdminExternalisationsActions from './AdminExternalisationsActions';
import AdminVerificationEtablissements from './AdminVerificationEtablissements';

const mocks = vi.hoisted(() => ({
  rpc: vi.fn(),
  notification: vi.fn(),
}));

vi.mock('@/components/LayoutAdmin', () => ({
  LayoutAdmin: ({ children }: { children: React.ReactNode }) => <>{children}</>,
}));

vi.mock('@/components/ui/EmptyState', () => ({
  EmptyState: ({ titre }: { titre: string }) => <p>{titre}</p>,
}));

vi.mock('@/components/y2k/BoutonY2K', () => ({
  BoutonY2K: ({ children, iconeGauche, variant: _variant, size: _size, loading: _loading, ...props }: any) => (
    <button type="button" {...props}>{iconeGauche}{children}</button>
  ),
}));

vi.mock('@/contexts/NotificationContext', () => ({
  useNotification: () => ({ afficherNotification: mocks.notification }),
}));

vi.mock('@/hooks/usePageTitle', () => ({ usePageTitle: vi.fn() }));

vi.mock('@/integrations/supabase/client', () => ({
  supabase: {
    rpc: mocks.rpc,
    storage: { from: vi.fn() },
  },
}));

describe('files admin — échec de chargement', () => {
  beforeEach(() => {
    mocks.rpc.mockReset();
    mocks.notification.mockReset();
    mocks.rpc.mockResolvedValue({ data: null, error: new Error('service indisponible') });
  });

  it('ne transforme pas une erreur établissements en file vide réussie', async () => {
    render(<AdminVerificationEtablissements />);

    expect(await screen.findByRole('alert')).toHaveTextContent('Dossiers indisponibles');
    expect(screen.queryByText('Aucun dossier en attente')).not.toBeInTheDocument();

    const appelsInitiaux = mocks.rpc.mock.calls.length;
    fireEvent.click(screen.getByRole('button', { name: /Réessayer/i }));
    await waitFor(() => expect(mocks.rpc.mock.calls.length).toBeGreaterThan(appelsInitiaux));
  });

  it('garde les fixtures pilotables sans les confondre avec un dossier réel', async () => {
    mocks.rpc.mockResolvedValueOnce({
      data: {
        success: true,
        etablissements: [{ id: 'fixture-etab', nom: 'Établissement test', est_compte_test: true }],
      },
      error: null,
    });

    render(<AdminVerificationEtablissements />);

    expect((await screen.findAllByText('Établissement test')).length).toBeGreaterThan(0);
    expect(screen.getByText('Donnée de test')).toBeInTheDocument();
    expect(screen.queryByText('Aucun dossier en attente')).not.toBeInTheDocument();
  });

  it('demande une confirmation intégrée avant une décision de preuve', async () => {
    const dossier = {
      id: 'fixture-etab',
      nom: 'Clinique de recette',
      est_compte_test: true,
      verification_source_version: 7,
      siret: '12345678901234',
      siret_verifie: true,
      siret_est_actif: true,
      finess: '750000001',
      finess_verifie: true,
      representant_identite_verifiee: true,
      justificatif_fonction_s3_key: 'fixture-etab/justificatif.pdf',
      justificatif_fonction_verifie: false,
      rattachement_verifie: false,
      contrat_service_signe: true,
    };
    mocks.rpc.mockImplementation((fonction: string) => {
      if (fonction === 'fn_admin_lister_etablissements_a_verifier') {
        return Promise.resolve({ data: { success: true, etablissements: [dossier] }, error: null });
      }
      if (fonction === 'fn_admin_decider_preuve_etablissement') {
        return Promise.resolve({ data: { success: true }, error: null });
      }
      throw new Error(`RPC inattendue : ${fonction}`);
    });

    render(<AdminVerificationEtablissements />);

    const approuver = (await screen.findAllByRole('button', { name: /^Approuver$/i }))
      .find(button => !button.hasAttribute('disabled'))!;
    fireEvent.click(approuver);
    expect(screen.getByRole('alertdialog')).toHaveTextContent('Approuver cette preuve ?');
    expect(mocks.rpc).not.toHaveBeenCalledWith(
      'fn_admin_decider_preuve_etablissement',
      expect.anything(),
    );

    fireEvent.click(screen.getByRole('button', { name: /Revenir au dossier/i }));
    await waitFor(() => expect(screen.queryByRole('alertdialog')).not.toBeInTheDocument());

    fireEvent.click(approuver);
    fireEvent.click(screen.getByRole('button', { name: /Confirmer l’approbation/i }));
    await waitFor(() => {
      expect(mocks.rpc).toHaveBeenCalledWith(
        'fn_admin_decider_preuve_etablissement',
        expect.objectContaining({
          p_etablissement_id: 'fixture-etab',
          p_preuve: 'FONCTION',
          p_decision: 'APPROUVER',
          p_version_attendue: 7,
          p_source_s3_key_attendue: 'fixture-etab/justificatif.pdf',
        }),
      );
    });
  });

  it('ne transforme pas une erreur d’externalisation en succès et expose un retry', async () => {
    render(<AdminExternalisationsActions />);

    expect(await screen.findByRole('alert')).toHaveTextContent('Actions indisponibles');
    expect(screen.queryByText('Toutes les actions ont été traitées')).not.toBeInTheDocument();

    const appelsInitiaux = mocks.rpc.mock.calls.length;
    fireEvent.click(screen.getByRole('button', { name: /Réessayer/i }));
    await waitFor(() => expect(mocks.rpc.mock.calls.length).toBeGreaterThan(appelsInitiaux));
  });
});
