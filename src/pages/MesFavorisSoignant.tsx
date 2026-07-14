import React, { useEffect, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { Star, Building2, ArrowRight, ChevronRight } from 'lucide-react';
import { LayoutApp } from '@/components/LayoutApp';
import { ChargementPage } from '@/components/ChargementPage';
import { usePageTitle } from '@/hooks/usePageTitle';
import { supabase } from '@/integrations/supabase/client';
import { format } from 'date-fns';
import { fr } from 'date-fns/locale';
import { toast } from 'sonner';
import { formatDateMission, formatDureeCompacte } from '@/lib/format-mission';

interface FavoriEtab {
  etablissement_id: string;
  nom: string;
  ville: string | null;
  logo_url: string | null;
  type_etablissement: string | null;
  nb_missions_ouvertes: number;
  cree_le: string;
}

export default function MesFavorisSoignant() {
  usePageTitle('Mes favoris');
  const navigate = useNavigate();
  const [items, setItems] = useState<FavoriEtab[]>([]);
  const [missionsSauvegardees, setMissionsSauvegardees] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);

  const charger = async () => {
    setLoading(true);
    // D1 (Lot 6c) : la page regroupe les 2 types de favoris — les MISSIONS
    // sauvegardées (⭐ du swipe / étoile des cartes) et les ÉTABLISSEMENTS suivis.
    const [{ data, error }, { data: ms }] = await Promise.all([
      supabase.rpc('fn_mes_favoris_etablissements' as any),
      supabase
        .from('missions_sauvegardees' as any)
        .select('mission_id, missions(id, intitule, debut_le, fin_le, duree_heures, nb_creneaux, statut, net_estime, taux_horaire_base)')
        .order('cree_le', { ascending: false }),
    ]);
    setMissionsSauvegardees(
      ((ms ?? []) as any[])
        .map((r) => r.missions)
        .filter((m) => m && m.statut === 'OUVERTE' && new Date(m.debut_le) > new Date()),
    );
    if (error) { toast.error(error.message); setLoading(false); return; }
    const payload = data as any;
    if (Array.isArray(payload)) {
      setItems(payload);
    } else if (payload?.error) {
      toast.error(payload.error);
    }
    setLoading(false);
  };

  const retirerMission = async (missionId: string) => {
    const { error } = await supabase
      .from('missions_sauvegardees' as any)
      .delete()
      .eq('mission_id', missionId);
    if (error) { toast.error(error.message); return; }
    toast.success('Mission retirée de tes favoris');
    charger();
  };

  useEffect(() => { charger(); }, []);

  const retirer = async (etab_id: string) => {
    if (!confirm('Retirer cet établissement de tes favoris ?')) return;
    const { error } = await supabase.rpc('fn_toggle_favori_etablissement' as any, {
      p_etablissement_id: etab_id, p_actif: false,
    });
    if (error) { toast.error(error.message); return; }
    toast.success('Retiré des favoris');
    charger();
  };

  return (
    <LayoutApp role="SOIGNANT">
      <div className="mb-6">
        <h1 className="text-2xl font-bold text-foreground inline-flex items-center gap-2">
          <Star className="h-6 w-6 text-warning fill-warning" /> Mes établissements favoris
        </h1>
        <p className="text-sm text-muted-foreground mt-1">
          Tu seras notifié dès que ces établissements publient une nouvelle mission compatible avec ton profil.
        </p>
      </div>

      {!loading && missionsSauvegardees.length > 0 && (
        <section className="mb-8">
          <h2 className="text-base font-bold text-foreground mb-3">
            ⭐ Missions sauvegardées ({missionsSauvegardees.length})
          </h2>
          <div className="space-y-2">
            {missionsSauvegardees.map((m: any) => (
              <div key={m.id} className="card-base flex items-center gap-3 hover:shadow-md transition-shadow">
                <button
                  type="button"
                  onClick={() => navigate(`/soignant/missions/${m.id}`)}
                  className="flex-1 min-w-0 text-left flex items-center gap-2"
                >
                  <span className="flex-1 min-w-0">
                    <span className="block text-sm font-semibold text-foreground truncate">{m.intitule}</span>
                    <span className="block text-xs text-muted-foreground truncate">
                      {formatDateMission(m)} · {formatDureeCompacte(m)}
                    </span>
                  </span>
                  <ChevronRight className="h-4 w-4 text-primary shrink-0" />
                </button>
                <button
                  type="button"
                  onClick={() => retirerMission(m.id)}
                  className="text-xs text-muted-foreground hover:text-destructive hover:underline shrink-0"
                >
                  Retirer
                </button>
              </div>
            ))}
          </div>
        </section>
      )}

      {!loading && missionsSauvegardees.length > 0 && (
        <h2 className="text-base font-bold text-foreground mb-3">🏥 Établissements suivis</h2>
      )}

      {loading ? (
        <ChargementPage />
      ) : items.length === 0 ? (
        <div className="card-base text-center py-10">
          <Star className="h-10 w-10 text-muted-foreground/30 mx-auto mb-3" />
          <p className="text-sm font-medium text-foreground">Aucun établissement favori</p>
          <p className="text-xs text-muted-foreground mt-1">
            Clique sur l'étoile ⭐ d'une mission pour ajouter l'établissement à tes favoris.
          </p>
        </div>
      ) : (
        <div className="space-y-3">
          {items.map((e) => (
            <article key={e.etablissement_id} className="card-base hover:shadow-md transition-shadow">
              <div className="flex items-start gap-3">
                {e.logo_url ? (
                  <img src={e.logo_url} alt="" className="h-14 w-14 rounded-2xl object-cover border border-border shrink-0" />
                ) : (
                  <div className="h-14 w-14 rounded-2xl border border-border bg-muted flex items-center justify-center shrink-0">
                    <Building2 className="h-6 w-6 text-muted-foreground" />
                  </div>
                )}
                <div className="flex-1 min-w-0">
                  <div className="flex items-start justify-between gap-2 mb-1">
                    <div className="min-w-0">
                      <h2 className="font-semibold text-foreground truncate">{e.nom}</h2>
                      <p className="text-xs text-muted-foreground">
                        {e.ville ?? '—'}
                        {e.type_etablissement && ` · ${e.type_etablissement.replace(/_/g, ' ').toLowerCase()}`}
                      </p>
                    </div>
                    {e.nb_missions_ouvertes > 0 && (
                      <span className="badge-base bg-primary/10 text-primary text-[10px] font-bold whitespace-nowrap">
                        {e.nb_missions_ouvertes} mission{e.nb_missions_ouvertes > 1 ? 's' : ''}
                      </span>
                    )}
                  </div>
                  <p className="text-xs text-muted-foreground">
                    Favorisé le {format(new Date(e.cree_le), 'd MMM yyyy', { locale: fr })}
                  </p>
                  <div className="flex items-center gap-2 mt-3 flex-wrap">
                    {e.nb_missions_ouvertes > 0 && (
                      <button
                        type="button"
                        onClick={() => navigate(`/soignant/recherche-missions?etablissement=${encodeURIComponent(e.etablissement_id)}`)}
                        className="btn-primary text-xs inline-flex items-center gap-1.5"
                      >
                        Voir missions ouvertes <ArrowRight className="h-3 w-3" />
                      </button>
                    )}
                    {/* 7e-2 (F2) : l'initiative côté soignante — l'étab reçoit une
                        notification avec « Reproposer en 2 clics » (dédup 7 j et
                        mission commune requise, gérées par la RPC). */}
                    <button
                      type="button"
                      onClick={async () => {
                        const { data, error } = await supabase.rpc('fn_demander_a_retravailler' as any, {
                          p_etablissement_id: e.etablissement_id,
                        });
                        if (error || (data as any)?.error) toast.error((data as any)?.error || 'Demande impossible.');
                        else toast.success('C\'est envoyé — l\'établissement est prévenu que tu veux retravailler avec lui ⭐');
                      }}
                      className="text-xs inline-flex items-center gap-1 px-2 py-1 rounded-lg bg-primary/10 text-primary hover:bg-primary/20 transition-colors font-medium"
                    >
                      Redemander à travailler ici
                    </button>
                    <button
                      type="button"
                      onClick={() => retirer(e.etablissement_id)}
                      className="text-xs text-muted-foreground hover:text-destructive hover:underline"
                    >
                      Retirer
                    </button>
                  </div>
                </div>
              </div>
            </article>
          ))}
        </div>
      )}
    </LayoutApp>
  );
}
