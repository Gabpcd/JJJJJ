import React from 'react';
import { fireEvent, render, screen, waitFor } from '@testing-library/react';
import { MemoryRouter, useLocation } from 'react-router-dom';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { DocumentsSoignantContent } from './DocumentsSoignant';

const mocks = vi.hoisted(() => ({
  from: vi.fn(),
  rpc: vi.fn(),
  user: { id: 'soignant-test' },
  results: {} as Record<string, { data: any; error: unknown }>,
}));

vi.mock('@/contexts/AuthContext', () => ({ useAuth: () => ({ user: mocks.user }) }));
vi.mock('@/lib/handleError', () => ({ handleErrorSilent: vi.fn() }));
vi.mock('@/components/ChargementPage', () => ({ ChargementPage: () => <p>Chargement</p> }));
vi.mock('@/components/mascotte/Mascotte', () => ({ Mascotte: () => null }));
vi.mock('@/components/ConfettiMini', () => ({ ConfettiMini: () => null }));
vi.mock('@/components/ModalTeleversement', () => ({ ModalTeleversement: () => <div role="dialog" aria-label="Téléverser un document" /> }));
vi.mock('@/components/ModalConfirmation', () => ({ ModalConfirmation: ({ ouvert, onConfirmer }: any) => ouvert ? <div role="dialog" aria-label="Supprimer ce document ?"><button onClick={onConfirmer}>Confirmer la suppression</button></div> : null }));
vi.mock('@/components/y2k/BoutonY2K', () => ({
  BoutonY2K: ({ children, iconeGauche, variant: _variant, size: _size, ...props }: any) => (
    <button type="button" {...props}>{iconeGauche}{children}</button>
  ),
}));
vi.mock('@/integrations/supabase/client', () => ({
  supabase: { from: mocks.from, rpc: mocks.rpc, storage: { from: vi.fn() } },
}));

function Emplacement() { return <output aria-label="Page actuelle">{useLocation().pathname}</output>; }
let queryClient: QueryClient;
function contenu() {
  return <QueryClientProvider client={queryClient}><MemoryRouter initialEntries={['/soignant/mes-documents']}><DocumentsSoignantContent /><Emplacement /></MemoryRouter></QueryClientProvider>;
}
function afficher() { return render(contenu()); }

const regle = (type_document: string, type_exercice_requis = 'TOUS', profession = 'IDE') => ({
  id: type_document, profession, type_document, type_exercice_requis, est_critique: true,
});

beforeEach(() => {
  vi.clearAllMocks();
  queryClient = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  mocks.results = {
    soignants: { data: null, error: null },
    documents_requis_par_profession: { data: [], error: null },
    documents_soignants: { data: [], error: null },
  };
  mocks.from.mockImplementation((table: string) => {
    const builder: Record<string, any> = {};
    for (const methode of ['select', 'eq', 'is', 'order']) builder[methode] = () => builder;
    builder.update = () => { mocks.results[table].data = []; return builder; };
    builder.maybeSingle = () => Promise.resolve(mocks.results[table]);
    builder.then = (resolve: (value: unknown) => unknown, reject: (reason: unknown) => unknown) =>
      Promise.resolve(mocks.results[table]).then(resolve, reject);
    return builder;
  });
  mocks.rpc.mockResolvedValue({ data: { coherent: true }, error: null });
});

describe('DocumentsSoignant — compte incomplet et vrais incidents', () => {
  it('laisse une identité seule explorer sans erreur, pièce demandée ou mutation', async () => {
    afficher();
    expect(await screen.findByRole('heading', { name: 'Votre dossier, quand vous en aurez besoin' })).toBeInTheDocument();
    expect(screen.queryByRole('alert')).not.toBeInTheDocument();
    expect(screen.queryByText(/Tous tes documents obligatoires sont à jour/i)).not.toBeInTheDocument();
    expect(mocks.from.mock.calls.map(([table]) => table)).toEqual(['soignants']);
    expect(mocks.rpc).not.toHaveBeenCalled();
    fireEvent.click(screen.getByRole('button', { name: 'Explorer les missions' }));
    expect(screen.getByLabelText('Page actuelle')).toHaveTextContent('/soignant/recherche-missions');
  });

  it('permet de préparer son dossier volontairement', async () => {
    afficher();
    fireEvent.click(await screen.findByRole('button', { name: 'Préparer mon dossier' }));
    expect(screen.getByLabelText('Page actuelle')).toHaveTextContent('/soignant/profil');
  });

  it('affiche une vraie erreur réseau, puis l’état sans dossier après réessai réussi', async () => {
    mocks.results.soignants = { data: null, error: new Error('503') };
    afficher();
    expect(await screen.findByRole('alert')).toHaveTextContent('Documents indisponibles');
    expect(screen.queryByText(/Tous tes documents obligatoires sont à jour/i)).not.toBeInTheDocument();
    mocks.results.soignants = { data: null, error: null };
    fireEvent.click(screen.getByRole('button', { name: 'Réessayer' }));
    expect(await screen.findByRole('heading', { name: 'Votre dossier, quand vous en aurez besoin' })).toBeInTheDocument();
    expect(screen.queryByRole('alert')).not.toBeInTheDocument();
  });

  it('ne masque pas une panne de pièces derrière un profil existant', async () => {
    mocks.results.soignants.data = { profession: 'IDE', type_exercice: 'SALARIE' };
    mocks.results.documents_soignants.error = new Error('503');
    afficher();
    expect(await screen.findByRole('alert')).toHaveTextContent('Documents indisponibles');
    expect(screen.queryByText(/Aucun document obligatoire/)).not.toBeInTheDocument();
  });

  it('garde les pièces existantes et les règles de la profession et du régime connus', async () => {
    mocks.results.soignants.data = { profession: 'IDE', type_exercice: 'SALARIE', rpps_verifie: true };
    mocks.results.documents_requis_par_profession.data = [
      regle('CARTE_IDENTITE'), regle('DIPLOME'), regle('RPPS_ADELI'),
      regle('RCP_ASSURANCE', 'LIBERAL_ONLY'), regle('AUTRE', 'TOUS', 'AS'),
    ];
    mocks.results.documents_soignants.data = [{
      id: 'piece-existante', type_document: 'CARTE_IDENTITE', nom_fichier: 'identite-validee.pdf',
      statut_verification: 'VERIFIE', televerse_le: '2026-09-01T09:00:00Z', valide_jusqua: null,
    }];
    afficher();
    expect(await screen.findByText(/identite-validee.pdf/)).toBeInTheDocument();
    expect(screen.getByText(/Tous tes documents obligatoires sont à jour/)).toBeInTheDocument();
    expect(screen.queryByRole('heading', { name: "Diplôme d'État" })).not.toBeInTheDocument();
    expect(screen.queryByRole('heading', { name: 'Assurance RCP' })).not.toBeInTheDocument();
    expect(screen.queryByRole('heading', { name: 'Autre document' })).not.toBeInTheDocument();
    await waitFor(() => expect(mocks.rpc).toHaveBeenCalledWith('fn_verifier_coherence_documents'));
  });

  it('n’annonce pas un dossier validé quand aucune règle n’est reçue', async () => {
    mocks.results.soignants.data = { profession: 'AS', type_exercice: 'SALARIE' };
    afficher();
    expect(await screen.findByText('Aucun document obligatoire n’est affiché pour votre profil actuellement.')).toBeInTheDocument();
    expect(screen.queryByText(/Tous tes documents obligatoires sont à jour/)).not.toBeInTheDocument();
  });

  it('conserve la modale et ne recharge pas les pièces si le SDK renouvelle le même utilisateur', async () => {
    mocks.results.soignants.data = { profession: 'IDE', type_exercice: 'SALARIE' };
    mocks.results.documents_requis_par_profession.data = [regle('CARTE_IDENTITE')];
    const view = afficher();
    fireEvent.click(await screen.findByRole('button', { name: /Téléverser — .*identité/ }));
    expect(screen.getByRole('dialog', { name: 'Téléverser un document' })).toBeInTheDocument();
    const lectures = mocks.from.mock.calls.length;
    mocks.user = { id: 'soignant-test' };
    view.rerender(contenu());
    expect(screen.getByRole('dialog', { name: 'Téléverser un document' })).toBeInTheDocument();
    expect(mocks.from.mock.calls.length).toBe(lectures);
  });

  it('invalide les seules données Explorer du compte après suppression d’une RCP', async () => {
    mocks.results.soignants.data = { profession: 'IDE', type_exercice: 'LIBERAL' };
    mocks.results.documents_requis_par_profession.data = [regle('RCP_ASSURANCE', 'LIBERAL_ONLY')];
    mocks.results.documents_soignants.data = [{ id: 'rcp', type_document: 'RCP_ASSURANCE', nom_fichier: 'rcp.pdf', statut_verification: 'VERIFIE', televerse_le: '2026-09-01T09:00:00Z', valide_jusqua: null }];
    afficher();
    await screen.findByText(/rcp.pdf/);
    const profil = ['explorer-profil', 'soignant-test'];
    const rcp = ['explorer-rcp', 'soignant-test'];
    const autre = ['explorer-rcp', 'autre-compte'];
    for (const key of [profil, rcp, autre]) queryClient.setQueryData(key, { valide: true });
    fireEvent.click(screen.getByRole('button', { name: 'Supprimer' }));
    fireEvent.click(screen.getByRole('button', { name: 'Confirmer la suppression' }));
    await waitFor(() => expect(screen.queryByText(/rcp.pdf/)).not.toBeInTheDocument());
    expect(queryClient.getQueryState(profil)?.isInvalidated).toBe(true);
    expect(queryClient.getQueryState(rcp)?.isInvalidated).toBe(true);
    expect(queryClient.getQueryState(autre)?.isInvalidated).toBe(false);
  });


  it('ne suppose pas un régime salarié lorsque le mode d’exercice n’est pas renseigné', async () => {
    mocks.results.soignants.data = { profession: 'IDE', type_exercice: null };
    mocks.results.documents_requis_par_profession.data = [regle('CARTE_IDENTITE'), regle('AUTRE', 'SALARIE_ONLY'), regle('RCP_ASSURANCE', 'LIBERAL_ONLY')];
    mocks.results.documents_soignants.data = [{ id: 'identite', type_document: 'CARTE_IDENTITE', nom_fichier: 'identite.pdf', statut_verification: 'VERIFIE', televerse_le: '2026-09-01T09:00:00Z', valide_jusqua: null }];
    afficher();
    expect(await screen.findByRole('heading', { name: 'Mode d’exercice à préciser' })).toBeInTheDocument();
    expect(screen.getByText(/Les justificatifs affichés sont à jour/)).toBeInTheDocument();
    expect(screen.queryByText(/Tous tes documents obligatoires sont à jour/)).not.toBeInTheDocument();
    expect(screen.queryByRole('heading', { name: 'Assurance RCP' })).not.toBeInTheDocument();
    expect(screen.queryByRole('heading', { name: 'Autre document' })).not.toBeInTheDocument();
  });

});
