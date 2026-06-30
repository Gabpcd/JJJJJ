import React, { useEffect, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { Flame, MapPin, Clock, Euro, CheckCircle2, AlertCircle, Loader2, ArrowRight } from 'lucide-react';
import { LayoutApp } from '@/components/LayoutApp';
import { ChargementPage } from '@/components/ChargementPage';
import { PoolUrgenceToggle } from '@/components/PoolUrgenceToggle';
import { usePageTitle } from '@/hooks/usePageTitle';
import { supabase } from '@/integrations/supabase/client';
import { getLabelProfession } from '@/lib/constantes';
import { toast } from 'sonner';

interface MissionUrgente {
  id: string;
  intitule: string;
  profession_requise: string;
  specialite_medicale_requise: string | null;
  taux_horaire_base: number;
  debut_le: string;
  fin_le: string;
  service: string | null;
  etablissement_nom: string;
  etablissement_ville: string | null;
  distance_km: number | null;
  deja_candidate: boolean;
  statut_candidature: string | null;
}

interface PoolMeta {
  pool_actif: boolean;
  rayon_km: number;
  sms_opt_in: boolean;
}

export default function PoolUrgenceSoignant() {
  usePageTitle('Pool urgence');
  const navigate = useNavigate();
  const [loading, setLoading] = useState(true);
  const [missions, setMissions] = useState<MissionUrgente[]>([]);
  const [meta, setMeta] = useState<PoolMeta>({ pool_actif: false, rayon_km: 30, sms_opt_in: false });
  const [accepting, setAccepting] = useState<string | null>(null);

  const charger = async () => {
    setLoading(true);
    const { data, error } = await supabase.rpc('fn_pool_urgence_missions_pour_soignant' as any);
    if (error) {
      toast.error(error.message ?? 'Erreur de chargement');
      setLoading(false);
      return;
    }
    const payload = data as any;
    if (payload?.error) {
      toast.error(payload.error);
      setLoading(false);
      return;
    }
    setMissions(payload?.missions ?? []);
    setMeta({
      pool_actif: payload?.pool_actif ?? false,
      rayon_km: payload?.rayon_km ?? 30,
      sms_opt_in: payload?.sms_opt_in ?? false,
    });
    setLoading(false);
  };

  useEffect(() => { charger(); }, []);

  const accepter = async (mission: MissionUrgente) => {
    if (!confirm(`Accepter cette mission urgente "${mission.intitule}" ?\n\nL'établissement validera ou refusera ton acceptation sous 1h.`)) return;
    setAccepting(mission.id);
    const { data, error } = await supabase.rpc('fn_accepter_mission_urgence' as any, { p_mission_id: mission.id });
    setAccepting(null);
    if (error) {
      toast.error(error.message ?? 'Erreur lors de l\'acceptation');
      return;
    }
    const result = data as any;
    if (result?.success) {
      toast.success(result.message ?? 'Acceptation enregistrée');
      charger();
    } else {
      toast.error(result?.error ?? 'Erreur inconnue');
    }
  };

  const formatDate = (iso: string) => {
    const d = new Date(iso);
    return d.toLocaleString('fr-FR', { weekday: 'short', day: '2-digit', month: 'short', hour: '2-digit', minute: '2-digit' });
  };

  return (
    <LayoutApp role="SOIGNANT">
      <div className="mb-6">
        <h1 className="text-2xl font-bold text-foreground inline-flex items-center gap-2">
          <Flame className="h-6 w-6 text-destructive" /> Pool urgence
        </h1>
        <p className="text-sm text-muted-foreground mt-1">
          Missions de remplacement de dernière minute correspondant à ton profil. Acceptation 1-clic, validation étab sous 1h.
        </p>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-[320px_1fr] gap-6">
        {/* Sidebar : toggle + paramètres */}
        <aside>
          <PoolUrgenceToggle
            actif={meta.pool_actif}
            rayonKm={meta.rayon_km}
            smsOptIn={meta.sms_opt_in}
            onUpdate={() => charger()}
          />
        </aside>

        {/* Liste missions urgentes */}
        <main>
          {loading ? (
            <ChargementPage />
          ) : !meta.pool_actif ? (
            <div className="card-base text-center py-10">
              <AlertCircle className="h-10 w-10 text-warning mx-auto mb-3" />
              <p className="text-sm text-foreground font-medium">Pool urgence désactivé</p>
              <p className="text-xs text-muted-foreground mt-1">
                Active le toggle à gauche pour recevoir les alertes urgentes et voir les missions disponibles.
              </p>
            </div>
          ) : missions.length === 0 ? (
            <div className="card-base text-center py-10">
              <CheckCircle2 className="h-10 w-10 text-success mx-auto mb-3" />
              <p className="text-sm text-foreground font-medium">Aucune mission urgente pour le moment</p>
              <p className="text-xs text-muted-foreground mt-1">
                Tu seras notifié dès qu'une mission urgente correspondra à ton profil dans ton rayon ({meta.rayon_km} km).
              </p>
            </div>
          ) : (
            <div className="space-y-3">
              <p className="text-sm text-muted-foreground">
                <strong className="text-foreground">{missions.length}</strong> mission{missions.length > 1 ? 's' : ''} urgente{missions.length > 1 ? 's' : ''} dans ton rayon · triée{missions.length > 1 ? 's' : ''} par distance
              </p>
              {missions.map((m) => (
                <article key={m.id} className="card-base border-l-4 border-l-destructive">
                  <div className="flex items-start justify-between gap-3 mb-2">
                    <div className="flex-1 min-w-0">
                      <h2 className="font-semibold text-foreground">{m.intitule}</h2>
                      <p className="text-xs text-muted-foreground mt-0.5">
                        {m.etablissement_nom}{m.service ? ` · ${m.service}` : ''}
                      </p>
                    </div>
                    <span className="badge-base bg-destructive/10 text-destructive text-[10px] font-bold inline-flex items-center gap-1">
                      <Flame className="h-3 w-3" /> URGENT
                    </span>
                  </div>

                  <div className="flex flex-wrap items-center gap-3 text-xs text-muted-foreground mb-3">
                    <span className="inline-flex items-center gap-1">
                      <Clock className="h-3.5 w-3.5" /> {formatDate(m.debut_le)} → {new Date(m.fin_le).toLocaleTimeString('fr-FR', { hour: '2-digit', minute: '2-digit' })}
                    </span>
                    <span className="inline-flex items-center gap-1">
                      <Euro className="h-3.5 w-3.5" /> {Number(m.taux_horaire_base).toFixed(2)} €/h
                    </span>
                    <span className="inline-flex items-center gap-1">
                      <MapPin className="h-3.5 w-3.5" /> {m.etablissement_ville ?? '—'}
                      {m.distance_km != null && ` · ${m.distance_km} km`}
                    </span>
                    <span className="badge-base bg-muted text-foreground text-[10px]">{getLabelProfession(m.profession_requise)}</span>
                    {m.specialite_medicale_requise && (
                      <span className="badge-base bg-info/10 text-info text-[10px]">{m.specialite_medicale_requise}</span>
                    )}
                  </div>

                  {m.deja_candidate ? (
                    <div className="flex items-center justify-between gap-2 pt-2 border-t border-border">
                      <span className="text-xs">
                        {m.statut_candidature === 'EN_ATTENTE_VALIDATION_ETAB' && (
                          <span className="inline-flex items-center gap-1 text-warning"><Loader2 className="h-3.5 w-3.5 animate-spin" /> En attente de validation étab</span>
                        )}
                        {m.statut_candidature === 'ACCEPTEE' && (
                          <span className="inline-flex items-center gap-1 text-success"><CheckCircle2 className="h-3.5 w-3.5" /> Validée par étab</span>
                        )}
                        {m.statut_candidature === 'REFUSEE' && (
                          <span className="text-destructive">Refusée par étab</span>
                        )}
                        {(!m.statut_candidature || m.statut_candidature === 'EN_ATTENTE') && (
                          <span className="text-muted-foreground">Tu as déjà candidaté</span>
                        )}
                      </span>
                      <button
                        type="button"
                        onClick={() => navigate(`/soignant/missions/${m.id}`)}
                        className="text-xs text-primary hover:underline inline-flex items-center gap-1"
                      >
                        Voir mission <ArrowRight className="h-3 w-3" />
                      </button>
                    </div>
                  ) : (
                    <div className="flex items-center justify-between gap-2 pt-2 border-t border-border">
                      <button
                        type="button"
                        onClick={() => navigate(`/soignant/missions/${m.id}`)}
                        className="text-xs text-muted-foreground hover:text-foreground hover:underline"
                      >
                        Voir détail
                      </button>
                      <button
                        type="button"
                        onClick={() => accepter(m)}
                        disabled={accepting === m.id}
                        className="btn-primary text-sm inline-flex items-center gap-2"
                      >
                        {accepting === m.id ? <Loader2 className="h-4 w-4 animate-spin" /> : <Flame className="h-4 w-4" />}
                        {accepting === m.id ? 'Acceptation…' : 'J\'accepte'}
                      </button>
                    </div>
                  )}
                </article>
              ))}
            </div>
          )}
        </main>
      </div>
    </LayoutApp>
  );
}
