import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import {
  Activity,
  Building2,
  CheckCircle2,
  CircleDollarSign,
  DatabaseZap,
  ExternalLink,
  EyeOff,
  Factory,
  Mail,
  MapPinned,
  Phone,
  PlayCircle,
  Plus,
  RefreshCw,
  Repeat2,
  ShieldCheck,
  Target,
  UserCheck,
  Users,
  XCircle,
} from 'lucide-react';
import { BadgeY2K } from '@/components/y2k/BadgeY2K';
import { BoutonY2K } from '@/components/y2k/BoutonY2K';
import { CardY2K, CardY2KContent, CardY2KHeader, CardY2KTitle } from '@/components/y2k/CardY2K';
import { CarteKPIY2K } from '@/components/y2k/CarteKPIY2K';
import { Label } from '@/components/ui/label';
import { PROFESSIONS, getLabelProfession } from '@/lib/constantes';
import { supabase } from '@/integrations/supabase/client';
import { toast } from 'sonner';

type Scope = 'REEL' | 'TEST' | 'TOUS';

interface StatsRadar {
  signaux_actifs: number;
  etablissements_a_potentiel: number;
  soignants_verifies: number;
  disponibles_14j: number;
  potentiel_commission_mensuel_ht: number;
  commission_observee_ht: number;
  actions_brouillon: number;
}

interface SegmentRadar {
  departement: string;
  profession: string;
  soignants_verifies: number;
  disponibles_14j: number;
  missions_90j: number;
  missions_ouvertes: number;
  missions_pourvues: number;
  etablissements_actifs: number;
  signaux_externes: number;
  volume_externe: number;
  score_signal: number;
  statut_territoire: 'OBSERVATION' | 'PREPARATION' | 'OUVERT' | 'PAUSE';
  objectif_ancres: number;
  objectif_soignants: number;
  objectif_missions: number;
  score_priorite: number;
  score_bmo?: number;
  potentiel_commission_mensuel_ht: number;
  commission_observee_ht: number;
  bmo_annee: number | null;
  bmo_projets_recrutement: number | null;
  bmo_difficulte_pct: number | null;
  bmo_precision?: 'EXACT' | 'AGREGAT' | null;
  bmo_code_metier?: string | null;
  bmo_libelle_metier?: string | null;
}

interface SignalRadar {
  id: string;
  source_code: string;
  source_url: string | null;
  nom_etablissement: string;
  intitule: string;
  profession: string | null;
  departement: string | null;
  ville: string | null;
  type_contrat: string | null;
  volume_estime: number;
  score_demande: number;
  statut: string;
  publie_le: string | null;
}

interface AncreRadar {
  nom: string;
  departement: string | null;
  ville: string | null;
  finess: string | null;
  siret: string | null;
  nb_signaux: number;
  volume: number;
  score: number;
  professions: string[] | null;
  deja_inscrit: boolean;
  potentiel_commission_mensuel_ht: number;
}

interface CibleExterne {
  id: string;
  finess: string;
  siret: string | null;
  nom: string;
  type_jolene: string;
  categorie_lib: string | null;
  telephone: string | null;
  email: string | null;
  ville: string | null;
  departement: string;
  profession: string;
  score: number;
  raison_priorite: string;
  force_signal: 'DIRECT' | 'INFERENCE_TERRITORIALE';
  signaux_directs: number;
  volume_direct: number;
  intitule_signal: string | null;
  source_signal: string | null;
  source_demande_url: string | null;
  finess_source_url: string | null;
  bmo_annee: number | null;
  bmo_projets_recrutement: number | null;
  bmo_difficulte_pct: number | null;
  bmo_precision: 'EXACT' | 'AGREGAT' | null;
}

interface CiblesExternesData {
  genere_le: string;
  contact_automatique: false;
  total_classe: number;
  methode: string;
  resultats: CibleExterne[];
}

interface RecurrenceRadar {
  id: string;
  nom: string;
  departement: string | null;
  missions: number;
  series: number;
  professions: number;
  commission_mensuelle_estimee_ht: number;
}

interface ActionRadar {
  id: string;
  type_action: string;
  titre: string;
  description: string | null;
  departement: string | null;
  profession: string | null;
  score: number;
  revenu_mensuel_estime_ht: number;
  statut: ActionStatut;
}

type ActionStatut = 'BROUILLON' | 'PRIORISEE' | 'EN_COURS' | 'TERMINEE' | 'IGNORE';
type ActionStatutCible = Exclude<ActionStatut, 'BROUILLON'>;

interface SourceRadar {
  code: string;
  libelle: string;
  type_source: string;
  source_url: string;
  automatique: boolean;
  actif: boolean;
  configuration_requise: string | null;
  dernier_import_le: string | null;
  dernier_statut: 'OK' | 'ERREUR' | 'NON_CONFIGURE' | null;
  dernier_message: string | null;
}

interface RadarData {
  scope: Scope;
  jours: number;
  genere_le: string;
  contact_automatique: boolean;
  marketing_actif: boolean;
  hypotheses: {
    taux_commission_pct: number;
    taux_horaire_moyen: number;
    duree_signal_heures: number;
    caractere: string;
  };
  stats: StatsRadar;
  segments: SegmentRadar[];
  signaux: SignalRadar[];
  ancres: AncreRadar[];
  recurrence: RecurrenceRadar[];
  actions: ActionRadar[];
  sources: SourceRadar[];
}

const ACTION_LABELS: Record<string, string> = {
  COMPTE_ANCRE: 'Compte ancre',
  RENFORCER_VIVIER: 'Vivier',
  REVERSE_MARKETPLACE: 'Reverse marketplace',
  RECURRENCE: 'Récurrence',
  CIBLER_GROUPE: 'Groupe',
  PARTENARIAT_ECOLE: 'École',
  QUALIFIER_SIGNAL: 'Qualification',
};

const ACTION_STATUTS: Record<ActionStatut, {
  label: string;
  variant: 'success' | 'warning' | 'error' | 'info';
}> = {
  BROUILLON: { label: 'Brouillon', variant: 'info' },
  PRIORISEE: { label: 'Priorisée', variant: 'warning' },
  EN_COURS: { label: 'En cours', variant: 'info' },
  TERMINEE: { label: 'Terminée', variant: 'success' },
  IGNORE: { label: 'Ignorée', variant: 'error' },
};

const ACTION_TRANSITIONS: Record<ActionStatut, readonly ActionStatutCible[]> = {
  BROUILLON: ['PRIORISEE', 'IGNORE'],
  PRIORISEE: ['EN_COURS', 'IGNORE'],
  EN_COURS: ['TERMINEE'],
  TERMINEE: [],
  IGNORE: [],
};

const ACTION_CONFIRMATIONS: Record<ActionStatutCible, string> = {
  PRIORISEE: 'Action priorisée. Aucun message envoyé.',
  EN_COURS: 'Action démarrée. Aucun message envoyé.',
  TERMINEE: 'Action marquée comme terminée. Aucun message envoyé.',
  IGNORE: 'Action ignorée. Aucun message envoyé.',
};

function peutChangerStatutAction(statut: ActionStatut, cible: ActionStatutCible): boolean {
  return ACTION_TRANSITIONS[statut].includes(cible);
}

const fmtEuro = (value: number) => new Intl.NumberFormat('fr-FR', {
  style: 'currency',
  currency: 'EUR',
  maximumFractionDigits: 0,
}).format(Number.isFinite(Number(value)) ? Number(value) : 0);

const fmtDate = (value: string | null) => value
  ? new Intl.DateTimeFormat('fr-FR', { dateStyle: 'medium', timeStyle: 'short' }).format(new Date(value))
  : 'Jamais';

function scoreVariant(score: number): 'success' | 'warning' | 'info' {
  if (score >= 75) return 'success';
  if (score >= 50) return 'warning';
  return 'info';
}

function sourceVariant(source: SourceRadar): 'success' | 'warning' | 'error' | 'info' {
  if (source.dernier_statut === 'ERREUR') return 'error';
  if (source.dernier_statut === 'NON_CONFIGURE' || !source.dernier_import_le) return 'warning';
  if (source.actif && source.dernier_statut === 'OK') return 'success';
  return 'info';
}

function sourceStatut(source: SourceRadar): string {
  if (source.dernier_statut === 'ERREUR') return 'erreur';
  if (source.dernier_statut === 'NON_CONFIGURE') return 'à configurer';
  if (!source.dernier_import_le) return 'jamais importée';
  if (!source.actif) return 'inactive';
  return source.dernier_statut === 'OK' ? 'opérationnelle' : 'active';
}

function messageErreurRadar(message: string): string {
  const normalise = message.toLowerCase();
  if (normalise.includes('statement timeout') || normalise.includes('canceling statement')) {
    return 'Le calcul a dépassé le délai de sécurité. Réessayez dans un instant ; les dernières données affichées ont été conservées.';
  }
  return 'Le radar est momentanément indisponible. Réessayez dans un instant ; les dernières données affichées ont été conservées.';
}

const DOMAINES_SOURCES_OFFICIELLES = [
  'boamp.fr',
  'data.gouv.fr',
  'esante.gouv.fr',
  'annuaire.sante.fr',
  'francetravail.fr',
  'pole-emploi.fr',
];

function urlSourceOfficielle(value: string | null): string | null {
  if (!value) return null;
  try {
    const url = new URL(value);
    if (url.protocol !== 'https:') return null;
    const hostname = url.hostname.toLowerCase();
    return DOMAINES_SOURCES_OFFICIELLES.some((domaine) => (
      hostname === domaine || hostname.endsWith(`.${domaine}`)
    )) ? url.toString() : null;
  } catch {
    return null;
  }
}

export function AdminAcquisitionRadar() {
  const [scope, setScope] = useState<Scope>('REEL');
  const [jours, setJours] = useState(90);
  const [departement, setDepartement] = useState('');
  const [profession, setProfession] = useState('');
  const [data, setData] = useState<RadarData | null>(null);
  const [ciblesExternes, setCiblesExternes] = useState<CiblesExternesData | null>(null);
  const [loading, setLoading] = useState(true);
  const [erreurChargement, setErreurChargement] = useState<string | null>(null);
  const [erreurCibles, setErreurCibles] = useState<string | null>(null);
  const [actionLoading, setActionLoading] = useState<string | null>(null);
  const requeteCourante = useRef(0);

  const charger = useCallback(async (silencieux = false, rechargerCibles = true) => {
    const numeroRequete = ++requeteCourante.current;
    if (!silencieux) setLoading(true);
    try {
      const [radar, cibles] = await Promise.all([
        supabase.rpc('fn_admin_acquisition_radar_externe' as never, {
          p_scope: scope,
          p_jours: jours,
          p_departement: departement.trim() || null,
          p_profession: profession || null,
        } as never),
        scope === 'TEST' || !rechargerCibles
          ? Promise.resolve({ data: null, error: null })
          : supabase.rpc('fn_admin_acquisition_cibles' as never, {
            p_departement: departement.trim() || null,
            p_profession: profession || null,
            p_limit: 100,
          } as never),
      ]);
      if (numeroRequete !== requeteCourante.current) return;
      if (radar.error) {
        const message = messageErreurRadar(radar.error.message);
        setErreurChargement(message);
        if (rechargerCibles) setCiblesExternes(null);
        if (!silencieux) toast.error(message);
        return;
      }
      setErreurChargement(null);
      setData(radar.data as unknown as RadarData);
      if (scope === 'TEST') {
        setCiblesExternes(null);
        setErreurCibles(null);
      } else if (!rechargerCibles) {
        // Le radar temps réel est léger ; le classement FINESS est recalculé
        // uniquement sur action ou changement de filtre.
      } else if (cibles.error) {
        setCiblesExternes(null);
        setErreurCibles(messageErreurRadar(cibles.error.message));
      } else {
        setErreurCibles(null);
        setCiblesExternes(cibles.data as unknown as CiblesExternesData);
      }
    } catch (cause) {
      if (numeroRequete !== requeteCourante.current) return;
      const message = messageErreurRadar(cause instanceof Error ? cause.message : 'Erreur réseau');
      setErreurChargement(message);
      if (rechargerCibles) setCiblesExternes(null);
      if (!silencieux) toast.error(message);
    } finally {
      if (numeroRequete === requeteCourante.current) setLoading(false);
    }
  }, [departement, jours, profession, scope]);

  useEffect(() => {
    void charger();
    const intervalle = window.setInterval(() => void charger(true, false), 60_000);
    return () => {
      window.clearInterval(intervalle);
      requeteCourante.current += 1;
    };
  }, [charger]);

  const franceTravail = useMemo(
    () => data?.sources.find((source) => source.code === 'FRANCE_TRAVAIL_OFFRES'),
    [data?.sources],
  );

  const synchroniserSourcesPubliques = async () => {
    if (!window.confirm('Synchroniser BMO et BOAMP en mode silencieux ? Aucun établissement ni soignant ne sera contacté.')) return;
    setActionLoading('IMPORT_PUBLIC');
    try {
      const executions = await Promise.allSettled([
        supabase.functions.invoke('import-bmo-acquisition', { body: { silencieux: true } }),
        supabase.functions.invoke('import-boamp-acquisition', { body: { silencieux: true } }),
      ]);
      const reussites = executions.flatMap((execution) => (
        execution.status === 'fulfilled' && !execution.value.error ? [execution.value] : []
      ));
      if (reussites.length === 0) {
        toast.error('Les deux sources publiques sont momentanément indisponibles. Aucun contact n’a été envoyé.');
      } else if (reussites.length < executions.length) {
        toast.warning('Une source a été synchronisée, l’autre sera réessayée automatiquement. Aucun contact envoyé.');
      } else {
        const imported = reussites.reduce((total, execution) => total + Number(execution.data?.imported || 0), 0);
        toast.success(`${imported} donnée(s) externe(s) intégrée(s), aucun contact envoyé.`);
      }
      await charger();
    } catch {
      toast.error('La synchronisation externe a échoué sans déclencher de contact.');
    } finally {
      setActionLoading(null);
    }
  };

  const ajouterCibleAuCrm = async (cible: CibleExterne) => {
    const key = `CIBLE:${cible.id}`;
    setActionLoading(key);
    const { error } = await supabase.rpc('fn_admin_sourcing_ajouter_crm' as never, {
      p_cible: 'ETABLISSEMENT',
      p_prospect_id: cible.finess,
      p_score: cible.score,
    } as never);
    setActionLoading(null);
    if (error) {
      toast.error(error.message);
      return;
    }
    toast.success('Établissement ajouté manuellement au CRM, séquence désactivée.');
    await charger();
  };

  const importerFranceTravail = async () => {
    if (!window.confirm('Importer silencieusement les offres France Travail ? Aucun employeur ni soignant ne sera contacté.')) return;
    setActionLoading('IMPORT_FRANCE_TRAVAIL');
    const { data: resultat, error } = await supabase.functions.invoke('import-signaux-acquisition', {
      body: { silencieux: true },
    });
    setActionLoading(null);
    if (error) {
      toast.error(resultat?.error || error.message);
      await charger();
      return;
    }
    toast.success(`${resultat?.imported || 0} signal(aux) de demande rapproché(s), aucun contact envoyé.`);
    await charger();
  };

  const genererActions = async () => {
    setActionLoading('GENERER_ACTIONS');
    const { data: resultat, error } = await supabase.rpc('fn_admin_acquisition_generer_actions' as never);
    setActionLoading(null);
    if (error) {
      toast.error(error.message);
      return;
    }
    const res = resultat as unknown as { actions_preparees?: number };
    toast.success(`${res.actions_preparees || 0} recommandation(s) interne(s) préparée(s) en brouillon.`);
    await charger();
  };

  const qualifierSignal = async (signal: SignalRadar, statut: 'QUALIFIE' | 'IGNORE') => {
    setActionLoading(signal.id);
    const { error } = await supabase.rpc('fn_admin_acquisition_qualifier_signal' as never, {
      p_signal_id: signal.id,
      p_statut: statut,
    } as never);
    setActionLoading(null);
    if (error) {
      toast.error(error.message);
      return;
    }
    toast.success(statut === 'IGNORE' ? 'Signal masqué.' : 'Signal qualifié, sans prise de contact.');
    await charger();
  };

  const ajouterCrm = async (signal: SignalRadar) => {
    setActionLoading(signal.id);
    const { data: resultat, error } = await supabase.rpc('fn_admin_acquisition_ajouter_crm' as never, {
      p_signal_id: signal.id,
    } as never);
    setActionLoading(null);
    if (error) {
      toast.error(error.message);
      return;
    }
    const res = resultat as unknown as { sequence_active?: boolean };
    if (res.sequence_active) {
      toast.error('Garde-fou : la séquence CRM ne devait pas être active.');
      return;
    }
    toast.success('Ajouté au CRM en mode silencieux : aucune séquence active.');
    await charger();
  };

  const changerAction = async (action: ActionRadar, statut: ActionStatutCible) => {
    if (actionLoading !== null || !peutChangerStatutAction(action.statut, statut)) return;
    setActionLoading(action.id);
    try {
      const { error } = await supabase.rpc('fn_admin_acquisition_changer_action' as never, {
        p_action_id: action.id,
        p_statut: statut,
      } as never);
      if (error) {
        toast.error(error.message);
        return;
      }
      toast.success(ACTION_CONFIRMATIONS[statut]);
      await charger();
    } catch (cause) {
      toast.error(cause instanceof Error ? cause.message : 'Le changement d’état a échoué. Réessayez.');
    } finally {
      setActionLoading(null);
    }
  };

  const changerTerritoire = async (segment: SegmentRadar, statut: SegmentRadar['statut_territoire']) => {
    setActionLoading(`TERRITOIRE:${segment.departement}:${segment.profession}`);
    const { error } = await supabase.rpc('fn_admin_acquisition_configurer_territoire' as never, {
      p_departement: segment.departement,
      p_profession: segment.profession,
      p_statut: statut,
      p_objectif_ancres: segment.objectif_ancres,
      p_objectif_soignants: segment.objectif_soignants,
      p_objectif_missions: segment.objectif_missions,
      p_notes: null,
    } as never);
    setActionLoading(null);
    if (error) {
      toast.error(error.message);
      return;
    }
    toast.success(`Territoire passé en ${statut.toLowerCase()}.`);
    await charger();
  };

  return (
    <section className="space-y-5" aria-labelledby="acquisition-radar-title" aria-busy={loading}>
      <div className="rounded-xl border-2 border-emerald-500/40 bg-emerald-500/5 p-4" role="status">
        <div className="flex items-start gap-3">
          <ShieldCheck className="mt-0.5 h-5 w-5 shrink-0 text-emerald-600" aria-hidden="true" />
          <div>
            <h2 id="acquisition-radar-title" className="font-bold text-foreground">Radar d’acquisition — mode silencieux</h2>
            <p className="mt-1 text-sm text-muted-foreground">
              Les sources, scores et recommandations sont automatisés. Aucun email, SMS, appel, WhatsApp ou notification n’est envoyé.
              Le passage au CRM conserve la séquence désactivée jusqu’à une décision humaine après lancement.
            </p>
          </div>
          <BadgeY2K variant={data?.marketing_actif ? 'error' : 'success'} className="ml-auto shrink-0">
            {data?.marketing_actif ? 'Marketing actif' : '0 contact auto'}
          </BadgeY2K>
        </div>
      </div>

      <div className="flex flex-col gap-3 rounded-xl border border-border bg-card p-4 lg:flex-row lg:items-end">
        <div className="space-y-1.5">
          <Label htmlFor="radar-scope">Données</Label>
          <select
            id="radar-scope"
            value={scope}
            onChange={(event) => setScope(event.target.value as Scope)}
            className="h-10 rounded-md border border-input bg-background px-3 text-sm"
          >
            <option value="REEL">Réel uniquement</option>
            <option value="TEST">Tests / captures</option>
            <option value="TOUS">Tout</option>
          </select>
        </div>
        <div className="space-y-1.5">
          <Label htmlFor="radar-departement">Département</Label>
          <input
            id="radar-departement"
            value={departement}
            onChange={(event) => setDepartement(event.target.value.toUpperCase().slice(0, 3))}
            className="h-10 w-36 rounded-md border border-input bg-background px-3 text-sm"
            placeholder="ex. 75"
            inputMode="text"
          />
        </div>
        <div className="space-y-1.5">
          <Label htmlFor="radar-profession">Profession demandée</Label>
          <select
            id="radar-profession"
            value={profession}
            onChange={(event) => setProfession(event.target.value)}
            className="h-10 min-w-64 rounded-md border border-input bg-background px-3 text-sm"
          >
            <option value="">Toutes</option>
            {PROFESSIONS.map((item) => <option key={item.valeur} value={item.valeur}>{item.label}</option>)}
          </select>
        </div>
        <div className="flex gap-2 lg:ml-auto">
          {[30, 90, 180].map((valeur) => (
            <BoutonY2K key={valeur} size="sm" variant={jours === valeur ? 'primary' : 'secondary'} onClick={() => setJours(valeur)}>
              {valeur}j
            </BoutonY2K>
          ))}
          <BoutonY2K size="sm" variant="ghost" onClick={() => void charger()} disabled={loading} aria-label="Rafraîchir le radar">
            <RefreshCw className={`h-4 w-4 ${loading ? 'animate-spin' : ''}`} />
          </BoutonY2K>
        </div>
      </div>

      <div className="grid grid-cols-2 gap-4 lg:grid-cols-4">
        <CarteKPIY2K icone={<Activity className="h-4 w-4" />} valeur={data?.stats.signaux_actifs || 0} label="Besoins détectés" variant="holographic" />
        <CarteKPIY2K
          icone={<Building2 className="h-4 w-4" />}
          valeur={scope === 'TEST' ? data?.stats.etablissements_a_potentiel || 0 : ciblesExternes?.total_classe || 0}
          label={scope === 'TEST' ? 'Établ. test avec demande' : 'Établ. externes classés'}
          variant="default"
        />
        <CarteKPIY2K icone={<UserCheck className="h-4 w-4" />} valeur={data?.stats.disponibles_14j || 0} label="Soignants Jolene dispo. J+14" variant="default" />
        <CarteKPIY2K icone={<CircleDollarSign className="h-4 w-4" />} valeur={fmtEuro(data?.stats.potentiel_commission_mensuel_ht || 0)} label="Potentiel mensuel estimé HT" variant="soft" />
      </div>

      <div className="flex flex-col gap-1 text-xs text-muted-foreground sm:flex-row sm:items-start sm:justify-between sm:gap-4">
        <p className="max-w-4xl">
          Le radar rapproche les missions Jolene, les tensions territoriales BMO, les avis BOAMP et l’annuaire FINESS. BMO sert à prioriser une zone, jamais à prétendre qu’un établissement recrute précisément ; un avis BOAMP est signalé séparément comme preuve directe. Le potentiel financier n’intègre pas les simples inférences BMO. Aucun contact n’est déclenché par ce calcul.
        </p>
        <p className="shrink-0 tabular-nums">
          {data ? `Dernier calcul : ${fmtDate(data.genere_le)}` : 'Calcul en attente'} · actualisation toutes les 60 s
        </p>
      </div>

      {erreurChargement ? (
        <div className="rounded-xl border border-destructive/30 bg-destructive/5 p-5 text-sm text-destructive" role="alert">
          {erreurChargement}
        </div>
      ) : null}

      {erreurCibles ? (
        <div className="rounded-xl border border-amber-500/30 bg-amber-500/5 p-4 text-sm text-amber-800 dark:text-amber-300" role="status">
          Le classement externe n’a pas pu être actualisé ; le reste du radar demeure disponible. {erreurCibles}
        </div>
      ) : null}

      {data ? (
        <>
          {scope !== 'TEST' ? (
            <CardY2K hoverLift={false}>
              <CardY2KHeader>
                <CardY2KTitle className="flex items-center gap-2 text-sm">
                  <Building2 className="h-4 w-4" /> Établissements externes à contacter en priorité
                </CardY2KTitle>
              </CardY2KHeader>
              <CardY2KContent>
                <div className="mb-3 flex flex-col gap-2 text-xs text-muted-foreground sm:flex-row sm:items-start sm:justify-between">
                  <p className="max-w-3xl">
                    Cibles FINESS hors comptes Jolene et hors CRM, avec coordonnées publiques. « Direct » signifie qu’un besoin BOAMP ou France Travail nommé a été rapproché ; « tension territoriale » reste une piste à qualifier humainement.
                  </p>
                  <span className="shrink-0">{ciblesExternes?.methode || 'Synchronisation externe en attente'}</span>
                </div>
                <div className="max-h-[620px] space-y-3 overflow-auto pr-1">
                  {(ciblesExternes?.resultats || []).map((cible) => {
                    const sourceDemandeUrl = urlSourceOfficielle(cible.source_demande_url);
                    const finessSourceUrl = urlSourceOfficielle(cible.finess_source_url);
                    return (
                    <article key={cible.id} className="rounded-xl border border-border p-4">
                      <div className="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
                        <div className="min-w-0">
                          <div className="flex flex-wrap items-center gap-2">
                            <h3 className="font-semibold text-foreground">{cible.nom}</h3>
                            <BadgeY2K variant={scoreVariant(cible.score)}>priorité {cible.score}/100</BadgeY2K>
                            <BadgeY2K variant={cible.force_signal === 'DIRECT' ? 'success' : 'info'}>
                              {cible.force_signal === 'DIRECT' ? 'besoin public direct' : 'tension territoriale'}
                            </BadgeY2K>
                            {cible.bmo_precision === 'AGREGAT' ? <BadgeY2K variant="warning">métier BMO agrégé</BadgeY2K> : null}
                          </div>
                          <p className="mt-1 text-sm text-foreground">
                            {cible.type_jolene} · {getLabelProfession(cible.profession)} · {[cible.ville, cible.departement].filter(Boolean).join(' · ')}
                          </p>
                          <p className="mt-2 text-xs text-muted-foreground">{cible.raison_priorite}</p>
                          {cible.type_jolene === 'CENTRE_SANTE' ? (
                            <p className="mt-1 text-[11px] font-medium text-amber-700 dark:text-amber-400">Centre de santé : exercice salarié uniquement.</p>
                          ) : null}
                          {cible.profession === 'IADE' || cible.profession === 'IBODE' ? (
                            <p className="mt-1 text-[11px] font-medium text-amber-700 dark:text-amber-400">Mission IADE/IBODE : contrat salarié uniquement.</p>
                          ) : null}
                        </div>
                        <div className="flex shrink-0 flex-wrap gap-2">
                          <BoutonY2K
                            size="sm"
                            variant="primary"
                            onClick={() => void ajouterCibleAuCrm(cible)}
                            disabled={actionLoading === `CIBLE:${cible.id}`}
                            iconeGauche={<Plus className="h-4 w-4" />}
                          >
                            CRM silencieux
                          </BoutonY2K>
                        </div>
                      </div>
                      <div className="mt-3 flex flex-wrap items-center gap-x-4 gap-y-2 border-t border-border pt-3 text-xs">
                        {cible.telephone ? (
                          <a href={`tel:${cible.telephone}`} className="inline-flex min-h-8 items-center gap-1 text-primary hover:underline">
                            <Phone className="h-3.5 w-3.5" /> {cible.telephone}
                          </a>
                        ) : null}
                        {cible.email ? (
                          <a href={`mailto:${cible.email}`} className="inline-flex min-h-8 items-center gap-1 text-primary hover:underline">
                            <Mail className="h-3.5 w-3.5" /> {cible.email}
                          </a>
                        ) : null}
                        <span className="font-mono text-muted-foreground">FINESS {cible.finess}</span>
                        {sourceDemandeUrl ? (
                          <a href={sourceDemandeUrl} target="_blank" rel="noreferrer" className="inline-flex min-h-8 items-center gap-1 text-primary hover:underline">
                            Preuve / tension <ExternalLink className="h-3 w-3" />
                          </a>
                        ) : null}
                        {finessSourceUrl ? (
                          <a href={finessSourceUrl} target="_blank" rel="noreferrer" className="inline-flex min-h-8 items-center gap-1 text-primary hover:underline">
                            Fiche source <ExternalLink className="h-3 w-3" />
                          </a>
                        ) : null}
                      </div>
                    </article>
                    );
                  })}
                  {!ciblesExternes ? (
                    <div className="py-8 text-center text-sm text-muted-foreground">
                      Classement des établissements externes en cours…
                    </div>
                  ) : null}
                  {ciblesExternes && ciblesExternes.resultats.length === 0 ? (
                    <div className="py-8 text-center text-sm text-muted-foreground">
                      Aucune cible externe classée pour l’instant. Lancez « Synchroniser BMO + BOAMP » ci-dessous ; aucun contact ne sera envoyé.
                    </div>
                  ) : null}
                </div>
              </CardY2KContent>
            </CardY2K>
          ) : null}

          <div className="grid gap-4 xl:grid-cols-2">
            <CardY2K hoverLift={false}>
              <CardY2KHeader>
                <CardY2KTitle className="flex items-center gap-2 text-sm"><MapPinned className="h-4 w-4" /> Liquidité locale</CardY2KTitle>
              </CardY2KHeader>
              <CardY2KContent>
                <p className="mb-3 text-xs text-muted-foreground">
                  La profession est celle demandée par la mission. « Disponibles » exige une disponibilité déclarée à J+14 ; « vérifiés » exige les documents validés.
                </p>
                <div className="max-h-[420px] overflow-auto">
                  <table className="w-full text-sm">
                    <thead className="sticky top-0 bg-card text-left text-xs text-muted-foreground">
                      <tr className="border-b">
                        <th className="py-2 pr-2">Zone</th>
                        <th className="px-2 py-2 text-right">Demande</th>
                        <th className="px-2 py-2 text-right">Vérifiés</th>
                        <th className="px-2 py-2 text-right">Dispo.</th>
                        <th className="px-2 py-2 text-right">Score</th>
                        <th className="py-2 pl-2">Pilotage</th>
                      </tr>
                    </thead>
                    <tbody>
                      {data.segments.slice(0, 40).map((segment) => {
                        const actionKey = `TERRITOIRE:${segment.departement}:${segment.profession}`;
                        return (
                          <tr key={`${segment.departement}:${segment.profession}`} className="border-b last:border-0 align-top">
                            <td className="py-2 pr-2">
                              <p className="font-medium text-foreground">{segment.departement} · {getLabelProfession(segment.profession)}</p>
                              <p className="text-[11px] text-muted-foreground">{segment.missions_90j} mission(s) / {jours}j</p>
                              {segment.bmo_projets_recrutement ? (
                                <p className="text-[11px] text-primary">
                                  BMO {segment.bmo_annee}{segment.bmo_precision === 'AGREGAT' ? ` · catégorie « ${segment.bmo_libelle_metier || 'métiers de santé'} »` : ''}
                                  {' : '}{segment.bmo_projets_recrutement} projet(s){segment.bmo_precision === 'AGREGAT' ? ' tous métiers confondus' : ''}
                                  {segment.bmo_difficulte_pct == null ? '' : ` · ${Number(segment.bmo_difficulte_pct).toLocaleString('fr-FR')} % difficiles`}
                                </p>
                              ) : null}
                            </td>
                            <td className="px-2 py-2 text-right">{segment.volume_externe + segment.missions_ouvertes}</td>
                            <td className="px-2 py-2 text-right">{segment.soignants_verifies}</td>
                            <td className="px-2 py-2 text-right">{segment.disponibles_14j}</td>
                            <td className="px-2 py-2 text-right"><BadgeY2K variant={scoreVariant(segment.score_priorite)}>{segment.score_priorite}</BadgeY2K></td>
                            <td className="py-2 pl-2">
                              <select
                                aria-label={`Statut du territoire ${segment.departement} ${getLabelProfession(segment.profession)}`}
                                value={segment.statut_territoire}
                                disabled={actionLoading === actionKey}
                                onChange={(event) => void changerTerritoire(segment, event.target.value as SegmentRadar['statut_territoire'])}
                                className="h-8 rounded-md border border-input bg-background px-2 text-xs"
                              >
                                <option value="OBSERVATION">Observer</option>
                                <option value="PREPARATION">Préparer</option>
                                <option value="OUVERT">Ouvrir</option>
                                <option value="PAUSE">Pause</option>
                              </select>
                            </td>
                          </tr>
                        );
                      })}
                    </tbody>
                  </table>
                  {data.segments.length === 0 ? <p className="py-8 text-center text-sm text-muted-foreground">Aucun segment pour ces filtres.</p> : null}
                </div>
              </CardY2KContent>
            </CardY2K>

            <CardY2K hoverLift={false}>
              <CardY2KHeader>
                <CardY2KTitle className="flex items-center gap-2 text-sm"><Factory className="h-4 w-4" /> Comptes ancres</CardY2KTitle>
              </CardY2KHeader>
              <CardY2KContent>
                <p className="mb-3 text-xs text-muted-foreground">Établissements concentrant plusieurs besoins : priorité aux comptes capables de publier des missions récurrentes.</p>
                <div className="max-h-[420px] space-y-2 overflow-auto">
                  {data.ancres.map((ancre) => (
                    <div key={`${ancre.nom}:${ancre.departement || ''}`} className="rounded-lg border border-border p-3">
                      <div className="flex items-start justify-between gap-3">
                        <div>
                          <p className="font-medium text-foreground">{ancre.nom}</p>
                          <p className="text-xs text-muted-foreground">{[ancre.ville, ancre.departement].filter(Boolean).join(' · ') || 'Localisation inconnue'}</p>
                        </div>
                        <BadgeY2K variant={scoreVariant(ancre.score)}>score {ancre.score}</BadgeY2K>
                      </div>
                      <div className="mt-2 flex flex-wrap gap-2 text-xs">
                        <span>{ancre.nb_signaux} signal(aux)</span>
                        <span>· {ancre.volume} poste(s)</span>
                        <span>· {fmtEuro(ancre.potentiel_commission_mensuel_ht)}/mois estimés</span>
                        {ancre.deja_inscrit ? <BadgeY2K variant="success">déjà inscrit</BadgeY2K> : null}
                      </div>
                      <p className="mt-2 text-[11px] text-muted-foreground">
                        {(ancre.professions || []).map(getLabelProfession).join(', ') || 'Profession non rapprochée'}
                      </p>
                    </div>
                  ))}
                  {data.ancres.length === 0 ? <p className="py-8 text-center text-sm text-muted-foreground">Les comptes ancres apparaîtront après import de signaux.</p> : null}
                </div>
              </CardY2KContent>
            </CardY2K>
          </div>

          <div className="grid gap-4 xl:grid-cols-2">
            <CardY2K hoverLift={false}>
              <CardY2KHeader>
                <CardY2KTitle className="flex items-center gap-2 text-sm"><Repeat2 className="h-4 w-4" /> Récurrence et pipeline estimé</CardY2KTitle>
              </CardY2KHeader>
              <CardY2KContent>
                <div className="space-y-2">
                  {data.recurrence.map((item) => (
                    <div key={item.id} className="flex items-center justify-between gap-3 rounded-lg border border-border p-3 text-sm">
                      <div>
                        <p className="font-medium text-foreground">{item.nom}</p>
                        <p className="text-xs text-muted-foreground">{item.missions} missions · {item.series} série(s) · {item.professions} profession(s)</p>
                      </div>
                      <span className="whitespace-nowrap font-semibold text-foreground">{fmtEuro(item.commission_mensuelle_estimee_ht)}/mois</span>
                    </div>
                  ))}
                  {data.recurrence.length === 0 ? <p className="py-8 text-center text-sm text-muted-foreground">Pas encore d’établissement réel avec au moins deux missions sur la période.</p> : null}
                </div>
              </CardY2KContent>
            </CardY2K>

            <CardY2K hoverLift={false}>
              <CardY2KHeader>
                <CardY2KTitle className="flex items-center gap-2 text-sm"><Target className="h-4 w-4" /> Recommandations internes</CardY2KTitle>
              </CardY2KHeader>
              <CardY2KContent>
                <div className="mb-3 flex items-center justify-between gap-3">
                  <p className="text-xs text-muted-foreground">
                    Générées en brouillon uniquement. Leur suivi est manuel et aucun changement d’état ne déclenche de contact.
                    Étapes : Brouillon → Priorisée → En cours → Terminée.
                  </p>
                  <BoutonY2K size="sm" variant="secondary" onClick={genererActions} disabled={actionLoading === 'GENERER_ACTIONS'} iconeGauche={<PlayCircle className="h-4 w-4" />}>
                    Préparer
                  </BoutonY2K>
                </div>
                <div className="max-h-[380px] space-y-2 overflow-auto">
                  {data.actions.map((action) => (
                    <div key={action.id} className="rounded-lg border border-border p-3">
                      <div className="flex items-start justify-between gap-3">
                        <div>
                          <div className="mb-1 flex flex-wrap items-center gap-2">
                            <BadgeY2K variant="info">{ACTION_LABELS[action.type_action] || action.type_action}</BadgeY2K>
                            {action.revenu_mensuel_estime_ht > 0 ? (
                              <span className="text-[11px] font-medium text-emerald-700 dark:text-emerald-400">
                                {fmtEuro(action.revenu_mensuel_estime_ht)}/mois estimés
                              </span>
                            ) : null}
                          </div>
                          <p className="font-medium text-foreground">{action.titre}</p>
                          <p className="mt-1 text-xs text-muted-foreground">{action.description}</p>
                        </div>
                        <BadgeY2K variant={ACTION_STATUTS[action.statut].variant}>{ACTION_STATUTS[action.statut].label}</BadgeY2K>
                      </div>
                      <div className="mt-3 flex flex-wrap items-center gap-2">
                        <BoutonY2K
                          size="sm"
                          variant="secondary"
                          onClick={() => void changerAction(action, 'PRIORISEE')}
                          disabled={actionLoading !== null || !peutChangerStatutAction(action.statut, 'PRIORISEE')}
                          title="Disponible pour une recommandation au statut Brouillon"
                        >
                          Prioriser
                        </BoutonY2K>
                        <BoutonY2K
                          size="sm"
                          variant="secondary"
                          onClick={() => void changerAction(action, 'EN_COURS')}
                          disabled={actionLoading !== null || !peutChangerStatutAction(action.statut, 'EN_COURS')}
                          title="Disponible après avoir priorisé la recommandation"
                        >
                          Démarrer
                        </BoutonY2K>
                        <BoutonY2K
                          size="sm"
                          variant="secondary"
                          onClick={() => void changerAction(action, 'TERMINEE')}
                          disabled={actionLoading !== null || !peutChangerStatutAction(action.statut, 'TERMINEE')}
                          title="Disponible lorsque la recommandation est en cours"
                        >
                          Terminer
                        </BoutonY2K>
                        <BoutonY2K
                          size="sm"
                          variant="ghost"
                          onClick={() => void changerAction(action, 'IGNORE')}
                          disabled={actionLoading !== null || !peutChangerStatutAction(action.statut, 'IGNORE')}
                          title="Disponible avant le démarrage de la recommandation"
                        >
                          Ignorer
                        </BoutonY2K>
                        <span className="ml-auto text-xs font-medium">score {action.score}</span>
                      </div>
                    </div>
                  ))}
                  {data.actions.length === 0 ? <p className="py-8 text-center text-sm text-muted-foreground">Cliquez sur « Préparer » pour générer la file interne.</p> : null}
                </div>
              </CardY2KContent>
            </CardY2K>
          </div>

          <CardY2K hoverLift={false}>
            <CardY2KHeader>
              <CardY2KTitle className="flex items-center gap-2 text-sm"><DatabaseZap className="h-4 w-4" /> Sources de nouveaux besoins et contacts</CardY2KTitle>
            </CardY2KHeader>
            <CardY2KContent>
              <div className="grid gap-3 md:grid-cols-2 xl:grid-cols-3">
                {data.sources.map((source) => (
                  <div key={source.code} className="rounded-lg border border-border p-3">
                    <div className="flex items-start justify-between gap-2">
                      <p className="font-medium text-foreground">{source.libelle}</p>
                      <BadgeY2K variant={sourceVariant(source)}>
                        {sourceStatut(source)}
                      </BadgeY2K>
                    </div>
                    <p className="mt-1 text-xs text-muted-foreground">Dernier import : {fmtDate(source.dernier_import_le)}</p>
                    {source.dernier_message ? <p className="mt-1 text-xs text-muted-foreground">{source.dernier_message}</p> : null}
                    {source.configuration_requise ? <p className="mt-2 text-[11px] text-amber-700 dark:text-amber-400">Requis : {source.configuration_requise}</p> : null}
                    <a href={source.source_url} target="_blank" rel="noreferrer" className="mt-2 inline-flex items-center gap-1 text-xs text-primary hover:underline">
                      Source officielle <ExternalLink className="h-3 w-3" />
                    </a>
                  </div>
                ))}
              </div>
              <div className="mt-4 flex flex-wrap items-center gap-3 border-t border-border pt-4">
                <BoutonY2K
                  size="sm"
                  variant="primary"
                  onClick={synchroniserSourcesPubliques}
                  disabled={actionLoading === 'IMPORT_PUBLIC'}
                  iconeGauche={<DatabaseZap className="h-4 w-4" />}
                >
                  Synchroniser BMO + BOAMP
                </BoutonY2K>
                <BoutonY2K
                  size="sm"
                  variant="secondary"
                  onClick={importerFranceTravail}
                  disabled={actionLoading === 'IMPORT_FRANCE_TRAVAIL'}
                  iconeGauche={<DatabaseZap className="h-4 w-4" />}
                >
                  Importer France Travail
                </BoutonY2K>
                <p className="text-xs text-muted-foreground">
                  {franceTravail?.configuration_requise && !franceTravail.actif
                    ? 'BMO et BOAMP fonctionnent sans clé. Les offres France Travail restent optionnelles et exigent l’habilitation indiquée.'
                    : 'Sources rapprochées par FINESS/SIRET, profession et département.'}
                </p>
              </div>
            </CardY2KContent>
          </CardY2K>

          <CardY2K hoverLift={false}>
            <CardY2KHeader>
              <CardY2KTitle className="flex items-center gap-2 text-sm"><Users className="h-4 w-4" /> Signaux à qualifier</CardY2KTitle>
            </CardY2KHeader>
            <CardY2KContent>
              <div className="space-y-2">
                {data.signaux.slice(0, 50).map((signal) => (
                  <article key={signal.id} className="rounded-lg border border-border p-3">
                    <div className="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
                      <div>
                        <div className="flex flex-wrap items-center gap-2">
                          <h3 className="font-medium text-foreground">{signal.nom_etablissement}</h3>
                          <BadgeY2K variant={scoreVariant(signal.score_demande)}>score {signal.score_demande}</BadgeY2K>
                          {signal.statut === 'CRM' ? <BadgeY2K variant="success">CRM silencieux</BadgeY2K> : null}
                        </div>
                        <p className="mt-1 text-sm text-foreground">{signal.intitule}</p>
                        <p className="mt-1 text-xs text-muted-foreground">
                          {[signal.profession ? getLabelProfession(signal.profession) : null, signal.type_contrat, signal.ville, signal.departement, `${signal.volume_estime} poste(s)`].filter(Boolean).join(' · ')}
                        </p>
                      </div>
                      <div className="flex flex-wrap gap-2">
                        {signal.source_url ? (
                          <a href={signal.source_url} target="_blank" rel="noreferrer" className="inline-flex h-8 items-center gap-1 rounded-md border border-input px-2 text-xs hover:bg-muted">
                            Voir <ExternalLink className="h-3 w-3" />
                          </a>
                        ) : null}
                        <BoutonY2K size="sm" variant="secondary" onClick={() => void qualifierSignal(signal, 'QUALIFIE')} disabled={actionLoading === signal.id || signal.statut === 'QUALIFIE'} iconeGauche={<CheckCircle2 className="h-4 w-4" />}>
                          Qualifier
                        </BoutonY2K>
                        <BoutonY2K size="sm" variant="primary" onClick={() => void ajouterCrm(signal)} disabled={actionLoading === signal.id || signal.statut === 'CRM'} iconeGauche={<EyeOff className="h-4 w-4" />}>
                          CRM silencieux
                        </BoutonY2K>
                        <BoutonY2K size="sm" variant="ghost" onClick={() => void qualifierSignal(signal, 'IGNORE')} disabled={actionLoading === signal.id} aria-label={`Ignorer le signal ${signal.intitule}`}>
                          <XCircle className="h-4 w-4" />
                        </BoutonY2K>
                      </div>
                    </div>
                  </article>
                ))}
                {data.signaux.length === 0 ? <p className="py-8 text-center text-sm text-muted-foreground">Aucun signal importé pour ces filtres.</p> : null}
              </div>
            </CardY2KContent>
          </CardY2K>

          <p className="text-[11px] text-muted-foreground">
            Estimations : {data.hypotheses.duree_signal_heures} h par poste signalé, taux horaire moyen {fmtEuro(data.hypotheses.taux_horaire_moyen)}, commission moyenne {data.hypotheses.taux_commission_pct} %. Ces montants ne sont pas des revenus garantis.
          </p>
        </>
      ) : null}
    </section>
  );
}
