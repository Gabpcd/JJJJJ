import React, { useEffect, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { AlertTriangle, FileText, Users, ArrowRight, Flame } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { format } from 'date-fns';
import { fr } from 'date-fns/locale';
import { getLabelProfession } from '@/lib/constantes';

interface MissionOrpheline {
  mission_id: string;
  intitule: string;
  profession_requise: string;
  debut_le: string;
  cree_le: string;
  taux_horaire_base: number;
  est_urgente: boolean;
  jours_sans_candidature: number;
}

interface ContratAUploader {
  mission_id: string;
  intitule: string;
  debut_le: string;
  soignant_prenom: string;
  soignant_nom_initiale: string;
  heures_avant_debut: number;
}

interface Alertes {
  missions_sans_candidature_48h: MissionOrpheline[];
  contrats_travail_a_uploader: ContratAUploader[];
  count_total: number;
}

export function BannerAlertesDashboardEtab() {
  const navigate = useNavigate();
  const [alertes, setAlertes] = useState<Alertes | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    let alive = true;
    (async () => {
      const { data } = await supabase.rpc('fn_alertes_dashboard_etab' as any);
      if (!alive) return;
      const payload = data as any;
      if (payload && !payload.error) {
        setAlertes(payload as Alertes);
      }
      setLoading(false);
    })();
    return () => { alive = false; };
  }, []);

  if (loading || !alertes || alertes.count_total === 0) return null;

  const orphelines = alertes.missions_sans_candidature_48h ?? [];
  const contrats = alertes.contrats_travail_a_uploader ?? [];

  return (
    <div className="card-base border-l-4 border-l-warning bg-warning/5 mb-4">
      <div className="flex items-start gap-3 mb-3">
        <AlertTriangle className="h-5 w-5 text-warning flex-shrink-0 mt-0.5" />
        <div className="flex-1 min-w-0">
          <h2 className="font-semibold text-foreground">
            {alertes.count_total} alerte{alertes.count_total > 1 ? 's' : ''} à traiter
          </h2>
          <p className="text-xs text-muted-foreground mt-0.5">
            Actions à prévoir pour assurer le bon déroulement de vos missions.
          </p>
        </div>
      </div>

      <div className="space-y-3">
        {orphelines.length > 0 && (
          <section>
            <h3 className="text-xs font-semibold text-muted-foreground uppercase tracking-wide mb-2 inline-flex items-center gap-1.5">
              <Users className="h-3.5 w-3.5" /> Missions sans candidature depuis +48h ({orphelines.length})
            </h3>
            <div className="space-y-1.5">
              {orphelines.slice(0, 4).map((m) => (
                <button
                  key={m.mission_id}
                  type="button"
                  onClick={() => navigate(`/etablissement/missions/${m.mission_id}`)}
                  className="w-full text-left rounded-xl border border-border bg-card p-2.5 hover:border-warning/50 hover:bg-warning/5 transition-colors flex items-center gap-3"
                >
                  <div className="flex-1 min-w-0">
                    <p className="text-sm font-medium text-foreground inline-flex items-center gap-2 truncate">
                      {m.est_urgente && <Flame className="h-3.5 w-3.5 text-destructive shrink-0" />}
                      {m.intitule}
                    </p>
                    <p className="text-xs text-muted-foreground mt-0.5">
                      {getLabelProfession(m.profession_requise)} · {format(new Date(m.debut_le), "EEE d MMM HH'h'mm", { locale: fr })} · {Number(m.taux_horaire_base).toFixed(2)} €/h
                    </p>
                    <p className="text-[11px] text-warning mt-0.5">
                      Publiée il y a {Math.round(m.jours_sans_candidature)} jour{Math.round(m.jours_sans_candidature) > 1 ? 's' : ''} · 0 candidature
                    </p>
                  </div>
                  <ArrowRight className="h-4 w-4 text-muted-foreground shrink-0" />
                </button>
              ))}
              {orphelines.length > 4 && (
                <button
                  type="button"
                  onClick={() => navigate('/etablissement/missions?statut=OUVERTE')}
                  className="text-xs text-warning hover:underline mt-1"
                >
                  Voir les {orphelines.length - 4} autres missions sans candidature →
                </button>
              )}
            </div>
          </section>
        )}

        {contrats.length > 0 && (
          <section className="pt-2 border-t border-border">
            <h3 className="text-xs font-semibold text-muted-foreground uppercase tracking-wide mb-2 inline-flex items-center gap-1.5">
              <FileText className="h-3.5 w-3.5" /> Contrats de travail à uploader avant 48h ({contrats.length})
            </h3>
            <div className="space-y-1.5">
              {contrats.slice(0, 4).map((c) => (
                <button
                  key={c.mission_id}
                  type="button"
                  onClick={() => navigate(`/etablissement/missions/${c.mission_id}`)}
                  className="w-full text-left rounded-xl border border-border bg-card p-2.5 hover:border-destructive/50 hover:bg-destructive/5 transition-colors flex items-center gap-3"
                >
                  <div className="flex-1 min-w-0">
                    <p className="text-sm font-medium text-foreground truncate">{c.intitule}</p>
                    <p className="text-xs text-muted-foreground mt-0.5">
                      {c.soignant_prenom} {c.soignant_nom_initiale} · {format(new Date(c.debut_le), "EEE d MMM HH'h'mm", { locale: fr })}
                    </p>
                    <p className="text-[11px] text-destructive mt-0.5">
                      {c.heures_avant_debut > 0 ? `Début dans ${c.heures_avant_debut.toFixed(0)}h` : 'Mission imminente'} · contrat de travail manquant
                    </p>
                  </div>
                  <ArrowRight className="h-4 w-4 text-muted-foreground shrink-0" />
                </button>
              ))}
              {contrats.length > 4 && (
                <button
                  type="button"
                  onClick={() => navigate('/etablissement/contrats')}
                  className="text-xs text-destructive hover:underline mt-1"
                >
                  Voir les {contrats.length - 4} autres contrats à uploader →
                </button>
              )}
            </div>
          </section>
        )}
      </div>
    </div>
  );
}
