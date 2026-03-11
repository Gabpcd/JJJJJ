import { Tag, TrendingDown } from 'lucide-react';

interface EncartCommissionDegressifProps {
  netEstime: number;
  tauxActuel: number;
  palierNom: string;
}

export function EncartCommissionDegressif({ netEstime, tauxActuel, palierNom }: EncartCommissionDegressifProps) {
  if (netEstime <= 0) return null;

  const commissionHT = netEstime * (tauxActuel / 100);
  const tva = commissionHT * 0.20;
  const commissionTTC = commissionHT + tva;

  // Comparaison avec taux Découverte (15%)
  const tauxDecouv = 15;
  const commissionDecouv = netEstime * (tauxDecouv / 100) * 1.20;
  const economie = commissionDecouv - commissionTTC;
  const aEconomie = tauxActuel < tauxDecouv;

  return (
    <div className="bg-gradient-to-r from-accent/5 to-primary/5 border border-accent/20 rounded-2xl p-5">
      <div className="flex items-center gap-2 mb-3">
        <Tag className="h-4 w-4 text-primary" />
        <p className="font-bold text-foreground">Commission Soin Direct</p>
      </div>

      <p className="text-sm text-muted-foreground mb-3">
        Votre palier actuel : <span className="font-semibold text-foreground">{palierNom} ({tauxActuel}%)</span>
      </p>

      <div className="space-y-1.5 text-sm">
        <div className="flex justify-between">
          <span className="text-muted-foreground">Net soignant estimé</span>
          <span className="font-medium">~{netEstime.toFixed(2)} €</span>
        </div>
        <div className="flex justify-between">
          <span className="text-muted-foreground">Commission HT ({tauxActuel}%)</span>
          <span className="font-medium">~{commissionHT.toFixed(2)} €</span>
        </div>
        <div className="flex justify-between">
          <span className="text-muted-foreground">TVA (20%)</span>
          <span className="font-medium">~{tva.toFixed(2)} €</span>
        </div>
        <div className="border-t border-border pt-1.5 flex justify-between">
          <span className="text-muted-foreground font-medium">Commission TTC</span>
          <span className="font-bold text-primary">~{commissionTTC.toFixed(2)} €</span>
        </div>
      </div>

      {aEconomie && economie > 0 && (
        <div className="mt-3 flex items-start gap-2 bg-green-50 dark:bg-green-950/30 border border-green-200 dark:border-green-800 rounded-xl p-3">
          <TrendingDown className="h-4 w-4 text-green-600 mt-0.5 shrink-0" />
          <p className="text-xs text-green-700 dark:text-green-400">
            Avec le palier Découverte ({tauxDecouv}%), cette commission aurait été de{' '}
            <span className="font-bold">{commissionDecouv.toFixed(2)} €</span> — vous économisez{' '}
            <span className="font-bold">{economie.toFixed(2)} €</span> !
          </p>
        </div>
      )}

      <p className="text-[10px] text-muted-foreground italic mt-2">Simulation à titre indicatif.</p>
    </div>
  );
}
