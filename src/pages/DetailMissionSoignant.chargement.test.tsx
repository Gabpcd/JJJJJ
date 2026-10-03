import React from 'react';
import { act, cleanup, fireEvent, render, screen } from '@testing-library/react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import DetailMissionSoignant from './DetailMissionSoignant';

const mocks = vi.hoisted(() => ({
  user: { id: 'soignant-a' } as { id: string } | null,
  id: 'mission-a', role: { resolved: true, parcours: undefined as any },
  from: vi.fn(), rpc: vi.fn(), explorer: vi.fn(), sentry: vi.fn(), safe: vi.fn(),
  etablissement: null as any, rendus: [] as string[],
}));
vi.mock('@/contexts/AuthContext', () => ({ useAuth: () => ({ user: mocks.user }) }));
vi.mock('@/hooks/useRole', () => ({ useRole: () => mocks.role }));
vi.mock('react-router-dom', () => ({ useParams: () => ({ id: mocks.id }), useNavigate: () => vi.fn() }));
vi.mock('@/hooks/usePageTitle', () => ({ usePageTitle: vi.fn() }));
vi.mock('@/lib/sentry', () => ({ capturerErreurSentry: mocks.sentry }));
vi.mock('@/lib/handleError', () => ({ handleErrorSilent: vi.fn() }));
vi.mock('@/lib/platform', () => ({ ouvrirNavigation: vi.fn() }));
vi.mock('@/lib/profil-soignant', () => ({ calculerCompletionProfil: () => ({ pourcentage: 100, peut_candidater: true, items_obligatoires_manquants: [] }), getMotifProfilIncomplet: () => '' }));
vi.mock('@/lib/haptics', () => ({ hapticNotification: vi.fn() }));
vi.mock('@/lib/etablissements', () => ({ fetchEtablissementsSafe: mocks.safe }));
vi.mock('@/lib/explorationInscription', () => ({ chargerMissionsInscription: mocks.explorer, preparerCandidatureInscription: vi.fn() }));
vi.mock('@/integrations/supabase/client', () => ({ supabase: { from: mocks.from, rpc: mocks.rpc } }));
vi.mock('@/components/ChoixContratDialog', () => ({ ChoixContratDialog: () => null }));
vi.mock('@/components/BoutonNoterMission', () => ({ BoutonNoterMission: () => <button>Noter l’établissement</button> }));
vi.mock('@/components/BadgeScoreEtabPublic', () => ({ BadgeScoreEtabPublic: () => null }));
vi.mock('@/components/LayoutApp', () => ({ LayoutApp: ({ children }: { children: React.ReactNode }) => {
  React.useLayoutEffect(() => { mocks.rendus.push(document.body.textContent ?? ''); });
  return <main>{children}</main>;
} }));
vi.mock('@/components/ChargementPage', () => ({ ChargementPage: () => <p role="status">Chargement</p> }));
vi.mock('@/components/BadgeStatut', () => ({ BadgeStatut: () => null }));
vi.mock('@/components/BadgeDistance', () => ({ BadgeDistance: () => null }));
vi.mock('@/components/DecompositionFinanciere', () => ({ DecompositionFinanciere: () => null }));
vi.mock('@/components/FactureHonorairesCard', () => ({ FactureHonorairesCard: () => null }));
vi.mock('@/components/SuiviMission', () => ({ SuiviMission: ({ onReessayerPlanning }: { onReessayerPlanning: () => void }) => <button onClick={onReessayerPlanning}>Recharger le planning</button> }));
vi.mock('@/components/BlocagePostulation', () => ({ BlocagePostulation: () => null }));
vi.mock('@/components/ChatConversation', () => ({ ChatConversation: () => null }));
vi.mock('@/components/BlocConformite', () => ({ BlocConformite: () => null }));
vi.mock('@/components/BoutonExclusion', () => ({ BoutonExclusion: () => null }));
vi.mock('@/components/SignalerUtilisateur', () => ({ SignalerUtilisateur: () => null }));
vi.mock('@/components/CompteurHebdomadaire', () => ({ CompteurHebdomadaire: () => null }));
vi.mock('@/components/ModalConfirmation', () => ({ ModalConfirmation: () => null }));
vi.mock('@/components/ModalCodeTravail', () => ({ ModalCodeTravail: () => null }));
vi.mock('@/components/ModalPerduDeVitesse', () => ({ ModalPerduDeVitesse: () => null }));
vi.mock('@/components/AnimationSuccesMission', () => ({ AnimationSuccesMission: () => null }));
vi.mock('@/components/y2k/BoutonY2K', () => ({ BoutonY2K: () => null }));
vi.mock('@/components/BlocContratTravailMission', () => ({ BlocContratTravailMission: () => null }));
vi.mock('@/components/DeclarationEmpechement', () => ({ DeclarationEmpechement: () => null }));
vi.mock('@/components/BandeauActionPrioritaire', () => ({ BandeauActionPrioritaire: () => null }));
vi.mock('@/components/soignant/ModaleAnnulationCandidature', () => ({ ModaleAnnulationCandidature: () => null }));
vi.mock('@/components/soignant/AnnulationCandidatureTimer', () => ({ AnnulationCandidatureTimer: () => null }));
vi.mock('@/components/planning/PlanningMissionCandidat', () => ({ PlanningMissionCandidat: () => null }));
vi.mock('@/components/planning/RecapitulatifCandidatureDialog', () => ({ RecapitulatifCandidatureDialog: () => null }));

type Lecture = { type: string; signal?: AbortSignal; resolve: (data: any) => void; reject: (error: Error) => void };
const lectures: Lecture[] = [];
function enAttente(type: string) {
  let resolve!: Lecture['resolve'], reject!: Lecture['reject'];
  const promise = new Promise<any>((a, b) => { resolve = a; reject = b; });
  const lecture: Lecture = { type, resolve, reject };
  lectures.push(lecture);
  // Le transport simulé peut répondre même après abort : le composant doit
  // également ignorer une réponse tardive, sans dépendre du comportement HTTP.
  return { promise, lecture };
}
function builder(table: string) {
  let pending: ReturnType<typeof enAttente> | undefined;
  let promise = Promise.resolve({ data: null, error: null, count: 0 });
  const query: any = {
    select(columns: string) {
      if (table === 'missions' && columns.includes('intitule')) {
        pending = enAttente('mission'); promise = pending.promise;
      }
      if (table === 'mission_creneaux' || columns.includes('nature_tva_prestation')) {
        promise = new Promise(() => {}); // Facultatives lentes, titre indépendant.
      }
      return query;
    },
    eq: () => query, order: () => query, limit: () => query,
    single: () => query, maybeSingle: () => query,
    abortSignal(signal: AbortSignal) { if (pending) pending.lecture.signal = signal; return query; },
    then(a: any, b: any) { return promise.then(a, b); },
  };
  return query;
}
const mission = (intitule = 'Mission actuelle') => ({
  id: mocks.id, intitule, statut: 'TERMINEE', soignant_assigne_id: mocks.user?.id,
  etablissement_id: 'etablissement-a', profession_requise: 'IDE',
  debut_le: '2026-10-12T06:00:00Z', fin_le: '2026-10-12T14:00:00Z',
  duree_heures: 8, nb_creneaux: 1, type_contrat_applique: 'SALARIE',
  taux_horaire_base: 20, total_brut: 160, net_a_payer: 120,
});
const profil = () => ({ id: mocks.user?.id, prenom: 'Recette', nom: 'Synthétique', profession: 'IDE' });
const avancer = async (ms: number) => act(async () => { await vi.advanceTimersByTimeAsync(ms); });
const repondre = async (index: number, data: any, error: any = null) => act(async () => { lectures[index].resolve({ data, error }); });
const reussir = async (index: number, titre = 'Mission actuelle') => {
  await repondre(index, mission(titre)); await repondre(index + 1, profil());
};
beforeEach(() => {
  vi.useFakeTimers(); vi.clearAllMocks(); lectures.length = 0; mocks.rendus.length = 0;
  mocks.etablissement = null; mocks.safe.mockResolvedValue({});
  mocks.user = { id: 'soignant-a' }; mocks.id = 'mission-a'; mocks.role = { resolved: true, parcours: undefined };
  mocks.from.mockImplementation(builder);
  mocks.rpc.mockImplementation((name: string) => {
    if (name === 'fn_mon_profil_soignant_complet') {
      const pending = enAttente('profil');
      return Object.assign(pending.promise, { abortSignal(signal: AbortSignal) { pending.lecture.signal = signal; return pending.promise; } });
    }
    if (name === 'fn_etablissement_public') return Promise.resolve({ data: mocks.etablissement, error: mocks.etablissement ? null : { message: 'Indisponible' } });
    return Promise.resolve({ data: null, error: null });
  });
  mocks.explorer.mockImplementation((_id: string, signal: AbortSignal) => {
    const pending = enAttente('exploration'); pending.lecture.signal = signal; return pending.promise;
  });
});
afterEach(() => { cleanup(); vi.useRealTimers(); });

describe('DetailMissionSoignant — cycle des lectures critiques', () => {
  it('ne relit pas pour le même utilisateur ni pour parcours undefined devenu null', async () => {
    const vue = render(<DetailMissionSoignant />);
    expect(lectures).toHaveLength(2);
    expect(lectures[0].signal).toBe(lectures[1].signal);
    mocks.user = { id: 'soignant-a' }; mocks.role = { resolved: true, parcours: null };
    vue.rerender(<DetailMissionSoignant />);
    expect(lectures).toHaveLength(2); expect(lectures[0].signal?.aborted).toBe(false);
    await reussir(0);
    expect(screen.getByRole('heading', { name: 'Mission actuelle' })).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Noter l’établissement' })).toBeInTheDocument();
  });
  it('attend le contexte local puis explore sans lire de profil complet', async () => {
    mocks.role = { resolved: false, parcours: undefined };
    const vue = render(<DetailMissionSoignant />); expect(lectures).toHaveLength(0);
    mocks.role = { resolved: true, parcours: { donnees: { profession: 'IDE' } } };
    vue.rerender(<DetailMissionSoignant />);
    expect(lectures.map(l => l.type)).toEqual(['exploration']);
    mocks.role = { resolved: true, parcours: { donnees: { profession: 'IDE', autre: true } } };
    vue.rerender(<DetailMissionSoignant />);
    expect(lectures).toHaveLength(1); expect(lectures[0].signal?.aborted).toBe(false);
    await act(async () => { lectures[0].resolve([mission()]); });
    expect(screen.getByRole('heading', { name: 'Mission actuelle' })).toBeInTheDocument();
  });
  it('annule les deux lectures à 8s avant la seconde tentative à 8350ms', async () => {
    render(<DetailMissionSoignant />);
    await avancer(8000);
    expect(lectures).toHaveLength(2); expect(lectures.every(l => l.signal?.aborted)).toBe(true);
    await avancer(349); expect(lectures).toHaveLength(2);
    await avancer(1); expect(lectures).toHaveLength(4);
    expect(lectures[2].signal).toBe(lectures[3].signal);
    expect(lectures[2].signal).not.toBe(lectures[0].signal);
    await reussir(2); await reussir(0, 'Réponse périmée');
    expect(screen.getByRole('heading', { name: 'Mission actuelle' })).toBeInTheDocument();
    expect(screen.queryByText('Réponse périmée')).not.toBeInTheDocument();
  });
  it('annule au démontage et ne reprend pas même si le transport reste en attente', async () => {
    const vue = render(<DetailMissionSoignant />); vue.unmount();
    expect(lectures.every(l => l.signal?.aborted)).toBe(true);
    await avancer(20000); await reussir(0, 'Abandonnée');
    expect(lectures).toHaveLength(2); expect(mocks.sentry).not.toHaveBeenCalled();
  });
  it('annule aussi la pause entre les tentatives au démontage', async () => {
    const vue = render(<DetailMissionSoignant />);
    await act(async () => { lectures[0].reject(new Error('Refus lecture')); });
    expect(lectures[1].signal?.aborted).toBe(true);
    vue.unmount(); await avancer(20000);
    expect(lectures).toHaveLength(2); expect(mocks.sentry).not.toHaveBeenCalled();
  });
  it.each(['compte', 'mission'])('ignore les réponses tardives après changement de %s', async (changement) => {
    const vue = render(<DetailMissionSoignant />);
    if (changement === 'compte') mocks.user = { id: 'soignant-b' }; else mocks.id = 'mission-b';
    vue.rerender(<DetailMissionSoignant />);
    expect(lectures[0].signal?.aborted).toBe(true); expect(lectures).toHaveLength(4);
    await reussir(2, 'Nouveau contexte'); await reussir(0, 'Ancien contexte');
    expect(screen.getByRole('heading', { name: 'Nouveau contexte' })).toBeInTheDocument();
    expect(screen.queryByText('Ancien contexte')).not.toBeInTheDocument();
  });
  it('masque A dès le premier rendu de B et refuse ses enrichissements périmés', async () => {
    mocks.etablissement = { nom: 'Établissement A', adresse_ville: 'Ville A' };
    mocks.safe.mockResolvedValue({ 'etablissement-a': mocks.etablissement });
    const vue = render(<DetailMissionSoignant />); await reussir(0, 'Mission A affichée');
    expect(screen.getByRole('heading', { name: 'Établissement A' })).toBeInTheDocument();
    const avantChangement = mocks.rendus.length;
    mocks.id = 'mission-b'; mocks.etablissement = null;
    mocks.safe.mockRejectedValue(new Error('Lecture B indisponible'));
    vue.rerender(<DetailMissionSoignant />);
    // Observations au commit React, avant les effets passifs du parent : aucun
    // rendu de l'ancien contenu ne doit rester actionnable dans le contexte B.
    expect(mocks.rendus.slice(avantChangement).every(texte => !texte.includes('Mission A affichée'))).toBe(true);
    await reussir(2, 'Mission B affichée');
    expect(screen.getByRole('heading', { name: 'Mission B affichée' })).toBeInTheDocument();
    expect(screen.queryByText('Établissement A')).not.toBeInTheDocument();
    expect(screen.queryByText('Ville A')).not.toBeInTheDocument();
    expect(screen.getByRole('heading', { name: /^Établissement$/ })).toBeInTheDocument();
  });
  it('affiche seulement l’erreur de B si A était déjà affichée', async () => {
    const vue = render(<DetailMissionSoignant />); await reussir(0, 'Mission A affichée');
    mocks.id = 'mission-b'; vue.rerender(<DetailMissionSoignant />);
    await avancer(16350);
    expect(lectures).toHaveLength(6);
    expect(screen.getByRole('heading', { name: 'Impossible de charger la mission' })).toBeInTheDocument();
    expect(screen.queryByText('Mission A affichée')).not.toBeInTheDocument();
    expect(screen.queryByRole('button', { name: 'Noter l’établissement' })).not.toBeInTheDocument();
    fireEvent.click(screen.getByRole('button', { name: 'Réessayer' }));
    await reussir(6, 'Mission B reprise');
    expect(screen.getByRole('heading', { name: 'Mission B reprise' })).toBeInTheDocument();
  });
  it('préserve la saisie au rechargement et l’efface au changement de contexte', async () => {
    const ouverte = () => ({ ...mission(), statut: 'OUVERTE', soignant_assigne_id: null, mode_attribution: 'CANDIDATURE' });
    const vue = render(<DetailMissionSoignant />);
    await repondre(0, ouverte()); await repondre(1, profil());
    fireEvent.change(screen.getByRole('textbox'), { target: { value: 'Mon message en cours' } });
    fireEvent.click(screen.getByRole('button', { name: 'Recharger le planning' }));
    await repondre(2, ouverte()); await repondre(3, profil());
    expect(screen.getByRole('textbox')).toHaveValue('Mon message en cours');
    mocks.id = 'mission-b'; vue.rerender(<DetailMissionSoignant />);
    await repondre(4, ouverte()); await repondre(5, profil());
    expect(screen.getByRole('textbox')).toHaveValue('');
  });
  it('annule exploration au changement de profession ou de mode', async () => {
    mocks.role = { resolved: true, parcours: { donnees: { profession: 'IDE' } } };
    const vue = render(<DetailMissionSoignant />);
    mocks.role = { resolved: true, parcours: { donnees: { profession: 'AS' } } };
    vue.rerender(<DetailMissionSoignant />); expect(lectures[0].signal?.aborted).toBe(true);
    mocks.role = { resolved: true, parcours: null }; vue.rerender(<DetailMissionSoignant />);
    expect(lectures[1].signal?.aborted).toBe(true);
    expect(lectures.map(l => l.type)).toEqual(['exploration', 'exploration', 'mission', 'profil']);
    await reussir(2); await act(async () => { lectures[0].resolve([mission('Ancienne exploration')]); });
    expect(screen.queryByText('Ancienne exploration')).not.toBeInTheDocument();
  });
  it('borne aussi exploration à deux tentatives et affiche une erreur récupérable', async () => {
    mocks.role = { resolved: true, parcours: { donnees: { profession: 'IDE' } } };
    render(<DetailMissionSoignant />); await avancer(16350);
    expect(lectures).toHaveLength(2); expect(lectures.every(l => l.signal?.aborted)).toBe(true);
    expect(screen.getByRole('heading', { name: 'Impossible de charger la mission' })).toBeInTheDocument();
    fireEvent.click(screen.getByRole('button', { name: 'Réessayer' }));
    await act(async () => { lectures[2].resolve([mission()]); });
    expect(screen.getByRole('heading', { name: 'Mission actuelle' })).toBeInTheDocument();
  });
  it('conserve Mission introuvable pour PGRST116 sans nouvelle tentative', async () => {
    render(<DetailMissionSoignant />);
    await repondre(0, null, { code: 'PGRST116' }); await repondre(1, profil());
    expect(screen.getByRole('heading', { name: 'Mission introuvable' })).toBeInTheDocument();
    await avancer(20000); expect(lectures).toHaveLength(2);
  });
  it('masque le contenu précédent quand le contexte local redevient non résolu', async () => {
    const vue = render(<DetailMissionSoignant />); await reussir(0);
    mocks.role = { resolved: false, parcours: undefined }; vue.rerender(<DetailMissionSoignant />);
    expect(screen.queryByRole('heading', { name: 'Mission actuelle' })).not.toBeInTheDocument();
    expect(screen.getByRole('status')).toHaveTextContent('Chargement');
  });
});
