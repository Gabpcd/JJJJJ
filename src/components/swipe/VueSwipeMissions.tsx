/**
 * VueSwipeMissions — Session G1, sémantique D1/D2 (Lot 6c)
 *
 * Vue swipe Hinge-style montée DANS la page canonique « Trouver une mission ».
 *
 * Gestes :
 * - ✕  passer · ⭐ SAUVEGARDER (favoris illimités, aucune candidature)
 * - ❤️ candidature IMMÉDIATE et ferme : haptic + toast + « Annuler » 5 s.
 *   Sheet pédagogique à la toute première candidature (une seule fois) :
 *   l'établissement peut accepter directement → mission confirmée.
 * - Conflit de planning : blocage backend avec message clair ; missions
 *   adjacentes < 1 h : warning non bloquant.
 * - Fin de deck : missions sauvegardées re-surfacées (anti-fuite du favori).
 */
import { useState, useCallback, useEffect, useMemo } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { useNavigate } from 'react-router-dom';
import { Loader2, Star, ChevronRight } from 'lucide-react';
import { toast } from 'sonner';
import { EmptyState } from '@/components/ui/EmptyState';
import { CardMissionSwipe, type MissionSwipePayload } from '@/components/swipe/CardMissionSwipe';
import { StackCards, type SwipeDirection } from '@/components/swipe/StackCards';
import { BoutonsActionSwipe } from '@/components/swipe/BoutonsActionSwipe';
import { ModalDetailMissionSwipe } from '@/components/swipe/ModalDetailMissionSwipe';
import { ChoixContratDialog } from '@/components/ChoixContratDialog';
import { BoutonY2K } from '@/components/y2k/BoutonY2K';
import {
  DialogResponsive,
  DialogResponsiveContent,
  DialogResponsiveHeader,
  DialogResponsiveTitle,
  DialogResponsiveDescription,
  DialogResponsiveBody,
  DialogResponsiveFooter,
} from '@/components/ui/DialogResponsive';
import { formatDateMission, formatDureeCompacte } from '@/lib/format-mission';
import { supabase } from '@/integrations/supabase/client';
import { useNotification } from '@/contexts/NotificationContext';

type SwipeDirEnum = 'LIKE' | 'DISLIKE' | 'FAVORI';

/** Sheet pédagogique « candidature = engagement ferme » : une seule fois. */
const CLE_SHEET_PREMIERE_CANDIDATURE = 'jolene_sheet_premiere_candidature_vue';

interface ContratOption { value: string; label: string; }
interface SwipeRpcResult {
  ok: boolean;
  error?: string;
  choix_requis?: boolean;
  options?: ContratOption[];
  candidature_id?: string;
  sauvegardee?: boolean;
  warning?: string;
  conflit_planning?: boolean;
}

interface VueSwipeMissionsProps {
  /** Bascule vers la vue Liste (gérée par le parent, pas de navigation). */
  onBasculerListe: () => void;
  /** Ouvre le flux « créer une alerte » du parent (RechercheMissions). */
  onCreerAlerte: () => void;
}

export function VueSwipeMissions({ onBasculerListe, onCreerAlerte }: VueSwipeMissionsProps) {
  const qc = useQueryClient();
  const navigate = useNavigate();
  const { afficherNotification } = useNotification();

  // Modal détail mission (tap sur la card ou bouton « Voir le détail »)
  const [detailMission, setDetailMission] = useState<MissionSwipePayload | null>(null);
  const [detailOpen, setDetailOpen] = useState(false);

  // Sheet pédagogique 1ʳᵉ candidature : intercepte le LIKE avant envoi.
  const [premiereCandidature, setPremiereCandidature] = useState<{
    missionId: string;
    mission: MissionSwipePayload;
  } | null>(null);

  // Choix de contrat (soignant MIXTE + mission acceptant salarié ET libéral)
  const [choixContrat, setChoixContrat] = useState<{
    options: ContratOption[];
    missionId: string;
    direction: SwipeDirEnum;
    mission: MissionSwipePayload;
  } | null>(null);

  // Fetch missions swipe
  const { data, isLoading } = useQuery({
    queryKey: ['swipe-missions'],
    queryFn: async () => {
      const { data, error } = await supabase.rpc('fn_obtenir_missions_swipe' as any, { p_limit: 20 });
      if (error) throw error;
      const missions = ((data as any)?.missions ?? []) as MissionSwipePayload[];
      return missions;
    },
    staleTime: 60_000,
  });

  // Missions sauvegardées (⭐) — re-surfacées en fin de deck (anti-fuite du favori)
  const { data: sauvegardees } = useQuery({
    queryKey: ['missions-sauvegardees'],
    queryFn: async () => {
      const { data } = await supabase
        .from('missions_sauvegardees' as any)
        .select('mission_id, missions(id, intitule, debut_le, fin_le, duree_heures, nb_creneaux, taux_horaire_base, net_estime, statut)')
        .order('cree_le', { ascending: false })
        .limit(10);
      return ((data ?? []) as any[])
        .map((r) => r.missions)
        .filter((m) => m && m.statut === 'OUVERTE' && new Date(m.debut_le) > new Date());
    },
    staleTime: 60_000,
  });

  const [localStack, setLocalStack] = useState<MissionSwipePayload[]>([]);
  useEffect(() => {
    if (data) setLocalStack(data);
  }, [data]);

  const retirerCandidature = useCallback(async (candidatureId: string, mission: MissionSwipePayload) => {
    const { data, error } = await supabase.rpc('fn_retirer_candidature' as any, { p_candidature_id: candidatureId });
    if (error || (data as any)?.success === false) {
      toast.error((data as any)?.error ?? 'Retrait impossible — la candidature a peut-être déjà été acceptée.');
      return;
    }
    // La card revient en tête de pile : l'annulation est réversible à l'infini.
    setLocalStack((prev) =>
      prev.some((m) => m.mission_id === mission.mission_id) ? prev : [mission, ...prev]);
    toast.success('Candidature annulée');
  }, []);

  const swipeMut = useMutation({
    mutationFn: async ({
      missionId,
      direction,
      choixContrat,
    }: {
      missionId: string;
      direction: SwipeDirEnum;
      mission: MissionSwipePayload;
      choixContrat?: string;
    }) => {
      const { data, error } = await supabase.rpc('fn_enregistrer_swipe' as any, {
        p_mission_id: missionId,
        p_direction: direction,
        ...(choixContrat ? { p_choix_contrat: choixContrat } : {}),
      });
      if (error) throw error;
      return data as SwipeRpcResult;
    },
    onSuccess: (result, vars) => {
      if (!result.ok) {
        // Choix de contrat requis : la card revient dans la pile, le swipe sera
        // rejoué avec p_choix_contrat.
        if (result.choix_requis) {
          setLocalStack((prev) =>
            prev.some((m) => m.mission_id === vars.missionId) ? prev : [vars.mission, ...prev],
          );
          setChoixContrat({
            options: result.options ?? [
              { value: 'SALARIE', label: 'Salarié (CDD)' },
              { value: 'LIBERAL', label: 'Libéral (note d’honoraires)' },
            ],
            missionId: vars.missionId,
            direction: vars.direction,
            mission: vars.mission,
          });
          return;
        }
        // D2 garde-fou : conflit de planning → la card revient dans la pile
        // (le soignant doit voir pourquoi ; il pourra la passer lui-même).
        if (result.conflit_planning) {
          setLocalStack((prev) =>
            prev.some((m) => m.mission_id === vars.missionId) ? prev : [vars.mission, ...prev],
          );
        }
        afficherNotification({ type: 'erreur', message: result.error || 'Action impossible' });
        return;
      }

      setChoixContrat(null);
      setLocalStack((prev) => prev.filter((m) => m.mission_id !== vars.missionId));

      if (vars.direction === 'FAVORI') {
        void qc.invalidateQueries({ queryKey: ['missions-sauvegardees'] });
        toast.success('Mission sauvegardée ⭐', {
          description: 'Retrouve-la en fin de deck ou dans Mes favoris.',
        });
        return;
      }

      if (vars.direction === 'LIKE') {
        // D2 : candidature immédiate FERME + annulation « dans la foulée » (5 s).
        // 6c.4 : compteur discret du jour (« 3ᵉ candidature aujourd'hui »).
        const candidatureId = result.candidature_id;
        void (async () => {
          const debutJour = new Date(); debutJour.setHours(0, 0, 0, 0);
          const { count } = await supabase
            .from('candidatures')
            .select('id', { count: 'exact', head: true })
            .gte('cree_le', debutJour.toISOString());
          toast.success('Candidature envoyée ✓', {
            duration: 5000,
            ...(count && count > 1 ? { description: `${count}ᵉ candidature aujourd'hui 💪` } : {}),
            ...(candidatureId
              ? {
                  action: {
                    label: 'Annuler',
                    onClick: () => void retirerCandidature(candidatureId, vars.mission),
                  },
                }
              : {}),
          });
        })();
        if (result.warning) {
          toast.warning(result.warning, { duration: 6000 });
        }
      }
    },
    onError: (err: any) => {
      afficherNotification({
        type: 'erreur',
        message: err?.message || 'Une erreur est survenue, veuillez réessayer.',
      });
    },
  });

  const ouvrirDetail = useCallback((m: MissionSwipePayload) => {
    setDetailMission(m);
    setDetailOpen(true);
  }, []);

  const handleSwipe = useCallback((dir: SwipeDirEnum, missionId: string) => {
    const mission = localStack.find((m) => m.mission_id === missionId);
    if (!mission) return;

    // Sheet pédagogique : à la TOUTE PREMIÈRE candidature uniquement, on
    // explique l'engagement avant d'envoyer (une candidature n'est pas un like).
    if (dir === 'LIKE') {
      let dejaVue = false;
      try { dejaVue = localStorage.getItem(CLE_SHEET_PREMIERE_CANDIDATURE) === '1'; } catch { dejaVue = true; }
      if (!dejaVue) {
        setPremiereCandidature({ missionId, mission });
        return;
      }
    }

    setLocalStack((prev) => prev.filter((m) => m.mission_id !== missionId));
    swipeMut.mutate({ missionId, direction: dir, mission });
  }, [swipeMut, localStack]);

  const confirmerPremiereCandidature = useCallback(() => {
    setPremiereCandidature((cur) => {
      if (cur) {
        try { localStorage.setItem(CLE_SHEET_PREMIERE_CANDIDATURE, '1'); } catch { /* ignore */ }
        setLocalStack((prev) => prev.filter((m) => m.mission_id !== cur.missionId));
        swipeMut.mutate({ missionId: cur.missionId, direction: 'LIKE', mission: cur.mission });
      }
      return null;
    });
  }, [swipeMut]);

  // Confirmation du choix de contrat (rejoue le swipe avec p_choix_contrat).
  const confirmerChoixContrat = useCallback((value: string) => {
    setChoixContrat((cur) => {
      if (cur) {
        swipeMut.mutate({
          missionId: cur.missionId,
          direction: cur.direction,
          mission: cur.mission,
          choixContrat: value,
        });
      }
      return cur;
    });
  }, [swipeMut]);

  const handleGestureSwipe = useCallback((direction: SwipeDirection, itemKey: string) => {
    handleSwipe(direction === 'right' ? 'LIKE' : 'DISLIKE', itemKey);
  }, [handleSwipe]);

  const stackItems = useMemo(
    () =>
      localStack.map((m) => ({
        key: m.mission_id,
        content: <CardMissionSwipe mission={m} onTap={() => ouvrirDetail(m)} />,
      })),
    [localStack, ouvrirDetail],
  );

  const topMission = localStack[0];
  const missionsSauvegardees = sauvegardees ?? [];

  return (
    <div className="max-w-md mx-auto w-full flex flex-col flex-1 min-h-0">
      <div className="flex-1 min-h-0 flex flex-col">
        <div className="flex-1 min-h-0 flex flex-col py-2 overflow-y-auto">
          {isLoading ? (
            <div className="m-auto flex flex-col items-center gap-3 text-jolene-bubblegum">
              <Loader2 className="h-8 w-8 animate-spin" />
              <span className="text-sm">Calcul de ton matching...</span>
            </div>
          ) : localStack.length === 0 ? (
            <div className="m-auto w-full space-y-4">
            {(data?.length ?? 0) > 0 ? (
              /* Le soignant a swipé toute la pile du jour */
              <EmptyState
                mascotte="happy"
                variant="success"
                titre="Tu as tout vu pour aujourd'hui"
                description="Crée une alerte : tu recevras un email dès qu'une nouvelle mission correspondant à ton profil est publiée."
                cta={{
                  label: '🔔 Me prévenir des prochaines missions',
                  onClick: onCreerAlerte,
                }}
                ctaSecondaire={{
                  label: 'Voir les missions en liste',
                  onClick: onBasculerListe,
                }}
              />
            ) : (
              /* Cas réel pré-traction : 0 mission sur le marché — l'état vide recrute */
              <EmptyState
                mascotte="thinking"
                titre="Aucune mission près de chez toi pour l'instant"
                description="Crée une alerte : tu recevras un email dès qu'une mission correspondant à ton profil est publiée."
                cta={{
                  label: "🔔 Me prévenir dès qu'une mission arrive",
                  onClick: onCreerAlerte,
                }}
                ctaSecondaire={{
                  label: 'Voir la recherche en liste',
                  onClick: onBasculerListe,
                }}
              />
            )}

            {/* D1 anti-fuite du favori : re-surfacer les missions sauvegardées
                en fin de deck — « intéressée, mais je vérifie mon planning ». */}
            {missionsSauvegardees.length > 0 && (
              <section className="rounded-2xl border border-jolene-butter-400/50 bg-jolene-cloud p-4">
                <h3 className="text-sm font-bold text-foreground flex items-center gap-1.5 mb-2">
                  <Star className="h-4 w-4 text-jolene-butter-600 fill-jolene-butter-400" aria-hidden="true" />
                  Tes missions sauvegardées ({missionsSauvegardees.length})
                </h3>
                <div className="space-y-1.5">
                  {missionsSauvegardees.slice(0, 5).map((m: any) => (
                    <button
                      key={m.id}
                      type="button"
                      onClick={() => navigate(`/soignant/missions/${m.id}`)}
                      className="w-full flex items-center gap-2 rounded-xl border border-jolene-rose-100 bg-card px-3 py-2.5 text-left hover:border-jolene-rose-300 transition-colors min-h-[44px]"
                    >
                      <span className="flex-1 min-w-0">
                        <span className="block text-sm font-medium text-foreground truncate">{m.intitule}</span>
                        <span className="block text-xs text-muted-foreground truncate">
                          {formatDateMission(m)} · {formatDureeCompacte(m)}
                        </span>
                      </span>
                      <ChevronRight className="h-4 w-4 text-primary shrink-0" aria-hidden="true" />
                    </button>
                  ))}
                </div>
              </section>
            )}
            </div>
          ) : (
            <StackCards className="flex-1 min-h-0" items={stackItems} onSwipe={handleGestureSwipe} />
          )}
        </div>

        {topMission && (
          <div className="shrink-0">
            <BoutonsActionSwipe
              onDislike={() => handleSwipe('DISLIKE', topMission.mission_id)}
              onLike={() => handleSwipe('LIKE', topMission.mission_id)}
              onFavori={() => handleSwipe('FAVORI', topMission.mission_id)}
              disabled={swipeMut.isPending}
            />
          </div>
        )}
      </div>

      <ModalDetailMissionSwipe
        mission={detailMission}
        open={detailOpen}
        onOpenChange={setDetailOpen}
        onPostuler={() => {
          setDetailOpen(false);
          if (detailMission) handleSwipe('LIKE', detailMission.mission_id);
        }}
        onSuivant={() => {
          setDetailOpen(false);
          if (detailMission) handleSwipe('DISLIKE', detailMission.mission_id);
        }}
      />

      {/* Sheet pédagogique — une seule fois, à la toute première candidature */}
      <DialogResponsive
        open={premiereCandidature !== null}
        onOpenChange={(o) => { if (!o) setPremiereCandidature(null); }}
      >
        <DialogResponsiveContent maxWidth="sm">
          <DialogResponsiveHeader>
            <DialogResponsiveTitle>Ta première candidature 🎉</DialogResponsiveTitle>
            <DialogResponsiveDescription>
              Ici, candidater est un engagement — pas un simple like.
            </DialogResponsiveDescription>
          </DialogResponsiveHeader>
          <DialogResponsiveBody>
            <div className="space-y-3 text-sm text-foreground">
              <p>
                <strong>L'établissement peut t'accepter directement</strong> — si c'est le cas,
                la mission est <strong>confirmée</strong> : il compte sur toi auprès de ses patients.
              </p>
              <ul className="space-y-1.5 text-muted-foreground text-xs list-disc ml-4">
                <li>Tu peux retirer ta candidature librement tant qu'elle n'est pas acceptée.</li>
                <li>Après acceptation, une annulation tardive impacte ton score de fiabilité.</li>
              </ul>
            </div>
          </DialogResponsiveBody>
          <DialogResponsiveFooter>
            <BoutonY2K variant="ghost" onClick={() => setPremiereCandidature(null)}>
              Pas maintenant
            </BoutonY2K>
            <BoutonY2K onClick={confirmerPremiereCandidature}>
              J'ai compris — envoyer ma candidature
            </BoutonY2K>
          </DialogResponsiveFooter>
        </DialogResponsiveContent>
      </DialogResponsive>

      <ChoixContratDialog
        open={choixContrat !== null}
        options={choixContrat?.options ?? []}
        loading={swipeMut.isPending}
        proposerMemorisation
        onChoose={confirmerChoixContrat}
        onClose={() => setChoixContrat(null)}
      />
    </div>
  );
}
