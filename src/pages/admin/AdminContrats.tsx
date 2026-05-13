import { useEffect, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { Search, FileText, Loader2 } from 'lucide-react';
import { LayoutAdmin } from '@/components/LayoutAdmin';
import { ChargementPage } from '@/components/ChargementPage';
import { supabase } from '@/integrations/supabase/client';
import { useNotification } from '@/contexts/NotificationContext';
import { usePageTitle } from '@/hooks/usePageTitle';
import { useDebounce } from '@/hooks/useDebounce';
import { format } from 'date-fns';
import { fr } from 'date-fns/locale';

interface ContratLigne {
  id: string;
  numero_contrat: string | null;
  mission_id: string;
  mission_intitule: string;
  soignant_id: string;
  soignant_nom: string;
  etablissement_id: string;
  etablissement_nom: string;
  type_contrat: string;
  statut: string;
  hash_court: string | null;
  signature_soignant: boolean;
  signature_etablissement: boolean;
  signature_soignant_le: string | null;
  signature_etablissement_le: string | null;
  mode_signature: string | null;
  dpae_effectuee: boolean;
  dpae_numero: string | null;
  cree_le: string;
}

const STATUTS_FILTRES = ['Tous', 'EN_ATTENTE_SIGNATURE_SOIGNANT', 'EN_ATTENTE_SIGNATURE_ETAB', 'SIGNE_COMPLET', 'ANNULE', 'EXPIRE'] as const;

const PAR_PAGE = 50;

export default function AdminContrats() {
  usePageTitle('Admin · Contrats');
  const navigate = useNavigate();
  const { afficherNotification } = useNotification();
  const [loading, setLoading] = useState(true);
  const [contrats, setContrats] = useState<ContratLigne[]>([]);
  const [total, setTotal] = useState(0);
  const [page, setPage] = useState(0);
  const [filtreStatut, setFiltreStatut] = useState<string>('Tous');
  const [recherche, setRecherche] = useState('');
  const rechercheDeb = useDebounce(recherche, 400);

  async function charger() {
    setLoading(true);
    const { data, error } = await supabase.rpc('fn_admin_lister_contrats' as any, {
      p_filtre_statut: filtreStatut === 'Tous' ? null : filtreStatut,
      p_recherche: rechercheDeb.trim() || null,
      p_limit: PAR_PAGE,
      p_offset: page * PAR_PAGE,
    });
    if (error) {
      afficherNotification({ type: 'erreur', message: error.message });
      setLoading(false);
      return;
    }
    const result = data as any;
    if (!result?.success) {
      afficherNotification({ type: 'erreur', message: result?.error || 'Erreur.' });
      setLoading(false);
      return;
    }
    setContrats(result.contrats as ContratLigne[]);
    setTotal(result.total as number);
    setLoading(false);
  }

  useEffect(() => { charger(); }, [filtreStatut, rechercheDeb, page]);

  if (loading && contrats.length === 0) return <LayoutAdmin><ChargementPage /></LayoutAdmin>;

  const totalPages = Math.ceil(total / PAR_PAGE);

  return (
    <LayoutAdmin>
      <div className="mb-6">
        <h1 className="text-2xl font-bold text-foreground inline-flex items-center gap-2">
          <FileText className="h-6 w-6 text-primary" /> Contrats
        </h1>
        <p className="text-sm text-muted-foreground mt-1">
          Consultation de tous les contrats Jolene avec hash SHA-256 + certificat + audit trail.
        </p>
      </div>

      {/* Filtres */}
      <div className="flex flex-col sm:flex-row gap-2 mb-4">
        <div className="relative flex-1">
          <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground" />
          <input
            type="text"
            value={recherche}
            onChange={(e) => { setRecherche(e.target.value); setPage(0); }}
            placeholder="Numéro, mission, soignant, étab…"
            className="input-base pl-9"
          />
        </div>
        <select
          value={filtreStatut}
          onChange={(e) => { setFiltreStatut(e.target.value); setPage(0); }}
          className="input-base sm:w-64"
        >
          {STATUTS_FILTRES.map((s) => (
            <option key={s} value={s}>{s === 'Tous' ? 'Tous statuts' : s}</option>
          ))}
        </select>
      </div>

      <p className="text-xs text-muted-foreground mb-2">{total} contrat{total > 1 ? 's' : ''} {loading && <Loader2 className="inline h-3 w-3 animate-spin" />}</p>

      {/* Liste */}
      <div className="overflow-x-auto">
        <table className="w-full text-sm">
          <thead>
            <tr className="border-b border-border text-xs uppercase text-muted-foreground">
              <th className="text-left py-2 px-2">N° / Mission</th>
              <th className="text-left py-2 px-2">Soignant</th>
              <th className="text-left py-2 px-2">Établissement</th>
              <th className="text-left py-2 px-2">Type</th>
              <th className="text-left py-2 px-2">Statut</th>
              <th className="text-left py-2 px-2">Hash</th>
              <th className="text-left py-2 px-2">Signé le</th>
              <th className="text-left py-2 px-2">DPAE</th>
              <th className="text-right py-2 px-2">Actions</th>
            </tr>
          </thead>
          <tbody>
            {contrats.map((c) => (
              <tr key={c.id} className="border-b border-border hover:bg-muted/30">
                <td className="py-2 px-2">
                  <p className="font-mono text-xs">{c.numero_contrat || '—'}</p>
                  <p className="text-[11px] text-muted-foreground truncate max-w-[200px]">{c.mission_intitule}</p>
                </td>
                <td className="py-2 px-2 text-xs">{c.soignant_nom}</td>
                <td className="py-2 px-2 text-xs">{c.etablissement_nom}</td>
                <td className="py-2 px-2 text-xs">{c.type_contrat}</td>
                <td className="py-2 px-2">
                  <span className={`text-[11px] px-2 py-0.5 rounded-full font-medium ${
                    c.statut === 'SIGNE_COMPLET' ? 'bg-success/20 text-success' :
                    c.statut === 'ANNULE' ? 'bg-destructive/20 text-destructive' :
                    c.statut?.startsWith('EXPIRE') ? 'bg-muted text-muted-foreground' :
                    'bg-warning/20 text-warning'
                  }`}>
                    {c.statut}
                  </span>
                </td>
                <td className="py-2 px-2 text-xs font-mono text-muted-foreground">{c.hash_court || '—'}</td>
                <td className="py-2 px-2 text-[11px]">
                  {c.signature_soignant_le && c.signature_etablissement_le
                    ? format(new Date(Math.max(new Date(c.signature_soignant_le).getTime(), new Date(c.signature_etablissement_le).getTime())), 'dd MMM yyyy', { locale: fr })
                    : '—'}
                </td>
                <td className="py-2 px-2 text-xs">
                  {c.dpae_effectuee && c.dpae_numero ? (
                    <span className="text-success">✅ {c.dpae_numero.slice(0, 8)}…</span>
                  ) : c.type_contrat?.startsWith('CDD') || c.type_contrat === 'CDDU' || c.type_contrat === 'SALARIE' ? (
                    <span className="text-warning">⏳</span>
                  ) : <span className="text-muted-foreground">N/A</span>}
                </td>
                <td className="py-2 px-2 text-right">
                  <button
                    onClick={() => navigate(`/admin/contrats/${c.id}`)}
                    className="btn-secondary text-xs py-1 px-3"
                  >
                    Voir
                  </button>
                </td>
              </tr>
            ))}
            {contrats.length === 0 && !loading && (
              <tr>
                <td colSpan={9} className="py-8 text-center text-sm text-muted-foreground italic">
                  Aucun contrat ne correspond à ces critères.
                </td>
              </tr>
            )}
          </tbody>
        </table>
      </div>

      {/* Pagination */}
      {totalPages > 1 && (
        <div className="flex items-center justify-between mt-4">
          <p className="text-xs text-muted-foreground">Page {page + 1} / {totalPages}</p>
          <div className="flex gap-2">
            <button onClick={() => setPage((p) => Math.max(0, p - 1))} disabled={page === 0} className="btn-secondary text-xs disabled:opacity-50">Précédent</button>
            <button onClick={() => setPage((p) => Math.min(totalPages - 1, p + 1))} disabled={page >= totalPages - 1} className="btn-secondary text-xs disabled:opacity-50">Suivant</button>
          </div>
        </div>
      )}
    </LayoutAdmin>
  );
}
