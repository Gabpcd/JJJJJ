import React, { useEffect, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { Star, ShieldCheck, ChevronRight, Send, ArrowRight } from 'lucide-react';
import { LayoutApp } from '@/components/LayoutApp';
import { ChargementPage } from '@/components/ChargementPage';
import { usePageTitle } from '@/hooks/usePageTitle';
import { supabase } from '@/integrations/supabase/client';
import { useEtablissementScope } from '@/hooks/useEtablissementScope';
import { format } from 'date-fns';
import { fr } from 'date-fns/locale';
import { toast } from 'sonner';
import { getLabelProfession } from '@/lib/constantes';

interface FavoriSoignant {
  soignant_id: string;
  prenom: string;
  nom_initiale: string;
  profession: string;
  specialite_medicale: string | null;
  avatar_url: string | null;
  score_fiabilite: number | null;
  note_moyenne: number | null;
  rpps_verifie: boolean;
  tous_documents_valides: boolean;
  disponible_urgence: boolean;
  cree_le: string;
}

interface MissionOuverte {
  id: string;
  intitule: string;
  debut_le: string;
  profession_requise: string;
}

export default function MesFavorisEtablissement() {
  usePageTitle('Mes favoris');
  const navigate = useNavigate();
  const { etablissementId } = useEtablissementScope();
  const [items, setItems] = useState<FavoriSoignant[]>([]);
  const [missions, setMissions] = useState<MissionOuverte[]>([]);
  const [loading, setLoading] = useState(true);
  const [openSend, setOpenSend] = useState<string | null>(null);

  const charger = async () => {
    setLoading(true);
    const [{ data: favs, error: e1 }, { data: missionsData }] = await Promise.all([
      supabase.rpc('fn_mes_favoris_soignants' as any),
      etablissementId
        ? supabase.from('missions').select('id, intitule, debut_le, profession_requise')
            .eq('etablissement_id', etablissementId).eq('statut', 'OUVERTE')
            .gt('debut_le', new Date().toISOString())
            .order('debut_le', { ascending: true }).limit(20)
        : Promise.resolve({ data: [] as MissionOuverte[] }),
    ]);
    if (e1) toast.error(e1.message);
    if (Array.isArray(favs)) setItems(favs as FavoriSoignant[]);
    setMissions((missionsData ?? []) as MissionOuverte[]);
    setLoading(false);
  };

  useEffect(() => { charger(); }, [etablissementId]);

  const inviter = async (soignant: FavoriSoignant, mission: MissionOuverte) => {
    // On crée une candidature statut PROPOSEE pour le soignant favori
    const { data, error } = await supabase
      .from('candidatures')
      .insert({
        mission_id: mission.id,
        soignant_id: soignant.soignant_id,
        statut: 'PROPOSEE',
        message: 'Invitation directe par établissement (favori)',
      })
      .select('id')
      .maybeSingle();
    if (error) { toast.error(error.message); return; }
    if (data?.id) {
      toast.success(`${soignant.prenom} invité·e à la mission`);
      setOpenSend(null);
    }
  };

  const retirer = async (soignant_id: string) => {
    if (!confirm('Retirer ce soignant de vos favoris ?')) return;
    const { error } = await supabase
      .from('favoris_etab_soignant' as any)
      .delete()
      .eq('soignant_id', soignant_id)
      .eq('etablissement_id', etablissementId);
    if (error) { toast.error(error.message); return; }
    toast.success('Retiré des favoris');
    charger();
  };

  return (
    <LayoutApp role="ADMIN_ETABLISSEMENT">
      <div className="mb-6">
        <h1 className="text-2xl font-bold text-foreground inline-flex items-center gap-2">
          <Star className="h-6 w-6 text-warning fill-warning" /> Mes soignants favoris
        </h1>
        <p className="text-sm text-muted-foreground mt-1">
          Soignants que vous appréciez : prioritaires dans le matching et invitables directement.
        </p>
      </div>

      {loading ? (
        <ChargementPage />
      ) : items.length === 0 ? (
        <div className="card-base text-center py-10">
          <Star className="h-10 w-10 text-muted-foreground/30 mx-auto mb-3" />
          <p className="text-sm font-medium text-foreground">Aucun soignant favori</p>
          <p className="text-xs text-muted-foreground mt-1">
            Ajoutez des soignants depuis l'annuaire ou la fiche profil détaillée.
          </p>
          <button onClick={() => navigate('/etablissement/soignants')} className="btn-secondary text-sm mt-4">
            Aller à l'annuaire
          </button>
        </div>
      ) : (
        <div className="space-y-3">
          {items.map((s) => (
            <article key={s.soignant_id} className="card-base">
              <div className="flex items-start gap-3">
                {s.avatar_url ? (
                  <img src={s.avatar_url} alt="" className="h-14 w-14 rounded-2xl object-cover border border-border shrink-0" />
                ) : (
                  <div className="h-14 w-14 rounded-2xl border border-border bg-muted flex items-center justify-center text-lg font-bold shrink-0">
                    {(s.prenom?.[0] ?? '') + (s.nom_initiale?.[0] ?? '')}
                  </div>
                )}
                <div className="flex-1 min-w-0">
                  <div className="flex items-start justify-between gap-2 mb-1">
                    <div className="min-w-0">
                      <h2 className="font-semibold text-foreground truncate">{s.prenom} {s.nom_initiale}</h2>
                      <p className="text-xs text-muted-foreground">
                        {getLabelProfession(s.profession)}
                        {s.specialite_medicale && ` · ${s.specialite_medicale}`}
                      </p>
                    </div>
                    <button
                      type="button"
                      onClick={() => navigate(`/etablissement/soignants/${s.soignant_id}`)}
                      className="text-xs text-primary hover:underline inline-flex items-center gap-1"
                    >
                      Profil <ChevronRight className="h-3 w-3" />
                    </button>
                  </div>

                  <div className="flex flex-wrap items-center gap-1.5 text-xs">
                    {s.score_fiabilite != null && (
                      <span className="inline-flex items-center gap-1 rounded-full bg-primary/10 text-primary px-2 py-0.5 font-medium">
                        <ShieldCheck className="h-3 w-3" /> {s.score_fiabilite}/100
                      </span>
                    )}
                    {s.note_moyenne != null && (
                      <span className="inline-flex items-center gap-1 rounded-full bg-amber-50 text-amber-700 px-2 py-0.5 font-medium">
                        ⭐ {Number(s.note_moyenne).toFixed(1)}
                      </span>
                    )}
                    {s.rpps_verifie && <span className="badge-base bg-success/10 text-success text-[10px]">RPPS ✓</span>}
                    {s.tous_documents_valides && <span className="badge-base bg-success/10 text-success text-[10px]">Docs ✓</span>}
                    {s.disponible_urgence && <span className="badge-base bg-orange-50 text-orange-700 text-[10px]">🚨 Urgence</span>}
                  </div>

                  <p className="text-xs text-muted-foreground mt-2">
                    Favori depuis le {format(new Date(s.cree_le), 'd MMM yyyy', { locale: fr })}
                  </p>

                  <div className="flex items-center gap-2 mt-3 pt-2 border-t border-border">
                    {missions.length > 0 ? (
                      openSend === s.soignant_id ? (
                        <div className="flex items-center gap-2 flex-1">
                          <select
                            onChange={(e) => {
                              const m = missions.find((mm) => mm.id === e.target.value);
                              if (m) inviter(s, m);
                            }}
                            className="text-xs px-2 py-1.5 rounded-lg border border-border bg-background flex-1"
                            defaultValue=""
                          >
                            <option value="" disabled>Choisir une mission…</option>
                            {missions.map((m) => (
                              <option key={m.id} value={m.id}>
                                {m.intitule} · {format(new Date(m.debut_le), 'd MMM HH:mm', { locale: fr })}
                              </option>
                            ))}
                          </select>
                          <button
                            type="button"
                            onClick={() => setOpenSend(null)}
                            className="text-xs text-muted-foreground hover:underline"
                          >
                            Annuler
                          </button>
                        </div>
                      ) : (
                        <button
                          type="button"
                          onClick={() => setOpenSend(s.soignant_id)}
                          className="btn-primary text-xs inline-flex items-center gap-1.5"
                        >
                          <Send className="h-3.5 w-3.5" /> Inviter à une mission
                        </button>
                      )
                    ) : (
                      <span className="text-xs text-muted-foreground italic">Pas de mission ouverte à proposer</span>
                    )}
                    <button
                      type="button"
                      onClick={() => retirer(s.soignant_id)}
                      className="text-xs text-muted-foreground hover:text-destructive hover:underline ml-auto"
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
