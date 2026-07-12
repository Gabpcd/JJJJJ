import React, { useEffect, useRef, useState } from 'react';
import { Loader2, RefreshCw, XCircle, AlertTriangle, CheckCircle, Clock } from 'lucide-react';
import { LayoutAdmin } from '@/components/LayoutAdmin';
import { supabase } from '@/integrations/supabase/client';
import { useNotification } from '@/contexts/NotificationContext';
import { usePageTitle } from '@/hooks/usePageTitle';
import { EmptyState } from '@/components/ui/EmptyState';
import { BoutonY2K } from '@/components/y2k/BoutonY2K';
import { BadgeY2K } from '@/components/y2k/BadgeY2K';
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
  const detailsRef = useRef<HTMLDivElement>(null);

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

  useEffect(() => {
    if (!details) return;
    detailsRef.current?.focus();
    const fermerAvecEchap = (event: KeyboardEvent) => {
      if (event.key === 'Escape') setDetails(null);
    };
    document.addEventListener('keydown', fermerAvecEchap);
    return () => document.removeEventListener('keydown', fermerAvecEchap);
  }, [details]);

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
          <BoutonY2K variant="secondary" size="sm" onClick={charger} iconeGauche={<RefreshCw className="h-4 w-4" />}>
            Rafraîchir
          </BoutonY2K>
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
          <select aria-label="Filtrer par statut" value={filtreStatut} onChange={e => setFiltreStatut(e.target.value as Filtre)} className="input-base">
            {STATUTS.map(s => <option key={s} value={s}>{s}</option>)}
          </select>
          <select aria-label="Filtrer par type d’action" value={filtreType} onChange={e => setFiltreType(e.target.value)} className="input-base">
            {TYPES_ACTION.map(t => <option key={t} value={t}>{t}</option>)}
          </select>
          <input
            aria-label="Rechercher une action externalisée"
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
            mascotte="happy"
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
                    <BoutonY2K variant="secondary" size="sm" onClick={() => setDetails(a)}>Détail</BoutonY2K>
                    {(a.statut === 'ERROR' || a.statut === 'PENDING_AIFE') && (
                      <BoutonY2K variant="primary" size="sm" onClick={() => retry(a.id)} iconeGauche={<RefreshCw className="h-3 w-3" />}>
                        Retry
                      </BoutonY2K>
                    )}
                    {(a.statut === 'PENDING' || a.statut === 'PENDING_AIFE' || a.statut === 'ERROR') && (
                      <BoutonY2K variant="destructive" size="sm" onClick={() => cancel(a.id)} iconeGauche={<XCircle className="h-3 w-3" />}>
                        Annuler
                      </BoutonY2K>
                    )}
                  </div>
                </div>
              </div>
            ))}
          </div>
        )}

        {details && (
          <div className="fixed inset-0 z-50 bg-black/50 flex items-center justify-center p-4" onClick={() => setDetails(null)}>
            <div
              ref={detailsRef}
              role="dialog"
              aria-modal="true"
              aria-labelledby="externalisation-details-title"
              tabIndex={-1}
              className="bg-card border border-border rounded-xl max-w-2xl w-full p-6 space-y-3 max-h-[80vh] overflow-auto outline-none"
              onClick={e => e.stopPropagation()}
            >
              <h2 id="externalisation-details-title" className="text-lg font-bold text-foreground">{details.type_action}</h2>
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
              <BoutonY2K variant="secondary" size="md" onClick={() => setDetails(null)} className="w-full">Fermer</BoutonY2K>
            </div>
          </div>
        )}
      </div>
    </LayoutAdmin>
  );
}

function StatutBadge({ statut }: { statut: Action['statut'] }) {
  const variantMap: Record<Action['statut'], 'warning' | 'info' | 'success' | 'error'> = {
    PENDING: 'warning',
    PROCESSING: 'info',
    DONE: 'success',
    ERROR: 'error',
    PENDING_AIFE: 'warning',
    CANCELLED: 'info',
  };
  const iconMap: Record<Action['statut'], React.ReactNode> = {
    PENDING: <Clock className="h-3 w-3" />,
    PROCESSING: <Loader2 className="h-3 w-3 animate-spin" />,
    DONE: <CheckCircle className="h-3 w-3" />,
    ERROR: <AlertTriangle className="h-3 w-3" />,
    PENDING_AIFE: <Clock className="h-3 w-3" />,
    CANCELLED: <XCircle className="h-3 w-3" />,
  };
  return (
    <BadgeY2K variant={variantMap[statut]} size="sm" icone={iconMap[statut]}>
      {statut}
    </BadgeY2K>
  );
}
