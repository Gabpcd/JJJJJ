import { useState, useEffect, type ReactNode } from 'react';
import { useParams, useNavigate } from 'react-router-dom';
import { differenceInMinutes } from 'date-fns';
import { ArrowLeft, Clock, MapPin, Radio, AlertTriangle, CheckCircle, XCircle } from 'lucide-react';
import { LayoutApp } from '@/components/LayoutApp';
import { LayoutAdmin } from '@/components/LayoutAdmin';
import { ChargementPage } from '@/components/ChargementPage';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/contexts/AuthContext';
import { BoutonY2K } from '@/components/y2k/BoutonY2K';
import { AffichageCodeRotatifEtab } from '@/components/pointage/AffichageCodeRotatifEtab';
import { toast } from 'sonner';
import { usePageTitle } from '@/hooks/usePageTitle';
import {
  ajouterRepliMissionPonctuelle,
  creneauChevauchePeriode,
  type CreneauPointage,
} from '@/lib/disponibilite-pointage';
import {
  construireSynthesePresenceMission,
  formatDureeMinutes,
} from '@/lib/synthese-presence-mission';
import {
  ajouterJoursCivilsParis,
  cleJourParis,
  debutJourParis,
  formatParis,
  memeJourParis,
} from '@/lib/date-heure-paris';

function fmt(v: number) {
  return new Intl.NumberFormat('fr-FR', { style: 'currency', currency: 'EUR' }).format(v);
}

function toNumberOrNull(value: unknown): number | null {
  if (value === null || value === undefined || value === '') return null;
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : null;
}

function formatHours(value: number): string {
  return value.toLocaleString('fr-FR', { minimumFractionDigits: 0, maximumFractionDigits: 2 });
}

interface CreneauAssocie {
  creneau: CreneauPointage;
  index: number;
  total: number;
}

function trouverCreneauDuJour(
  creneaux: CreneauPointage[],
  datePresence: Date | null,
): CreneauAssocie | null {
  if (!datePresence) return null;

  const debutJour = debutJourParis(datePresence);
  const finJour = ajouterJoursCivilsParis(debutJour, 1);
  const creneau = creneaux
    .filter((item) => creneauChevauchePeriode(item, debutJour, finJour))
    .sort((a, b) => (
      Math.abs(new Date(a.debut).getTime() - datePresence.getTime())
      - Math.abs(new Date(b.debut).getTime() - datePresence.getTime())
    ))[0];

  if (!creneau) return null;
  return { creneau, index: creneaux.indexOf(creneau), total: creneaux.length };
}

function formatPlageExacte(debut: Date, fin: Date): string {
  const debutFormate = formatParis(debut, 'EEE d MMM yyyy · HH:mm');
  const finFormatee = memeJourParis(debut, fin)
    ? formatParis(fin, 'HH:mm')
    : formatParis(fin, 'EEE d MMM yyyy · HH:mm');
  return `${debutFormate} → ${finFormatee}`;
}

function formatPeriodePlanning(creneaux: CreneauPointage[]): string | null {
  const premier = creneaux[0];
  const dernier = creneaux.at(-1);
  if (!premier?.fin || !dernier?.fin) return null;

  const debut = new Date(premier.debut);
  const fin = new Date(dernier.fin);
  if (creneaux.length === 1 || memeJourParis(debut, fin)) return formatPlageExacte(debut, fin);

  return `${creneaux.length} dates planifiées · ${formatParis(debut, 'd MMM yyyy')} → ${formatParis(fin, 'd MMM yyyy')}`;
}

interface Props {
  role?: 'ADMIN_ETABLISSEMENT' | 'SOIGNANT' | 'ADMIN_PLATEFORME';
}

function DetailPresencesLayout({ role, children }: Required<Pick<Props, 'role'>> & { children: ReactNode }) {
  if (role === 'ADMIN_PLATEFORME') return <LayoutAdmin>{children}</LayoutAdmin>;
  return <LayoutApp role={role}>{children}</LayoutApp>;
}

export default function DetailPresencesMission({ role = 'ADMIN_ETABLISSEMENT' }: Props) {
  const { id: missionId } = useParams<{ id: string }>();
  const navigate = useNavigate();
  const { user } = useAuth();
  const [loading, setLoading] = useState(true);
  const [mission, setMission] = useState<any>(null);
  const [presences, setPresences] = useState<any[]>([]);
  const [creneaux, setCreneaux] = useState<CreneauPointage[]>([]);
  const [planningIndisponible, setPlanningIndisponible] = useState(false);
  const [soignant, setSoignant] = useState<any>(null);
  const [simulationPaieActive, setSimulationPaieActive] = useState<any>(null);
  const [relancing, setRelancing] = useState(false);
  usePageTitle(mission?.intitule ? `Présences · ${mission.intitule}` : 'Détail des présences');

  const relancerEtablissement = async () => {
    if (!missionId) return;
    setRelancing(true);
    const { data, error } = await supabase.rpc('fn_relancer_validation_presence' as any, { p_mission_id: missionId });
    setRelancing(false);
    if (error) { toast.error(error.message); return; }
    const r = data as any;
    if (r?.success) toast.success(r.message ?? 'Établissement relancé.');
    else toast.error(r?.message ?? r?.error ?? 'Relance impossible.');
  };

  useEffect(() => {
    if (!missionId || !user) return;
    const load = async () => {
      const [{ data: missionData }, { data: presData }, detailRes, creneauxRes, simulationPaieRes] = await Promise.all([
        supabase
          .from('missions')
          .select('id, intitule, service, debut_le, fin_le, duree_heures, statut, taux_horaire_base, taux_rist_plafonne, rist_plafond_applique, heures_nuit, heures_dimanche, heures_ferie, montant_majoration_nuit, montant_majoration_dimanche, montant_majoration_ferie, montant_ifm, montant_icp, total_brut, net_estime, soignant_assigne_id, code_arrivee, code_depart, type_paiement_soignant, type_contrat_applique, type_contrat_recherche, mode_remuneration, etablissement_id')
          .eq('id', missionId)
          .single(),
        supabase
          .from('presences')
          .select('*')
          .eq('mission_id', missionId)
          .order('pointage_arrivee_le', { ascending: true }),
        supabase.rpc('fn_presences_detail_mission' as any, { p_mission_id: missionId }),
        supabase
          .from('mission_creneaux')
          .select('id, mission_id, debut, fin, est_pause, type_creneau')
          .eq('mission_id', missionId)
          .eq('est_pause', false)
          .order('debut', { ascending: true }),
        supabase
          .from('bulletins_paie')
          .select('id, numero_bulletin, salaire_brut, net_avant_impot, ifm, icp, statut, modifie_le')
          .eq('mission_id', missionId)
          .neq('statut', 'ANNULE')
          .order('modifie_le', { ascending: false })
          .limit(1)
          .maybeSingle(),
      ]);

      // Store detail data for enhanced display
      const detailData = detailRes.data as any;

      if (missionData) {
        setMission({ ...missionData, _detail: detailData });
        setPlanningIndisponible(Boolean(creneauxRes.error));
        setCreneaux(creneauxRes.error
          ? []
          : ajouterRepliMissionPonctuelle((creneauxRes.data || []) as CreneauPointage[], missionData));
        if (missionData.soignant_assigne_id) {
          const { data: sg } = await supabase
            .from('soignants')
            .select('id, prenom, nom, profession, numero_rpps')
            .eq('id', missionData.soignant_assigne_id)
            .single();
          setSoignant(sg);
        }
      }

      setPresences(presData || []);
      setSimulationPaieActive(simulationPaieRes.error ? null : simulationPaieRes.data);
      setLoading(false);
    };
    load();
  }, [missionId, user, role]);

  if (loading) return <DetailPresencesLayout role={role}><ChargementPage /></DetailPresencesLayout>;
  if (!mission) return (
    <DetailPresencesLayout role={role}>
      <div className="py-12 text-center">
        <h1 className="text-lg font-semibold text-foreground">Mission introuvable</h1>
        <p className="mt-2 text-sm text-muted-foreground">Cette mission n’existe pas ou n’est plus accessible.</p>
      </div>
    </DetailPresencesLayout>
  );

  const brutMission = Number(mission.total_brut || 0);
  const brutSimulation = toNumberOrNull(simulationPaieActive?.salaire_brut);
  const ifmSimulation = toNumberOrNull(simulationPaieActive?.ifm) ?? 0;
  const icpSimulation = toNumberOrNull(simulationPaieActive?.icp) ?? 0;
  const brutAvantIfmIcpSimulation = brutSimulation === null
    ? null
    : Math.max(0, brutSimulation - ifmSimulation - icpSimulation);
  const brut = brutSimulation ?? brutMission;
  const cotis = brut * 0.22;
  const net = toNumberOrNull(simulationPaieActive?.net_avant_impot)
    ?? mission.net_estime
    ?? brut - cotis;
  const maintenant = new Date();
  const synthese = construireSynthesePresenceMission(creneaux, maintenant);
  const planifies = synthese.previsionnels;
  const dernierCreneauFin = synthese.dernierPrevisionnelFin;
  const planningEchu = !planningIndisponible && synthese.planningTermine;
  const missionTerminee = mission.statut === 'TERMINEE';
  const clotureAvantFinPlanning = missionTerminee && !planningEchu && planifies.length > 0;
  const creneauxEchus = planifies.filter((creneau) => (
    Boolean(creneau.fin) && new Date(creneau.fin!).getTime() <= maintenant.getTime()
  )).length;
  const prochainCreneau = planifies.find((creneau) => (
    Boolean(creneau.fin) && new Date(creneau.fin!).getTime() > maintenant.getTime()
  )) ?? null;
  const heuresPlanifieesCreneaux = synthese.minutesPlanifiees / 60;
  const heuresTravaillees = synthese.minutesTravaillees / 60;
  const presenceReference = presences[0] ?? null;
  const heuresAjusteesLitige = toNumberOrNull(presenceReference?.heures_ajustees_litige);
  const estRetrocession = mission.mode_remuneration === 'RETROCESSION';
  const estMissionLiberale = !estRetrocession && (
    mission.type_contrat_applique === 'LIBERAL'
    || (!mission.type_contrat_applique && mission.type_contrat_recherche === 'LIBERAL')
  );
  const heuresRetenues = heuresAjusteesLitige ?? heuresTravaillees;
  const tauxHoraireDemande = Number(mission.taux_horaire_base || 0);
  const tauxHoraireRist = toNumberOrNull(mission.taux_rist_plafonne);
  const tauxHoraireMission = mission.rist_plafond_applique && tauxHoraireRist !== null
    ? tauxHoraireRist
    : tauxHoraireDemande;
  const tauxHoraireSimulation = heuresAjusteesLitige !== null
    && heuresRetenues > 0
    && brutAvantIfmIcpSimulation !== null
      ? brutAvantIfmIcpSimulation / heuresRetenues
      : null;
  const tauxHoraireRetenu = tauxHoraireSimulation !== null
    ? tauxHoraireSimulation
    : tauxHoraireMission;
  const baseHoraireSelonReleve = heuresRetenues * tauxHoraireRetenu;
  const baseBruteRetenue = brutAvantIfmIcpSimulation ?? brutMission;
  const brutAvecComplements = brutSimulation
    ?? brutMission + Number(mission.montant_ifm || 0) + Number(mission.montant_icp || 0);
  const ifmAffichee = brutSimulation === null ? Number(mission.montant_ifm || 0) : ifmSimulation;
  const icpAffichee = brutSimulation === null ? Number(mission.montant_icp || 0) : icpSimulation;
  // 9.1 — la relance ne devient possible qu'au même moment que la validation :
  // après le dernier PREVISIONNEL et sans aucun EFFECTIF encore ouvert.
  const presenceEnAttente = Boolean(
    presenceReference
    && !presenceReference.valide_par_etablissement
    && !planningIndisponible
    && synthese.validationPossible,
  );

  // Le détail de temps est construit depuis les segments EFFECTIF. La ligne
  // `presences` reste uniquement le support de validation et des métadonnées.
  const effectifs = [...synthese.effectifsFermes, ...synthese.effectifsOuverts]
    .sort((a, b) => new Date(a.debut).getTime() - new Date(b.debut).getTime());
  const effectifsByDay: Record<string, CreneauPointage[]> = {};
  for (const effectif of effectifs) {
    const dateKey = cleJourParis(effectif.debut);
    (effectifsByDay[dateKey] ||= []).push(effectif);
  }

  const sortedDays = Object.keys(effectifsByDay).sort();
  const minutesInterruptionCalculees = sortedDays.reduce((total, day) => {
    const segmentsFermes = effectifsByDay[day].filter((segment) => Boolean(segment.fin));
    return total + segmentsFermes.slice(1).reduce((totalJour, segment, index) => {
      const finPrecedente = new Date(segmentsFermes[index].fin!);
      return totalJour + Math.max(differenceInMinutes(new Date(segment.debut), finPrecedente), 0);
    }, 0);
  }, 0);

  return (
    <DetailPresencesLayout role={role}>
      <BoutonY2K
        variant="ghost"
        size="sm"
        className="app-inline-back mb-4"
        onClick={() => {
          if (window.history.length > 2) navigate(-1);
          else if (role === 'ADMIN_PLATEFORME') navigate('/admin/missions');
          else if (role === 'SOIGNANT') navigate('/soignant/presences');
          else navigate('/etablissement/presences');
        }}
        iconeGauche={<ArrowLeft className="h-4 w-4" />}
      >
        Retour
      </BoutonY2K>

      {/* Mission header */}
      <div className="card-base mb-6">
        <h1 className="text-lg font-bold text-foreground">{mission.intitule}</h1>
        {mission.service && <p className="text-sm text-muted-foreground">{mission.service}</p>}
        <div className="flex flex-wrap gap-x-6 gap-y-1 mt-2 text-sm text-muted-foreground">
          <span>
            📅 {planifies.length > 0 && formatPeriodePlanning(planifies)
              ? formatPeriodePlanning(planifies)
              : `${formatParis(mission.debut_le, 'dd/MM/yyyy HH:mm')} → ${formatParis(mission.fin_le, 'dd/MM/yyyy HH:mm')}`}
          </span>
          <span>
            ⏱ {planifies.length > 0
              ? `${formatHours(heuresPlanifieesCreneaux)}h sur ${planifies.length} créneau${planifies.length > 1 ? 'x' : ''}`
              : `${mission.duree_heures}h prévues`}
          </span>
          <span>
            💰 {fmt(tauxHoraireRetenu)}/h
            {mission.rist_plafond_applique && tauxHoraireRetenu !== tauxHoraireDemande
              ? ` retenus (taux demandé : ${fmt(tauxHoraireDemande)}/h)`
              : ''}
          </span>
        </div>
        {planifies.length > 0 ? (
          <p className="mt-2 text-xs text-muted-foreground">
            {clotureAvantFinPlanning
              ? `Mission clôturée · ${creneauxEchus}/${planifies.length} ${planifies.length > 1 ? 'créneaux initialement prévus étaient échus' : 'créneau initialement prévu était échu'}`
              : <>
                Progression : {creneauxEchus}/{planifies.length} {planifies.length > 1 ? 'créneaux échus' : 'créneau échu'}
                {prochainCreneau?.fin
                  ? ` · prochain : ${formatPlageExacte(new Date(prochainCreneau.debut), new Date(prochainCreneau.fin))}`
                  : ' · planning terminé'}
              </>}
          </p>
        ) : (
          <p className="mt-2 text-xs text-muted-foreground">
            {planningIndisponible ? 'Planning détaillé indisponible.' : 'Planning détaillé à confirmer.'}
          </p>
        )}
        {soignant && role !== 'SOIGNANT' && (
          <p className="text-sm font-medium text-foreground mt-2">
            👤 {soignant.prenom} {soignant.nom} · {soignant.profession}
            {soignant.numero_rpps && <span className="text-muted-foreground"> · RPPS {soignant.numero_rpps}</span>}
          </p>
        )}
      </div>

      {/* Synthèse présences via fn_presences_detail_mission */}
      {mission._detail && (() => {
        const d = mission._detail;
        // La valeur RPC/legacy `heures_reelles` n'est volontairement pas
        // utilisée : elle peut couvrir toute la période entre première arrivée
        // et dernier départ. Les EFFECTIF fermés sont la seule source canonique.
        const heuresReelles = heuresTravaillees;
        const heuresPlanifiees = planifies.length > 0
          ? heuresPlanifieesCreneaux
          : toNumberOrNull(mission.duree_heures) ?? 0;
        const comparaisons = planifies.flatMap((creneau) => {
          if (!creneau.fin) return [];
          const segmentsAssocies = synthese.effectifsFermes
            .filter((effectif) => trouverCreneauDuJour(planifies, new Date(effectif.debut))?.creneau === creneau)
            .sort((a, b) => new Date(a.debut).getTime() - new Date(b.debut).getTime());
          if (segmentsAssocies.length === 0) return [];

          const arrivee = new Date(segmentsAssocies[0].debut);
          const depart = new Date(segmentsAssocies.at(-1)!.fin!);
          const debutPrevu = new Date(creneau.debut);
          const finPrevue = new Date(creneau.fin);
          return [{
            retard: Math.max(differenceInMinutes(arrivee, debutPrevu), 0),
            departAnticipe: finPrevue.getTime() <= maintenant.getTime()
              ? Math.max(differenceInMinutes(finPrevue, depart), 0)
              : 0,
          }];
        });
        const retardMinutes = comparaisons.reduce((total, item) => total + item.retard, 0);
        const departAnticipeMinutes = comparaisons.reduce((total, item) => total + item.departAnticipe, 0);
        const dureePauseRpc = toNumberOrNull(d.duree_pause_minutes ?? d.duree_pause_min);
        const dureePauseMinutes = minutesInterruptionCalculees > 0
          ? minutesInterruptionCalculees
          : dureePauseRpc;
        const distanceGps = toNumberOrNull(d.distance_gps_m ?? d.distance_m);
        const methodePointage = d.methode_pointage ?? d.methode_arrivee ?? d.methode_depart ?? null;
        const bilanFinalisable = (planningEchu || missionTerminee) && synthese.effectifsOuverts.length === 0;
        const deficit = bilanFinalisable
          && !clotureAvantFinPlanning
          && heuresReelles < heuresPlanifiees * 0.9;
        const bilanEnAttente = !bilanFinalisable;
        const alerteTelep = d.alerte_teleportation === true;

        return (
          <div className={`card-base mb-6 ${alerteTelep || deficit ? 'border-destructive/40 bg-destructive/5' : ''}`}>
            <h2 className="font-semibold text-foreground mb-3 flex items-center gap-2">
              <Clock className="h-5 w-5 text-primary" /> Synthèse des présences
            </h2>
            <div className="grid grid-cols-2 sm:grid-cols-3 gap-3 text-sm">
              <div>
                <p className="text-xs text-muted-foreground">Heures planifiées</p>
                <p className="font-semibold text-foreground">{formatHours(heuresPlanifiees)}h</p>
              </div>
              <div>
                <p className="text-xs text-muted-foreground">Heures réelles</p>
                <p className={`font-semibold ${deficit ? 'text-destructive' : 'text-foreground'}`}>
                  {formatHours(heuresReelles)}h
                </p>
              </div>
              {heuresAjusteesLitige !== null && (
                <div>
                  <p className="text-xs text-muted-foreground">Heures retenues après litige</p>
                  <p className="font-semibold text-primary">{formatHours(heuresAjusteesLitige)}h</p>
                </div>
              )}
              {retardMinutes !== null && retardMinutes > 0 && (
                <div>
                  <p className="text-xs text-muted-foreground">Retard</p>
                  <p className="font-semibold text-warning">+{Math.round(retardMinutes)} min</p>
                </div>
              )}
              {departAnticipeMinutes !== null && departAnticipeMinutes > 0 && (
                <div>
                  <p className="text-xs text-muted-foreground">Départ anticipé</p>
                  <p className="font-semibold text-warning">-{Math.round(departAnticipeMinutes)} min</p>
                </div>
              )}
              {dureePauseMinutes !== null && dureePauseMinutes > 0 && (
                <div>
                  <p className="text-xs text-muted-foreground">Pauses / interruptions</p>
                  <p className="font-semibold text-muted-foreground">{Math.round(dureePauseMinutes)} min</p>
                </div>
              )}
              {distanceGps !== null && (
                <div>
                  <p className="text-xs text-muted-foreground">Distance GPS</p>
                  <p className={`font-semibold ${distanceGps > 500 ? 'text-destructive' : 'text-foreground'}`}>
                    {Math.round(distanceGps)}m
                  </p>
                </div>
              )}
              {methodePointage && (
                <div>
                  <p className="text-xs text-muted-foreground">Méthode</p>
                  <p className="font-semibold text-foreground">{methodePointage}</p>
                </div>
              )}
            </div>

            {bilanEnAttente && (
              <p className="mt-3 border-t border-border pt-3 text-xs text-muted-foreground">
                {synthese.effectifsOuverts.length > 0
                  ? 'Bilan définitif après la fermeture du pointage en cours.'
                  : dernierCreneauFin
                    ? `Bilan définitif après le dernier créneau, le ${formatParis(dernierCreneauFin, 'dd/MM/yyyy à HH:mm')}. Aucun déficit n’est signalé avant cette échéance.`
                    : 'Bilan définitif indisponible tant que le planning détaillé n’est pas confirmé.'}
              </p>
            )}

            {clotureAvantFinPlanning && synthese.effectifsOuverts.length === 0 && (
              <p className="mt-3 border-t border-border pt-3 text-xs text-muted-foreground">
                Mission clôturée avant la fin du planning initial. Les créneaux futurs ne sont plus à effectuer ; les heures retenues après arbitrage déterminent la régularisation financière.
              </p>
            )}

            {(alerteTelep || deficit) && (
              <div className="mt-3 pt-3 border-t border-destructive/20 flex items-center gap-2 text-sm text-destructive font-medium">
                <AlertTriangle className="h-4 w-4" />
                {alerteTelep && <span>🚨 Alerte téléportation détectée</span>}
                {deficit && <span>⚠️ Heures réelles inférieures à 90% du planifié</span>}
              </div>
            )}
          </div>
        );
      })()}

      {role === 'ADMIN_PLATEFORME' && (
        <section className="card-base mb-6 border-primary/30 bg-primary/5" aria-label="Intervention admin sur les présences">
          <h2 className="font-semibold text-foreground">Contrôle admin des heures et paiements</h2>
          <p className="mt-1 text-sm text-muted-foreground">
            {heuresAjusteesLitige !== null
              ? `${formatHours(heuresAjusteesLitige)} h sont retenues après arbitrage, pour ${formatHours(heuresTravaillees)} h enregistrées par le pointage.`
              : 'Aucun ajustement admin n’est appliqué. Les segments de pointage ci-dessous restent la source des heures réelles.'}
          </p>
          {planningEchu && Math.abs(heuresTravaillees - heuresPlanifieesCreneaux) >= 0.01 && (
            <p className="mt-2 rounded-lg border border-warning/30 bg-warning/10 px-3 py-2 text-sm font-medium text-warning-foreground">
              Écart à traiter : {formatHours(heuresPlanifieesCreneaux)} h planifiées contre {formatHours(heuresTravaillees)} h pointées.
            </p>
          )}
          <BoutonY2K
            className="mt-3"
            size="sm"
            variant="secondary"
            onClick={() => navigate(`/admin/missions/${encodeURIComponent(missionId!)}`)}
          >
            Intervenir sur les heures ou le paiement
          </BoutonY2K>
          <p className="mt-2 text-xs text-muted-foreground">
            L’intervention ouvre un dossier audité ; toute correction financière reste confirmée séparément.
          </p>
        </section>
      )}

      {/* Code de pointage rotatif (système ②) — l'ancien affichage statique est retiré. */}
      {role === 'ADMIN_ETABLISSEMENT' ? (
        <div className="mb-6">
          <AffichageCodeRotatifEtab missionId={missionId} />
        </div>
      ) : null}

      {/* Détail des créneaux EFFECTIF par jour */}
      <h2 className="text-base font-bold text-foreground mb-3 flex items-center gap-2">
        <Clock className="h-5 w-5 text-primary" /> Détail des créneaux travaillés ({effectifs.length} segment{effectifs.length > 1 ? 's' : ''})
      </h2>

      {effectifs.length === 0 ? (
        <div className="card-base text-center py-8">
          <Clock className="h-8 w-8 text-muted-foreground/40 mx-auto mb-2" />
          <p className="text-sm text-muted-foreground">Aucun créneau de travail effectif enregistré pour cette mission.</p>
        </div>
      ) : (
        <div className="space-y-4 mb-6">
          {sortedDays.map(day => (
            <div key={day} className="card-base">
              <h3 className="font-semibold text-foreground text-sm mb-3 border-b border-border pb-2">
                📅 {day !== 'sans-date' ? formatParis(`${day}T12:00:00+02:00`, 'EEEE d MMMM yyyy') : 'Date inconnue'}
              </h3>
              <div className="space-y-3">
                {effectifsByDay[day].map((effectif, idx) => {
                  const arrivee = new Date(effectif.debut);
                  const depart = effectif.fin ? new Date(effectif.fin) : null;
                  const dureeMin = depart ? differenceInMinutes(depart, arrivee) : null;
                  const precedent = idx > 0 ? effectifsByDay[day][idx - 1] : null;
                  const finPrecedente = precedent?.fin ? new Date(precedent.fin) : null;
                  const interruptionMinutes = finPrecedente
                    ? Math.max(differenceInMinutes(arrivee, finPrecedente), 0)
                    : 0;
                  const associe = trouverCreneauDuJour(planifies, arrivee);
                  const segmentsAssocies = associe
                    ? effectifsByDay[day].filter((segment) => (
                      trouverCreneauDuJour(planifies, new Date(segment.debut))?.index === associe.index
                    ))
                    : [];
                  const indexAssocie = segmentsAssocies.indexOf(effectif);
                  const premierSegmentAssocie = indexAssocie <= 0;
                  const dernierSegmentAssocie = indexAssocie === segmentsAssocies.length - 1;
                  const debutPrevu = associe ? new Date(associe.creneau.debut) : null;
                  const finPrevue = associe?.creneau.fin ? new Date(associe.creneau.fin) : null;
                  const retard = debutPrevu && premierSegmentAssocie
                    ? Math.max(differenceInMinutes(arrivee, debutPrevu), 0)
                    : 0;
                  const finPrevueEchue = finPrevue !== null && finPrevue.getTime() <= maintenant.getTime();
                  const departAnticipe = depart && finPrevue && finPrevueEchue && dernierSegmentAssocie
                    ? Math.max(differenceInMinutes(finPrevue, depart), 0)
                    : 0;
                  const comparaisonEnAttente = !missionTerminee
                    && depart !== null
                    && finPrevue !== null
                    && dernierSegmentAssocie
                    && depart.getTime() < finPrevue.getTime()
                    && !finPrevueEchue;

                  return (
                    <div key={effectif.id ?? `${effectif.debut}-${idx}`} className={`rounded-xl border p-3 space-y-2 ${
                      presenceReference?.alerte_teleportation ? 'border-destructive/40 bg-destructive/5' :
                      presenceReference?.perimetre_gps_valide === false && presenceReference?.distance_etablissement_m !== null ? 'border-warning/40 bg-warning/5' :
                      presenceReference?.valide_par_etablissement ? 'border-success/30 bg-success/5' :
                      'border-border'
                    }`}>
                      {effectifsByDay[day].length > 1 ? (
                        <p className="text-[10px] font-semibold text-muted-foreground uppercase tracking-wide">
                          Segment travaillé {idx + 1} / {effectifsByDay[day].length}
                          {idx > 0 && ' · reprise après interruption'}
                          {associe && ` · créneau planifié ${associe.index + 1}/${associe.total}`}
                        </p>
                      ) : associe ? (
                        <p className="text-[10px] font-semibold text-muted-foreground uppercase tracking-wide">
                          Créneau planifié {associe.index + 1} / {associe.total}
                        </p>
                      ) : null}

                      {interruptionMinutes > 0 && (
                        <div className="rounded-lg border border-border/70 bg-muted/30 px-3 py-2 text-xs text-muted-foreground">
                          Pause / interruption depuis le segment précédent :{' '}
                          <span className="font-medium text-foreground">{formatDureeMinutes(interruptionMinutes)}</span>
                        </div>
                      )}

                      {debutPrevu && finPrevue ? (
                        <div className="rounded-lg bg-muted/40 px-3 py-2 text-xs">
                          <p className="text-muted-foreground">Horaire prévu</p>
                          <p className="font-medium text-foreground">{formatPlageExacte(debutPrevu, finPrevue)}</p>
                          <div className="mt-1 flex flex-wrap gap-x-3 gap-y-1">
                            {retard > 0 && <span className="text-warning">Retard : +{retard} min</span>}
                            {departAnticipe > 0 && <span className="text-warning">Départ anticipé : -{departAnticipe} min</span>}
                            {comparaisonEnAttente && (
                              <span className="text-muted-foreground">
                                Bilan après l’échéance de {formatParis(finPrevue, 'HH:mm')}
                              </span>
                            )}
                          </div>
                        </div>
                      ) : (
                        <p className="text-xs text-muted-foreground">
                          {planningIndisponible
                            ? 'Planning détaillé indisponible.'
                            : planifies.length > 0
                              ? 'Aucun créneau planifié ne correspond à ce jour.'
                              : 'Planning détaillé à confirmer.'}
                        </p>
                      )}

                      {/* Arrivée */}
                      <div className="flex items-center justify-between">
                        <div className="flex items-center gap-2">
                          <span className="text-success text-xs font-medium">▶ Arrivée</span>
                          <span className="text-sm font-semibold text-foreground">
                            {formatParis(arrivee, 'dd/MM/yyyy HH:mm:ss')}
                          </span>
                        </div>
                      </div>

                      {/* Départ */}
                      {depart ? (
                        <div className="flex items-center justify-between">
                          <div className="flex items-center gap-2">
                            <span className="text-destructive text-xs font-medium">■ Départ</span>
                            <span className="text-sm font-semibold text-foreground">
                              {formatParis(depart, 'dd/MM/yyyy HH:mm:ss')}
                            </span>
                          </div>
                        </div>
                      ) : (
                        <p className="text-xs text-warning italic">⏳ En cours — départ non pointé</p>
                      )}

                      {/* Duration */}
                      {dureeMin !== null && (
                        <p className="text-xs text-muted-foreground">
                          Durée : <span className="font-medium text-foreground">{Math.floor(dureeMin / 60)}h{String(dureeMin % 60).padStart(2, '0')}</span>
                        </p>
                      )}

                      {/* Validation status */}
                      <div className="text-[11px] pt-1 border-t border-border/50">
                        {presenceReference?.valide_par_etablissement ? (
                          <span className="text-success font-medium">
                            ✅ Validé{presenceReference.valide_le ? ` le ${formatParis(presenceReference.valide_le, 'dd/MM/yyyy HH:mm')}` : ''}
                          </span>
                        ) : missionTerminee ? (
                          <span className="text-success font-medium">
                            {heuresAjusteesLitige !== null ? '✅ Relevé clôturé après arbitrage' : '✅ Relevé clôturé'}
                          </span>
                        ) : synthese.validationPossible ? (
                          <span className="text-warning">⏳ En attente de validation</span>
                        ) : synthese.effectifsOuverts.length > 0 ? (
                          <span className="text-warning">Pointage en cours</span>
                        ) : (
                          <span className="text-muted-foreground">Mission en cours</span>
                        )}
                      </div>
                    </div>
                  );
                })}
              </div>
            </div>
          ))}
        </div>
      )}

      {/* Métadonnées legacy conservées comme contrôles anti-fraude, jamais
          comme source de durée. Elles décrivent la première arrivée et le
          dernier départ globaux de la mission. */}
      {presenceReference && (
        <div className="card-base mb-6">
          <h2 className="font-semibold text-foreground mb-3">Contrôles du pointage</h2>
          <div className="flex flex-wrap gap-3 text-xs text-muted-foreground">
            {presenceReference.distance_etablissement_m !== null && (
              <span className={`flex items-center gap-1 ${presenceReference.perimetre_gps_valide ? 'text-success' : 'text-warning'}`}>
                <MapPin className="h-3.5 w-3.5" />
                Première arrivée : {Math.round(presenceReference.distance_etablissement_m)}m
                {presenceReference.perimetre_gps_valide ? <CheckCircle className="h-3 w-3" /> : <XCircle className="h-3 w-3" />}
              </span>
            )}
            {presenceReference.arrivee_precision_gps_m && (
              <span className="flex items-center gap-1">
                <Radio className="h-3.5 w-3.5" />
                Précision première arrivée : {Math.round(presenceReference.arrivee_precision_gps_m)}m
              </span>
            )}
            {presenceReference.depart_precision_gps_m && (
              <span className="flex items-center gap-1">
                <Radio className="h-3.5 w-3.5" />
                Précision dernier départ : {Math.round(presenceReference.depart_precision_gps_m)}m
              </span>
            )}
          </div>
          {presenceReference.alerte_teleportation && (
            <div className="mt-3 flex items-center gap-1 text-xs text-destructive font-medium">
              <AlertTriangle className="h-3.5 w-3.5" />
              Alerte téléportation détectée
            </div>
          )}
        </div>
      )}

      {/* 9.1 — Relancer l'établissement (soignant, présence en attente de validation) */}
      {role === 'SOIGNANT' && presenceEnAttente && (
        <div className="card-base border-warning/30 bg-warning/5">
          <p className="text-sm text-foreground font-medium mb-1">⏳ Tes présences attendent la validation de l'établissement</p>
          <p className="text-xs text-muted-foreground mb-3">Le paiement se débloque à la validation (automatique sous 72h). Tu peux envoyer un rappel.</p>
          <BoutonY2K variant="secondary" size="sm" onClick={relancerEtablissement} disabled={relancing}>
            {relancing ? 'Envoi…' : 'Relancer l\'établissement'}
          </BoutonY2K>
        </div>
      )}

      {/* Récapitulatif financier */}
      <div className="card-base">
        <h2 className="font-semibold text-foreground mb-3">💶 Récapitulatif financier</h2>
        {estRetrocession ? (
          <div className="rounded-xl border border-primary/20 bg-primary/5 p-3 text-sm">
            <p className="font-semibold text-foreground">Rémunération par rétrocession d’honoraires</p>
            <p className="mt-1 text-xs text-muted-foreground">
              Le pointage contrôle les heures de présence, mais le montant dépend du relevé d’actes et de la rétrocession confirmée. Consultez le détail financier de la mission.
            </p>
          </div>
        ) : (
        <>
        <div className="grid grid-cols-2 sm:grid-cols-5 gap-3 text-sm">
          <div>
            <p className="text-xs text-muted-foreground">{estMissionLiberale ? 'Taux d’honoraires' : 'Taux horaire brut retenu'}</p>
            <p className="font-semibold text-foreground">{fmt(tauxHoraireRetenu)}</p>
            {tauxHoraireRetenu !== tauxHoraireDemande && (
              <p className="text-[10px] text-muted-foreground">Demandé : {fmt(tauxHoraireDemande)}</p>
            )}
          </div>
          <div>
            <p className="text-xs text-muted-foreground">Heures planifiées</p>
            <p className="font-semibold text-foreground">{formatDureeMinutes(synthese.minutesPlanifiees)}</p>
          </div>
          <div>
            <p className="text-xs text-muted-foreground">Heures travaillées fermées</p>
            <p className="font-semibold text-foreground">{formatDureeMinutes(synthese.minutesTravaillees)}</p>
          </div>
          {heuresAjusteesLitige !== null && (
            <div>
              <p className="text-xs text-muted-foreground">Heures retenues après litige</p>
              <p className="font-semibold text-primary">{formatDureeMinutes(heuresAjusteesLitige * 60)}</p>
            </div>
          )}
          <div>
            <p className="text-xs text-muted-foreground">{estMissionLiberale ? 'Honoraires selon heures retenues' : brutAvantIfmIcpSimulation !== null ? 'Brut retenu avant IFM/ICP' : 'Base brute retenue'}</p>
            <p className="font-semibold text-foreground">{fmt(estMissionLiberale ? baseHoraireSelonReleve : baseBruteRetenue)}</p>
          </div>
          <div>
            <p className="text-xs text-muted-foreground">{estMissionLiberale ? 'Total honoraires mission' : 'Brut simulé avec compléments'}</p>
            <p className="font-bold text-foreground">{fmt(estMissionLiberale ? brut : brutAvecComplements)}</p>
          </div>
        </div>

        {(brutSimulation !== null || (mission.montant_majoration_nuit || 0) > 0 || (mission.montant_majoration_dimanche || 0) > 0 || (mission.montant_majoration_ferie || 0) > 0 || ifmAffichee > 0 || icpAffichee > 0) && (
          <div className="mt-3 pt-3 border-t border-border">
            <p className="text-xs font-medium text-muted-foreground mb-2">Détail des compléments</p>
            <div className="grid grid-cols-2 sm:grid-cols-5 gap-2 text-xs">
              {brutSimulation === null && (mission.montant_majoration_nuit || 0) > 0 && (
                <div><p className="text-muted-foreground">Maj. nuit</p><p className="font-medium text-foreground">{fmt(mission.montant_majoration_nuit)}</p></div>
              )}
              {brutSimulation === null && (mission.montant_majoration_dimanche || 0) > 0 && (
                <div><p className="text-muted-foreground">Maj. dimanche</p><p className="font-medium text-foreground">{fmt(mission.montant_majoration_dimanche)}</p></div>
              )}
              {brutSimulation === null && (mission.montant_majoration_ferie || 0) > 0 && (
                <div><p className="text-muted-foreground">Maj. férié</p><p className="font-medium text-foreground">{fmt(mission.montant_majoration_ferie)}</p></div>
              )}
              {ifmAffichee > 0 && (
                <div><p className="text-muted-foreground">IFM</p><p className="font-medium text-foreground">{fmt(ifmAffichee)}</p></div>
              )}
              {icpAffichee > 0 && (
                <div><p className="text-muted-foreground">ICP</p><p className="font-medium text-foreground">{fmt(icpAffichee)}</p></div>
              )}
            </div>
            {brutSimulation !== null && (
              <p className="mt-2 text-[10px] text-muted-foreground">
                Source : simulation active {simulationPaieActive.numero_bulletin || 'la plus récente'}. Les anciens calculs annulés ne sont pas affichés ici.
              </p>
            )}
          </div>
        )}

        {!estMissionLiberale && (
          <div className="mt-3 pt-3 border-t border-border flex justify-between items-center">
            <span className="text-sm text-muted-foreground">Net salarié estimé avant PAS</span>
            <span className="text-lg font-bold text-success">{fmt(net)}</span>
          </div>
        )}
        <p className="text-[10px] text-muted-foreground italic mt-1">
          {estMissionLiberale
            ? '⚠️ La base selon heures retenues exclut les éventuelles majorations. Seuls les documents d’honoraires officiels corrigés font foi.'
            : '⚠️ Le total de mission n’est pas le montant à payer lorsque les heures pointées ou retenues diffèrent. Seul le bulletin de paie officiel corrigé fait foi.'}
        </p>
        {role === 'SOIGNANT' && !estMissionLiberale && missionTerminee && (
          <BoutonY2K
            className="mt-3 w-full"
            size="sm"
            variant="secondary"
            onClick={() => navigate(`/soignant/mes-gains?tab=bulletins&mission=${encodeURIComponent(missionId!)}`)}
          >
            Voir la simulation de paie détaillée
          </BoutonY2K>
        )}
        </>
        )}
      </div>
    </DetailPresencesLayout>
  );
}
