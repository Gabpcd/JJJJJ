import { useState } from 'react';
import { telechargerOuPartager } from '@/lib/telechargement';
import { Loader2, CheckCircle2, XCircle, Download } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { useNotification } from '@/contexts/NotificationContext';

/**
 * Composant <BoutonsBulkFactures /> (Sprint 7 PR 6 - P2 §11).
 *
 * Actions multi-factures pour la page AdminFacturation :
 * - Marquer comme payées
 * - Marquer comme impayées
 * - Export CSV
 *
 * Prêt à embarquer dans AdminFacturation au-dessus de la table.
 * Aucune action automatique sans sélection explicite.
 */

interface FactureLite {
  id: string;
  numero?: string | null;
  montant_ttc?: number | null;
  statut?: string | null;
  date_emission?: string | null;
  etablissement_nom?: string | null;
}

interface Props {
  selection: FactureLite[];
  onActionTerminee?: () => void;
  className?: string;
}

export function BoutonsBulkFactures({ selection, onActionTerminee, className }: Props) {
  const { afficherNotification } = useNotification();
  const [enCours, setEnCours] = useState<'PAYEES' | 'IMPAYEES' | 'CSV' | null>(null);

  const aucuneSelection = selection.length === 0;

  const marquer = async (statut: 'PAYEE' | 'IMPAYEE') => {
    if (aucuneSelection) return;
    setEnCours(statut === 'PAYEE' ? 'PAYEES' : 'IMPAYEES');
    try {
      const ids = selection.map((f) => f.id);
      const { error } = await (supabase as any)
        .from('factures')
        .update({ statut })
        .in('id', ids);
      if (error) throw error;
      afficherNotification({
        type: 'succes',
        message: `${ids.length} facture(s) marquée(s) comme ${statut === 'PAYEE' ? 'payée(s)' : 'impayée(s)'}.`,
      });
      onActionTerminee?.();
    } catch (err: any) {
      afficherNotification({
        type: 'erreur',
        message: `Erreur : ${err?.message ?? 'Impossible de mettre à jour le statut.'}`,
      });
    } finally {
      setEnCours(null);
    }
  };

  const exportCsv = async () => {
    if (aucuneSelection) return;
    setEnCours('CSV');
    try {
      const entetes = ['numero', 'date_emission', 'etablissement', 'montant_ttc', 'statut'];
      const lignes = selection.map((f) =>
        [
          f.numero ?? f.id,
          f.date_emission ?? '',
          (f.etablissement_nom ?? '').replace(/[";\n]/g, ' '),
          (f.montant_ttc ?? 0).toFixed(2),
          f.statut ?? '',
        ].join(';'),
      );
      const csv = [entetes.join(';'), ...lignes].join('\n');
      await telechargerOuPartager(`\uFEFF${csv}`, `factures-${new Date().toISOString().slice(0, 10)}.csv`, 'text/csv');
      afficherNotification({
        type: 'succes',
        message: `Export effectué : ${selection.length} ligne(s) exportée(s).`,
      });
    } catch (err: any) {
      afficherNotification({
        type: 'erreur',
        message: `Erreur export : ${err?.message ?? "Impossible d'exporter le CSV."}`,
      });
    } finally {
      setEnCours(null);
    }
  };

  return (
    <div
      className={`flex flex-wrap items-center gap-2 p-3 rounded-md border bg-slate-50 ${className ?? ''}`}
      role="toolbar"
      aria-label="Actions multi-factures"
    >
      <span className="text-sm font-medium">
        {aucuneSelection ? 'Aucune sélection' : `${selection.length} sélectionnée(s)`}
      </span>
      <div className="flex-1" />
      <button
        type="button"
        disabled={aucuneSelection || enCours !== null}
        onClick={() => marquer('PAYEE')}
        className="inline-flex items-center gap-1 px-3 py-1.5 text-sm rounded border bg-emerald-50 text-emerald-700 hover:bg-emerald-100 disabled:opacity-40 disabled:cursor-not-allowed"
      >
        {enCours === 'PAYEES' ? (
          <Loader2 className="w-3.5 h-3.5 animate-spin" />
        ) : (
          <CheckCircle2 className="w-3.5 h-3.5" />
        )}
        Marquer payées
      </button>
      <button
        type="button"
        disabled={aucuneSelection || enCours !== null}
        onClick={() => marquer('IMPAYEE')}
        className="inline-flex items-center gap-1 px-3 py-1.5 text-sm rounded border bg-orange-50 text-orange-700 hover:bg-orange-100 disabled:opacity-40 disabled:cursor-not-allowed"
      >
        {enCours === 'IMPAYEES' ? (
          <Loader2 className="w-3.5 h-3.5 animate-spin" />
        ) : (
          <XCircle className="w-3.5 h-3.5" />
        )}
        Marquer impayées
      </button>
      <button
        type="button"
        disabled={aucuneSelection || enCours !== null}
        onClick={exportCsv}
        className="inline-flex items-center gap-1 px-3 py-1.5 text-sm rounded border bg-white hover:bg-slate-100 disabled:opacity-40 disabled:cursor-not-allowed"
      >
        {enCours === 'CSV' ? <Loader2 className="w-3.5 h-3.5 animate-spin" /> : <Download className="w-3.5 h-3.5" />}
        Export CSV
      </button>
    </div>
  );
}

export default BoutonsBulkFactures;
