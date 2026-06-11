/**
 * SwipeMissions — Sprint 13-B PR 4
 *
 * Page swipe Hinge-style soignant : découverte de missions matchées.
 *
 * - Fetch via fn_obtenir_missions_swipe(p_limit=20)
 * - StackCards centrale avec CardMissionSwipe
 * - BoutonsActionSwipe (LIKE / DISLIKE / SUPER_LIKE) avec quota
 * - Trigger fn_enregistrer_swipe + invocation edge function notif-match si SUPER_LIKE
 * - Confettis sur SUPER_LIKE
 * - EmptyState avec Mascotte quand stack vide
 */
import { useState, useCallback, useEffect, useMemo } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { useNavigate } from 'react-router-dom';
import { usePageTitle } from '@/hooks/usePageTitle';
import { LayoutApp } from '@/components/LayoutApp';
import { Loader2, LayoutGrid, Sparkles } from 'lucide-react';
import { EmptyState } from '@/components/ui/EmptyState';
import { CardMissionSwipe, type MissionSwipePayload } from '@/components/swipe/CardMissionSwipe';
import { StackCards, type SwipeDirection } from '@/components/swipe/StackCards';
import { BoutonsActionSwipe } from '@/components/swipe/BoutonsActionSwipe';
import { ConfettiSwipe } from '@/components/swipe/ConfettiSwipe';
import { BoutonY2K } from '@/components/y2k/BoutonY2K';
import { supabase } from '@/integrations/supabase/client';
import { useNotification } from '@/contexts/NotificationContext';

type SwipeDirEnum = 'LIKE' | 'DISLIKE' | 'SUPER_LIKE';

const VIEW_PREF_KEY = 'jolene_missions_view_pref'; // 'swipe' | 'liste'

export default function SwipeMissions() {
  usePageTitle('Découvrir');
  const qc = useQueryClient();
  const navigate = useNavigate();

  // Au mount : si pref localStorage = 'liste', rediriger vers /soignant/recherche-missions
  useEffect(() => {
    try {
      const pref = localStorage.getItem(VIEW_PREF_KEY);
      if (pref === 'liste') navigate('/soignant/recherche-missions', { replace: true });
    } catch { /* localStorage indisponible (incognito strict) */ }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const switchToListe = useCallback(() => {
    try { localStorage.setItem(VIEW_PREF_KEY, 'liste'); } catch { /* ignore */ }
    navigate('/soignant/recherche-missions');
  }, [navigate]);
  const { afficherNotification } = useNotification();
  const [confettiKey, setConfettiKey] = useState<number | null>(null);

  // Fetch missions swipe
  const { data, isLoading, refetch } = useQuery({
    queryKey: ['swipe-missions'],
    queryFn: async () => {
      const { data, error } = await supabase.rpc('fn_obtenir_missions_swipe' as any, { p_limit: 20 });
      if (error) throw error;
      const missions = ((data as any)?.missions ?? []) as MissionSwipePayload[];
      return missions;
    },
    staleTime: 60_000,
  });

  // Quota super-likes du jour
  const { data: quotaSuperLike } = useQuery({
    queryKey: ['super-likes-quota'],
    queryFn: async () => {
      const today = new Date().toISOString().slice(0, 10);
      const { data } = await supabase
        .from('super_swipes_quota' as any)
        .select('count')
        .eq('date', today)
        .maybeSingle();
      const used = (data as any)?.count ?? 0;
      return Math.max(0, 5 - used);
    },
    staleTime: 30_000,
  });

  // Streak quotidien — affiché en tête (mécanique d'engagement, reset si jour manqué)
  const { data: streak } = useQuery({
    queryKey: ['ma-streak'],
    queryFn: async () => {
      const { data } = await supabase.rpc('fn_ma_streak' as any);
      const row = Array.isArray(data) ? data[0] : data;
      return (row?.streak_count as number) ?? 0;
    },
    staleTime: 60_000,
  });

  const [localStack, setLocalStack] = useState<MissionSwipePayload[]>([]);
  useEffect(() => {
    if (data) setLocalStack(data);
  }, [data]);

  const swipeMut = useMutation({
    mutationFn: async ({ missionId, direction }: { missionId: string; direction: SwipeDirEnum }) => {
      const { data, error } = await supabase.rpc('fn_enregistrer_swipe' as any, {
        p_mission_id: missionId,
        p_direction: direction,
      });
      if (error) throw error;
      return data as { ok: boolean; error?: string; quota_restant?: number };
    },
    onSuccess: (result, vars) => {
      if (!result.ok) {
        afficherNotification({
          type: 'erreur',
          message:
            result.error === 'quota_super_like_atteint'
              ? "Quota super-like atteint pour aujourd'hui (5/jour)"
              : 'Action impossible',
        });
        return;
      }
      if (vars.direction === 'SUPER_LIKE') {
        setConfettiKey(Date.now());
        afficherNotification({
          type: 'succes',
          message: "Super-like envoyé ! L'établissement est notifié.",
        });
        // Best-effort notif-match (l'edge function valide en interne le quota + direction)
        void supabase.functions.invoke('notif-match', {
          body: { soignant_id: undefined, mission_id: vars.missionId, direction: 'SUPER_LIKE' },
        });
      }
      void qc.invalidateQueries({ queryKey: ['super-likes-quota'] });
    },
    onError: () => {
      afficherNotification({ type: 'erreur', message: 'Une erreur est survenue, veuillez réessayer.' });
    },
  });

  // "Recharger" : force un vrai refetch (bypass staleTime via invalidate) +
  // feedback. fn_obtenir_missions_swipe exclut les missions déjà swipées
  // côté serveur ; on re-fetch pour récupérer celles publiées entre-temps.
  const handleRecharger = useCallback(async () => {
    await qc.invalidateQueries({ queryKey: ['swipe-missions'] });
    const res = await refetch();
    const nb = res.data?.length ?? 0;
    afficherNotification({
      type: nb > 0 ? 'succes' : 'info',
      message: nb > 0
        ? `${nb} mission${nb > 1 ? 's' : ''} à découvrir !`
        : "Aucune nouvelle mission pour l'instant. Revenez plus tard ou élargissez vos critères.",
    });
  }, [qc, refetch, afficherNotification]);

  const handleSwipe = useCallback((dir: SwipeDirEnum, missionId: string) => {
    setLocalStack((prev) => prev.filter((m) => m.mission_id !== missionId));
    swipeMut.mutate({ missionId, direction: dir });
  }, [swipeMut]);

  const handleGestureSwipe = useCallback((direction: SwipeDirection, itemKey: string) => {
    handleSwipe(direction === 'right' ? 'LIKE' : 'DISLIKE', itemKey);
  }, [handleSwipe]);

  const stackItems = useMemo(
    () =>
      localStack.map((m) => ({
        key: m.mission_id,
        content: <CardMissionSwipe mission={m} />,
      })),
    [localStack],
  );

  const topMission = localStack[0];

  return (
    <LayoutApp role="SOIGNANT">
      <div className="container mx-auto px-4 pt-4 pb-2 max-w-md">
        <div className="flex items-start justify-between gap-3">
          <div>
            <h1 className="text-2xl font-bold text-jolene-midnight">Découvrir</h1>
            <p className="text-sm text-jolene-bubblegum">Swipez à droite pour postuler, à gauche pour passer.</p>
            <div className="flex items-center gap-2 mt-2">
              {(streak ?? 0) > 0 && (
                <span className="inline-flex items-center gap-1 px-2.5 py-1 rounded-full bg-gradient-hero text-white text-xs font-bold shadow-sm">
                  🔥 {streak} jour{(streak ?? 0) > 1 ? 's' : ''} d'affilée
                </span>
              )}
              {quotaSuperLike != null && (
                <span className="inline-flex items-center gap-1 px-2.5 py-1 rounded-full bg-jolene-butter-100 text-jolene-midnight text-xs font-semibold border border-jolene-butter-300">
                  ⭐ {quotaSuperLike}/5 super-likes aujourd'hui
                </span>
              )}
            </div>
          </div>
          <div className="inline-flex rounded-2xl bg-jolene-cloud border border-jolene-rose-200 p-1 shrink-0" role="tablist" aria-label="Vue Swipe ou Liste">
            <button
              type="button"
              role="tab"
              aria-selected="true"
              className="inline-flex items-center gap-1.5 rounded-xl px-3 py-1.5 text-xs font-semibold bg-gradient-hero text-white shadow-md transition-snap"
              onClick={() => {
                try { localStorage.setItem(VIEW_PREF_KEY, 'swipe'); } catch { /* ignore */ }
              }}
            >
              <Sparkles className="h-3.5 w-3.5" aria-hidden="true" />
              Swipe
            </button>
            <button
              type="button"
              role="tab"
              aria-selected="false"
              className="inline-flex items-center gap-1.5 rounded-xl px-3 py-1.5 text-xs font-semibold text-jolene-bubblegum hover:text-jolene-rose-700 transition-snap"
              onClick={switchToListe}
            >
              <LayoutGrid className="h-3.5 w-3.5" aria-hidden="true" />
              Liste
            </button>
          </div>
        </div>
      </div>

      <div className="container mx-auto px-4 max-w-md min-h-[70vh] flex flex-col">
        <div className="flex-1 flex items-center justify-center py-2">
          {isLoading ? (
            <div className="flex flex-col items-center gap-3 text-jolene-bubblegum">
              <Loader2 className="h-8 w-8 animate-spin" />
              <span className="text-sm">Calcul de votre matching...</span>
            </div>
          ) : localStack.length === 0 ? (
            <EmptyState
              mascotte="happy"
              variant="success"
              titre="Vous avez tout vu pour aujourd'hui !"
              description="Revenez plus tard ou élargissez vos critères pour découvrir plus de missions."
              cta={{
                label: 'Recharger',
                onClick: handleRecharger,
              }}
              ctaSecondaire={{
                label: 'Voir en liste',
                onClick: switchToListe,
              }}
            />
          ) : (
            <StackCards items={stackItems} onSwipe={handleGestureSwipe} />
          )}
        </div>

        {topMission && (
          <BoutonsActionSwipe
            onDislike={() => handleSwipe('DISLIKE', topMission.mission_id)}
            onLike={() => handleSwipe('LIKE', topMission.mission_id)}
            onSuperLike={() => handleSwipe('SUPER_LIKE', topMission.mission_id)}
            quotaSuperLikeRestant={quotaSuperLike ?? null}
            disabled={swipeMut.isPending}
          />
        )}
      </div>

      {confettiKey != null && (
        <ConfettiSwipe key={confettiKey} onComplete={() => setConfettiKey(null)} />
      )}
    </LayoutApp>
  );
}
