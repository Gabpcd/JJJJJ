import React, { useState, useEffect, useMemo } from 'react';
import { LayoutAdmin } from '@/components/LayoutAdmin';
import { BreadcrumbAdmin } from '@/components/BreadcrumbAdmin';
import { ChargementAdmin } from '@/components/admin/ChargementAdmin';
import { supabase } from '@/integrations/supabase/client';
import { usePageTitle } from '@/hooks/usePageTitle';
import { AlertTriangle, ChevronLeft, ChevronRight } from 'lucide-react';
import { useNavigate } from 'react-router-dom';
import { BADGES_STATUT } from '@/lib/constantes';
import { extraireMessageErreur } from '@/lib/erreurs';
import { analyserCompletudePlanningMission } from '@/lib/completude-planning-mission';
import { chargerCreneauxMissionsPagines } from '@/lib/mission-creneaux-pagines';
import {
  ajouterJoursCivilsParis,
  ajouterMoisCivilsParis,
  cleJourParis,
  debutJourParis,
  debutMoisParis,
  debutSemaineParis,
  finMoisParis,
  formatParis,
  memeJourParis,
  memeMoisParis,
} from '@/lib/date-heure-paris';

const JOURS_SEMAINE = ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'];

type MissionCal = {
  id: string;
  intitule: string;
  debut_le: string;
  fin_le: string;
  statut: string;
  soignant_assigne_id: string | null;
  etablissement_id: string;
  profession_requise: string;
  service: string | null;
  est_urgente: boolean;
  nb_creneaux?: number | null;
  etab_nom?: string;
  soignant_nom?: string;
  creneaux: CreneauCal[];
};

type CreneauCal = {
  mission_id: string;
  debut: string;
  fin: string;
};

function getStatutStyle(m: MissionCal): { bg: string; text: string; label: string } {
  if (m.statut === 'OUVERTE' && !m.soignant_assigne_id) {
    return { bg: 'bg-destructive', text: 'text-destructive-foreground', label: 'Non pourvue' };
  }
  switch (m.statut) {
    case 'OUVERTE': return { bg: 'bg-warning', text: 'text-warning-foreground', label: 'Ouverte' };
    case 'ASSIGNEE': return { bg: 'bg-info', text: 'text-info-foreground', label: 'Assignée' };
    case 'EN_COURS': return { bg: 'bg-success', text: 'text-success-foreground', label: 'Active' };
    case 'TERMINEE': return { bg: 'bg-muted-foreground/40', text: 'text-foreground', label: 'Terminée' };
    case 'ANNULEE_PAR_ETABLISSEMENT':
    case 'ANNULEE_PAR_SOIGNANT': return { bg: 'bg-destructive/60', text: 'text-destructive-foreground', label: 'Annulée' };
    default: return { bg: 'bg-muted', text: 'text-muted-foreground', label: BADGES_STATUT[m.statut]?.label || 'Autre' };
  }
}

function getHorairePourJour(m: MissionCal, d: Date): string {
  const creneaux = m.creneaux.filter(creneau => creneauChevaucheJour(creneau, d));
  if (creneaux.length === 0) return 'Horaire non renseigné';

  const debutJour = `${cleJourParis(d)}T00:00:00`;
  const debutLendemain = `${cleJourParis(ajouterJoursCivilsParis(d, 1))}T00:00:00`;
  return creneaux
    .map(creneau => {
      const debutCreneau = formatParis(creneau.debut, "yyyy-MM-dd'T'HH:mm:ss");
      const finCreneau = formatParis(creneau.fin, "yyyy-MM-dd'T'HH:mm:ss");
      const heureDebut = debutCreneau < debutJour ? '00:00' : formatParis(creneau.debut, 'HH:mm');
      const heureFin = finCreneau > debutLendemain ? '00:00' : formatParis(creneau.fin, 'HH:mm');
      return `${heureDebut}–${heureFin}`;
    })
    .join(' · ');
}

function creneauChevaucheJour(creneau: CreneauCal, d: Date): boolean {
  const jourDebut = `${cleJourParis(debutJourParis(d))}T00:00:00`;
  const lendemain = `${cleJourParis(ajouterJoursCivilsParis(d, 1))}T00:00:00`;
  const debutCreneau = formatParis(creneau.debut, "yyyy-MM-dd'T'HH:mm:ss");
  const finCreneau = formatParis(creneau.fin, "yyyy-MM-dd'T'HH:mm:ss");
  return debutCreneau < lendemain && finCreneau > jourDebut;
}

export default function AdminCalendrier() {
  usePageTitle('Calendrier missions');
  const navigate = useNavigate();
  const [moisCourant, setMoisCourant] = useState(() => debutMoisParis(new Date()));
  const [missions, setMissions] = useState<MissionCal[]>([]);
  const [loading, setLoading] = useState(true);
  const [erreurChargement, setErreurChargement] = useState<string | null>(null);
  const [tentativeChargement, setTentativeChargement] = useState(0);
  const [filtreStatut, setFiltreStatut] = useState<string | null>(null);

  const { debutGrille, finGrille, finGrilleExclusive } = useMemo(() => {
    const debut = debutSemaineParis(debutMoisParis(moisCourant));
    const finExclusive = ajouterJoursCivilsParis(debutSemaineParis(finMoisParis(moisCourant)), 7);
    return {
      debutGrille: debut,
      finGrille: new Date(finExclusive.getTime() - 1),
      finGrilleExclusive: finExclusive,
    };
  }, [moisCourant]);

  const jours: Date[] = [];
  let jour = debutGrille;
  while (jour < finGrilleExclusive) {
    jours.push(jour);
    jour = ajouterJoursCivilsParis(jour, 1);
  }

  useEffect(() => {
    let actif = true;
    setLoading(true);
    setErreurChargement(null);
    void Promise.resolve(supabase
      .from('missions')
      .select('id, intitule, debut_le, fin_le, statut, soignant_assigne_id, etablissement_id, profession_requise, service, est_urgente, nb_creneaux')
      .gte('fin_le', debutGrille.toISOString())
      .lte('debut_le', finGrille.toISOString())
      .order('debut_le')
      .then(async ({ data, error }) => {
        if (error) throw error;
        const items = (data || []).map(mission => ({
          ...(mission as Omit<MissionCal, 'creneaux'>),
          creneaux: [],
        }));
        if (items.length > 0) {
          const etabIds = [...new Set(items.map(m => m.etablissement_id))];
          const soignantIds = [...new Set(items.map(m => m.soignant_assigne_id).filter(Boolean))] as string[];
          const missionIds = items.map(m => m.id);

          const [resEtabs, resSoignants, creneauxCharges] = await Promise.all([
            etabIds.length ? supabase.from('etablissements').select('id, nom').in('id', etabIds) : Promise.resolve({ data: [] } as any),
            soignantIds.length ? supabase.from('soignants').select('id, prenom, nom').in('id', soignantIds) : Promise.resolve({ data: [] } as any),
            chargerCreneauxMissionsPagines(missionIds, {
              typeCreneau: 'PREVISIONNEL',
              exclurePauses: true,
            }),
          ]);

          const erreurDependance = (resEtabs as any).error
            || (resSoignants as any).error;
          if (erreurDependance) throw erreurDependance;

          const etabMap = new Map<string, string>((resEtabs.data || []).map((e: any) => [e.id, e.nom]));
          const soignantMap = new Map<string, string>((resSoignants.data || []).map((s: any) => [s.id, `${s.prenom || ''} ${s.nom || ''}`.trim()]));
          const creneauxMap = new Map<string, CreneauCal[]>();
          creneauxCharges.forEach((creneau) => {
            if (!creneau.fin) return;
            const creneauxMission = creneauxMap.get(creneau.mission_id) || [];
            creneauxMission.push({
              mission_id: creneau.mission_id,
              debut: creneau.debut,
              fin: creneau.fin,
            });
            creneauxMap.set(creneau.mission_id, creneauxMission);
          });

          items.forEach(m => {
            m.etab_nom = etabMap.get(m.etablissement_id) || '';
            m.soignant_nom = m.soignant_assigne_id ? soignantMap.get(m.soignant_assigne_id) || '' : '';
            const creneauxMission = creneauxMap.get(m.id) || [];
            const analyse = analyserCompletudePlanningMission(m, creneauxMission.map(creneau => ({
              ...creneau,
              est_pause: false,
              type_creneau: 'PREVISIONNEL',
            })));
            if (!analyse.complet) {
              throw new Error(
                `Le planning détaillé de la mission « ${m.intitule} » est incomplet ou ne correspond pas au nombre de créneaux attendu.`,
              );
            }
            m.creneaux = analyse.creneauxPlanifies.map(creneau => ({
              mission_id: m.id,
              debut: creneau.debut,
              fin: creneau.fin!,
            }));
          });
        }
        if (actif) setMissions(items);
      }))
      .catch((error) => {
        if (!actif) return;
        setMissions([]);
        setErreurChargement(extraireMessageErreur(error));
      })
      .finally(() => { if (actif) setLoading(false); });
    return () => { actif = false; };
  }, [debutGrille, finGrille, tentativeChargement]);

  function getMissionsDuJour(d: Date) {
    return missions.filter(m => {
      const dansJour = m.creneaux.some(creneau => creneauChevaucheJour(creneau, d));
      if (!dansJour) return false;
      if (!filtreStatut) return true;
      if (filtreStatut === 'NON_POURVUE') return m.statut === 'OUVERTE' && !m.soignant_assigne_id;
      return m.statut === filtreStatut;
    });
  }

  // Stats
  const nonPourvues = missions.filter(m => m.statut === 'OUVERTE' && !m.soignant_assigne_id).length;
  const assignees = missions.filter(m => m.statut === 'ASSIGNEE').length;
  const enCours = missions.filter(m => m.statut === 'EN_COURS').length;
  const terminees = missions.filter(m => m.statut === 'TERMINEE').length;

  const filtresRapides: Array<{
    valeur: string | null;
    libelle: string;
    classeActive: string;
  }> = [
    {
      valeur: 'NON_POURVUE',
      libelle: `${nonPourvues} non pourvue${nonPourvues > 1 ? 's' : ''}`,
      classeActive: 'border-destructive/50 bg-destructive/10 text-destructive',
    },
    {
      valeur: 'ASSIGNEE',
      libelle: `${assignees} assignée${assignees > 1 ? 's' : ''}`,
      classeActive: 'border-info/50 bg-info/10 text-info',
    },
    {
      valeur: 'EN_COURS',
      libelle: `${enCours} active${enCours > 1 ? 's' : ''}`,
      classeActive: 'border-success/50 bg-success/10 text-success',
    },
    {
      valeur: 'TERMINEE',
      libelle: `${terminees} terminée${terminees > 1 ? 's' : ''}`,
      classeActive: 'border-muted-foreground/40 bg-muted text-foreground',
    },
    {
      valeur: null,
      libelle: `${missions.length} total`,
      classeActive: 'border-primary/50 bg-primary/10 text-primary',
    },
  ];

  const joursAgenda = jours
    .filter(d => memeMoisParis(d, moisCourant))
    .map(d => ({ date: d, missions: getMissionsDuJour(d) }))
    .filter(groupe => groupe.missions.length > 0);

  const LEGENDE = [
    { label: 'Non pourvue', cls: 'bg-destructive' },
    { label: 'Ouverte', cls: 'bg-warning' },
    { label: 'Assignée', cls: 'bg-info' },
    { label: 'Active', cls: 'bg-success' },
    { label: 'Terminée', cls: 'bg-muted-foreground/40' },
    { label: 'Annulée', cls: 'bg-destructive/60' },
  ];

  if (loading) return <LayoutAdmin><ChargementAdmin titre="Calendrier des missions" /></LayoutAdmin>;

  if (erreurChargement) {
    return (
      <LayoutAdmin>
        <BreadcrumbAdmin pageName="Calendrier" />
        <div className="mx-auto max-w-xl rounded-2xl border border-destructive/30 bg-card p-5" role="alert">
          <div className="flex items-start gap-3">
            <AlertTriangle className="h-5 w-5 shrink-0 text-destructive" />
            <div>
              <h1 className="font-semibold text-foreground">Impossible de charger le calendrier</h1>
              <p className="mt-1 text-sm text-muted-foreground">{erreurChargement}</p>
              <button
                type="button"
                className="btn-primary mt-4"
                onClick={() => setTentativeChargement((tentative) => tentative + 1)}
              >
                Réessayer
              </button>
            </div>
          </div>
        </div>
      </LayoutAdmin>
    );
  }

  return (
    <LayoutAdmin>
      <BreadcrumbAdmin pageName="Calendrier" />
      <div className="space-y-4">
        <h1 className="text-2xl font-bold text-foreground">Calendrier des missions</h1>

        {/* Stats bar */}
        <fieldset className="flex flex-wrap gap-2">
          <legend className="sr-only">Filtrer les missions par statut</legend>
          {filtresRapides.map(filtre => {
            const actif = filtreStatut === filtre.valeur;
            return (
              <button
                key={filtre.valeur ?? 'TOUTES'}
                type="button"
                aria-pressed={actif}
                onClick={() => setFiltreStatut(courant => (
                  filtre.valeur !== null && courant === filtre.valeur ? null : filtre.valeur
                ))}
                className={`inline-flex min-h-[44px] items-center rounded-full border px-3 py-2 text-sm font-semibold transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary focus-visible:ring-offset-2 ${
                  actif
                    ? filtre.classeActive
                    : 'border-border bg-card text-muted-foreground hover:border-primary/40 hover:text-foreground'
                }`}
              >
                {filtre.libelle}
              </button>
            );
          })}
        </fieldset>

        {/* Navigation */}
        <div className="flex items-center justify-between">
          <button type="button" onClick={() => setMoisCourant(ajouterMoisCivilsParis(moisCourant, -1))} className="inline-flex min-h-[44px] min-w-[44px] items-center justify-center rounded-lg p-2 transition-colors hover:bg-muted" aria-label="Mois précédent">
            <ChevronLeft className="h-5 w-5 text-muted-foreground" />
          </button>
          <div className="text-center">
            <h2 className="text-lg font-bold text-foreground capitalize">
              {formatParis(moisCourant, 'MMMM yyyy')}
            </h2>
            <button type="button" onClick={() => setMoisCourant(debutMoisParis(new Date()))} className="mt-0.5 inline-flex min-h-[44px] items-center px-2 text-sm font-medium text-primary hover:underline">
              Aujourd'hui
            </button>
          </div>
          <button type="button" onClick={() => setMoisCourant(ajouterMoisCivilsParis(moisCourant, 1))} className="inline-flex min-h-[44px] min-w-[44px] items-center justify-center rounded-lg p-2 transition-colors hover:bg-muted" aria-label="Mois suivant">
            <ChevronRight className="h-5 w-5 text-muted-foreground" />
          </button>
        </div>

        {/* Légende */}
        <div className="flex flex-wrap gap-3 justify-center">
          {LEGENDE.map(l => (
            <div key={l.label} className="flex items-center gap-1.5 text-[11px] text-muted-foreground">
              <span className={`w-2.5 h-2.5 rounded-full ${l.cls}`} />
              {l.label}
            </div>
          ))}
        </div>

        {/* Agenda mobile */}
        <div className="space-y-3 lg:hidden" aria-label="Agenda des missions du mois">
          {joursAgenda.length === 0 ? (
            <div className="rounded-xl border border-border bg-card px-4 py-8 text-center">
              <p className="text-sm font-medium text-foreground">Aucune mission à afficher</p>
              <p className="mt-1 text-sm text-muted-foreground">
                Aucune mission ne correspond à ce filtre pour le mois sélectionné.
              </p>
            </div>
          ) : joursAgenda.map(groupe => (
            <section key={groupe.date.toISOString()} className="rounded-2xl border border-border bg-card p-3" aria-labelledby={`agenda-${cleJourParis(groupe.date)}`}>
              <h3 id={`agenda-${cleJourParis(groupe.date)}`} className="mb-2 text-sm font-bold capitalize text-foreground">
                <time dateTime={cleJourParis(groupe.date)} aria-current={memeJourParis(groupe.date, new Date()) ? 'date' : undefined}>
                  {formatParis(groupe.date, 'EEEE d MMMM')}
                </time>
                {memeJourParis(groupe.date, new Date()) && <span className="ml-2 text-primary">Aujourd'hui</span>}
              </h3>
              <div className="space-y-2">
                {groupe.missions.map(m => {
                  const style = getStatutStyle(m);
                  return (
                    <button
                      key={m.id}
                      type="button"
                      onClick={() => navigate(`/admin/missions/${m.id}`)}
                      className="flex min-h-[56px] w-full items-start justify-between gap-3 rounded-xl border border-border px-3 py-2.5 text-left transition-colors hover:border-primary/40 hover:bg-muted/40 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary focus-visible:ring-offset-2"
                    >
                      <span className="min-w-0">
                        <span className="block font-semibold text-foreground">
                          {m.est_urgente ? 'Urgente — ' : ''}{m.intitule}
                        </span>
                        <span className="mt-0.5 block text-sm text-muted-foreground">
                          {getHorairePourJour(m, groupe.date)}
                          {m.etab_nom ? ` · ${m.etab_nom}` : ''}
                        </span>
                        <span className="mt-0.5 block text-sm text-muted-foreground">
                          {m.soignant_nom || 'Aucun soignant assigné'}
                        </span>
                      </span>
                      <span className={`shrink-0 rounded-full px-2.5 py-1 text-xs font-semibold ${style.bg} ${style.text}`}>
                        {style.label}
                      </span>
                    </button>
                  );
                })}
              </div>
            </section>
          ))}
        </div>

        {/* Days header desktop */}
        <div className="hidden grid-cols-7 gap-px lg:grid">
          {JOURS_SEMAINE.map(j => (
            <div key={j} className="text-center text-xs font-semibold text-muted-foreground py-2">
              {j}
            </div>
          ))}
        </div>

        {/* Calendar grid desktop */}
        <div className="hidden grid-cols-7 gap-px lg:grid">
          {jours.map((d, i) => {
            const dansLeMois = memeMoisParis(d, moisCourant);
            const estAujourdhui = memeJourParis(d, new Date());
            const msDuJour = getMissionsDuJour(d);
            const hasNonPourvue = msDuJour.some(m => m.statut === 'OUVERTE' && !m.soignant_assigne_id);

            return (
              <div key={i} className={`min-h-[140px] p-1 rounded-md border transition-colors
                ${dansLeMois ? 'bg-card border-border/50' : 'bg-muted/30 border-transparent'}
                ${estAujourdhui ? 'ring-2 ring-primary/40' : ''}
                ${hasNonPourvue && dansLeMois ? 'border-destructive/50' : ''}
              `}>
                <span className={`text-[11px] font-medium block text-center mb-0.5
                  ${estAujourdhui ? 'text-primary font-bold' : dansLeMois ? 'text-foreground' : 'text-muted-foreground/40'}
                `}>
                  {formatParis(d, 'd')}
                </span>

                <div className="space-y-0.5">
                  {msDuJour.slice(0, 4).map(m => {
                    const style = getStatutStyle(m);
                    return (
                      <button key={m.id}
                        type="button"
                        onClick={() => navigate(`/admin/missions/${m.id}`)}
                        className={`block min-h-[32px] w-full truncate rounded px-1.5 py-1 text-left text-xs leading-tight transition-opacity hover:opacity-80 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary focus-visible:ring-offset-1 ${style.bg} ${style.text}`}
                        title={`${m.intitule} — ${style.label} — ${m.etab_nom || ''}${m.soignant_nom ? ` · ${m.soignant_nom}` : ' · Aucun soignant assigné'}`}
                      >
                        <span className="sr-only">Statut : {style.label}. </span>
                        {m.est_urgente ? 'Urgente — ' : ''}{m.intitule}
                      </button>
                    );
                  })}
                  {msDuJour.length > 4 && (
                    <span className="block text-center text-xs text-muted-foreground">+{msDuJour.length - 4}</span>
                  )}
                </div>
              </div>
            );
          })}
        </div>
      </div>
    </LayoutAdmin>
  );
}
