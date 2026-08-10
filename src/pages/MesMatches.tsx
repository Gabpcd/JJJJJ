/**
 * MesMatches — Sprint 13-C PR 5
 *
 * Page soignant /soignant/mes-matches : liste candidatures ASSIGNEE/EN_COURS/
 * TERMINEE issues de la découverte swipe + stats engagement. La valeur
 * SUPER_LIKE ne subsiste que pour la compatibilité des anciennes données.
 */
import { useState, useMemo } from 'react';
import { useQuery } from '@tanstack/react-query';
import { useNavigate } from 'react-router-dom';
import { useOuvrirConversation } from '@/hooks/useOuvrirConversation';
import { Calendar, Euro, MessageCircle, Sparkles, TrendingUp } from 'lucide-react';
import { usePageTitle } from '@/hooks/usePageTitle';
import { LayoutApp } from '@/components/LayoutApp';
import { CardY2K, CardY2KHeader, CardY2KTitle, CardY2KContent } from '@/components/y2k/CardY2K';
import { CarteKPIY2K } from '@/components/y2k/CarteKPIY2K';
import { BadgeY2K } from '@/components/y2k/BadgeY2K';
import { BoutonY2K } from '@/components/y2k/BoutonY2K';
import { EmptyState } from '@/components/ui/EmptyState';
import { supabase } from '@/integrations/supabase/client';
import { Loader2 } from 'lucide-react';

type StatutFilter = 'tous' | 'en_cours' | 'terminees';

interface MatchPayload {
  candidature_id: string;
  mission_id: string;
  mission_intitule: string | null;
  mission_debut_le: string | null;
  mission_fin_le: string | null;
  mission_taux_horaire_base: number | null;
  mission_statut: string;
  etablissement_id: string;
  etablissement_nom: string;
  etablissement_ville: string | null;
  swipe_direction: 'LIKE' | 'SUPER_LIKE';
  candidature_statut: string;
  updated_at: string;
}

interface MesMatchesResponse {
  matches: MatchPayload[];
  stats: {
    total_swipes: number;
    total_likes: number;
    total_matches: number;
    taux_match: number;
  };
}

function formatDate(iso: string | null): string {
  if (!iso) return '—';
  try {
    return new Date(iso).toLocaleDateString('fr-FR', { day: 'numeric', month: 'short', year: 'numeric' });
  } catch {
    return '—';
  }
}

export default function MesMatches() {
  usePageTitle('Mes matches');
  const navigate = useNavigate();
  const ouvrirConversation = useOuvrirConversation('/soignant/messagerie');
  const [filtre, setFiltre] = useState<StatutFilter>('tous');

  const { data, isLoading } = useQuery({
    queryKey: ['mes-matches'],
    queryFn: async () => {
      const { data, error } = await supabase.rpc('fn_mes_matches' as any);
      if (error) throw error;
      return data as MesMatchesResponse;
    },
    staleTime: 60_000,
  });

  const matches = data?.matches ?? [];
  const stats = data?.stats;

  const matchesFiltres = useMemo(() => {
    if (filtre === 'en_cours') return matches.filter((m) => m.candidature_statut !== 'TERMINEE');
    if (filtre === 'terminees') return matches.filter((m) => m.candidature_statut === 'TERMINEE');
    return matches;
  }, [matches, filtre]);

  return (
    <LayoutApp role="SOIGNANT">
      <div className="container mx-auto px-4 pt-4 pb-6 max-w-2xl">
        <header className="mb-5">
          <h1 className="text-2xl font-bold text-jolene-midnight">Mes matches</h1>
          <p className="text-sm text-jolene-bubblegum">
            Vos candidatures acceptées issues de la découverte swipe.
          </p>
        </header>

        {/* Stats engagement */}
        {stats && (
          <section className="grid grid-cols-3 gap-3 mb-6" aria-label="Statistiques engagement">
            <CarteKPIY2K
              icone={<Sparkles className="h-4 w-4" />}
              label="Swipes"
              valeur={stats.total_swipes}
              variant="default"
            />
            <CarteKPIY2K
              icone={<TrendingUp className="h-4 w-4" />}
              label="Matches"
              valeur={stats.total_matches}
              variant="holographic"
            />
            <CarteKPIY2K
              icone={<Euro className="h-4 w-4" />}
              label="Taux match"
              valeur={`${stats.taux_match}%`}
              contexte={`sur ${stats.total_likes} likes`}
              variant="soft"
            />
          </section>
        )}

        {/* Filtres */}
        <div className="flex gap-2 mb-4 overflow-x-auto pb-1">
          {(
            [
              { v: 'tous', label: 'Tous' },
              { v: 'en_cours', label: 'En cours' },
              { v: 'terminees', label: 'Terminées' },
            ] as const
          ).map(({ v, label }) => (
            <BoutonY2K
              key={v}
              size="sm"
              variant={filtre === v ? 'primary' : 'secondary'}
              onClick={() => setFiltre(v)}
              className="whitespace-nowrap"
            >
              {label}
            </BoutonY2K>
          ))}
        </div>

        {/* Liste matches */}
        {isLoading ? (
          <div className="flex flex-col items-center gap-3 py-12 text-jolene-bubblegum">
            <Loader2 className="h-8 w-8 animate-spin" />
            <span className="text-sm">Chargement de vos matches...</span>
          </div>
        ) : matchesFiltres.length === 0 ? (
          <EmptyState
            mascotte="thinking"
            variant="info"
            titre={filtre === 'tous' ? 'Aucun match pour le moment' : 'Rien dans cette catégorie'}
            description={
              filtre === 'tous'
                ? 'Continuez à swiper pour découvrir des missions qui vous correspondent !'
                : 'Aucune candidature dans cette catégorie pour le moment.'
            }
            cta={{
              label: 'Découvrir des missions',
              onClick: () => navigate('/soignant/recherche-missions?vue=swipe'),
            }}
          />
        ) : (
          <ul className="space-y-3">
            {matchesFiltres.map((m) => (
              <li key={m.candidature_id}>
                <CardY2K noPadding>
                  <CardY2KHeader className="pb-2">
                    <div className="flex items-start gap-2">
                      <div className="flex-1 min-w-0">
                        <CardY2KTitle className="text-base">{m.mission_intitule || 'Mission'}</CardY2KTitle>
                        <p className="text-sm text-jolene-bubblegum mt-0.5">
                          {m.etablissement_nom}
                          {m.etablissement_ville && ` · ${m.etablissement_ville}`}
                        </p>
                      </div>
                      <div className="flex flex-col gap-1 items-end shrink-0">
                        {m.swipe_direction === 'SUPER_LIKE' && (
                          <BadgeY2K variant="premium" size="sm" icone={<Sparkles className="h-3 w-3" />}>
                            Priorité historique
                          </BadgeY2K>
                        )}
                        <BadgeY2K
                          variant={
                            m.candidature_statut === 'TERMINEE'
                              ? 'success'
                              : m.candidature_statut === 'EN_COURS'
                                ? 'info'
                                : 'warning'
                          }
                          size="sm"
                        >
                          {m.candidature_statut}
                        </BadgeY2K>
                      </div>
                    </div>
                  </CardY2KHeader>
                  <CardY2KContent>
                    <div className="flex flex-wrap gap-3 text-sm text-jolene-midnight mb-3">
                      <span className="inline-flex items-center gap-1">
                        <Calendar className="h-3.5 w-3.5 text-jolene-rose-600" aria-hidden="true" />
                        {formatDate(m.mission_debut_le)}
                      </span>
                      {m.mission_taux_horaire_base != null && (
                        <span className="inline-flex items-center gap-1">
                          <Euro className="h-3.5 w-3.5 text-jolene-cyan-700" aria-hidden="true" />
                          {m.mission_taux_horaire_base} €/h
                        </span>
                      )}
                    </div>
                    <div className="flex flex-wrap gap-2">
                      <BoutonY2K
                        size="sm"
                        variant="primary"
                        onClick={() => navigate(`/soignant/missions/${m.mission_id}`)}
                      >
                        Voir la mission
                      </BoutonY2K>
                      <BoutonY2K
                        size="sm"
                        variant="ghost"
                        onClick={() => m.etablissement_id
                          ? ouvrirConversation(m.etablissement_id, m.mission_id, true)
                          : navigate('/soignant/messagerie')}
                        iconeGauche={<MessageCircle className="h-4 w-4" />}
                      >
                        Conversation
                      </BoutonY2K>
                    </div>
                  </CardY2KContent>
                </CardY2K>
              </li>
            ))}
          </ul>
        )}
      </div>
    </LayoutApp>
  );
}
