import { useState, useEffect } from 'react';
import { Trophy, Star, Briefcase, Award } from 'lucide-react';
import { usePageTitle } from '@/hooks/usePageTitle';
import { LayoutApp } from '@/components/LayoutApp';
import { ChargementPage } from '@/components/ChargementPage';
import { EmptyState } from '@/components/ui/EmptyState';
import { supabase } from '@/integrations/supabase/client';
import { useNotification } from '@/contexts/NotificationContext';
import { PROFESSIONS } from '@/lib/constantes';

interface TopSoignant {
  rang: number;
  prenom: string;
  profession: string;
  note_moyenne: number;
  score_fiabilite: number;
  total_missions_terminees: number;
}

const labelProfession = (valeur: string) =>
  PROFESSIONS.find((p) => p.valeur === valeur)?.label ?? valeur;

const LIMIT_OPTIONS = [10, 20, 50] as const;

export default function ClassementSoignants() {
  usePageTitle('Classement');
  return (
    <LayoutApp role="SOIGNANT">
      <ClassementContent />
    </LayoutApp>
  );
}

export function ClassementContent() {
  const { afficherNotification } = useNotification();
  const [loading, setLoading] = useState(true);
  const [soignants, setSoignants] = useState<TopSoignant[]>([]);
  const [profession, setProfession] = useState<string>('');
  const [limit, setLimit] = useState<number>(10);

  async function charger() {
    setLoading(true);
    const { data, error } = await supabase.rpc('fn_top_soignants' as any, {
      p_profession: profession || null,
      p_limit: limit,
    });
    if (error) {
      // Ne jamais exposer le message Postgres brut à l'utilisateur.
      afficherNotification({ type: 'erreur', message: 'Le classement est momentanément indisponible. Réessayez plus tard.' });
      setSoignants([]);
      setLoading(false);
      return;
    }
    // Le rang n'est pas renvoyé par la fonction : on le dérive de l'ordre (déjà trié).
    const classes = ((data as Omit<TopSoignant, 'rang'>[]) || []).map((s, i) => ({ ...s, rang: i + 1 }));
    setSoignants(classes);
    setLoading(false);
  }

  useEffect(() => { charger(); }, [profession, limit]);

  const medalColor = (rang: number) => {
    if (rang === 1) return 'text-yellow-500';
    if (rang === 2) return 'text-gray-400';
    if (rang === 3) return 'text-amber-600';
    return 'text-muted-foreground';
  };

  const medalIcon = (rang: number) => {
    if (rang <= 3) return <Trophy className={`h-5 w-5 ${medalColor(rang)}`} />;
    return <span className={`text-sm font-bold tabular-nums ${medalColor(rang)}`}>{rang}</span>;
  };

  if (loading && soignants.length === 0) return <ChargementPage />;

  return (
    <>
      <div className="mb-6">
        <h1 className="text-2xl font-bold text-foreground inline-flex items-center gap-2">
          <Trophy className="h-6 w-6 text-yellow-500" />
          Classement soignants
        </h1>
        <p className="text-sm text-muted-foreground mt-1">
          Les soignants les mieux notés par profession sur la plateforme.
        </p>
      </div>

      {/* Filtres */}
      <div className="flex flex-col sm:flex-row gap-2 mb-6">
        <select
          value={profession}
          onChange={(e) => setProfession(e.target.value)}
          className="input-base sm:w-72"
          aria-label="Filtrer par profession"
        >
          <option value="">Toutes les professions</option>
          {PROFESSIONS.map((p) => (
            <option key={p.valeur} value={p.valeur}>{p.label}</option>
          ))}
        </select>
        <select
          value={limit}
          onChange={(e) => setLimit(Number(e.target.value))}
          className="input-base sm:w-28"
          aria-label="Nombre de résultats"
        >
          {LIMIT_OPTIONS.map((n) => (
            <option key={n} value={n}>Top {n}</option>
          ))}
        </select>
      </div>

      {soignants.length === 0 ? (
        <EmptyState
          icone={<Trophy />}
          mascotte="empty"
          titre="Aucun résultat"
          description="Aucun soignant trouvé pour ce filtre."
          cta={{ label: 'Toutes les professions', onClick: () => setProfession(''), variant: 'secondary' }}
        />
      ) : (
        <div className="space-y-2">
          {soignants.map((s) => (
            <div
              key={s.rang}
              className={`flex items-center gap-4 rounded-2xl border border-border bg-card p-4 ${
                s.rang === 1 ? 'border-yellow-400/40 bg-yellow-50/10' :
                s.rang === 2 ? 'border-gray-300/40' :
                s.rang === 3 ? 'border-amber-500/40' : ''
              }`}
            >
              {/* Rang */}
              <div className="w-8 flex items-center justify-center shrink-0">
                {medalIcon(s.rang)}
              </div>

              {/* Infos */}
              <div className="flex-1 min-w-0">
                <p className="font-semibold text-foreground">{s.prenom}</p>
                <p className="text-xs text-muted-foreground">{labelProfession(s.profession)}</p>
              </div>

              {/* Stats */}
              <div className="hidden sm:flex items-center gap-4 text-xs text-muted-foreground shrink-0">
                <div className="flex items-center gap-1" title="Note moyenne">
                  <Star className="h-3.5 w-3.5 fill-yellow-400 text-yellow-400" />
                  <span className="font-medium text-foreground tabular-nums">{Number(s.note_moyenne).toFixed(1)}</span>
                </div>
                <div className="flex items-center gap-1" title="Score fiabilité">
                  <Award className="h-3.5 w-3.5 text-primary" />
                  <span className="font-medium text-foreground tabular-nums">{s.score_fiabilite}</span>
                  <span className="text-muted-foreground">/100</span>
                </div>
                <div className="flex items-center gap-1" title="Missions terminées">
                  <Briefcase className="h-3.5 w-3.5 text-muted-foreground" />
                  <span className="tabular-nums">{s.total_missions_terminees}</span>
                </div>
              </div>

              {/* Stats mobile (compactes) */}
              <div className="flex sm:hidden flex-col items-end gap-0.5 shrink-0 text-[11px]">
                <span className="flex items-center gap-0.5 font-medium">
                  <Star className="h-3 w-3 fill-yellow-400 text-yellow-400" />
                  {Number(s.note_moyenne).toFixed(1)}
                </span>
                <span className="text-muted-foreground">{s.score_fiabilite}/100</span>
                <span className="text-muted-foreground">{s.total_missions_terminees} missions</span>
              </div>
            </div>
          ))}
        </div>
      )}
    </>
  );
}
