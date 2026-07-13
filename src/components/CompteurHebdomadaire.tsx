import React, { useState, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import { CalendarDays, ChevronRight } from 'lucide-react';
import { useAuth } from '@/contexts/AuthContext';
import { supabase } from '@/integrations/supabase/client';
import { fetchEtablissementsSafe, type EtablissementSafe } from '@/lib/etablissements';
import { format } from 'date-fns';
import { fr } from 'date-fns/locale';
import {
  additionnerHeuresSalarieesParSemaine,
  cleSemaineCivile,
  debutSemaineCivile,
  heuresMissionParSemaine,
  missionComptePourPlafond48h,
  missionPlafond48hConditionnel,
  semaineSuivante,
  type CreneauMissionPourCalculHebdomadaire,
  type MissionPourCalculHebdomadaire,
} from '@/lib/heures-hebdomadaires-mission';

function getCouleurBarre(heures: number) {
  if (heures >= 44) return 'bg-destructive';
  if (heures >= 36) return 'bg-warning';
  return 'bg-primary';
}

function getMessageHeures(heures: number) {
  const restant = Math.max(0, 48 - heures);
  if (heures >= 48) return { texte: '🛑 Plafond de 48h atteint — vous ne pouvez plus accepter de mission sur cette semaine', classe: 'text-destructive font-bold' };
  if (heures >= 44) return { texte: `🚨 Quasi plein : seulement ${restant.toFixed(0)}h disponibles`, classe: 'text-destructive' };
  if (heures >= 36) return { texte: `⚠️ Attention : il ne vous reste que ${restant.toFixed(0)}h`, classe: 'text-warning' };
  return { texte: `✅ Il vous reste ${restant.toFixed(0)}h de disponibilité sur cette semaine`, classe: 'text-primary' };
}

interface CompteurHebdomadaireProps {
  compact?: boolean;
  missionCandidate?: MissionPourCalculHebdomadaire;
}

interface SemaineAffichee {
  cle: string;
  heuresExistantes: number;
  heuresCandidate: number;
}

interface MissionAffichee extends MissionPourCalculHebdomadaire {
  intitule: string;
  statut: string | null;
  etablissement_id: string;
  etablissements?: EtablissementSafe | null;
}

function libelleSemaine(cle: string, cleActuelle: string): string {
  if (cle === cleActuelle) return 'Cette semaine';
  const date = new Date(`${cle}T12:00:00Z`);
  return `Semaine du ${format(date, 'd MMM', { locale: fr })}`;
}

export function CompteurHebdomadaire({ compact = false, missionCandidate }: CompteurHebdomadaireProps) {
  const navigate = useNavigate();
  const { user } = useAuth();
  const [missions, setMissions] = useState<MissionAffichee[]>([]);
  const [semaines, setSemaines] = useState<SemaineAffichee[]>([]);
  const [loading, setLoading] = useState(true);
  const cleActuelle = cleSemaineCivile(new Date());
  const candidateId = missionCandidate?.id;
  const candidateDebut = missionCandidate?.debut_le;
  const candidateFin = missionCandidate?.fin_le;
  const candidateDuree = missionCandidate?.duree_heures;
  const candidateNbCreneaux = missionCandidate?.nb_creneaux;
  const candidateTypeContratApplique = missionCandidate?.type_contrat_applique;
  const candidateChoixContrat = missionCandidate?.choix_contrat_soignant;
  const candidateTypeContratRecherche = missionCandidate?.type_contrat_recherche;
  const candidateComptePourPlafond = missionCandidate
    ? missionComptePourPlafond48h(missionCandidate)
    : true;
  const candidatePlafondConditionnel = missionCandidate
    ? missionPlafond48hConditionnel(missionCandidate)
    : false;

  useEffect(() => {
    if (!user) return;
    let actif = true;
    const candidate = candidateId && candidateDebut && candidateFin
      ? {
          id: candidateId,
          debut_le: candidateDebut,
          fin_le: candidateFin,
          duree_heures: candidateDuree ?? null,
          nb_creneaux: candidateNbCreneaux,
          type_contrat_applique: candidateTypeContratApplique,
          choix_contrat_soignant: candidateChoixContrat,
          type_contrat_recherche: candidateTypeContratRecherche,
        }
      : undefined;

    const charger = async () => {
      setLoading(true);
      if (candidate && !missionComptePourPlafond48h(candidate)) {
        if (!actif) return;
        setMissions([]);
        setSemaines([]);
        setLoading(false);
        return;
      }
      const debutPeriode = candidate
        ? debutSemaineCivile(new Date(candidate.debut_le))
        : debutSemaineCivile(new Date());
      const finPeriode = candidate
        ? semaineSuivante(debutSemaineCivile(new Date(candidate.fin_le)))
        : semaineSuivante(debutPeriode);

      const { data, error: missionsError } = await supabase
        .from('missions')
        .select('id, intitule, debut_le, fin_le, duree_heures, nb_creneaux, statut, etablissement_id, type_contrat_applique, choix_contrat_soignant, type_contrat_recherche')
        .eq('soignant_assigne_id', user.id)
        .in('statut', ['ASSIGNEE', 'EN_COURS', 'TERMINEE'])
        .lt('debut_le', finPeriode.toISOString())
        .gt('fin_le', debutPeriode.toISOString())
        .order('debut_le', { ascending: true });

      if (missionsError) {
        if (!actif) return;
        setMissions([]);
        setSemaines([]);
        setLoading(false);
        return;
      }

      const items = (data || []) as MissionAffichee[];
      const idsCreneaux = [...new Set([
        ...items.map((m) => m.id),
        ...(candidate ? [candidate.id] : []),
      ])];
      let creneaux: CreneauMissionPourCalculHebdomadaire[] = [];
      if (idsCreneaux.length > 0) {
        const { data: creneauxData, error: creneauxError } = await supabase
          .from('mission_creneaux')
          .select('mission_id, debut, fin, est_pause, type_creneau')
          .in('mission_id', idsCreneaux);
        if (creneauxError) {
          if (!actif) return;
          setMissions(items);
          setSemaines([]);
          setLoading(false);
          return;
        }
        creneaux = (creneauxData || []) as CreneauMissionPourCalculHebdomadaire[];
      }

      if (items.length > 0) {
        const etabMap = await fetchEtablissementsSafe(items.map((m) => m.etablissement_id));
        items.forEach((m) => { m.etablissements = etabMap[m.etablissement_id] || null; });
      }

      const heuresExistantes = additionnerHeuresSalarieesParSemaine(items, creneaux);
      const heuresCandidate = candidate
        ? heuresMissionParSemaine(candidate, creneaux)
        : [];
      const cles = candidate
        ? heuresCandidate.map((semaine) => semaine.cleSemaine)
        : [cleSemaineCivile(new Date())];

      if (!actif) return;
      setMissions(items);
      setSemaines(cles.map((cle) => {
        const candidate = heuresCandidate.find((semaine) => semaine.cleSemaine === cle);
        const existante = heuresExistantes.get(cle);
        return {
          cle,
          heuresExistantes: existante?.heures ?? 0,
          heuresCandidate: candidate?.heures ?? 0,
        };
      }));
      setLoading(false);
    };

    charger();
    return () => { actif = false; };
  }, [
    user,
    candidateId,
    candidateDebut,
    candidateFin,
    candidateDuree,
    candidateNbCreneaux,
    candidateTypeContratApplique,
    candidateChoixContrat,
    candidateTypeContratRecherche,
  ]);

  if (loading) return null;

  const semaineActuelle = semaines.find((semaine) => semaine.cle === cleActuelle);
  const heuresSemaine = semaineActuelle?.heuresExistantes ?? 0;
  const heuresAffichees = heuresSemaine;
  const msg = getMessageHeures(heuresAffichees);

  if (compact) {
    if (missionCandidate && !candidateComptePourPlafond) {
      return (
        <div className="card-base" role="status">
          <p className="text-xs font-semibold text-foreground">📊 Plafond hebdomadaire salarié</p>
          <p className="text-xs text-muted-foreground mt-1.5">
            Cette mission libérale n'entre pas dans le calcul du plafond salarié de 48 h.
          </p>
        </div>
      );
    }
    return (
      <div className="card-base space-y-3">
        <p className="text-xs font-semibold text-foreground">📊 Plafond hebdomadaire</p>
        {semaines.map((semaine) => {
          const total = semaine.heuresExistantes + semaine.heuresCandidate;
          const message = candidatePlafondConditionnel
            ? total > 48
              ? {
                  texte: "⚠️ Dépassement si contrat salarié ; le régime libéral n'est pas concerné.",
                  classe: 'text-warning font-semibold',
                }
              : {
                  texte: "Calcul de l'option salariée ; le régime libéral n'est pas concerné.",
                  classe: 'text-muted-foreground',
                }
            : getMessageHeures(total);
          const largeurExistante = Math.min((semaine.heuresExistantes / 48) * 100, 100);
          const largeurCandidate = Math.max(0, Math.min((semaine.heuresCandidate / 48) * 100, 100 - largeurExistante));
          return (
            <div key={semaine.cle}>
              <div className="flex items-center justify-between mb-2">
                <span className="text-xs font-semibold text-foreground">{libelleSemaine(semaine.cle, cleActuelle)}</span>
                <span className="text-xs font-bold text-foreground">{total.toFixed(0)}h / 48h</span>
              </div>
              <div className="relative h-2.5 rounded-full bg-muted overflow-hidden">
                <div
                  className={`absolute inset-y-0 left-0 rounded-full ${getCouleurBarre(total)} transition-all duration-500`}
                  style={{ width: `${Math.min((total / 48) * 100, 100)}%` }}
                />
                {semaine.heuresCandidate > 0 && (
                  <div
                    className="absolute inset-y-0 rounded-full bg-primary/30 border-r-2 border-dashed border-primary transition-all duration-500"
                    style={{ left: `${largeurExistante}%`, width: `${largeurCandidate}%` }}
                  />
                )}
              </div>
              {semaine.heuresCandidate > 0 && (
                <p className="text-[10px] text-muted-foreground mt-1">
                  Planifiées : {semaine.heuresExistantes.toFixed(0)}h + mission : {semaine.heuresCandidate.toFixed(0)}h
                </p>
              )}
              <p className={`text-xs mt-1.5 ${message.classe}`}>{message.texte}</p>
            </div>
          );
        })}
        {semaines.length === 0 && (
          <p className="text-xs text-muted-foreground">Planning hebdomadaire indisponible.</p>
        )}
      </div>
    );
  }

  return (
    <div className="card-base">
      <div className="flex items-center justify-between mb-3">
        <h3 className="text-sm font-bold text-foreground flex items-center gap-2">
          <CalendarDays className="h-4 w-4 text-primary" />
          Ma semaine ({format(new Date(`${cleActuelle}T12:00:00Z`), "EEE d", { locale: fr })} → {format(new Date(new Date(`${cleActuelle}T12:00:00Z`).getTime() + 6 * 86400000), "EEE d MMM", { locale: fr })})
        </h3>
        <button onClick={() => navigate('/soignant/planning')} className="text-xs text-primary hover:underline flex items-center gap-0.5">
          Planning <ChevronRight className="h-3 w-3" />
        </button>
      </div>

      <div className="flex items-center gap-3 mb-2">
        <div className="flex-1 relative h-3 rounded-full bg-muted overflow-hidden">
          <div
            className={`absolute inset-y-0 left-0 rounded-full ${getCouleurBarre(heuresSemaine)} transition-all duration-700`}
            style={{ width: `${Math.min((heuresSemaine / 48) * 100, 100)}%` }}
          />
        </div>
        <span className="text-sm font-bold text-foreground whitespace-nowrap">{heuresSemaine.toFixed(0)}h / 48h</span>
      </div>

      <p className={`text-xs mb-3 ${msg.classe}`}>{msg.texte}</p>

      {missions.length > 0 && (
        <div className="border-t border-border pt-3 space-y-1.5">
          <p className="text-[10px] font-semibold text-muted-foreground uppercase tracking-wider mb-1">Missions planifiées</p>
          {missions.map(m => (
            <button
              key={m.id}
              onClick={() => navigate(`/soignant/missions/${m.id}`)}
              className="w-full text-left flex items-center gap-2 text-xs text-foreground hover:bg-muted/50 rounded-lg px-2 py-1.5 transition-colors"
            >
              <span className="text-muted-foreground font-medium w-16 shrink-0">
                {format(new Date(m.debut_le), 'EEE d', { locale: fr })}
              </span>
              <span className="truncate flex-1">{m.intitule} ({m.etablissements?.nom})</span>
              <span className="text-muted-foreground shrink-0">
                {format(new Date(m.debut_le), "HH'h'mm", { locale: fr })}→{format(new Date(m.fin_le), "HH'h'mm", { locale: fr })} ({m.duree_heures || 0}h)
              </span>
            </button>
          ))}
        </div>
      )}
    </div>
  );
}
