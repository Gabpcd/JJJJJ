import React from 'react';
import { act, cleanup, fireEvent, render, screen, waitFor, within } from '@testing-library/react';
import { Link, MemoryRouter, Route, Routes } from 'react-router-dom';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import AdminDetailUtilisateur from './AdminDetailUtilisateur';

const mocks = vi.hoisted(() => ({ read: vi.fn(), rpc: vi.fn(), invoke: vi.fn() }));
vi.mock('@/components/LayoutAdmin', () => ({ LayoutAdmin: ({ children }: { children: React.ReactNode }) => <main>{children}</main> }));
vi.mock('@/hooks/usePageTitle', () => ({ usePageTitle: vi.fn() }));
vi.mock('@/hooks/useOuvrirConversation', () => ({ useOuvrirConversation: () => vi.fn() }));
vi.mock('@/integrations/supabase/client', () => ({
  SUPABASE_URL: 'https://invalid.example', SUPABASE_PUBLISHABLE_KEY: 'synthetic',
  supabase: {
    from(table: string) {
      const filters: Record<string, unknown> = {};
      const builder: Record<string, any> = {};
      for (const method of ['select', 'order', 'limit', 'maybeSingle']) builder[method] = () => builder;
      for (const method of ['eq', 'is']) builder[method] = (field: string, value: unknown) => { filters[field] = value; return builder; };
      builder.then = (resolve: (value: unknown) => unknown, reject: (reason: unknown) => unknown) =>
        Promise.resolve(mocks.read(table, filters)).then(resolve, reject);
      return builder;
    },
    auth: { getUser: async () => ({ data: { user: null } }) },
    rpc: mocks.rpc,
    functions: { invoke: mocks.invoke },
  },
}));

const ok = (data: unknown) => ({ data, error: null });
const unavailable = () => ({ data: null, error: { code: '42501', message: 'Indisponible' } });
const soignant = (id: string) => ({ id, nom: id.toUpperCase(), prenom: 'Dossier', profession: 'AS',
  email: `${id}@example.invalid`, telephone: null, date_naissance: null, numero_rpps: null, numero_adeli: null,
  adresse_lat: null, adresse_lng: null, prevoyance_inscrit: false, prevoyance_fournisseur: null, eligible_conversion_3200h: false,
  cree_le: '2026-10-01T12:00:00Z', modifie_le: '2026-10-01T12:00:00Z', derniere_activite_le: null, rayon_deplacement_km: 30,
  type_contrat: 'SALARIE', score_fiabilite: null, total_missions_annulees: 0, total_retards_pointage: 0, total_absences: 0,
  diplome_verifie: false, statut_verification_aria: 'EN_ATTENTE', rpps_verifie: true, tous_documents_valides: true,
  identite_verifiee: true, est_compte_test: true, heures_cumulees: 0, total_missions_terminees: 0 });
const etablissementTemoin = () => ({ id: 'etab', nom: 'Établissement témoin', est_compte_test: true,
  email_contact: 'etablissement@example.invalid', telephone_contact: null, siret: '00000000000000', finess: null, type: 'EHPAD',
  adresse_rue: '1 rue de la Recette fictive', adresse_code_postal: '00000', adresse_ville: 'Ville témoin',
  adresse_departement: null, adresse_lat: null, adresse_lng: null, cree_le: '2026-10-01T12:00:00Z',
  formule_abonnement: 'GRATUIT', taux_commission_negocie: 15, delai_paiement_jours: 30,
  mode_facturation: 'PAR_MISSION', mode_paiement_commission: 'FACTURE_MENSUELLE', convention_collective: null,
  chorus_pro_actif: false, rist_plafond_actif: true,
  taux_majoration_nuit_pourcent: 25, taux_majoration_dimanche_pourcent: 50, taux_majoration_ferie_pourcent: 100 });
const document = (id: string, statut = 'VERIFIE', revoque_le: string | null = null) => ({ id,
  type_document: 'DIPLOME', statut_verification: statut, nom_fichier: `${id}.pdf`,
  supprime_le: null, revoque_le, televerse_le: '2026-10-01T12:00:00Z', valide_jusqua: null,
});
function deferred() {
  let resolve!: (value: unknown) => void;
  const promise = new Promise(res => { resolve = res; });
  return { promise, resolve };
}
let docs: Record<string, unknown>;
let required: unknown;
let profiles: Record<string, unknown>;
let etablissement: unknown;
function mount() {
  return render(<MemoryRouter initialEntries={['/admin/utilisateurs/a']}>
    <nav><Link to="/admin/utilisateurs/a">Dossier A</Link><Link to="/admin/utilisateurs/b">Dossier B</Link><Link to="/admin/utilisateurs/etab">Dossier établissement</Link></nav>
    <Routes><Route path="/admin/utilisateurs/:id" element={<AdminDetailUtilisateur />} /></Routes>
  </MemoryRouter>);
}
function openTab(name: string) { fireEvent.mouseDown(screen.getByRole('tab', { name }), { button: 0, ctrlKey: false }); }

describe('Fiche administrateur — pièces de diplôme actuelles', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    docs = { a: ok([document('a-verifie')]), b: ok([]) };
    profiles = { a: ok(soignant('a')), b: ok(soignant('b')), etab: ok(null) };
    etablissement = ok(etablissementTemoin());
    required = ok([]);
    mocks.read.mockImplementation((table: string, filters: Record<string, unknown>) => {
      if (table === 'soignants') return profiles[String(filters.id)];
      if (table === 'etablissements') return etablissement;
      if (table === 'documents_soignants') return docs[String(filters.soignant_id)];
      if (table === 'documents_requis_par_profession') return required;
      if (table === 'emails_envoyes') return ok(null);
      return ok([]);
    });
  });
  afterEach(cleanup);

  it('affiche les statuts des pièces dans les deux onglets malgré les anciens indicateurs, puis ouvre Documents', async () => {
    docs.a = ok([document('a-verifie'), document('a-attente', 'EN_ATTENTE')]);
    mount();
    await screen.findByRole('heading', { name: 'Dossier A' });
    for (const tab of ['Fiabilité', 'Fiche complète']) {
      openTab(tab);
      expect(await screen.findByText('1 pièce vérifiée')).toBeVisible();
      expect(screen.getByText('1 pièce en attente')).toBeVisible();
      expect(screen.queryByText('Diplôme vérifié')).not.toBeInTheDocument();
      expect(screen.queryByText('Statut vérification ARIA')).not.toBeInTheDocument();
    }
    fireEvent.click(screen.getByRole('button', { name: 'Consulter les documents' }));
    expect(screen.getByRole('tab', { name: 'Documents' })).toHaveAttribute('aria-selected', 'true');
    expect(screen.getAllByText('Vérifié ✓').length).toBeGreaterThan(0);
    expect(screen.getAllByText('En attente de vérification').length).toBeGreaterThan(0);
    expect(mocks.rpc).not.toHaveBeenCalled();
    expect(mocks.invoke).not.toHaveBeenCalled();
  });

  it('distingue une ancienne pièce révoquée, une pièce rejetée et une absence sans déduire la validité du RPPS', async () => {
    profiles.a = ok({ ...soignant('a'), diplome_verifie: true });
    docs.a = ok([document('ancien', 'VERIFIE', '2026-10-02T12:00:00Z'), document('rejete', 'REJETE')]);
    mount();
    await screen.findByRole('heading', { name: 'Dossier A' });
    openTab('Fiabilité');
    expect(await screen.findByText('1 pièce révoquée')).toBeVisible();
    expect(screen.getByText('1 pièce rejetée')).toBeVisible();
    expect(screen.queryByText('1 pièce vérifiée')).not.toBeInTheDocument();
    fireEvent.click(screen.getByRole('button', { name: 'Consulter les documents' }));
    expect(screen.getAllByText('Révoqué').length).toBeGreaterThan(0);
    expect(screen.queryByText('Vérifié ✓')).not.toBeInTheDocument();
    fireEvent.click(screen.getByRole('link', { name: 'Dossier B' }));
    await screen.findByRole('heading', { name: 'Dossier B' });
    openTab('Fiche complète');
    expect(await screen.findByText('Aucun diplôme déposé.')).toBeVisible();
    expect(screen.queryByText('1 pièce vérifiée')).not.toBeInTheDocument();
    expect(screen.queryByText(/inéligible/i)).not.toBeInTheDocument();
  });

  it('ne transforme pas une erreur après un autre dossier en absence et permet de relire les pièces du bon compte', async () => {
    docs.b = unavailable();
    mount();
    await screen.findByRole('heading', { name: 'Dossier A' });
    openTab('Fiabilité');
    await screen.findByText('1 pièce vérifiée');
    fireEvent.click(screen.getByRole('link', { name: 'Dossier B' }));
    expect(screen.queryByText('1 pièce vérifiée')).not.toBeInTheDocument();
    await screen.findByRole('heading', { name: 'Dossier B' });
    openTab('Documents');
    expect(await screen.findByRole('alert')).toHaveTextContent('Documents indisponibles');
    expect(screen.queryByText('Aucun document téléversé.')).not.toBeInTheDocument();
    expect(screen.queryByRole('heading', { name: 'Documents (0)' })).not.toBeInTheDocument();
    expect(screen.queryByRole('button', { name: 'Envoyer un rappel' })).not.toBeInTheDocument();
    docs.b = ok([document('b-attente', 'EN_ATTENTE')]);
    fireEvent.click(screen.getByRole('button', { name: 'Réessayer les documents' }));
    await screen.findByRole('heading', { name: 'Dossier B' });
    expect(screen.getByRole('tab', { name: 'Documents' })).toHaveAttribute('aria-selected', 'true');
    expect(screen.getAllByText('b-attente.pdf').length).toBeGreaterThan(0);
    expect(screen.queryByText('a-verifie.pdf')).not.toBeInTheDocument();
    openTab('Fiabilité');
    expect(await screen.findByText('1 pièce en attente')).toBeVisible();
    expect(screen.queryByText('1 pièce vérifiée')).not.toBeInTheDocument();
  });

  it('ignore les documents tardifs du soignant après la navigation vers un établissement', async () => {
    const retard = deferred();
    docs.a = retard.promise;
    mount();
    await waitFor(() => expect(mocks.read).toHaveBeenCalledWith('documents_soignants', { soignant_id: 'a', supprime_le: null }));
    fireEvent.click(screen.getByRole('link', { name: 'Dossier établissement' }));
    await screen.findByRole('heading', { name: 'Établissement témoin' });
    await act(async () => retard.resolve(ok([document('ancien-dossier')])));
    expect(screen.getByRole('heading', { name: 'Établissement témoin' })).toBeVisible();
    expect(screen.queryByRole('tab', { name: 'Documents' })).not.toBeInTheDocument();
    expect(screen.queryByRole('heading', { name: 'Dossier A' })).not.toBeInTheDocument();
    expect(screen.queryByText('ancien-dossier.pdf')).not.toBeInTheDocument();
  });

  it('ignore également une identité tardive et masque les rappels quand les règles requises sont indisponibles', async () => {
    const retard = deferred();
    profiles.a = retard.promise;
    required = unavailable();
    mount();
    await waitFor(() => expect(mocks.read).toHaveBeenCalledWith('soignants', { id: 'a' }));
    fireEvent.click(screen.getByRole('link', { name: 'Dossier B' }));
    await screen.findByRole('heading', { name: 'Dossier B' });
    await act(async () => retard.resolve(ok(soignant('a'))));
    expect(screen.getByRole('heading', { name: 'Dossier B' })).toBeVisible();
    expect(mocks.read.mock.calls.some(([table, filters]) => table === 'documents_soignants' && filters.soignant_id === 'a')).toBe(false);
    openTab('Documents');
    expect(await screen.findByRole('alert')).toHaveTextContent('liste des pièces requises est indisponible');
    expect(screen.queryByRole('button', { name: 'Envoyer un rappel' })).not.toBeInTheDocument();
    expect(mocks.rpc).not.toHaveBeenCalled();
    expect(mocks.invoke).not.toHaveBeenCalled();
  });

  it('ne confond pas un refus de lecture soignant avec un établissement ou un compte inexistant', async () => {
    profiles.a = unavailable();
    mount();
    expect(await screen.findByRole('alert')).toHaveTextContent('Impossible de charger ce dossier');
    expect(screen.queryByText('Utilisateur introuvable')).not.toBeInTheDocument();
    expect(mocks.read.mock.calls.some(([table]) => table === 'etablissements')).toBe(false);
    profiles.a = ok(soignant('a'));
    fireEvent.click(screen.getByRole('button', { name: 'Réessayer le chargement' }));
    await screen.findByRole('heading', { name: 'Dossier A' });
    openTab('Fiabilité');
    expect(await screen.findByText('1 pièce vérifiée')).toBeVisible();
  });

  it.each([
    { remplacement: null, rappel: true },
    { remplacement: 'VERIFIE', rappel: false },
    { remplacement: 'EN_ATTENTE', rappel: false },
  ])('propose le rappel pour une pièce requise révoquée seulement si elle n’a pas de remplacement ($remplacement)', async ({ remplacement, rappel }) => {
    profiles.a = ok({ ...soignant('a'), rpps_verifie: false });
    required = ok([{ type_document: 'DIPLOME', est_critique: true }]);
    docs.a = ok([
      { ...document('ancienne-piece', 'VERIFIE', '2026-10-02T12:00:00Z'), valide_jusqua: '2001-01-01' },
      ...(remplacement ? [document('nouvelle-piece', remplacement)] : []),
    ]);
    mount();
    await screen.findByRole('heading', { name: 'Dossier A' });
    if (rappel) {
      expect(screen.getByText("Documents manquants : Diplôme d'État")).toBeVisible();
      expect(screen.getByRole('button', { name: 'Envoyer un rappel' })).toBeEnabled();
    } else {
      expect(screen.queryByText(/Documents manquants/)).not.toBeInTheDocument();
      expect(screen.queryByRole('button', { name: 'Envoyer un rappel' })).not.toBeInTheDocument();
    }
    // Une ancienne version révoquée et expirée ne réclame pas à nouveau
    // une pièce quand un remplacement est déjà déposé (même en attente).
    expect(screen.queryByText(/Documents expirés/)).not.toBeInTheDocument();
    openTab('Fiabilité');
    expect(await screen.findByText('1 pièce révoquée')).toBeVisible();
    expect(mocks.rpc).not.toHaveBeenCalled();
    expect(mocks.invoke).not.toHaveBeenCalled();
  });

  it.each([null, undefined, 'date-invalide'])('n’invente pas de date ni de rayon quand les informations sont absentes ou invalides (%s)', async (date) => {
    profiles.a = ok({ ...soignant('a'), cree_le: date, rayon_deplacement_km: null });
    mount();
    await screen.findByRole('heading', { name: 'Dossier A' });
    for (const tab of ['Vue d’ensemble', 'Fiche complète']) {
      openTab(tab);
      expect(within(screen.getByText('Inscrit le').parentElement!).getByText('—')).toBeVisible();
      expect(within(screen.getByText('Rayon déplacement').parentElement!).getByText('—')).toBeVisible();
      expect(screen.queryByText(/Invalid Date|null km|undefined km|1970/)).not.toBeInTheDocument();
    }
  });

  it('conserve le rayon et une date réelle quand ces informations sont renseignées', async () => {
    mount();
    await screen.findByRole('heading', { name: 'Dossier A' });
    for (const tab of ['Vue d’ensemble', 'Fiche complète']) {
      openTab(tab);
      expect(within(screen.getByText('Inscrit le').parentElement!).getByText('1 octobre 2026')).toBeVisible();
      expect(within(screen.getByText('Rayon déplacement').parentElement!).getByText('30 km')).toBeVisible();
    }
  });

  it('ne transforme pas une date d’inscription établissement absente en 1970', async () => {
    etablissement = ok({ ...etablissementTemoin(), cree_le: null });
    mount();
    await screen.findByRole('heading', { name: 'Dossier A' });
    fireEvent.click(screen.getByRole('link', { name: 'Dossier établissement' }));
    await screen.findByRole('heading', { name: 'Établissement témoin' });
    expect(within(screen.getByText('Inscrit le').parentElement!).getByText('—')).toBeVisible();
    expect(screen.queryByText(/Invalid Date|1970/)).not.toBeInTheDocument();
  });

  it.each([null, undefined])('affiche les champs commerciaux absents sans inventer un taux ou un délai (%s)', async (absent) => {
    etablissement = ok({ ...etablissementTemoin(), taux_commission_negocie: absent, delai_paiement_jours: absent,
      taux_majoration_nuit_pourcent: absent, taux_majoration_dimanche_pourcent: absent, taux_majoration_ferie_pourcent: absent });
    mount();
    await screen.findByRole('heading', { name: 'Dossier A' });
    fireEvent.click(screen.getByRole('link', { name: 'Dossier établissement' }));
    await screen.findByRole('heading', { name: 'Établissement témoin' });
    for (const tab of ['Vue d’ensemble', 'Fiche complète']) {
      openTab(tab);
      for (const label of ['Taux commission HT', 'Délai paiement', ...(tab === 'Fiche complète' ? ['Majoration nuit', 'Majoration dimanche', 'Majoration férié'] : [])]) {
        expect(within(screen.getByText(label).parentElement!).getByText('—')).toBeVisible();
      }
      expect(screen.queryByText(/undefined|null|NaN/)).not.toBeInTheDocument();
    }
    expect(mocks.rpc).not.toHaveBeenCalled();
    expect(mocks.invoke).not.toHaveBeenCalled();
  });

  it.each([
    { taux: 0, delai: 0, nuit: 0, dimanche: 0, ferie: 0, attenteDelai: '0 jour' },
    { taux: 15, delai: 1, nuit: 25, dimanche: 50, ferie: 100, attenteDelai: '1 jour' },
    { taux: 15, delai: 30, nuit: 25, dimanche: 50, ferie: 100, attenteDelai: '30 jours' },
  ])('conserve les valeurs renseignées, y compris zéro, dans les deux fiches ($attenteDelai)', async ({ taux, delai, nuit, dimanche, ferie, attenteDelai }) => {
    etablissement = ok({ ...etablissementTemoin(), taux_commission_negocie: taux, delai_paiement_jours: delai,
      taux_majoration_nuit_pourcent: nuit, taux_majoration_dimanche_pourcent: dimanche, taux_majoration_ferie_pourcent: ferie });
    mount();
    await screen.findByRole('heading', { name: 'Dossier A' });
    fireEvent.click(screen.getByRole('link', { name: 'Dossier établissement' }));
    await screen.findByRole('heading', { name: 'Établissement témoin' });
    for (const tab of ['Vue d’ensemble', 'Fiche complète']) {
      openTab(tab);
      expect(within(screen.getByText('Taux commission HT').parentElement!).getByText(`${taux}%`)).toBeVisible();
      expect(within(screen.getByText('Délai paiement').parentElement!).getByText(attenteDelai)).toBeVisible();
      if (tab === 'Fiche complète') for (const [label, valeur] of [['Majoration nuit', nuit], ['Majoration dimanche', dimanche], ['Majoration férié', ferie]] as const) {
        expect(within(screen.getByText(label).parentElement!).getByText(`${valeur}%`)).toBeVisible();
      }
    }
  });

  it.each([
    { lat: null, lng: null, attendu: '—' },
    { lat: 48, lng: null, attendu: '—' },
    { lat: null, lng: 2, attendu: '—' },
    { lat: 0, lng: 0, attendu: '0, 0' },
    { lat: 48, lng: 2, attendu: '48, 2' },
  ])('affiche seulement des coordonnées complètes, y compris zéro, pour les deux rôles ($lat/$lng)', async ({ lat, lng, attendu }) => {
    profiles.a = ok({ ...soignant('a'), adresse_lat: lat, adresse_lng: lng });
    etablissement = ok({ ...etablissementTemoin(), adresse_lat: lat, adresse_lng: lng });
    mount();
    await screen.findByRole('heading', { name: 'Dossier A' });
    expect(within(screen.getByText('Coordonnées GPS').parentElement!).getByText(attendu)).toBeVisible();
    fireEvent.click(screen.getByRole('link', { name: 'Dossier établissement' }));
    await screen.findByRole('heading', { name: 'Établissement témoin' });
    openTab('Fiche complète');
    expect(within(screen.getByText('Coordonnées').parentElement!).getByText(attendu)).toBeVisible();
  });
});
