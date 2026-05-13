import { useState, useEffect } from 'react';
import { usePageTitle } from '@/hooks/usePageTitle';
import { LayoutAdmin } from '@/components/LayoutAdmin';
import { ChargementPage } from '@/components/ChargementPage';
import { supabase } from '@/integrations/supabase/client';
import { Search, RefreshCw, ChevronLeft, ChevronRight, Shield, Clock } from 'lucide-react';
import { format } from 'date-fns';
import { fr } from 'date-fns/locale';

const ACTIONS_COLORS: Record<string, string> = {
  'RGPD_SUPPRESSION_COMPTE': 'bg-destructive/10 text-destructive',
  'RGPD_EXPORT_DONNEES': 'bg-info/10 text-info',
  'DOCUMENT_VERIFICATION_AUTO': 'bg-primary/10 text-primary',
  'GPS_CONSENTEMENT_ACTIVE': 'bg-success/10 text-success',
  'GPS_CONSENTEMENT_RETIRE': 'bg-warning/10 text-warning',
  'SMS_CONSENTEMENT_ACTIVE': 'bg-success/10 text-success',
  'SMS_CONSENTEMENT_RETIRE': 'bg-warning/10 text-warning',
  'DONNEES_PERSO_MODIFICATION': 'bg-info/10 text-info',
  'DONNEES_PERSO_CONSULTATION': 'bg-muted text-muted-foreground',
  // Sprint 6 PR 11 — anti-triche pointage filtres (Fix P1-15)
  'POINTAGE': 'bg-warning/10 text-warning',
  'ADMIN_ACTION': 'bg-primary/10 text-primary',
};

// Sprint 6 PR 11 — Evenements anti-triche dans details->>'evenement' (Fix P1-15)
const EVENEMENTS_ANTITRICHE = [
  'TELEPORTATION_DETECTED',
  'POINTAGE_INCOHERENT',
  'QR_SCAN_GPS_ELOIGNE',
  'GPS_SPOOFING_DETECTED',
  'MOCK_GPS_DETECTED',
  'ALERTE_POINTAGE_TRAITEE',
];

const PAGE_SIZE = 50;

export default function AdminAuditLogs() {
  usePageTitle('Journaux d\'audit');
  const [loading, setLoading] = useState(true);
  const [logs, setLogs] = useState<any[]>([]);
  const [page, setPage] = useState(0);
  const [hasMore, setHasMore] = useState(true);
  const [search, setSearch] = useState('');
  const [filterAction, setFilterAction] = useState('');
  const [filterType, setFilterType] = useState('');
  const [filterEvenement, setFilterEvenement] = useState('');

  const charger = async () => {
    setLoading(true);
    let query = supabase
      .from('journaux_audit')
      .select('*')
      .order('cree_le', { ascending: false })
      .range(page * PAGE_SIZE, (page + 1) * PAGE_SIZE - 1);

    if (filterAction) query = query.eq('action', filterAction);
    if (filterType) query = query.eq('type_acteur', filterType);
    if (filterEvenement) {
      // Sprint 6 PR 11 — filtre événements anti-triche via details->>'evenement' jsonb
      query = (query as any).eq('details->>evenement', filterEvenement);
    }
    if (search) query = query.or(`action.ilike.%${search}%,type_ressource.ilike.%${search}%`);

    const { data } = await query;
    setLogs(data || []);
    setHasMore((data || []).length === PAGE_SIZE);
    setLoading(false);
  };

  useEffect(() => { charger(); }, [page, filterAction, filterType, filterEvenement]);

  const actions = ['RGPD_SUPPRESSION_COMPTE', 'RGPD_EXPORT_DONNEES', 'DOCUMENT_VERIFICATION_AUTO', 'GPS_CONSENTEMENT_ACTIVE', 'GPS_CONSENTEMENT_RETIRE', 'SMS_CONSENTEMENT_ACTIVE', 'SMS_CONSENTEMENT_RETIRE', 'DONNEES_PERSO_MODIFICATION', 'DONNEES_PERSO_CONSULTATION', 'POINTAGE', 'ADMIN_ACTION'];
  const types = ['SOIGNANT', 'ADMIN_ETABLISSEMENT', 'ADMIN_PLATEFORME', 'SYSTEME'];

  return (
    <LayoutAdmin>
      <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between mb-6 gap-3">
        <div>
          <h1 className="text-xl font-bold text-foreground flex items-center gap-2"><Shield className="h-5 w-5 text-primary" /> Journaux d'audit</h1>
          <p className="text-sm text-muted-foreground">Traçabilité RGPD — conservation 5 ans</p>
        </div>
        <button onClick={() => { setPage(0); charger(); }} className="p-2 rounded-lg bg-muted hover:bg-muted/80">
          <RefreshCw className="h-4 w-4 text-muted-foreground" />
        </button>
      </div>

      {/* Filters */}
      <div className="flex flex-wrap gap-3 mb-4">
        <div className="flex-1 min-w-[200px]">
          <div className="relative">
            <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground" />
            <input
              value={search}
              onChange={e => setSearch(e.target.value)}
              onKeyDown={e => e.key === 'Enter' && charger()}
              placeholder="Rechercher action ou ressource..."
              className="input-base pl-10"
            />
          </div>
        </div>
        <select value={filterAction} onChange={e => { setFilterAction(e.target.value); setPage(0); }} className="input-base w-auto">
          <option value="">Toutes les actions</option>
          {actions.map(a => <option key={a} value={a}>{a}</option>)}
        </select>
        <select value={filterType} onChange={e => { setFilterType(e.target.value); setPage(0); }} className="input-base w-auto">
          <option value="">Tous les acteurs</option>
          {types.map(t => <option key={t} value={t}>{t}</option>)}
        </select>
        <select value={filterEvenement} onChange={e => { setFilterEvenement(e.target.value); setPage(0); }} className="input-base w-auto" aria-label="Filtrer par événement anti-triche">
          <option value="">Tous les événements</option>
          {EVENEMENTS_ANTITRICHE.map(e => <option key={e} value={e}>{e}</option>)}
        </select>
      </div>

      {loading ? <ChargementPage /> : (
        <>
          <div className="card-base overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b border-border text-left">
                  <th className="py-2 px-3 font-medium text-muted-foreground">Date</th>
                  <th className="py-2 px-3 font-medium text-muted-foreground">Acteur</th>
                  <th className="py-2 px-3 font-medium text-muted-foreground">Action</th>
                  <th className="py-2 px-3 font-medium text-muted-foreground">Ressource</th>
                  <th className="py-2 px-3 font-medium text-muted-foreground">Détails</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-border/50">
                {logs.map(log => (
                  <tr key={log.id} className="hover:bg-muted/30 transition">
                    <td className="py-2.5 px-3 text-muted-foreground whitespace-nowrap">
                      <div className="flex items-center gap-1.5">
                        <Clock className="h-3 w-3" />
                        {log.cree_le ? format(new Date(log.cree_le), 'dd/MM/yy HH:mm', { locale: fr }) : '—'}
                      </div>
                    </td>
                    <td className="py-2.5 px-3">
                      <span className="text-xs font-mono text-muted-foreground">{log.type_acteur}</span>
                      <p className="text-[10px] text-muted-foreground/60 font-mono truncate max-w-[120px]">{log.acteur_id?.slice(0, 8)}...</p>
                    </td>
                    <td className="py-2.5 px-3">
                      <span className={`inline-flex items-center rounded-full px-2 py-0.5 text-[10px] font-semibold ${ACTIONS_COLORS[log.action] || 'bg-muted text-muted-foreground'}`}>
                        {log.action}
                      </span>
                    </td>
                    <td className="py-2.5 px-3 text-muted-foreground">
                      <span className="text-xs">{log.type_ressource}</span>
                      {log.id_ressource && <p className="text-[10px] text-muted-foreground/60 font-mono truncate max-w-[120px]">{log.id_ressource?.slice(0, 8)}...</p>}
                    </td>
                    <td className="py-2.5 px-3">
                      {log.details ? (
                        <details className="text-[10px]">
                          <summary className="cursor-pointer text-primary hover:underline">Voir</summary>
                          <pre className="mt-1 p-2 bg-muted/50 rounded text-[9px] text-muted-foreground overflow-x-auto max-w-[300px]">
                            {JSON.stringify(log.details, null, 2)}
                          </pre>
                        </details>
                      ) : <span className="text-muted-foreground/40">—</span>}
                    </td>
                  </tr>
                ))}
                {logs.length === 0 && (
                  <tr><td colSpan={5} className="py-12 text-center text-muted-foreground">Aucun log trouvé.</td></tr>
                )}
              </tbody>
            </table>
          </div>

          {/* Pagination */}
          <div className="flex items-center justify-between mt-4">
            <p className="text-xs text-muted-foreground">{logs.length} résultats — page {page + 1}</p>
            <div className="flex gap-2">
              <button onClick={() => setPage(p => Math.max(0, p - 1))} disabled={page === 0} className="p-2 rounded-lg bg-muted hover:bg-muted/80 disabled:opacity-30">
                <ChevronLeft className="h-4 w-4" />
              </button>
              <button onClick={() => setPage(p => p + 1)} disabled={!hasMore} className="p-2 rounded-lg bg-muted hover:bg-muted/80 disabled:opacity-30">
                <ChevronRight className="h-4 w-4" />
              </button>
            </div>
          </div>
        </>
      )}
    </LayoutAdmin>
  );
}
