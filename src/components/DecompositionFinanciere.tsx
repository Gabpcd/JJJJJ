import React from 'react';

interface DecompositionFinanciereProps {
  mission: any;
  etablissement?: any;
}

function fmt(v: number | null | undefined): string {
  if (v == null) return '—';
  return new Intl.NumberFormat('fr-FR', { style: 'currency', currency: 'EUR' }).format(v);
}

export function DecompositionFinanciere({ mission, etablissement }: DecompositionFinanciereProps) {
  const m = mission;
  const etab = etablissement || m.etablissements;
  const duree = m.duree_heures ?? 0;
  const heuresNormales = Math.max(0, duree - (m.heures_nuit || 0) - (m.heures_dimanche || 0) - (m.heures_ferie || 0));
  const tauxEffectif = m.taux_rist_plafonne || m.taux_horaire_base;

  return (
    <div className="bg-gradient-to-br from-primary/5 to-info/5 border border-primary/20 rounded-2xl p-5 shadow-sm">
      <h3 className="text-lg font-bold text-foreground mb-4">💰 Décomposition financière</h3>

      <div className="space-y-3 text-sm">
        <div className="flex justify-between">
          <span className="text-muted-foreground">Taux horaire effectif</span>
          <span className="font-medium text-foreground">{tauxEffectif?.toFixed(2)} €/h</span>
        </div>

        {m.rist_plafond_applique && (
          <div className="bg-warning/10 border-l-4 border-warning p-3 rounded-r-lg">
            <p className="text-xs font-semibold text-warning">⚠️ PLAFOND LOI RIST APPLIQUÉ</p>
            <p className="text-xs text-warning/80 mt-1">
              Taux demandé : {m.taux_horaire_base?.toFixed(2)} €/h → Plafonné : {m.taux_rist_plafonne?.toFixed(2)} €/h
            </p>
            <p className="text-[10px] text-warning/60 mt-0.5">(Décret 2023-920)</p>
          </div>
        )}

        <div className="border-t border-border pt-3">
          <p className="text-xs font-semibold text-muted-foreground uppercase tracking-wide mb-2">Heures</p>
          <div className="flex justify-between">
            <span className="text-muted-foreground">Heures normales</span>
            <span className="font-medium">{heuresNormales.toFixed(1)}h</span>
          </div>
        </div>

        {(m.heures_nuit || 0) > 0 && (
          <div className="flex justify-between items-start">
            <div>
              <span className="text-muted-foreground">🌙 Heures de nuit</span>
              <p className="text-[10px] text-muted-foreground">(21h-6h, +{etab?.taux_majoration_nuit_pourcent ?? 25}%)</p>
            </div>
            <div className="text-right">
              <span className="font-medium">{m.heures_nuit?.toFixed(1)}h</span>
              <p className="text-xs text-primary">+{fmt(m.montant_majoration_nuit)}</p>
            </div>
          </div>
        )}

        {(m.heures_dimanche || 0) > 0 && (
          <div className="flex justify-between items-start">
            <div>
              <span className="text-muted-foreground">☀️ Heures dimanche</span>
              <p className="text-[10px] text-muted-foreground">(+{etab?.taux_majoration_dimanche_pourcent ?? 50}%)</p>
            </div>
            <div className="text-right">
              <span className="font-medium">{m.heures_dimanche?.toFixed(1)}h</span>
              <p className="text-xs text-info">+{fmt(m.montant_majoration_dimanche)}</p>
            </div>
          </div>
        )}

        {(m.heures_ferie || 0) > 0 && (
          <div className="flex justify-between items-start">
            <div>
              <span className="text-muted-foreground">🎌 Heures jour férié</span>
              <p className="text-[10px] text-muted-foreground">(+{etab?.taux_majoration_ferie_pourcent ?? 100}%)</p>
            </div>
            <div className="text-right">
              <span className="font-medium">{m.heures_ferie?.toFixed(1)}h</span>
              <p className="text-xs text-warning">+{fmt(m.montant_majoration_ferie)}</p>
            </div>
          </div>
        )}

        <div className="border-t border-border pt-3 space-y-2">
          <p className="text-xs font-semibold text-muted-foreground uppercase tracking-wide mb-2">Totaux</p>
          <div className="flex justify-between">
            <span className="text-muted-foreground">Sous-total brut</span>
            <span className="font-medium">{fmt(m.total_brut)}</span>
          </div>
          {(m.montant_ifm || 0) > 0 && (
            <div className="flex justify-between">
              <span className="text-muted-foreground">IFM 10%</span>
              <span className="font-medium text-primary">+{fmt(m.montant_ifm)}</span>
            </div>
          )}
          {(m.montant_icp || 0) > 0 && (
            <div className="flex justify-between">
              <span className="text-muted-foreground">ICP 10%</span>
              <span className="font-medium text-primary">+{fmt(m.montant_icp)}</span>
            </div>
          )}
        </div>

        <div className="border-t-2 border-primary/30 pt-3">
          <div className="flex justify-between items-center">
            <span className="font-bold text-foreground">NET À PAYER</span>
            <span className="text-2xl font-bold text-primary">{fmt(m.net_a_payer)}</span>
          </div>
        </div>
      </div>
    </div>
  );
}
