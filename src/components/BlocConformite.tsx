import React, { useCallback, useState, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import { ChevronDown, ChevronUp, CheckCircle2, XCircle, AlertTriangle } from 'lucide-react';
import { useAuth } from '@/contexts/AuthContext';
import { supabase } from '@/integrations/supabase/client';
import { ARTICLES_CODE_TRAVAIL } from '@/constantes/loi';
import { format } from 'date-fns';
import { fr } from 'date-fns/locale';
import {
  additionnerHeuresSalarieesParSemaine,
  heuresMissionParSemaine,
  missionComptePourPlafond48h,
  missionPlafond48hConditionnel,
  planningMissionHebdomadaireDisponible,
  type CreneauMissionPourCalculHebdomadaire,
  type MissionPourCalculHebdomadaire,
} from '@/lib/heures-hebdomadaires-mission';

interface ControleSemaine48h {
  cle: string;
  label: string;
  heuresActuelles: number;
  heuresMission: number;
  total: number;
}

interface MissionConflictuelle {
  id: string;
  intitule: string;
  debut_le: string;
  fin_le: string;
  duree_heures: number | null;
  nb_creneaux: number;
  statut: string | null;
  etablissement_id: string;
  type_contrat_applique: string | null;
  choix_contrat_soignant: string | null;
  type_contrat_recherche: string | null;
}

interface ResultatConformite {
  repos11h: { ok: boolean; detail: string; missionConflictuelle: MissionConflictuelle | null; suggestion?: string };
  plafond48h: {
    ok: boolean;
    detail: string;
    heuresActuelles: number;
    heuresAvecNouvelle: number;
    semaines: ControleSemaine48h[];
    applicable: boolean;
    conditionnel: boolean;
  };
  chevauchement: { ok: boolean; detail: string; missionConflictuelle: MissionConflictuelle | null };
}

interface BlocConformiteProps {
  missionId: string;
  onResultat?: (toutOk: boolean) => void;
}

function formatHeure(d: string) {
  return format(new Date(d), "HH'h'mm", { locale: fr });
}

function labelSemaine(cle: string) {
  return `Semaine du ${format(new Date(`${cle}T12:00:00Z`), 'dd/MM', { locale: fr })}`;
}

export function BlocConformite({ missionId, onResultat }: BlocConformiteProps) {
  const { user } = useAuth();
  const navigate = useNavigate();
  const [resultats, setResultats] = useState<ResultatConformite | null>(null);
  const [loading, setLoading] = useState(true);
  const [indisponible, setIndisponible] = useState<string | null>(null);
  const [detailsOuverts, setDetailsOuverts] = useState<Record<string, boolean>>({});

  const preverifier = useCallback(async () => {
    setLoading(true);
    setIndisponible(null);
    onResultat?.(false);

    const marquerIndisponible = (message: string) => {
      setResultats(null);
      setIndisponible(message);
      setLoading(false);
      onResultat?.(false);
    };

    try {
      const [missionResponse, missionsResponse] = await Promise.all([
        supabase.from('missions')
          .select('debut_le, fin_le, duree_heures, nb_creneaux, type_contrat_applique, choix_contrat_soignant, type_contrat_recherche')
          .eq('id', missionId)
          .single(),
        supabase.from('missions')
          .select('id, intitule, debut_le, fin_le, duree_heures, nb_creneaux, statut, etablissement_id, type_contrat_applique, choix_contrat_soignant, type_contrat_recherche')
          .eq('soignant_assigne_id', user!.id)
          .in('statut', ['ASSIGNEE', 'EN_COURS', 'TERMINEE'])
          .order('debut_le', { ascending: true }),
      ]);
      const missionCible = missionResponse.data;
      const missionsExistantes = missionsResponse.data;

      if (missionResponse.error || missionsResponse.error || !missionCible || !missionsExistantes) {
        marquerIndisponible('Vérification de conformité indisponible. Réessayez avant de postuler.');
        return;
      }

      const res: ResultatConformite = {
        repos11h: { ok: true, detail: '', missionConflictuelle: null },
        plafond48h: {
          ok: true,
          detail: '',
          heuresActuelles: 0,
          heuresAvecNouvelle: 0,
          semaines: [],
          applicable: true,
          conditionnel: false,
        },
        chevauchement: { ok: true, detail: '', missionConflictuelle: null },
      };

      const debutCible = new Date(missionCible.debut_le).getTime();
      const finCible = new Date(missionCible.fin_le).getTime();

      for (const m of missionsExistantes) {
        const debutM = new Date(m.debut_le).getTime();
        const finM = new Date(m.fin_le).getTime();

        if (debutM < finCible && finM > debutCible) {
          res.chevauchement = {
            ok: false,
            detail: `Chevauchement avec "${m.intitule}" (${formatHeure(m.debut_le)}→${formatHeure(m.fin_le)})`,
            missionConflictuelle: m,
          };
        }

        if (finM <= debutCible) {
          const ecart = (debutCible - finM) / 3600000;
          if (ecart < 11 && ecart >= 0) {
            const heureMin = new Date(finM + 11 * 3600000);
            res.repos11h = {
              ok: false,
              detail: `Seulement ${ecart.toFixed(1)}h de repos après "${m.intitule}" (fin ${formatHeure(m.fin_le)}). Minimum légal : 11h.`,
              missionConflictuelle: m,
              suggestion: `Compatible si début après ${format(heureMin, "HH'h'mm", { locale: fr })}`,
            };
          }
        }

        if (debutM >= finCible) {
          const ecart = (debutM - finCible) / 3600000;
          if (ecart < 11 && ecart >= 0) {
            res.repos11h = {
              ok: false,
              detail: `Seulement ${ecart.toFixed(1)}h de repos avant "${m.intitule}" (début ${formatHeure(m.debut_le)}). Minimum légal : 11h.`,
              missionConflictuelle: m,
            };
          }
        }
      }

      const missionPourCalcul: MissionPourCalculHebdomadaire = {
        id: missionId,
        debut_le: missionCible.debut_le,
        fin_le: missionCible.fin_le,
        duree_heures: missionCible.duree_heures,
        nb_creneaux: missionCible.nb_creneaux,
        type_contrat_applique: missionCible.type_contrat_applique,
        choix_contrat_soignant: missionCible.choix_contrat_soignant,
        type_contrat_recherche: missionCible.type_contrat_recherche,
      };

      if (!missionComptePourPlafond48h(missionPourCalcul)) {
        res.plafond48h.applicable = false;
        res.plafond48h.detail = "Cette mission libérale n'entre pas dans le calcul du plafond salarié de 48 h.";
        setResultats(res);
        setLoading(false);
        onResultat?.(res.repos11h.ok && res.chevauchement.ok);
        return;
      }
      res.plafond48h.conditionnel = missionPlafond48hConditionnel(missionPourCalcul);

      // Plafond 48h : les créneaux salariés sont regroupés par semaine civile
      // réelle. Les missions libérales existantes sont exclues comme en SQL.
      const idsCreneaux = [...new Set([missionId, ...missionsExistantes.map((m) => m.id)])];
      const { data: creneauxData, error: creneauxError } = await supabase
        .from('mission_creneaux')
        .select('mission_id, debut, fin, est_pause, type_creneau')
        .in('mission_id', idsCreneaux);
      const creneaux = (creneauxData || []) as CreneauMissionPourCalculHebdomadaire[];
      const planningsDisponibles = !creneauxError
        && planningMissionHebdomadaireDisponible(missionPourCalcul, creneaux)
        && missionsExistantes
          .filter((mission) => missionComptePourPlafond48h(mission))
          .every((mission) => planningMissionHebdomadaireDisponible(mission, creneaux));
      if (!planningsDisponibles) {
        marquerIndisponible('Impossible de vérifier les créneaux par semaine. Réessayez avant de postuler.');
        return;
      }
      const heuresExistantes = additionnerHeuresSalarieesParSemaine(
        missionsExistantes as MissionPourCalculHebdomadaire[],
        creneaux,
      );
      res.plafond48h.semaines = heuresMissionParSemaine(missionPourCalcul, creneaux).map((semaine) => {
        const heuresActuelles = heuresExistantes.get(semaine.cleSemaine)?.heures ?? 0;
        return {
          cle: semaine.cleSemaine,
          label: labelSemaine(semaine.cleSemaine),
          heuresActuelles,
          heuresMission: semaine.heures,
          total: heuresActuelles + semaine.heures,
        };
      });

      const semaineLaPlusChargee = res.plafond48h.semaines.reduce<ControleSemaine48h | null>(
        (max, semaine) => (!max || semaine.total > max.total ? semaine : max),
        null,
      );
      res.plafond48h.heuresActuelles = semaineLaPlusChargee?.heuresActuelles ?? 0;
      res.plafond48h.heuresAvecNouvelle = semaineLaPlusChargee?.total ?? 0;
      const semainesEnDepassement = res.plafond48h.semaines.filter((semaine) => semaine.total > 48);
      if (semainesEnDepassement.length > 0) {
        res.plafond48h.ok = false;
        const detailSemaines = semainesEnDepassement
          .map((semaine) => `${semaine.label} : ${semaine.heuresActuelles.toFixed(1)}h planifiées + ${semaine.heuresMission.toFixed(1)}h = ${semaine.total.toFixed(1)}h / 48h`)
          .join(' · ');
        res.plafond48h.detail = res.plafond48h.conditionnel
          ? `Dépassement si contrat salarié ; le régime libéral n'est pas concerné. ${detailSemaines}`
          : detailSemaines;
      } else if (res.plafond48h.conditionnel) {
        res.plafond48h.detail = "Calcul de l'option salariée ; le régime libéral n'est pas concerné.";
      }

      setResultats(res);
      setLoading(false);
      const peutContinuer = res.repos11h.ok
        && (res.plafond48h.ok || res.plafond48h.conditionnel)
        && res.chevauchement.ok;
      onResultat?.(peutContinuer);
    } catch {
      marquerIndisponible('Vérification de conformité indisponible. Réessayez avant de postuler.');
    }
  }, [missionId, onResultat, user]);

  useEffect(() => {
    if (!user) {
      setLoading(false);
      setIndisponible('Connexion requise pour vérifier la conformité de cette mission.');
      onResultat?.(false);
      return;
    }
    void preverifier();
  }, [onResultat, preverifier, user]);

  if (loading) {
    return (
      <div className="card-base animate-pulse">
        <div className="h-4 bg-muted rounded w-48 mb-3" />
        <div className="space-y-2">
          <div className="h-3 bg-muted rounded w-full" />
          <div className="h-3 bg-muted rounded w-3/4" />
        </div>
      </div>
    );
  }

  if (indisponible) {
    return (
      <div className="rounded-2xl p-5 border bg-warning/5 border-warning/30" role="alert">
        <h3 className="text-sm font-bold text-foreground flex items-center gap-2">
          <AlertTriangle className="h-4 w-4 text-warning" aria-hidden="true" />
          Vérification indisponible
        </h3>
        <p className="text-xs text-muted-foreground mt-2">{indisponible}</p>
      </div>
    );
  }

  if (!resultats) return null;

  const peutContinuer = resultats.repos11h.ok
    && (resultats.plafond48h.ok || resultats.plafond48h.conditionnel)
    && resultats.chevauchement.ok;
  const avertissementContrat = resultats.plafond48h.conditionnel;
  const pct48 = Math.min(Math.round((resultats.plafond48h.heuresAvecNouvelle / 48) * 100), 120);

  const toggleDetail = (key: string) => setDetailsOuverts(p => ({ ...p, [key]: !p[key] }));

  const checks = [
    {
      key: 'repos11h',
      ok: resultats.repos11h.ok,
      labelOk: 'Repos 11h respecté',
      labelKo: 'Repos 11h NON respecté',
      detail: resultats.repos11h.detail,
      detailOk: 'Aucun conflit de repos avec vos missions existantes',
      article: 'L3131-1',
      suggestion: resultats.repos11h.suggestion,
      conditionnel: false,
      labelConditionnel: '',
    },
    {
      key: 'plafond48h',
      ok: resultats.plafond48h.ok,
      labelOk: 'Plafond 48h respecté',
      labelKo: 'Plafond 48h en danger',
      labelConditionnel: 'Plafond 48h selon le contrat',
      conditionnel: resultats.plafond48h.conditionnel,
      detail: resultats.plafond48h.detail,
      detailOk: resultats.plafond48h.applicable
        ? resultats.plafond48h.semaines.map((semaine) =>
            `${semaine.label} : ${semaine.heuresActuelles.toFixed(0)}h + ${semaine.heuresMission.toFixed(0)}h = ${semaine.total.toFixed(0)}h / 48h`,
          )
        : resultats.plafond48h.detail,
      article: 'L3121-20',
      showBar: resultats.plafond48h.applicable,
    },
    {
      key: 'chevauchement',
      ok: resultats.chevauchement.ok,
      labelOk: 'Pas de chevauchement',
      labelKo: 'Chevauchement détecté',
      detail: resultats.chevauchement.detail,
      detailOk: 'Aucune mission ne chevauche cet horaire',
      article: null,
      conditionnel: false,
      labelConditionnel: '',
    },
  ];

  return (
    <div className={`rounded-2xl p-5 border ${
      avertissementContrat
        ? 'bg-warning/5 border-warning/30'
        : peutContinuer
          ? 'bg-success/5 border-success/20'
          : 'bg-destructive/5 border-destructive/20'
    }`}>
      <h3 className="text-sm font-bold text-foreground mb-4 flex items-center gap-2">
        🔍 Vérification de compatibilité
      </h3>

      <div className="space-y-3">
        {checks.map(c => {
          const detailsAffiches = c.conditionnel
            ? [c.detail]
            : c.ok
            ? (Array.isArray(c.detailOk) ? c.detailOk : [c.detailOk])
            : [c.detail];
          return <div key={c.key}>
            <div className="flex items-start gap-2">
              {c.conditionnel ? (
                <AlertTriangle className="h-4 w-4 text-warning shrink-0 mt-0.5" />
              ) : c.ok ? (
                <CheckCircle2 className="h-4 w-4 text-success shrink-0 mt-0.5" />
              ) : (
                <XCircle className="h-4 w-4 text-destructive shrink-0 mt-0.5" />
              )}
              <div className="flex-1 min-w-0">
                <p className={`text-sm font-semibold ${
                  c.conditionnel ? 'text-warning' : c.ok ? 'text-success' : 'text-destructive'
                }`}>
                  {c.conditionnel
                    ? `⚠️ ${c.labelConditionnel}`
                    : c.ok ? `✅ ${c.labelOk}` : `❌ ${c.labelKo}`}
                </p>
                <div className="text-xs text-muted-foreground mt-0.5 space-y-0.5">
                  {detailsAffiches.map((detail) => <p key={detail}>{detail}</p>)}
                </div>

                {c.showBar && (
                  <div className="mt-2 relative h-2 rounded-full bg-muted overflow-hidden">
                    <div
                      className={`absolute inset-y-0 left-0 rounded-full transition-all ${pct48 > 100 ? 'bg-destructive' : pct48 > 92 ? 'bg-destructive' : pct48 > 75 ? 'bg-warning' : 'bg-primary'}`}
                      style={{ width: `${Math.min(pct48, 100)}%` }}
                    />
                  </div>
                )}

                {c.suggestion && !c.ok && (
                  <p className="text-xs text-info mt-1">💡 {c.suggestion}</p>
                )}

                {!c.ok && !c.conditionnel && c.article && (
                  <button
                    onClick={() => toggleDetail(c.key)}
                    className="flex items-center gap-1 text-xs text-primary hover:underline mt-1"
                  >
                    📖 Art. {c.article} du Code du Travail
                    {detailsOuverts[c.key] ? <ChevronUp className="h-3 w-3" /> : <ChevronDown className="h-3 w-3" />}
                  </button>
                )}

                {detailsOuverts[c.key] && c.article && ARTICLES_CODE_TRAVAIL[c.article] && (
                  <div className="mt-2 bg-muted/50 rounded-xl p-3 space-y-2 text-xs">
                    <p className="font-semibold text-foreground">{ARTICLES_CODE_TRAVAIL[c.article].titre}</p>
                    <p className="text-muted-foreground italic">"{ARTICLES_CODE_TRAVAIL[c.article].texteOfficiel}"</p>
                    <p className="text-muted-foreground"><strong>Ce que cela signifie :</strong> {ARTICLES_CODE_TRAVAIL[c.article].explicationSimple}</p>
                    <p className="text-muted-foreground">💡 <strong>Conseil :</strong> {ARTICLES_CODE_TRAVAIL[c.article].conseil}</p>
                    <p className="text-destructive">⚠️ <strong>Sanction :</strong> {ARTICLES_CODE_TRAVAIL[c.article].sanction}</p>
                  </div>
                )}
              </div>
            </div>
          </div>;
        })}
      </div>

      <div className="mt-4 pt-3 border-t border-border">
        {avertissementContrat && peutContinuer ? (
          <p className="text-xs text-warning font-medium">
            → Tu peux continuer : l'option salariée restera bloquée en cas de dépassement, l'option libérale n'est pas concernée.
          </p>
        ) : peutContinuer ? (
          <p className="text-xs text-success font-medium">→ Tout est conforme. Vous pouvez accepter cette mission.</p>
        ) : (
          <div>
            <p className="text-xs text-destructive font-medium mb-2">
              ⛔ Cette mission ne peut pas être acceptée en l'état. Consultez vos missions existantes pour résoudre le conflit.
            </p>
            <div className="flex gap-2">
              <button onClick={() => navigate('/soignant/planning')} className="text-xs text-primary font-medium hover:underline">
                📅 Voir mon planning →
              </button>
            </div>
          </div>
        )}
      </div>
    </div>
  );
}
