import { useState } from 'react';
import { telechargerOuPartager } from '@/lib/telechargement';
import { encoderCelluleCsv } from '@/lib/csv';
import { Loader2, Download } from 'lucide-react';
import { useNotification } from '@/contexts/NotificationContext';

/**
 * Composant <BoutonsBulkFactures /> (Sprint 7 PR 6 - P2 §11).
 *
 * Action multi-factures pour la page AdminFacturation : export CSV.
 *
 * Les mutations de statut sont volontairement absentes au lancement : PAYEE
 * exige une preuve/date et un audit serveur, EN_RETARD une transition CAS
 * auditée. Une écriture directe PostgREST ne satisfait aucune de ces garanties.
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

export function BoutonsBulkFactures({ selection, className }: Props) {
  const { afficherNotification } = useNotification();
  const [enCours, setEnCours] = useState<'CSV' | null>(null);

  const aucuneSelection = selection.length === 0;

  const exportCsv = async () => {
    if (aucuneSelection) return;
    setEnCours('CSV');
    try {
      const entetes = [
        'numero',
        'date_emission',
        'etablissement',
        'montant_ttc',
        'statut',
      ];
      const lignes = selection.map((f) =>
        [
          f.numero ?? f.id,
          f.date_emission ?? '',
          f.etablissement_nom ?? '',
          (f.montant_ttc ?? 0).toFixed(2),
          f.statut ?? '',
        ].map(encoderCelluleCsv).join(';'),
      );
      const csv = [entetes.map(encoderCelluleCsv).join(';'), ...lignes].join('\n');
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
      <span className="text-xs text-slate-500">
        Les changements de statut se font depuis la fiche avec leur justificatif.
      </span>
      <div className="flex-1" />
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
