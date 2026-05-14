import { useEffect, useState } from 'react';
import { Loader2, RefreshCw, XCircle, AlertTriangle, CheckCircle, Clock } from 'lucide-react';
import { LayoutAdmin } from '@/components/LayoutAdmin';
import { supabase } from '@/integrations/supabase/client';
import { useNotification } from '@/contexts/NotificationContext';
import { usePageTitle } from '@/hooks/usePageTitle';
import { EmptyState } from '@/components/ui/EmptyState';
import { format } from 'date-fns';
import { fr } from 'date-fns/locale';

interface Action {
  id: string;
  type_action: string;
  statut: 'PENDING' | 'PROCESSING' | 'DONE' | 'ERROR' | 'PENDING_AIFE' | 'CANCELLED';
  source: string;
  source_id: string | null;
  tentatives: number;
  derniere_erreur: string | null;
  next_retry_at: string | null;
  cree_le: string;
  traite_le: string | null;
  payload: Record<string, any>;
  resultat: Record<string, any> | null;
}

const STATUTS = ['PENDING', 'PROCESSING', 'DONE', 'ERROR', 'PENDING_AIFE', 'CANCELLED', 'TOUS'] as const;
type Filtre = typeof STATUTS[number];

const TYPES_ACTION = [
  'TOUS', 'STRIPE_REFUND_TOTAL', 'STRIPE_REFUND_PARTIEL', 'STRIPE_PAYMENT',
  'CHORUS_RECYCLER_FACTURE', 'DPAE_ANNULATION', 'EMAIL_NOTIF', 'PUSH_NOTIF',
  'AVOIR_PDF_GENERATION',
];

export default function AdminExternalisationsActions() {
  usePageTitle('Worker externalisations');
  const { afficherNotification } = useNotification();
  const [filtreStatut, setFiltreStatut] = useState<Filtre>('PENDING');
  const [filtreType, setFiltreType] = useState<string>('TOUS');
  const [actions, setActions] = useState<Action[]>([]);
  const [loading, setLoading] = useState(true);
  const [search, setSearch] = useState('');
  const [details, setDetails] = useState<Action | null>(null);

  async function charger() {
    setLoading(true);
    const { data, error } = await supabase.rpc('fn_admin_lister_externalisations' as any, {
      p_statut: filtreStatut === 'TOUS' ? null : filtreStatut,
      p_type_action: filtreType === 'TOUS' ? null : filtreType,
      p_limit: 200,
    });
    if (error) afficherNotification({ type: 'erreur', message: error.message });
    else if ((data as any)?.success) setActions(((data as any).actions || []) as Action[]);
    setLoading(false);
  }

  useEffect(() => { charger(); }, [filtreStatut, filtreType]);

  async function retry(id: string) {
    const { data, error } = await supabase.rpc('fn_admin_externalisation_retry' as any, { p_id: id });
    if (error || !(data as any)?.success) {
      afficherNotification({ type: 'erreur', message: 'Erreur retry' });
      return;
    }
    afficherNotification({ type: 'succes', message: 'Action remise en queue' });
    charger();
  }

  async function cancel(id: string) {
    const motif = prompt('Motif de l\'annulation ?');
    if (!motif) return;
    const { data, error } = await supabase.rpc('fn_admin_externalisation_cancel' as any, { p_id: id, p_motif: motif });
    if (error || !(data as any)?.success) {
      afficherNotification({ type: 'erreur', message: 'Erreur annulation' });
      return;
    }
    afficherNotification({ type: 'succes', message: 'Action annulée' });
    charger();
  }

  const filtered = actions.filter(a => {
    if (!search) return true;
    return (a.source_id || '').toLowerCase().includes(search.toLowerCase())
      || (a.derniere_erreur || '').toLowerCase().includes(search.toLowerCase())
      || a.id.toLowerCase().includes(search.toLowerCase());
  });

  const stats = {
    pending: actions.filter(a => a.statut === 'PENDING').length,
    processing: actions.filter(a => a.statut === 'PROCESSING').length,
    done: actions.filter(a => a.statut === 'DONE').length,
    error: actions.filter(a => a.statut === 'ERROR').length,
    pendingAife: actions.filter(a => a.statut === 'PENDING_AIFE').length,
  };

  return (
    <LayoutAdmin>
      <div className="max-w-7xl mx-auto p-4 space-y-4">
        <div className="flex items-center justify-between">
          <h1 className="text-2xl font-bold text-foreground">Worker externalisations</h1>
          <button onClick={charger} className="btn-secondary inline-flex items-center gap-2">
            <RefreshCw className="h-4 w-4" /> Rafraîchir
          </button>
        </div>

        {/* Stats */}
        <div className="grid grid-cols-2 sm:grid-cols-5 gap-3">
          {[
            { label: 'PENDING', value: stats.pending, color: 'text-amber-600' },
            { label: 'PROCESSING', value: stats.processing, color: 'text-blue-600' },
            { label: 'DONE', value: stats.done, color: 'text-emerald-600' },
            { label: 'ERROR', value: stats.error, color: 'text-destructive' },
            { label: 'PENDING_AIFE', value: stats.pendingAife, color: 'text-purple-600' },
          ].map(s => (
            <div key={s.label} className="rounded-xl border border-border bg-card p-3 text-center">
              <p className="text-[10px] text-muted-foreground uppercase">{s.label}</p>
              <p className={`text-2xl font-bold ${s.color}`}>{s.value}</p>
            </div>
          ))}
        </div>

        {/* Filtres */}
        <div className="flex flex-wrap gap-2">
          <select value={filtreStatut} onChange={e => setFiltreStatut(e.target.value as Filtre)} className="input-base">
            {STATUTS.map(s => <option key={s} value={s}>{s}</option>)}
          </select>
          <select value={filtreType} onChange={e => setFiltreType(e.target.value)} className="input-base">
            {TYPES_ACTION.map(t => <option key={t} value={t}>{t}</option>)}
          </select>
          <input
            type="text"
            placeholder="Rechercher (source_id, erreur, action ID)..."
            value={search} onChange={e => setSearch(e.target.value)}
            className="input-base flex-1 min-w-[200px]"
          />
        </div>

        {loading ? (
          <div className="flex justify-center py-8"><Loader2 className="h-6 w-6 animate-spin text-muted-foreground" /></div>
        ) : filtered.length === 0 ? (
          <EmptyState
            icone={<CheckCircle />}
            titre="Toutes les actions ont été traitées"
            description="Aucune action d'externalisation en attente, en cours ou en échec ne correspond à ces filtres."
            variant="success"
          />
        ) : (
          <div className="space-y-2">
            {filtered.map(a => (
              <div key={a.id} className="rounded-xl border border-border bg-card p-3 hover:bg-muted/20 transition">
                <div className="flex items-start justify-between gap-3">
                  <div className="flex-1 min-w-0">
                    <div className="flex items-center gap-2 flex-wrap">
                      <StatutBadge statut={a.statut} />
                      <span className="font-semibold text-sm text-foreground">{a.type_action}</span>
                      <span className="text-xs text-muted-foreground font-mono">{a.source}</span>
                      {a.tentatives > 0 && (
                        <span className="text-xs px-1.5 py-0.5 rounded bg-amber-100 dark:bg-amber-900 text-amber-900 dark:text-amber-100">
                          {a.tentatives} tentative{a.tentatives > 1 ? 's' : ''}
                        </span>
                      )}
                    </div>
                    {a.derniere_erreur && (
                      <p className="text-xs text-destructive mt-1 truncate">{a.derniere_erreur}</p>
                    )}
                    <p className="text-[10px] text-muted-foreground mt-1">
                      Créée {format(new Date(a.cree_le), "d MMM HH:mm", { locale: fr })}
                      {a.next_retry_at && ` • retry ${format(new Date(a.next_retry_at), "d MMM HH:mm", { locale: fr })}`}
                      {a.traite_le && ` • terminée ${format(new Date(a.traite_le), "d MMM HH:mm", { locale: fr })}`}
                    </p>
                  </div>
                  <div className="flex gap-1 shrink-0">
                    <button onClick={() => setDetails(a)} className="btn-secondary text-xs">Détail</button>
                    {(a.statut === 'ERROR' || a.statut === 'PENDING_AIFE') && (
                      <button onClick={() => retry(a.id)} className="btn-primary text-xs inline-flex items-center gap-1">
                        <RefreshCw className="h-3 w-3" /> Retry
                      </button>
                    )}
                    {(a.statut === 'PENDING' || a.statut === 'PENDING_AIFE' || a.statut === 'ERROR') && (
                      <button onClick={() => cancel(a.id)} className="btn-secondary text-xs inline-flex items-center gap-1 text-destructive">
                        <XCircle className="h-3 w-3" /> Annuler
                      </button>
                    )}
                  </div>
                </div>
              </div>
            ))}
          </div>
        )}

        {details && (
          <div className="fixed inset-0 z-50 bg-black/50 flex items-center justify-center p-4" onClick={() => setDetails(null)}>
            <div className="bg-card border border-border rounded-xl max-w-2xl w-full p-6 space-y-3 max-h-[80vh] overflow-auto" onClick={e => e.stopPropagation()}>
              <h2 className="text-lg font-bold text-foreground">{details.type_action}</h2>
              <p className="text-xs text-muted-foreground font-mono">{details.id}</p>
              <div className="rounded-lg bg-muted/40 p-3">
                <p className="text-xs font-semibold mb-1">Payload :</p>
                <pre className="text-[10px] font-mono whitespace-pre-wrap break-all">{JSON.stringify(details.payload, null, 2)}</pre>
              </div>
              {details.resultat && (
                <div className="rounded-lg bg-emerald-50 dark:bg-emerald-950/30 p-3">
                  <p className="text-xs font-semibold mb-1">Résultat :</p>
                  <pre className="text-[10px] font-mono whitespace-pre-wrap break-all">{JSON.stringify(details.resultat, null, 2)}</pre>
                </div>
              )}
              {details.derniere_erreur && (
                <div className="rounded-lg bg-destructive/10 p-3">
                  <p className="text-xs font-semibold mb-1">Dernière erreur :</p>
                  <pre className="text-[10px] font-mono whitespace-pre-wrap break-all">{details.derniere_erreur}</pre>
                </div>
              )}
              <button onClick={() => setDetails(null)} className="btn-secondary w-full">Fermer</button>
            </div>
          </div>
        )}
      </div>
    </LayoutAdmin>
  );
}

function StatutBadge({ statut }: { statut: Action['statut'] }) {
  const config = {
    PENDING: { icon: Clock, color: 'bg-amber-100 dark:bg-amber-900 text-amber-900 dark:text-amber-100' },
    PROCESSING: { icon: Loader2, color: 'bg-blue-100 dark:bg-blue-900 text-blue-900 dark:text-blue-100' },
    DONE: { icon: CheckCircle, color: 'bg-emerald-100 dark:bg-emerald-900 text-emerald-900 dark:text-emerald-100' },
    ERROR: { icon: AlertTriangle, color: 'bg-destructive/10 text-destructive' },
    PENDING_AIFE: { icon: Clock, color: 'bg-purple-100 dark:bg-purple-900 text-purple-900 dark:text-purple-100' },
    CANCELLED: { icon: XCircle, color: 'bg-muted text-muted-foreground' },
  }[statut];
  const Icon = config.icon;
  return (
    <span className={`inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-xs ${config.color}`}>
      <Icon className={`h-3 w-3 ${statut === 'PROCESSING' ? 'animate-spin' : ''}`} />
      {statut}
    </span>
  );
}
