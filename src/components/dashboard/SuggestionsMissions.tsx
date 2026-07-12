import React, { useEffect, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { Sparkles, MapPin, Star, Flame, ArrowRight, Loader2 } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { toast } from 'sonner';
import { format } from 'date-fns';
import { fr } from 'date-fns/locale';
import { getLabelProfession } from '@/lib/constantes';

interface Suggestion {
  id: string;
  intitule: string;
  profession_requise: string;
  specialite_medicale_requise: string | null;
  taux_horaire_base: number;
  debut_le: string;
  fin_le: string;
  est_urgente: boolean;
  etablissement_id: string;
  etab_nom: string;
  etab_ville: string | null;
  etab_note_moyenne: number | null;
  distance_km: number | null;
}

export function SuggestionsMissions() {
  const navigate = useNavigate();
  const [items, setItems] = useState<Suggestion[]>([]);
  const [loading, setLoading] = useState(true);
  const [candidating, setCandidating] = useState<string | null>(null);

  const charger = async () => {
    setLoading(true);
    const { data } = await supabase.rpc('fn_suggestions_missions_pour_soignant' as any, { p_limit: 3 });
    setItems(((data as any) ?? []) as Suggestion[]);
    setLoading(false);
  };

  useEffect(() => { charger(); }, []);

  const candidater = async (s: Suggestion) => {
    setCandidating(s.id);
    const { data, error } = await supabase.rpc('fn_postuler_mission_rate_limited' as any, {
      p_mission_id: s.id,
      p_message: 'Candidature rapide depuis suggestions dashboard',
      p_choix_contrat: null,
    });
    setCandidating(null);
    if (error) {
      toast.error(error.message);
      return;
    }
    const r = data as any;
    if (r?.choix_requis) {
      toast('Choisis ton type de contrat sur le détail de la mission');
      navigate(`/soignant/missions/${s.id}`);
      return;
    }
    if (r?.success || r?.candidature_id) {
      toast.success('Candidature envoyée ✨');
      charger();
    } else {
      toast.error(r?.error ?? 'Erreur de candidature');
    }
  };

  if (loading || items.length === 0) return null;

  return (
    <div className="mb-6">
      <div className="flex items-center justify-between mb-3">
        <h2 className="text-base font-bold text-foreground inline-flex items-center gap-2">
          <Sparkles className="h-4 w-4 text-primary" /> Suggestions pour toi
        </h2>
        <button
          type="button"
          onClick={() => navigate('/soignant/recherche-missions')}
          className="text-xs text-primary hover:underline inline-flex items-center gap-1"
        >
          Voir plus <ArrowRight className="h-3 w-3" />
        </button>
      </div>
      <div className="space-y-2">
        {items.map((s) => (
          <article key={s.id} className="card-base hover:shadow-md transition-shadow">
            <div className="flex items-start justify-between gap-3 mb-2">
              <div className="flex-1 min-w-0">
                <div className="flex items-center gap-2">
                  {s.est_urgente && <span className="badge-base bg-destructive/10 text-destructive text-[10px] inline-flex items-center gap-1"><Flame className="h-3 w-3" /> URGENT</span>}
                  <h3 className="font-semibold text-sm text-foreground truncate">{s.intitule}</h3>
                </div>
                <p className="text-xs text-muted-foreground mt-1">
                  {s.etab_nom} · {s.etab_ville ?? '—'}
                </p>
              </div>
              <span className="text-primary font-bold text-sm whitespace-nowrap">{Number(s.taux_horaire_base).toFixed(2)} €/h</span>
            </div>

            <div className="flex flex-wrap items-center gap-2 text-xs text-muted-foreground mb-2">
              <span>{format(new Date(s.debut_le), "EEE d MMM HH'h'mm", { locale: fr })} → {format(new Date(s.fin_le), "HH'h'mm", { locale: fr })}</span>
              {s.distance_km != null && (
                <span className="inline-flex items-center gap-1"><MapPin className="h-3 w-3" /> {s.distance_km} km</span>
              )}
              {s.etab_note_moyenne != null && (
                <span className="inline-flex items-center gap-1 text-amber-700"><Star className="h-3 w-3" /> {Number(s.etab_note_moyenne).toFixed(1)}/5</span>
              )}
              <span className="badge-base bg-muted text-foreground text-[10px]">{getLabelProfession(s.profession_requise)}</span>
            </div>

            <div className="flex items-center gap-2 pt-2 border-t border-border">
              <button
                type="button"
                onClick={() => navigate(`/soignant/missions/${s.id}`)}
                className="text-xs text-muted-foreground hover:text-foreground hover:underline"
              >
                Voir détail
              </button>
              <div className="ml-auto">
                <button
                  type="button"
                  onClick={() => candidater(s)}
                  disabled={candidating === s.id}
                  className="btn-primary text-xs inline-flex items-center gap-1.5"
                >
                  {candidating === s.id ? <Loader2 className="h-3.5 w-3.5 animate-spin" /> : <Sparkles className="h-3.5 w-3.5" />}
                  {candidating === s.id ? 'Envoi…' : 'Candidater'}
                </button>
              </div>
            </div>
          </article>
        ))}
      </div>
    </div>
  );
}
