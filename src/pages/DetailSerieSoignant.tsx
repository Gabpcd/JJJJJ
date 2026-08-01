import React, { useState, useEffect } from 'react';
import { useParams, useNavigate } from 'react-router-dom';
import { ArrowLeft, CheckCircle2, XCircle } from 'lucide-react';
import { LayoutApp } from '@/components/LayoutApp';
import { ChargementPage } from '@/components/ChargementPage';
import { BadgeStatut } from '@/components/BadgeStatut';
import { BadgeDistance } from '@/components/BadgeDistance';
import { ModalCodeTravail } from '@/components/ModalCodeTravail';
import { AnimationSuccesMission } from '@/components/AnimationSuccesMission';
import { ARTICLES_CODE_TRAVAIL } from '@/constantes/loi';
import { useAuth } from '@/contexts/AuthContext';
import { supabase } from '@/integrations/supabase/client';
import { enrichirEtablissements } from '@/lib/etablissements';
import { calculerDistanceKm } from '@/lib/geo';
import { getLabelProfession } from '@/lib/constantes';
import { estBlocageCodeTravail } from '@/lib/erreurs';
import { chargerCreneauxMissionsPagines } from '@/lib/mission-creneaux-pagines';
import { PlanningMissionCandidat } from '@/components/planning/PlanningMissionCandidat';
import {
  associerCreneauxAuxMissions,
  construirePlanningCandidat,
  construirePlanningConformite,
  creneauxConfirmesPourAction,
  trouverChevauchementPlannings,
  trouverReposInsuffisant,
} from '@/components/planning/planning-candidat';
import {
  DialogResponsive,
  DialogResponsiveBody,
  DialogResponsiveContent,
  DialogResponsiveDescription,
  DialogResponsiveFooter,
  DialogResponsiveHeader,
  DialogResponsiveTitle,
} from '@/components/ui/DialogResponsive';
import { BoutonY2K } from '@/components/y2k/BoutonY2K';
import { formatParis } from '@/lib/date-heure-paris';
import {
  additionnerHeuresSalarieesParSemaine,
  heuresMissionParSemaine,
  missionComptePourPlafond48h,
} from '@/lib/heures-hebdomadaires-mission';
import { analyserSelectionSerie } from '@/components/planning/selection-serie-candidat';
import { toast } from 'sonner';
import { montantFinanceAfficheMission } from '@/lib/missionFinanceDisplay';

function fmt(v: number | null): string {
  if (v == null || v === 0) return '—';
  return new Intl.NumberFormat('fr-FR', { style: 'currency', currency: 'EUR' }).format(v);
}

interface Conflit {
  missionId: string;
  date: string;
  type: 'CHEVAUCHEMENT' | 'REPOS_11H' | 'PLAFOND_48H';
  detail: string;
  article?: string;
}

export default function DetailSerieSoignant() {
  const { serieId } = useParams<{ serieId: string }>();
  const navigate = useNavigate();
  const { user } = useAuth();
  const [missions, setMissions] = useState<any[]>([]);
  const [soignant, setSoignant] = useState<any>(null);
  const [missionsExistantes, setMissionsExistantes] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [selectedIds, setSelectedIds] = useState<Set<string>>(new Set());
  const [conflits, setConflits] = useState<Conflit[]>([]);
  const [detailsOuverts, setDetailsOuverts] = useState<Record<string, boolean>>({});
  const [erreurPlanning, setErreurPlanning] = useState(false);

  // Modals
  const [modalConfirm, setModalConfirm] = useState(false);
  const [acceptationEnCours, setAcceptationEnCours] = useState(false);
  const [modalCodeTravail, setModalCodeTravail] = useState<any>(null);
  const [animationSucces, setAnimationSucces] = useState(false);
  const [resultatsAcceptation, setResultatsAcceptation] = useState<{ reussies: number; echouees: number } | null>(null);

  useEffect(() => {
    if (!user || !serieId) return;
    const load = async () => {
      const decoded = decodeURIComponent(serieId);
      const [missionsResult, soignantResult, existantesResult] = await Promise.all([
        supabase.from('missions').select(`
          id, intitule, description, service, profession_requise,
          debut_le, fin_le, duree_heures, nb_creneaux, taux_horaire_base, total_brut, net_a_payer, net_estime,
          est_urgente, niveau_urgence, statut, soignant_assigne_id, cree_le, etablissement_id,
          type_contrat_applique, choix_contrat_soignant, type_contrat_recherche
        `).ilike('description', `%[SERIE_ID:${decoded}]%`).order('debut_le', { ascending: true }),
        supabase.from('soignants').select('profession, adresse_lat, adresse_lng, rayon_deplacement_km, tous_documents_valides').eq('id', user.id).maybeSingle(),
        supabase.from('missions').select('id, intitule, debut_le, fin_le, duree_heures, nb_creneaux, statut, type_contrat_applique, choix_contrat_soignant, type_contrat_recherche')
          .eq('soignant_assigne_id', user.id).in('statut', ['ASSIGNEE', 'EN_COURS', 'TERMINEE']).order('debut_le'),
      ]);
      const allMissions = missionsResult.data;
      const s = soignantResult.data;
      const existantes = existantesResult.data;

      const ids = [...(allMissions ?? []), ...(existantes ?? [])].map((mission: any) => mission.id);
      let creneaux: any[] = [];
      let planningEnErreur = Boolean(missionsResult.error || existantesResult.error);
      try {
        creneaux = await chargerCreneauxMissionsPagines(ids, {
          exclurePauses: true,
        });
      } catch {
        planningEnErreur = true;
      }

      const enriched = allMissions ? await enrichirEtablissements(allMissions as any) : [];
      const mWithDist = enriched.map((m: any) => ({
        ...m,
        distance_km: calculerDistanceKm(s?.adresse_lat, s?.adresse_lng, m.etablissements?.adresse_lat, m.etablissements?.adresse_lng),
      }));
      const missionsPlanifiees = associerCreneauxAuxMissions(mWithDist, creneaux, planningEnErreur);
      setMissions(missionsPlanifiees);
      setSoignant(s);
      setMissionsExistantes(associerCreneauxAuxMissions((existantes ?? []) as any[], creneaux, planningEnErreur));
      setErreurPlanning(planningEnErreur);

      // Auto-select all open
      const openIds = new Set(missionsPlanifiees.filter((m: any) => m.statut === 'OUVERTE' && m.planning_exact).map((m: any) => m.id));
      setSelectedIds(openIds);

      setLoading(false);
    };
    load();
  }, [user, serieId]);

  // Compute conflicts
  useEffect(() => {
    if (!missions.length || !missionsExistantes) return;
    const ouvertes = missions.filter(m => selectedIds.has(m.id));
    const toutesLesMissions = [...missionsExistantes, ...ouvertes];
    const tousLesCreneaux = [...new Map(
      toutesLesMissions
        .flatMap((mission) => mission.creneaux_planifies ?? [])
        .map((creneau: any) => [creneau.id ?? `${creneau.mission_id}:${creneau.debut}`, creneau]),
    ).values()] as any[];
    const heuresParSemaine = additionnerHeuresSalarieesParSemaine(
      toutesLesMissions,
      tousLesCreneaux,
    );
    const newConflits: Conflit[] = [];

    for (const mission of ouvertes) {
      const planningCible = construirePlanningCandidat(mission);
      if (!planningCible.exact) continue;

      for (const existante of toutesLesMissions) {
        if (existante.id === mission.id) continue;
        const planningExistant = construirePlanningConformite(existante);
        if (!planningExistant.exact) continue;

        const chevauchement = trouverChevauchementPlannings(planningCible, planningExistant);
        if (chevauchement) {
          newConflits.push({
            missionId: mission.id,
            date: chevauchement.cible.debut,
            type: 'CHEVAUCHEMENT',
            detail: `Chevauchement le ${formatParis(chevauchement.cible.debut, 'd MMM')}`,
          });
        }
        const repos = trouverReposInsuffisant(planningCible, planningExistant);
        if (repos) {
          newConflits.push({
            missionId: mission.id,
            date: mission.debut_le,
            type: 'REPOS_11H',
            detail: `Repos insuffisant autour du ${formatParis(mission.debut_le, 'd MMM')} (${repos.heures.toFixed(1)}h < 11h)`,
            article: 'L3131-1',
          });
        }
      }

      // 48 h : somme des créneaux exacts, répartie sur les vraies semaines civiles.
      const semaineDepassee = missionComptePourPlafond48h(mission)
        ? heuresMissionParSemaine(mission, tousLesCreneaux)
        .map((semaine) => ({
          ...semaine,
          total: heuresParSemaine.get(semaine.cleSemaine)?.heures ?? 0,
        }))
        .find((semaine) => semaine.total > 48)
        : undefined;
      if (semaineDepassee) {
        const alreadyAdded = newConflits.find(c => c.missionId === mission.id && c.type === 'PLAFOND_48H');
        if (!alreadyAdded) {
          newConflits.push({
            missionId: mission.id,
            date: mission.debut_le,
            type: 'PLAFOND_48H',
            detail: `Plafond 48h dépassé semaine du ${formatParis(semaineDepassee.debutSemaine, 'd MMM')} (${semaineDepassee.total.toFixed(0)}h)`,
            article: 'L3121-20',
          });
        }
      }
    }

    // Deduplicate
    const unique = newConflits.filter((c, i, arr) =>
      arr.findIndex(x => x.missionId === c.missionId && x.type === c.type) === i
    );
    setConflits(unique);
  }, [missions, missionsExistantes, selectedIds]);

  if (loading || !soignant) return <LayoutApp role="SOIGNANT"><ChargementPage /></LayoutApp>;

  const ouvertes = missions.filter(m => m.statut === 'OUVERTE');
  const first = missions[0];
  const last = missions[missions.length - 1];
  const distance = first?.distance_km;
  const montantsSelection = missions.filter(m => selectedIds.has(m.id)).reduce((totaux, mission) => {
    const finance = montantFinanceAfficheMission(mission);
    if (finance) totaux[finance.nature] += finance.montant;
    return totaux;
  }, { HONORAIRES_LIBERAUX: 0, NET_SALARIE_ESTIME: 0, BRUT_INDICATIF: 0 });
  const resumeMontantsSelection = [
    montantsSelection.HONORAIRES_LIBERAUX > 0 ? `${fmt(montantsSelection.HONORAIRES_LIBERAUX)} honoraires` : null,
    montantsSelection.NET_SALARIE_ESTIME > 0 ? `~${fmt(montantsSelection.NET_SALARIE_ESTIME)} net salarié*` : null,
    montantsSelection.BRUT_INDICATIF > 0 ? `~${fmt(montantsSelection.BRUT_INDICATIF)} brut indicatif` : null,
  ].filter(Boolean);
  const conflitMissionIds = new Set(conflits.map(c => c.missionId));
  const planningEngagementsDisponibles = !erreurPlanning
    && missionsExistantes.every((mission) => construirePlanningConformite(mission).exact);
  const planningTousDisponibles = !erreurPlanning
    && planningEngagementsDisponibles
    && ouvertes.every(m => construirePlanningCandidat(m).exact);
  const analyseSelection = analyserSelectionSerie(ouvertes, selectedIds, conflitMissionIds);
  const toutCompatible = conflits.length === 0;

  const toggleSelect = (id: string) => {
    setSelectedIds(prev => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id); else next.add(id);
      return next;
    });
  };

  const accepterSerie = async () => {
    if (!analyseSelection.peutAccepter || !planningEngagementsDisponibles) {
      toast.error('Corrige la sélection : aucune mission en conflit ou au planning incomplet ne sera omise automatiquement.');
      return;
    }
    const toAccept = analyseSelection.missionsSelectionnees;

    setAcceptationEnCours(true);
    setModalConfirm(false);
    let reussies = 0;
    let echouees = 0;
    const acceptees: any[] = [];

    for (const mission of toAccept) {
      const creneauxConfirmes = creneauxConfirmesPourAction(mission);
      if (!creneauxConfirmes) {
        echouees++;
        continue;
      }
      const { data, error } = await supabase.rpc('fn_confirmer_action_planning_v1' as any, {
        p_mission_id: mission.id,
        p_action: 'ACCEPTER',
        p_creneaux_confirmes: creneauxConfirmes as any,
        p_message: null,
        p_choix_contrat: null,
        p_candidature_id: null,
      });

      if (error) {
        echouees++;
        if (estBlocageCodeTravail(error)) {
          setModalCodeTravail(error);
          break;
        }
      } else if (data?.choix_requis) {
        // Series don't support contract choice dialog — direct user to mission detail
        toast.error('Choix de contrat requis', {
          description: `La mission "${mission.intitule}" accepte salarié ou libéral : ouvre son détail pour choisir ton mode de contrat avant d'accepter.`,
          duration: 8000,
        });
        echouees++;
      } else if (data?.error) {
        echouees++;
      } else {
        reussies++;
        acceptees.push(mission);
      }
    }

    // Audit HDS — un log par mission acceptée
    for (const mission of acceptees) {
      await supabase.rpc('fn_ecrire_audit_safe', {
        p_acteur_id: user!.id, p_type_acteur: 'SOIGNANT', p_action: 'MISSION_ASSIGNATION',
        p_type_ressource: 'mission', p_id_ressource: mission.id, p_cle_s3: null,
        p_details: { type: 'acceptation_serie', serie_id: serieId, intitule: mission.intitule },
        p_ip: null, p_navigateur: navigator.userAgent,
      });
    }

    setAcceptationEnCours(false);
    setResultatsAcceptation({ reussies, echouees });

    if (reussies > 0 && echouees === 0) {
      setAnimationSucces(true);
      // Redirect to contracts list after animation
      setTimeout(() => navigate('/soignant/contrats'), 2000);
    } else if (reussies > 0) {
      toast.warning(`${reussies} mission(s) acceptée(s), ${echouees} en conflit.`);
      navigate('/soignant/contrats');
    } else {
      toast.error('Aucune mission n\'a pu être acceptée.');
    }
  };

  return (
    <LayoutApp role="SOIGNANT">
      <button onClick={() => navigate(-1)} className="flex items-center gap-1 text-sm text-primary mb-4 hover:underline">
        <ArrowLeft className="h-4 w-4" /> Retour
      </button>

      {/* Header */}
      <div className="card-base mb-4">
        <div className="flex items-center gap-2 mb-2">
          <span className="badge-base bg-primary/10 text-primary text-[10px]">🔁 Pack de missions</span>
        </div>
        <h1 className="text-lg font-bold text-foreground mb-1">{first?.intitule}</h1>
        {first?.etablissements && (
          <>
            <p className="text-xs text-muted-foreground">🏥 {first.etablissements.nom} · {first.etablissements.adresse_ville}</p>
            <BadgeDistance distanceKm={distance} />
          </>
        )}
        <p className="text-xs text-muted-foreground mt-2">
          📅 Du {formatParis(first?.debut_le, 'd MMM')} au {formatParis(last?.debut_le, 'd MMM yyyy')}
        </p>
        <p className="text-xs text-muted-foreground">
          📋 {ouvertes.length} mission{ouvertes.length > 1 ? 's' : ''} disponible{ouvertes.length > 1 ? 's' : ''} sur {missions.length}
        </p>
      </div>

      {/* Conformity bloc */}
      <div className={`rounded-2xl p-4 border mb-4 ${toutCompatible ? 'bg-success/5 border-success/20' : 'bg-destructive/5 border-destructive/20'}`}>
        <h3 className="text-sm font-bold text-foreground mb-3">🔍 Vérification de compatibilité — Pack complet</h3>
        {!planningEngagementsDisponibles ? (
          <div className="space-y-1">
            <p className="text-xs font-semibold text-destructive">
              Le planning exact de tes engagements existants ne peut pas être vérifié.
            </p>
            <p className="text-xs text-muted-foreground">
              L’acceptation du pack est bloquée pour éviter un chevauchement ou un repos insuffisant non détecté.
            </p>
          </div>
        ) : !planningTousDisponibles ? (
          <div className="space-y-1">
            <p className="text-xs font-semibold text-destructive">
              Le planning détaillé ne peut pas être vérifié pour toutes les missions.
            </p>
            <p className="text-xs text-muted-foreground">
              Les missions dont le planning exact est disponible restent sélectionnables ; les autres sont bloquées.
            </p>
          </div>
        ) : toutCompatible ? (
          <div className="space-y-1">
            <p className="text-xs text-success flex items-center gap-1"><CheckCircle2 className="h-3.5 w-3.5" /> Repos 11h respecté entre chaque créneau</p>
            <p className="text-xs text-success flex items-center gap-1"><CheckCircle2 className="h-3.5 w-3.5" /> Plafond 48h respecté chaque semaine</p>
            <p className="text-xs text-success flex items-center gap-1"><CheckCircle2 className="h-3.5 w-3.5" /> Aucun chevauchement avec tes missions existantes</p>
            <p className="text-xs text-success font-medium mt-2">→ Tu peux accepter l'ensemble du pack.</p>
          </div>
        ) : (
          <div className="space-y-2">
            <p className="text-xs text-destructive font-semibold">❌ Conflit détecté sur {conflits.length} mission{conflits.length > 1 ? 's' : ''} :</p>
            {conflits.slice(0, 5).map((c, i) => (
              <div key={i} className="text-xs text-muted-foreground ml-4">
                <p>• {c.detail}</p>
                {c.article && (
                  <button onClick={() => setDetailsOuverts(p => ({ ...p, [c.article!]: !p[c.article!] }))}
                    className="text-primary hover:underline text-[10px]">
                    📖 Art. {c.article} [En savoir plus]
                  </button>
                )}
                {c.article && detailsOuverts[c.article] && ARTICLES_CODE_TRAVAIL[c.article] && (
                  <div className="bg-muted/50 rounded-lg p-2 mt-1 text-[10px] space-y-1">
                    <p className="font-semibold">{ARTICLES_CODE_TRAVAIL[c.article].titre}</p>
                    <p>{ARTICLES_CODE_TRAVAIL[c.article].explicationSimple}</p>
                  </div>
                )}
              </div>
            ))}
            {conflits.length > 5 && <p className="text-[10px] text-muted-foreground ml-4">... et {conflits.length - 5} autre(s)</p>}
            <p className="text-xs text-muted-foreground mt-2">💡 Tu peux accepter les créneaux compatibles individuellement.</p>
          </div>
        )}
      </div>

      {/* Créneaux list */}
      <div className="card-base mb-4">
        <h3 className="text-sm font-bold text-foreground mb-3">📋 Créneaux</h3>
        <div className="space-y-2 max-h-96 overflow-y-auto">
          {missions.map(m => {
            const isOpen = m.statut === 'OUVERTE';
            const hasConflict = conflitMissionIds.has(m.id);
            const planningExact = construirePlanningCandidat(m).exact;
            const isSelected = selectedIds.has(m.id);
            return (
              <div key={m.id}
                className={`flex items-center gap-3 p-2.5 rounded-xl border transition-colors ${
                  !isOpen ? 'bg-muted/30 border-border opacity-60' :
                  hasConflict ? 'bg-destructive/5 border-destructive/20' :
                  isSelected ? 'bg-primary/5 border-primary/20' : 'border-border'
                }`}
              >
                {isOpen && planningExact && (
                  <input
                    type="checkbox"
                    checked={isSelected}
                    onChange={() => toggleSelect(m.id)}
                    className="h-4 w-4 rounded border-border text-primary"
                  />
                )}
                {isOpen && hasConflict && <XCircle className="h-4 w-4 text-destructive shrink-0" />}
                {isOpen && !planningExact && <XCircle className="h-4 w-4 text-destructive shrink-0" />}
                {!isOpen && <span className="text-muted-foreground text-sm">⬜</span>}

                <div className="flex-1 min-w-0">
                  <PlanningMissionCandidat
                    mission={m}
                    compact
                    limite={3}
                    afficherMentionJoursNonTravailles={false}
                  />
                  {!isOpen && (
                    <p className="text-[10px] text-muted-foreground">
                      {m.soignant_assigne_id ? 'Déjà pourvue' : m.statut}
                    </p>
                  )}
                  {hasConflict && <p className="text-[10px] text-destructive">⚠️ Conflit détecté</p>}
                  {isOpen && !planningExact && (
                    <p className="text-[10px] text-destructive">⚠️ Planning détaillé indisponible</p>
                  )}
                </div>

                <div className="shrink-0">
                  {isOpen ? (
                    (() => {
                      const finance = montantFinanceAfficheMission(m);
                      return (
                        <span className="text-xs font-medium text-foreground">
                          {finance ? `${finance.approximatif ? '~' : ''}${fmt(finance.montant)}` : '—'}
                          {finance && <span className="block text-[9px] font-normal text-muted-foreground">{finance.libelleCourt}</span>}
                        </span>
                      );
                    })()
                  ) : (
                    <BadgeStatut statut={m.statut} />
                  )}
                </div>
              </div>
            );
          })}
        </div>
      </div>

      {/* Totaux séparés par régime : honoraires libéraux et net salarié ne se fusionnent pas. */}
      {resumeMontantsSelection.length > 0 && (
        <div className="card-base bg-gradient-to-r from-primary/5 to-info/5 mb-4">
          <p className="text-sm font-bold text-foreground">💰 {resumeMontantsSelection.join(' · ')}</p>
          <p className="text-[10px] text-muted-foreground/60 italic mt-1">
            Simulation à titre indicatif. Seuls les montants calculés par le moteur de paie font foi.
          </p>
        </div>
      )}

      {/* Action buttons */}
      <div className="space-y-3">
        {ouvertes.length > 0 ? (
          <button
            onClick={() => setModalConfirm(true)}
            disabled={acceptationEnCours || !planningEngagementsDisponibles || !analyseSelection.peutAccepter}
            className="btn-primary w-full text-base py-3.5 disabled:opacity-50"
          >
            {acceptationEnCours
              ? 'Acceptation en cours…'
              : analyseSelection.idsEnConflit.length > 0
                ? 'Décoche les missions en conflit pour continuer'
                : `★ Accepter la sélection (${analyseSelection.missionsSelectionnees.length})`}
          </button>
        ) : null}

        <button onClick={() => navigate(`/soignant/planning?serie=${serieId}`)} className="text-xs text-primary font-medium hover:underline block text-center">
          📅 Voir dans mon planning
        </button>
      </div>

      {/* Modals */}
      <DialogResponsive open={modalConfirm} onOpenChange={(open) => { if (!acceptationEnCours) setModalConfirm(open); }}>
        <DialogResponsiveContent maxWidth="lg">
          <DialogResponsiveHeader>
            <DialogResponsiveTitle>Vérifie tous tes engagements</DialogResponsiveTitle>
            <DialogResponsiveDescription>
              Confirme uniquement si tu peux assurer chacun des créneaux exacts sélectionnés.
            </DialogResponsiveDescription>
          </DialogResponsiveHeader>
          <DialogResponsiveBody>
            <div className="max-h-[60vh] space-y-4 overflow-y-auto">
              {analyseSelection.missionsSelectionnees.map(mission => (
                <section key={mission.id} className="rounded-xl border border-border p-3">
                  <h4 className="mb-2 text-sm font-semibold text-foreground">{mission.intitule}</h4>
                  <PlanningMissionCandidat mission={mission} compact />
                </section>
              ))}
            </div>
          </DialogResponsiveBody>
          <DialogResponsiveFooter>
            <BoutonY2K variant="ghost" onClick={() => setModalConfirm(false)} disabled={acceptationEnCours}>Annuler</BoutonY2K>
            <BoutonY2K
              variant="primary"
              onClick={() => void accepterSerie()}
              loading={acceptationEnCours}
              disabled={acceptationEnCours || !planningEngagementsDisponibles || !analyseSelection.peutAccepter}
            >
              Accepter tous ces créneaux
            </BoutonY2K>
          </DialogResponsiveFooter>
        </DialogResponsiveContent>
      </DialogResponsive>

      {modalCodeTravail && <ModalCodeTravail erreur={modalCodeTravail} onFermer={() => setModalCodeTravail(null)} />}

      {animationSucces && (
        <AnimationSuccesMission
          mission={{ ...first, _message: `${resultatsAcceptation?.reussies || selectedIds.size} mission${(resultatsAcceptation?.reussies || selectedIds.size) > 1 ? 's' : ''} acceptée${(resultatsAcceptation?.reussies || selectedIds.size) > 1 ? 's' : ''} !` }}
          onTermine={() => { setAnimationSucces(false); navigate('/soignant/missions'); }}
        />
      )}
    </LayoutApp>
  );
}
