import { useEffect, useMemo, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { Loader2, Search, Eye, MessageSquare } from 'lucide-react';
import { EmptyState } from '@/components/ui/EmptyState';
import { TableOuCartes, type ColonneTableau } from '@/components/ui/TableOuCartes';
import { supabase } from '@/integrations/supabase/client';
import { useNotification } from '@/contexts/NotificationContext';
import { BoutonY2K } from '@/components/y2k/BoutonY2K';
import { BadgeY2K } from '@/components/y2k/BadgeY2K';

/**
 * Page admin /admin/scores (Sprint 7 PR 6 - P2 §14).
 *
 * Tableau global centralisé : soignants + établissements avec leur score,
 * niveau de fiabilité (BRONZE / ARGENT / OR / PLATINE), filtres par type + niveau,
 * et actions rapides (voir profil, messagerie).
 *
 * Par défaut filtre sur les scores < 50 (warnings) pour faciliter le triage.
 */

type TypeFiltre = 'TOUS' | 'SOIGNANT' | 'ETAB';
type NiveauFiltre = 'TOUS' | 'WARNING' | 'BRONZE' | 'ARGENT' | 'OR' | 'PLATINE';

interface LigneScore {
  user_id: string;
  type: 'SOIGNANT' | 'ETAB';
  nom: string;
  email: string;
  score: number;
  niveau: 'BRONZE' | 'ARGENT' | 'OR' | 'PLATINE';
}

function niveauDepuisScore(score: number): LigneScore['niveau'] {
  if (score >= 85) return 'PLATINE';
  if (score >= 70) return 'OR';
  if (score >= 50) return 'ARGENT';
  return 'BRONZE';
}

function badgeNiveauVariant(niveau: LigneScore['niveau']): 'premium' | 'warning' | 'info' | 'success' {
  switch (niveau) {
    case 'PLATINE': return 'premium';
    case 'OR': return 'warning';
    case 'ARGENT': return 'info';
    case 'BRONZE':
    default: return 'success';
  }
}

/* Session D-bis : contenu embarqué comme onglet « Triage des scores » de
   /admin/reclamations (l'ancienne route /admin/scores redirige). */
export function ScoreTriageContent() {
  const navigate = useNavigate();
  const { afficherNotification } = useNotification();
  const [lignes, setLignes] = useState<LigneScore[]>([]);
  const [loading, setLoading] = useState(true);
  const [recherche, setRecherche] = useState('');
  const [filtreType, setFiltreType] = useState<TypeFiltre>('TOUS');
  const [filtreNiveau, setFiltreNiveau] = useState<NiveauFiltre>('WARNING');

  useEffect(() => {
    const charger = async () => {
      setLoading(true);
      try {
        // Source de vérité : RPC admin unifiée (soignants.score_fiabilite +
        // etablissements.score_qualite). Cf. fn_admin_triage_scores.
        const { data, error } = await supabase.rpc('fn_admin_triage_scores' as any);
        if (error) throw error;
        if ((data as any)?.error) throw new Error((data as any).error);

        const lignesRpc = ((data as any)?.lignes ?? []) as Array<{
          user_id: string; type: 'SOIGNANT' | 'ETAB'; nom: string | null; email: string; score: number;
        }>;

        const mapped: LigneScore[] = lignesRpc.map((l) => {
          const score = Number(l.score ?? 0);
          return {
            user_id: l.user_id,
            type: l.type,
            nom: l.nom || '(sans nom)',
            email: l.email ?? '',
            score,
            niveau: niveauDepuisScore(score),
          };
        });

        setLignes(mapped.sort((a, b) => a.score - b.score));
      } catch (err: any) {
        console.error('Erreur chargement triage scores :', err);
        afficherNotification({
          type: 'erreur',
          message: 'Impossible de charger les scores. Veuillez réessayer plus tard.',
        });
      } finally {
        setLoading(false);
      }
    };
    charger();
  }, [afficherNotification]);

  const lignesFiltrees = useMemo(() => {
    const q = recherche.trim().toLowerCase();
    return lignes.filter((l) => {
      if (filtreType !== 'TOUS' && l.type !== filtreType) return false;
      if (filtreNiveau === 'WARNING' && l.score >= 50) return false;
      if (filtreNiveau !== 'TOUS' && filtreNiveau !== 'WARNING' && l.niveau !== filtreNiveau) return false;
      if (q && !l.nom.toLowerCase().includes(q) && !l.email.toLowerCase().includes(q)) return false;
      return true;
    });
  }, [lignes, recherche, filtreType, filtreNiveau]);

  const ouvrirProfil = (l: LigneScore) => {
    if (l.type === 'SOIGNANT') navigate(`/admin/utilisateurs/${l.user_id}`);
    else navigate(`/admin/utilisateurs/${l.user_id}`);
  };

  const ouvrirMessagerie = () => {
    navigate('/admin/messagerie');
  };

  return (
      <div className="space-y-6">
        <p className="text-sm text-muted-foreground">
          Vue centralisée soignants + établissements pour identifier rapidement les comptes à risque.
        </p>

        <div className="flex flex-col gap-3 md:flex-row md:items-center md:justify-between">
          <div className="relative flex-1 max-w-md">
            <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-muted-foreground" />
            <input
              aria-label="Rechercher un compte à trier"
              type="search"
              value={recherche}
              onChange={(e) => setRecherche(e.target.value)}
              placeholder="Rechercher nom, email…"
              className="w-full pl-10 pr-3 py-2 border rounded-md text-sm"
            />
          </div>
          <div className="flex flex-wrap gap-2">
            <select
              value={filtreType}
              onChange={(e) => setFiltreType(e.target.value as TypeFiltre)}
              className="border rounded-md px-3 py-2 text-sm"
              aria-label="Filtre type compte"
            >
              <option value="TOUS">Tous types</option>
              <option value="SOIGNANT">Soignants</option>
              <option value="ETAB">Établissements</option>
            </select>
            <select
              value={filtreNiveau}
              onChange={(e) => setFiltreNiveau(e.target.value as NiveauFiltre)}
              className="border rounded-md px-3 py-2 text-sm"
              aria-label="Filtre niveau"
            >
              <option value="WARNING">À risque (&lt;50)</option>
              <option value="TOUS">Tous niveaux</option>
              <option value="BRONZE">Bronze</option>
              <option value="ARGENT">Argent</option>
              <option value="OR">Or</option>
              <option value="PLATINE">Platine</option>
            </select>
          </div>
        </div>

        {loading ? (
          <div className="flex items-center justify-center py-16">
            <Loader2 className="w-6 h-6 animate-spin text-muted-foreground" />
          </div>
        ) : (() => {
          const colonnes: ColonneTableau<LigneScore>[] = [
            { cle: 'type', titre: 'Type' },
            { cle: 'nom', titre: 'Nom' },
            { cle: 'email', titre: 'Email' },
            { cle: 'score', titre: 'Score' },
            { cle: 'niveau', titre: 'Niveau' },
            { cle: 'actions', titre: 'Actions', align: 'right' },
          ];

          const typeBadge = (l: LigneScore) => (
            <BadgeY2K variant="info" size="sm">
              {l.type === 'SOIGNANT' ? 'Soignant' : 'Étab'}
            </BadgeY2K>
          );
          const niveauBadge = (l: LigneScore) => (
            <BadgeY2K variant={badgeNiveauVariant(l.niveau)} size="sm">
              {l.niveau}
            </BadgeY2K>
          );

          return (
            <TableOuCartes
              colonnes={colonnes}
              donnees={lignesFiltrees}
              getId={(l) => `${l.type}-${l.user_id}`}
              onClickLigne={(l) => ouvrirProfil(l)}
              etatVide={<EmptyState titre="Aucun compte trouvé" description="Aucun compte ne correspond aux filtres sélectionnés." />}
              renduCellule={(l, col) => {
                switch (col.cle) {
                  case 'type':
                    return typeBadge(l);
                  case 'nom':
                    return <span className="font-medium">{l.nom}</span>;
                  case 'email':
                    return <span className="text-muted-foreground">{l.email}</span>;
                  case 'score':
                    return <span className="font-mono">{l.score.toFixed(1)}</span>;
                  case 'niveau':
                    return niveauBadge(l);
                  case 'actions':
                    return (
                      <div className="flex justify-end gap-2" onClick={(e) => e.stopPropagation()}>
                        <BoutonY2K
                          variant="secondary"
                          size="sm"
                          onClick={() => ouvrirProfil(l)}
                          aria-label={`Voir le profil de ${l.nom}`}
                          iconeGauche={<Eye className="w-3.5 h-3.5" />}
                        >
                          Voir
                        </BoutonY2K>
                        <BoutonY2K
                          variant="ghost"
                          size="sm"
                          onClick={ouvrirMessagerie}
                          aria-label={`Messagerie ${l.nom}`}
                          iconeGauche={<MessageSquare className="w-3.5 h-3.5" />}
                        >
                          Message
                        </BoutonY2K>
                      </div>
                    );
                  default:
                    return null;
                }
              }}
              renduCarte={(l) => (
                <div className="space-y-2">
                  <div className="flex items-start justify-between gap-2">
                    <div className="min-w-0">
                      <div className="flex items-center gap-2 mb-1">
                        {typeBadge(l)}
                        {niveauBadge(l)}
                      </div>
                      <p className="font-semibold text-foreground truncate">{l.nom}</p>
                      <p className="text-xs text-muted-foreground truncate">{l.email}</p>
                    </div>
                    <p className="font-mono text-lg font-bold tabular-nums shrink-0">{l.score.toFixed(1)}</p>
                  </div>
                  <div className="grid grid-cols-2 gap-2 pt-2 border-t border-border" onClick={(e) => e.stopPropagation()}>
                    <BoutonY2K
                      variant="secondary"
                      size="sm"
                      onClick={() => ouvrirProfil(l)}
                      iconeGauche={<Eye className="w-3.5 h-3.5" />}
                      className="w-full"
                    >
                      Voir le profil
                    </BoutonY2K>
                    <BoutonY2K
                      variant="ghost"
                      size="sm"
                      onClick={ouvrirMessagerie}
                      iconeGauche={<MessageSquare className="w-3.5 h-3.5" />}
                      className="w-full"
                    >
                      Message
                    </BoutonY2K>
                  </div>
                </div>
              )}
            />
          );
        })()}
      </div>
  );
}
