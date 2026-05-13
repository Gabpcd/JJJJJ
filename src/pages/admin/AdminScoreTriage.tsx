import { useEffect, useMemo, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { Loader2, Search, Eye, MessageSquare, Award } from 'lucide-react';
import { LayoutAdmin } from '@/components/LayoutAdmin';
import { supabase } from '@/integrations/supabase/client';
import { useNotification } from '@/contexts/NotificationContext';
import { usePageTitle } from '@/hooks/usePageTitle';

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
  derniere_maj: string | null;
}

function niveauDepuisScore(score: number): LigneScore['niveau'] {
  if (score >= 85) return 'PLATINE';
  if (score >= 70) return 'OR';
  if (score >= 50) return 'ARGENT';
  return 'BRONZE';
}

function badgeNiveauClasses(niveau: LigneScore['niveau']): string {
  switch (niveau) {
    case 'PLATINE':
      return 'bg-indigo-100 text-indigo-700 border-indigo-200';
    case 'OR':
      return 'bg-amber-100 text-amber-700 border-amber-200';
    case 'ARGENT':
      return 'bg-slate-100 text-slate-700 border-slate-200';
    case 'BRONZE':
    default:
      return 'bg-orange-100 text-orange-700 border-orange-200';
  }
}

export default function AdminScoreTriage() {
  usePageTitle('Triage scores');
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
        const { data: soignants, error: errS } = await (supabase as any)
          .from('scores_soignants')
          .select('soignant_id, score_global, derniere_maj, profils(nom, prenom, email)')
          .order('score_global', { ascending: true })
          .limit(500);
        if (errS) throw errS;

        const { data: etabs, error: errE } = await (supabase as any)
          .from('scores_etablissements')
          .select('etablissement_id, score_global, derniere_maj, etablissements(raison_sociale, email)')
          .order('score_global', { ascending: true })
          .limit(500);
        if (errE) throw errE;

        const mapS: LigneScore[] = (soignants ?? []).map((s: any) => {
          const score = Number(s.score_global ?? 0);
          return {
            user_id: s.soignant_id,
            type: 'SOIGNANT' as const,
            nom: `${s.profils?.prenom ?? ''} ${s.profils?.nom ?? ''}`.trim() || '(sans nom)',
            email: s.profils?.email ?? '',
            score,
            niveau: niveauDepuisScore(score),
            derniere_maj: s.derniere_maj,
          };
        });

        const mapE: LigneScore[] = (etabs ?? []).map((e: any) => {
          const score = Number(e.score_global ?? 0);
          return {
            user_id: e.etablissement_id,
            type: 'ETAB' as const,
            nom: e.etablissements?.raison_sociale ?? '(sans nom)',
            email: e.etablissements?.email ?? '',
            score,
            niveau: niveauDepuisScore(score),
            derniere_maj: e.derniere_maj,
          };
        });

        setLignes([...mapS, ...mapE].sort((a, b) => a.score - b.score));
      } catch (err: any) {
        afficherNotification({
          type: 'erreur',
          message: `Erreur de chargement : ${err?.message ?? 'Impossible de charger les scores.'}`,
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
    <LayoutAdmin>
      <div className="max-w-7xl mx-auto p-4 sm:p-6 space-y-6">
        <header className="flex items-center gap-3">
          <Award className="w-7 h-7 text-amber-600" aria-hidden />
          <div>
            <h1 className="text-2xl font-bold">Triage des scores</h1>
            <p className="text-sm text-muted-foreground">
              Vue centralisée soignants + établissements pour identifier rapidement les comptes à risque.
            </p>
          </div>
        </header>

        <div className="flex flex-col gap-3 md:flex-row md:items-center md:justify-between">
          <div className="relative flex-1 max-w-md">
            <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-muted-foreground" />
            <input
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
              <option value="WARNING">Warnings (&lt;50)</option>
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
        ) : lignesFiltrees.length === 0 ? (
          <div className="text-center py-16 text-sm text-muted-foreground border rounded-md">
            Aucun compte ne correspond aux filtres sélectionnés.
          </div>
        ) : (
          <div className="overflow-x-auto border rounded-md">
            <table className="w-full text-sm">
              <thead className="bg-slate-50 text-left">
                <tr>
                  <th className="px-3 py-2 font-medium">Type</th>
                  <th className="px-3 py-2 font-medium">Nom</th>
                  <th className="px-3 py-2 font-medium">Email</th>
                  <th className="px-3 py-2 font-medium">Score</th>
                  <th className="px-3 py-2 font-medium">Niveau</th>
                  <th className="px-3 py-2 font-medium text-right">Actions</th>
                </tr>
              </thead>
              <tbody>
                {lignesFiltrees.map((l) => (
                  <tr key={`${l.type}-${l.user_id}`} className="border-t hover:bg-slate-50">
                    <td className="px-3 py-2">
                      <span className="px-2 py-0.5 text-xs rounded bg-slate-100">
                        {l.type === 'SOIGNANT' ? 'Soignant' : 'Étab'}
                      </span>
                    </td>
                    <td className="px-3 py-2 font-medium">{l.nom}</td>
                    <td className="px-3 py-2 text-muted-foreground">{l.email}</td>
                    <td className="px-3 py-2 font-mono">{l.score.toFixed(1)}</td>
                    <td className="px-3 py-2">
                      <span className={`px-2 py-0.5 text-xs rounded border ${badgeNiveauClasses(l.niveau)}`}>
                        {l.niveau}
                      </span>
                    </td>
                    <td className="px-3 py-2">
                      <div className="flex justify-end gap-2">
                        <button
                          type="button"
                          onClick={() => ouvrirProfil(l)}
                          className="inline-flex items-center gap-1 px-2 py-1 text-xs border rounded hover:bg-slate-100"
                          aria-label={`Voir le profil de ${l.nom}`}
                        >
                          <Eye className="w-3.5 h-3.5" /> Voir
                        </button>
                        <button
                          type="button"
                          onClick={ouvrirMessagerie}
                          className="inline-flex items-center gap-1 px-2 py-1 text-xs border rounded hover:bg-slate-100"
                          aria-label={`Messagerie ${l.nom}`}
                        >
                          <MessageSquare className="w-3.5 h-3.5" /> Message
                        </button>
                      </div>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>
    </LayoutAdmin>
  );
}
