import React from 'react';
import { render, screen, fireEvent } from '@testing-library/react';
import { MemoryRouter, Route, Routes } from 'react-router-dom';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import PresencesEtablissement from './PresencesEtablissement';
import ListeContrats from './ListeContrats';
import DashboardRH from './DashboardRH';
import ExportPaie from './ExportPaie';
import RechercheSoignantsEtab from './RechercheSoignantsEtab';
import ProfilSoignantEtablissement from './ProfilSoignantEtablissement';
import EquipeEtablissement from './EquipeEtablissement';
import ParrainageEtablissement from './PageParrainageEtablissement';
import PageScoreEtablissement from './PageScoreEtablissement';
import LitigesEtablissement from './LitigesEtablissement';
import AnalyticsEtablissement from './AnalyticsEtablissement';

const mocks = vi.hoisted(() => ({
  scope: {
    user: { id: 'membre-1' },
    etablissementId: null as string | null,
    parcours: { type_compte: 'ETABLISSEMENT' } as { type_compte: string } | null,
    loading: false,
    resolved: true,
    error: null as Error | null,
    retry: vi.fn(),
  },
  rpc: vi.fn(), from: vi.fn(), notification: vi.fn(),
  tables: {} as Record<string, { data: unknown; error: unknown }>,
}));
vi.mock('@/hooks/useEtablissementScope', () => ({ useEtablissementScope: () => mocks.scope }));
vi.mock('@/contexts/AuthContext', () => ({ useAuth: () => ({ user: mocks.scope.user }) }));
vi.mock('@/integrations/supabase/client', () => ({ supabase: { rpc: mocks.rpc, from: mocks.from } }));
vi.mock('@/contexts/NotificationContext', () => ({ useNotification: () => ({ afficherNotification: mocks.notification }) }));
vi.mock('@/components/LayoutApp', () => ({ LayoutApp: ({ children }: { children: React.ReactNode }) => <main>{children}</main> }));
vi.mock('@/components/ChargementPage', () => ({ ChargementPage: () => <p role="status">Chargement en cours</p> }));
vi.mock('@/hooks/usePageTitle', () => ({ usePageTitle: vi.fn() }));
vi.mock('@/components/NotationsRecues', () => ({ NotationsRecues: () => null }));
vi.mock('@/components/score/SectionEvenementsScore', () => ({ SectionEvenementsScore: () => null }));

function afficher(element: React.ReactNode) {
  return render(<MemoryRouter>{element}</MemoryRouter>);
}
function requete(table: string) {
  const builder: Record<string, unknown> = {};
  for (const method of ['select', 'eq', 'in', 'not', 'order', 'limit', 'maybeSingle']) {
    builder[method] = () => builder;
  }
  builder.then = (resolve: (value: unknown) => unknown, reject: (error: unknown) => unknown) =>
    Promise.resolve(mocks.tables[table] ?? { data: [], error: null }).then(resolve, reject);
  return builder;
}

beforeEach(() => {
  vi.clearAllMocks();
  Object.assign(mocks.scope, { etablissementId: null, parcours: { type_compte: 'ETABLISSEMENT' }, loading: false, resolved: true, error: null });
  mocks.tables = {};
  mocks.from.mockImplementation(requete);
  mocks.rpc.mockResolvedValue({ data: [], error: null });
});

describe('Exploration des rubriques établissement sans dossier', () => {
  it.each([
    ['Présences', <PresencesEtablissement />],
    ['Contrats', <ListeContrats role="ADMIN_ETABLISSEMENT" />],
    ['Tableau RH', <DashboardRH />],
    ['Export paie', <ExportPaie />],
    ['Annuaire des soignants', <RechercheSoignantsEtab />],
    ['Profil soignant', <ProfilSoignantEtablissement />],
    ['Mon équipe', <EquipeEtablissement />],
    ['Parrainage entre établissements', <ParrainageEtablissement />],
    ['Score qualité', <PageScoreEtablissement />],
    ['Litiges et contestations', <LitigesEtablissement />],
    ['Indicateurs de performance', <AnalyticsEtablissement />],
  ])('%s propose une prochaine étape facultative sans requête métier', (titre, page) => {
    afficher(page);
    expect(screen.getByRole('heading', { level: 1, name: titre })).toBeInTheDocument();
    expect(screen.getByRole('link', { name: 'Préparer une mission' })).toHaveAttribute('href', '/etablissement/missions/creer');
    expect(screen.getByRole('link', { name: 'Compléter mon établissement' })).toHaveAttribute('href', '/inscription/completer');
    expect(screen.queryByText('Chargement en cours')).not.toBeInTheDocument();
    expect(screen.queryByRole('alert')).not.toBeInTheDocument();
    expect(mocks.rpc).not.toHaveBeenCalled();
    expect(mocks.from).not.toHaveBeenCalled();
  });

  it('attend la résolution puis termine normalement sans scope', () => {
    mocks.scope.loading = true;
    mocks.scope.resolved = false;
    const vue = afficher(<PresencesEtablissement />);
    expect(screen.getByRole('status')).toHaveTextContent('Chargement en cours');
    expect(screen.queryByRole('link', { name: 'Compléter mon établissement' })).not.toBeInTheDocument();
    mocks.scope.loading = false;
    mocks.scope.resolved = true;
    vue.rerender(<MemoryRouter><PresencesEtablissement /></MemoryRouter>);
    expect(screen.getByRole('link', { name: 'Compléter mon établissement' })).toBeInTheDocument();
    expect(mocks.rpc).not.toHaveBeenCalled();
  });

  it('un ancien compte sans rattachement n’est pas présenté comme une inscription à compléter', () => {
    mocks.scope.parcours = null;
    afficher(<EquipeEtablissement />);
    expect(screen.getByRole('alert')).toHaveTextContent('Établissement non rattaché');
    expect(screen.queryByRole('link', { name: 'Compléter mon établissement' })).not.toBeInTheDocument();
    fireEvent.click(screen.getByRole('button', { name: 'Réessayer' }));
    expect(mocks.scope.retry).toHaveBeenCalledOnce();
    expect(mocks.rpc).not.toHaveBeenCalled();
  });

  it('ne présente pas une panne de résolution comme un dossier manquant', () => {
    mocks.scope.error = new Error('503');
    mocks.scope.resolved = false;
    afficher(<EquipeEtablissement />);
    expect(screen.getByRole('alert')).toHaveTextContent('Impossible de vérifier votre établissement');
    expect(screen.queryByRole('link', { name: 'Compléter mon établissement' })).not.toBeInTheDocument();
    fireEvent.click(screen.getByRole('button', { name: 'Réessayer' }));
    expect(mocks.scope.retry).toHaveBeenCalledOnce();
    expect(mocks.rpc).not.toHaveBeenCalled();
  });
});

describe('Données et permissions après résolution du périmètre', () => {
  beforeEach(() => { mocks.scope.etablissementId = 'etablissement-partage'; });

  it('distingue une panne du profil soignant puis retrouve la fiche au réessai', async () => {
    let panne = true;
    mocks.rpc.mockImplementation((nom:string) => Promise.resolve(nom === 'fn_soignant_pour_etablissement'
      ? panne ? {data:null,error:{message:'503'}} : {data:{id:'soignant-1',prenom:'Camille',nom:'Recette',profession:'IDE',type_exercice:'SALARIE',total_missions_terminees:4,score_fiabilite:92},error:null}
      : {data:{moyenne:4.5,total:2},error:null}));
    render(<MemoryRouter initialEntries={['/etablissement/soignants/soignant-1']}><Routes><Route path="/etablissement/soignants/:id" element={<ProfilSoignantEtablissement />} /></Routes></MemoryRouter>);
    expect(await screen.findByRole('alert')).toHaveTextContent('Impossible de charger ce profil');
    expect(screen.queryByText('Profil soignant indisponible.')).not.toBeInTheDocument();
    panne = false;
    fireEvent.click(screen.getByRole('button',{name:'Réessayer'}));
    expect(await screen.findByRole('heading',{name:'Camille Recette'})).toBeInTheDocument();
    expect(screen.getByText('4.5/5 (2)')).toBeInTheDocument();
    expect(screen.queryByRole('alert')).not.toBeInTheDocument();
  });

  it('conserve un refus de membership sans créer de membre', async () => {
    mocks.rpc.mockResolvedValue({ data: { success: false, error_code: 'NON_AUTORISE' }, error: null });
    afficher(<EquipeEtablissement />);
    expect(await screen.findByText("Vous n'êtes pas membre de cette équipe.")).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: 'Inviter un membre' })).not.toBeInTheDocument();
    expect(mocks.rpc).toHaveBeenCalledWith('fn_lister_membres_etab', { p_etablissement_id: 'etablissement-partage' });
  });

  it('sépare une panne de l’équipe du refus puis recharge les données', async () => {
    mocks.rpc.mockResolvedValueOnce({ data: null, error: { message: '503' } })
      .mockResolvedValue({ data: { success: true, role_courant: 'LECTURE_SEULE', membres: [], invitations: [] }, error: null });
    afficher(<EquipeEtablissement />);
    expect(await screen.findByRole('alert')).toHaveTextContent('Équipe indisponible');
    expect(screen.queryByText("Vous n'êtes pas membre de cette équipe.")).not.toBeInTheDocument();
    fireEvent.click(screen.getByRole('button', { name: 'Réessayer' }));
    expect(await screen.findByRole('heading', { name: 'Mon équipe' })).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: 'Inviter un membre' })).not.toBeInTheDocument();
  });

  it('une panne contrats ne se transforme pas en absence de contrats', async () => {
    mocks.tables.contrats_mission = { data: null, error: { message: '503' } };
    afficher(<ListeContrats role="ADMIN_ETABLISSEMENT" />);
    expect(await screen.findByRole('alert')).toHaveTextContent('Contrats indisponibles');
    expect(screen.queryByText('Aucun contrat')).not.toBeInTheDocument();
    mocks.tables.contrats_mission = { data: [], error: null };
    fireEvent.click(screen.getByRole('button', { name: 'Réessayer' }));
    expect(await screen.findByText('Aucun contrat')).toBeInTheDocument();
  });

  it('le score quitte le chargement même sur réponse vide puis se recharge', async () => {
    mocks.rpc.mockResolvedValueOnce({ data: {}, error: null }).mockResolvedValue({ data: {
      score_qualite: null, niveau: null,
      composantes: { notation_pct: null, nb_notations: 0, paiement_pct: null, nb_factures: 0, nb_litiges_perdus: 0 },
    }, error: null });
    afficher(<PageScoreEtablissement />);
    expect(await screen.findByRole('alert')).toHaveTextContent('Score indisponible');
    fireEvent.click(screen.getByRole('button', { name: 'Réessayer' }));
    expect(await screen.findByText('Pas encore de score')).toBeInTheDocument();
  });

  it('une panne litiges ne se présente jamais comme « tout est en ordre »', async () => {
    mocks.rpc.mockImplementation((fn: string) => Promise.resolve({ data: null, error: fn === 'fn_litiges_etablissement' ? { message: '503' } : null }));
    afficher(<LitigesEtablissement />);
    expect(await screen.findByRole('alert')).toHaveTextContent('Litiges indisponibles');
    expect(screen.queryByText('Aucun litige en cours')).not.toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Réessayer' })).toBeInTheDocument();
  });

  it('les analytics utilisent le périmètre partagé, jamais l’identité du membre', async () => {
    mocks.rpc.mockResolvedValue({ data: null, error: { message: '503' } });
    afficher(<AnalyticsEtablissement />);
    expect(await screen.findByRole('alert')).toHaveTextContent('Indicateurs indisponibles');
    expect(mocks.rpc).toHaveBeenCalledWith('fn_analytics_etablissement', { p_etablissement_id: 'etablissement-partage', p_mois: 6 });
  });

  it('le parrainage sans code ne permet aucun partage sans attribution', async () => {
    mocks.tables.etablissements = { data: { code_parrainage: null }, error: null };
    mocks.rpc.mockImplementation((fn: string) => Promise.resolve({ data: fn === 'fn_mes_credits_etab'
      ? { total_disponible_eur: 0, total_applique_eur: 0, credits: [] } : [], error: null }));
    afficher(<ParrainageEtablissement />);
    expect(await screen.findByText('Votre code de parrainage n’est pas encore disponible')).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: 'Copier le lien' })).not.toBeInTheDocument();
    expect(screen.queryByRole('img', { name: 'QR code lien parrainage' })).not.toBeInTheDocument();
    expect(screen.queryByRole('link', { name: 'WhatsApp' })).not.toBeInTheDocument();
    expect(document.querySelector('[href*="?ref="]')).toBeNull();
  });

  it('un code valide est identique dans le lien, le QR et tous les canaux', async () => {
    mocks.tables.etablissements = { data: { code_parrainage: 'ETB-123456' }, error: null };
    mocks.rpc.mockImplementation((fn: string) => Promise.resolve({ data: fn === 'fn_mes_credits_etab'
      ? { total_disponible_eur: 0, total_applique_eur: 0, credits: [] } : [], error: null }));
    afficher(<ParrainageEtablissement />);
    expect(await screen.findByRole('button', { name: 'Copier le lien' })).toBeInTheDocument();
    expect(screen.getByRole('img', { name: 'QR code lien parrainage' })).toBeInTheDocument();
    const lien = 'https://jolene.app/inscription/etablissement?ref=ETB-123456';
    expect(screen.getByText(lien)).toBeInTheDocument();
    for (const canal of ['LinkedIn', 'Email', 'WhatsApp']) {
      expect(decodeURIComponent(screen.getByRole('link', { name: canal }).getAttribute('href')!)).toContain(lien);
    }
  });

  it('une panne parrainage garde les invitations indisponibles et propose un réessai', async () => {
    mocks.tables.etablissements = { data: { code_parrainage: 'ETB-123456' }, error: null };
    mocks.rpc.mockResolvedValue({ data: null, error: { message: '503' } });
    afficher(<ParrainageEtablissement />);
    expect(await screen.findByRole('alert')).toHaveTextContent('Parrainage indisponible');
    expect(screen.queryByRole('button', { name: 'Copier le lien' })).not.toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Réessayer' })).toBeInTheDocument();
  });
});
