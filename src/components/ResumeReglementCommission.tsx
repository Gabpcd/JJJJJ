import { formatMontantCommission, soldeCommissionPourAffichage } from '@/lib/soldeCommission';
import type { FactureSoldeCommission } from '../../supabase/functions/_shared/commission-balance';

/** Le TTC reste celui du document ; seul son règlement est diminué par les avoirs. */
type FactureAffichable = Partial<FactureSoldeCommission> & {
  avoirs?: {
    avoir_eligible?: boolean;
    avoir_reliquat?: number | null;
    imputations?: Array<{ avoir_id: string; numero_avoir: string; montant_ttc: number; restitue: boolean }>;
  };
};

export function ResumeReglementCommission({ facture }: { facture: FactureAffichable }) {
  if (facture.type_document === 'AVOIR') {
    if (facture.statut === 'ANNULEE') return null;
    const credit = facture.avoirs;
    if (!credit) return null;
    if (credit.avoir_eligible === false) return <p className="text-sm text-muted-foreground">L’imputation de cet avoir doit être rapprochée des règlements déjà effectués.</p>;
    if (credit.avoir_eligible === true && typeof credit.avoir_reliquat === 'number' && Number.isFinite(credit.avoir_reliquat) && credit.avoir_reliquat >= 0) {
      return <p className="text-sm">Crédit encore disponible : {formatMontantCommission(Math.round(credit.avoir_reliquat * 100))}</p>;
    }
    return <p className="text-sm text-muted-foreground">Reliquat de l’avoir indisponible.</p>;
  }
  const solde = soldeCommissionPourAffichage(facture);
  if (!solde) return <p role="status" className="text-sm text-muted-foreground">Solde indisponible. Rechargez la facture avant de régler.</p>;
  if (solde.rapprochementRequis) return <p role="status" className="text-sm text-amber-800 dark:text-amber-200">Règlement à rapprocher après remboursement. Aucun nouveau paiement n’est demandé pendant la vérification.</p>;
  if (solde.avoirsImputesCents === 0 || !['EMISE', 'EN_RETARD', 'VIREMENT_DECLARE', 'PAYEE'].includes(String(facture.statut))) return null;
  return <div className="space-y-1 text-sm"><dl className="space-y-1" aria-label="Déduction des avoirs">
    <div className="flex flex-wrap justify-between gap-x-3"><dt>Avoirs déduits</dt><dd>−{formatMontantCommission(solde.avoirsImputesCents)}</dd></div>
    <div className="flex flex-wrap justify-between gap-x-3 font-semibold"><dt>{facture.statut === 'PAYEE' ? 'Montant réglé hors avoirs' : 'Montant à régler'}</dt><dd>{formatMontantCommission(solde.montantExterneCents)}</dd></div>
    {facture.statut === 'PAYEE' && <div className="flex flex-wrap justify-between gap-x-3"><dt>Restant à payer</dt><dd>{formatMontantCommission(0)}</dd></div>}
    {facture.avoirs?.imputations?.filter(ligne => !ligne.restitue).map(ligne => <div key={ligne.avoir_id} className="flex flex-wrap justify-between gap-x-3 text-xs text-muted-foreground"><dt>{ligne.numero_avoir}</dt><dd>{formatMontantCommission(Math.round(ligne.montant_ttc * 100))}</dd></div>)}
  </dl>
    {facture.statut === 'PAYEE' && solde.montantExterneCents === 0 && <p className="text-muted-foreground">Soldée par avoir. Aucun débit bancaire.</p>}
  </div>;
}
