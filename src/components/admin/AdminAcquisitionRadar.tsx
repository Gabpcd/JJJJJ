import { useCallback, useEffect, useMemo, useState } from 'react';
import {
  Activity,
  Building2,
  CheckCircle2,
  CircleDollarSign,
  DatabaseZap,
  ExternalLink,
  EyeOff,
  Factory,
  MapPinned,
  PlayCircle,
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
  potentiel_commission_mensuel_ht: number;
  commission_observee_ht: number;
  bmo_annee: number | null;
  bmo_projets_recrutement: number | null;
  bmo_difficulte_pct: number | null;
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
  statut: 'BROUILLON' | 'PRIORISEE' | 'EN_COURS';
}

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
  if (source.dernier_statut === 'NON_CONFIGURE' || !source.actif) return 'warning';
  if (source.actif) return 'success';
  return 'info';
}

export function AdminAcquisitionRadar() {
  const [scope, setScope] = useState<Scope>('REEL');
  const [jours, setJours] = useState(90);
  const [departement, setDepartement] = useState('');
  const [profession, setProfession] = useState('');
  const [data, setData] = useState<RadarData | null>(null);
  const [loading, setLoading] = useState(true);
  const [actionLoading, setActionLoading] = useState<string | null>(null);

  const charger = useCallback(async () => {
    setLoading(true);
    const { data: resultat, error } = await supabase.rpc('fn_admin_acquisition_radar' as never, {
      p_scope: scope,
      p_jours: jours,
      p_departement: departement.trim() || null,
      p_profession: profession || null,
    } as never);
    setLoading(false);
    if (error) {
      toast.error(`Radar d’acquisition indisponible : ${error.message}`);
      setData(null);
      return;
    }
    setData(resultat as unknown as RadarData);
  }, [departement, jours, profession, scope]);

  useEffect(() => {
    void charger();
  }, [charger]);

  const franceTravail = useMemo(
    () => data?.sources.find((source) => source.code === 'FRANCE_TRAVAIL_OFFRES'),
    [data?.sources],
  );

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

  const changerAction = async (action: ActionRadar, statut: 'PRIORISEE' | 'IGNORE') => {
    setActionLoading(action.id);
    const { error } = await supabase.rpc('fn_admin_acquisition_changer_action' as never, {
      p_action_id: action.id,
      p_statut: statut,
    } as never);
    setActionLoading(null);
    if (error) {
      toast.error(error.message);
      return;
    }
    toast.success(statut === 'PRIORISEE' ? 'Action priorisée. Aucun message envoyé.' : 'Action ignorée.');
    await charger();
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
            inputMode="numeric"
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
          <BoutonY2K size="sm" variant="ghost" onClick={charger} disabled={loading} aria-label="Rafraîchir le radar">
            <RefreshCw className={`h-4 w-4 ${loading ? 'animate-spin' : ''}`} />
          </BoutonY2K>
        </div>
      </div>

      <div className="grid grid-cols-2 gap-4 lg:grid-cols-4">
        <CarteKPIY2K icone={<Activity className="h-4 w-4" />} valeur={data?.stats.signaux_actifs || 0} label="Signaux actifs" variant="holographic" />
        <CarteKPIY2K icone={<Building2 className="h-4 w-4" />} valeur={data?.stats.etablissements_a_potentiel || 0} label="Établ. à potentiel" variant="default" />
        <CarteKPIY2K icone={<UserCheck className="h-4 w-4" />} valeur={data?.stats.disponibles_14j || 0} label="Disponibles à 14 j" variant="default" />
        <CarteKPIY2K icone={<CircleDollarSign className="h-4 w-4" />} valeur={fmtEuro(data?.stats.potentiel_commission_mensuel_ht || 0)} label="Potentiel mensuel HT" variant="soft" />
      </div>

      {!data && !loading ? (
        <div className="rounded-xl border border-destructive/30 bg-destructive/5 p-5 text-sm text-destructive" role="alert">
          Le radar n’a pas pu être chargé. La page d’attribution par canal reste disponible plus bas.
        </div>
      ) : null}

      {data ? (
        <>
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
                <CardY2KTitle className="flex items-center gap-2 text-sm"><Repeat2 className="h-4 w-4" /> Récurrence et revenu observé</CardY2KTitle>
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
                  <p className="text-xs text-muted-foreground">Générées en brouillon uniquement, jamais envoyées.</p>
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
                        <BadgeY2K variant={action.statut === 'PRIORISEE' ? 'warning' : 'info'}>{action.statut.toLowerCase()}</BadgeY2K>
                      </div>
                      <div className="mt-3 flex items-center gap-2">
                        <BoutonY2K size="sm" variant="secondary" onClick={() => void changerAction(action, 'PRIORISEE')} disabled={actionLoading === action.id || action.statut === 'PRIORISEE'}>
                          Prioriser
                        </BoutonY2K>
                        <BoutonY2K size="sm" variant="ghost" onClick={() => void changerAction(action, 'IGNORE')} disabled={actionLoading === action.id}>
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
                        {source.dernier_statut === 'NON_CONFIGURE' ? 'à configurer' : source.actif ? 'active' : 'inactive'}
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
                  onClick={importerFranceTravail}
                  disabled={actionLoading === 'IMPORT_FRANCE_TRAVAIL'}
                  iconeGauche={<DatabaseZap className="h-4 w-4" />}
                >
                  Importer France Travail
                </BoutonY2K>
                <p className="text-xs text-muted-foreground">
                  {franceTravail?.configuration_requise && !franceTravail.actif
                    ? 'Le bouton vérifiera l’habilitation et indiquera les secrets manquants sans créer de faux résultat.'
                    : 'Offres actives rapprochées par SIRET, profession et département.'}
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
