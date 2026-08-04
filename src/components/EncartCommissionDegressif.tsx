import { Tag } from 'lucide-react';

interface EncartCommissionDegressifProps {
  netEstime: number;
  tauxActuel: number;
  /** Conservé pour compatibilité d'appel — n'est plus affiché (modèle par paliers abandonné). */
  palierNom?: string;
}

/**
 * Encart commission : taux unique de 15 % HT (ou taux HT négocié de l'établissement).
 * Le modèle « paliers dégressifs par volume » a été abandonné (décision
 * produit 12/06/2026) — la facturation applique COALESCE(taux_negocie, 15).
 */
export function EncartCommissionDegressif({ netEstime, tauxActuel }: EncartCommissionDegressifProps) {
  if (netEstime <= 0) return null;

  const commissionHT = netEstime * (tauxActuel / 100);
  const tva = commissionHT * 0.20;
  const commissionTTC = commissionHT + tva;

  return (
    <div className="bg-gradient-to-r from-accent/5 to-primary/5 border border-accent/20 rounded-2xl p-5">
      <div className="flex items-center gap-2 mb-3">
        <Tag className="h-4 w-4 text-primary" />
        <p className="font-bold text-foreground">Commission Jolene</p>
      </div>

      <p className="text-sm text-muted-foreground mb-3">
        Taux appliqué : <span className="font-semibold text-foreground">{tauxActuel}% HT</span>
        <span className="text-xs"> ({(tauxActuel * 1.2).toLocaleString('fr-FR', { maximumFractionDigits: 2 })}% TTC)</span>
        {tauxActuel !== 15 && <span className="text-xs"> (taux négocié)</span>}
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
    </div>
  );
}
