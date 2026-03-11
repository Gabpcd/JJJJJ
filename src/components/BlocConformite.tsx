import React, { useState, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import { ChevronDown, ChevronUp, CheckCircle2, XCircle, AlertTriangle } from 'lucide-react';
import { useAuth } from '@/contexts/AuthContext';
import { supabase } from '@/integrations/supabase/client';
import { ARTICLES_CODE_TRAVAIL } from '@/constantes/loi';
import { format } from 'date-fns';
import { fr } from 'date-fns/locale';

interface ResultatConformite {
  repos11h: { ok: boolean; detail: string; missionConflictuelle: any; suggestion?: string };
  plafond48h: { ok: boolean; detail: string; heuresActuelles: number; heuresAvecNouvelle: number };
  chevauchement: { ok: boolean; detail: string; missionConflictuelle: any };
}

interface BlocConformiteProps {
  missionId: string;
  onResultat?: (toutOk: boolean) => void;
}

function formatHeure(d: string) {
  return format(new Date(d), "HH'h'mm", { locale: fr });
}

export function BlocConformite({ missionId, onResultat }: BlocConformiteProps) {
  const { user } = useAuth();
  const navigate = useNavigate();
  const [resultats, setResultats] = useState<ResultatConformite | null>(null);
  const [loading, setLoading] = useState(true);
  const [detailsOuverts, setDetailsOuverts] = useState<Record<string, boolean>>({});

  useEffect(() => {
    if (!user) return;
    preverifier();
  }, [user, missionId]);

  async function preverifier() {
    setLoading(true);
    const [{ data: missionCible }, { data: missionsExistantes }] = await Promise.all([
      supabase.from('missions').select('debut_le, fin_le, duree_heures').eq('id', missionId).single(),
      supabase.from('missions')
        .select('id, intitule, debut_le, fin_le, duree_heures, statut, etablissements(nom)')
        .eq('soignant_assigne_id', user!.id)
        .in('statut', ['ASSIGNEE', 'EN_COURS', 'TERMINEE'])
        .order('debut_le', { ascending: true }),
    ]);

    const res: ResultatConformite = {
      repos11h: { ok: true, detail: '', missionConflictuelle: null },
      plafond48h: { ok: true, detail: '', heuresActuelles: 0, heuresAvecNouvelle: 0 },
      chevauchement: { ok: true, detail: '', missionConflictuelle: null },
    };

    if (!missionsExistantes || !missionCible) {
      setResultats(res);
      setLoading(false);
      onResultat?.(true);
      return;
    }

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

    // Plafond 48h
    const debutSemaine = new Date(missionCible.debut_le);
    const jourSem = debutSemaine.getDay();
    debutSemaine.setDate(debutSemaine.getDate() - (jourSem === 0 ? 6 : jourSem - 1));
    debutSemaine.setHours(0, 0, 0, 0);
    const finSemaine = new Date(debutSemaine);
    finSemaine.setDate(debutSemaine.getDate() + 7);

    const heuresSemaine = missionsExistantes
      .filter(m => new Date(m.debut_le) >= debutSemaine && new Date(m.debut_le) < finSemaine)
      .reduce((t, m) => t + (m.duree_heures || 0), 0);
    const heuresAvec = heuresSemaine + (missionCible.duree_heures || 0);

    res.plafond48h.heuresActuelles = heuresSemaine;
    res.plafond48h.heuresAvecNouvelle = heuresAvec;
    if (heuresAvec > 48) {
      res.plafond48h.ok = false;
      res.plafond48h.detail = `Vous auriez ${heuresAvec.toFixed(1)}h cette semaine (plafond : 48h). Actuellement : ${heuresSemaine.toFixed(1)}h + cette mission : ${missionCible.duree_heures}h.`;
    }

    setResultats(res);
    setLoading(false);
    const toutOk = res.repos11h.ok && res.plafond48h.ok && res.chevauchement.ok;
    onResultat?.(toutOk);
  }

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

  if (!resultats) return null;

  const toutOk = resultats.repos11h.ok && resultats.plafond48h.ok && resultats.chevauchement.ok;
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
    },
    {
      key: 'plafond48h',
      ok: resultats.plafond48h.ok,
      labelOk: 'Plafond 48h respecté',
      labelKo: 'Plafond 48h en danger',
      detail: resultats.plafond48h.detail,
      detailOk: `Cette semaine : ${resultats.plafond48h.heuresActuelles.toFixed(0)}h + ${(resultats.plafond48h.heuresAvecNouvelle - resultats.plafond48h.heuresActuelles).toFixed(0)}h = ${resultats.plafond48h.heuresAvecNouvelle.toFixed(0)}h / 48h`,
      article: 'L3121-20',
      showBar: true,
    },
    {
      key: 'chevauchement',
      ok: resultats.chevauchement.ok,
      labelOk: 'Pas de chevauchement',
      labelKo: 'Chevauchement détecté',
      detail: resultats.chevauchement.detail,
      detailOk: 'Aucune mission ne chevauche cet horaire',
      article: null,
    },
  ];

  return (
    <div className={`rounded-2xl p-5 border ${toutOk ? 'bg-success/5 border-success/20' : 'bg-destructive/5 border-destructive/20'}`}>
      <h3 className="text-sm font-bold text-foreground mb-4 flex items-center gap-2">
        🔍 Vérification de compatibilité
      </h3>

      <div className="space-y-3">
        {checks.map(c => (
          <div key={c.key}>
            <div className="flex items-start gap-2">
              {c.ok ? (
                <CheckCircle2 className="h-4 w-4 text-success shrink-0 mt-0.5" />
              ) : (
                <XCircle className="h-4 w-4 text-destructive shrink-0 mt-0.5" />
              )}
              <div className="flex-1 min-w-0">
                <p className={`text-sm font-semibold ${c.ok ? 'text-success' : 'text-destructive'}`}>
                  {c.ok ? `✅ ${c.labelOk}` : `❌ ${c.labelKo}`}
                </p>
                <p className="text-xs text-muted-foreground mt-0.5">
                  {c.ok ? c.detailOk : c.detail}
                </p>

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

                {!c.ok && c.article && (
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
          </div>
        ))}
      </div>

      <div className="mt-4 pt-3 border-t border-border">
        {toutOk ? (
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
