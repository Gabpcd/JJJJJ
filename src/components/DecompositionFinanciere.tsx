import React from 'react';
import { Tooltip, TooltipContent, TooltipProvider, TooltipTrigger } from '@/components/ui/tooltip';
import { Info } from 'lucide-react';

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
  const tauxEffectif = m.taux_rist_plafonne || m.taux_horaire_base;
  const heuresNormales = Math.max(0, duree - (m.heures_nuit || 0) - (m.heures_dimanche || 0) - (m.heures_ferie || 0));
  const brutBase = tauxEffectif * duree;
  const totalMajorations = (m.montant_majoration_nuit || 0) + (m.montant_majoration_dimanche || 0) + (m.montant_majoration_ferie || 0);
  const totalBrut = m.total_brut || (brutBase + totalMajorations);
  const ifm = m.montant_ifm || 0;
  const icp = m.montant_icp || 0;
  const superBrut = totalBrut + ifm + icp;
  const cotisationsEstimees = superBrut * 0.22;
  const netEstime = m.net_estime || (superBrut * 0.78);

  return (
    <div className="bg-gradient-to-br from-primary/5 to-info/5 border border-primary/20 rounded-2xl p-5 shadow-sm">
      <h3 className="text-lg font-bold text-foreground mb-4">💰 Décomposition financière</h3>

      <div className="space-y-3 text-sm">
        <div className="flex justify-between">
          <span className="text-muted-foreground">Taux horaire</span>
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
            <span className="text-muted-foreground">Heures totales</span>
            <span className="font-medium">{duree.toFixed(1)}h</span>
          </div>
          {heuresNormales !== duree && (
            <div className="flex justify-between mt-1">
              <span className="text-muted-foreground pl-3">dont normales</span>
              <span className="font-medium">{heuresNormales.toFixed(1)}h</span>
            </div>
          )}
          {(m.heures_nuit || 0) > 0 && (
            <div className="flex justify-between mt-1">
              <span className="text-muted-foreground pl-3">🌙 nuit</span>
              <span className="font-medium">{m.heures_nuit?.toFixed(1)}h</span>
            </div>
          )}
          {(m.heures_dimanche || 0) > 0 && (
            <div className="flex justify-between mt-1">
              <span className="text-muted-foreground pl-3">☀️ dimanche</span>
              <span className="font-medium">{m.heures_dimanche?.toFixed(1)}h</span>
            </div>
          )}
          {(m.heures_ferie || 0) > 0 && (
            <div className="flex justify-between mt-1">
              <span className="text-muted-foreground pl-3">🎌 jour férié</span>
              <span className="font-medium">{m.heures_ferie?.toFixed(1)}h</span>
            </div>
          )}
        </div>

        <div className="border-t border-border pt-3 space-y-2">
          <p className="text-xs font-semibold text-muted-foreground uppercase tracking-wide mb-2">Calcul</p>
          <div className="flex justify-between">
            <span className="text-muted-foreground">Brut de base ({duree.toFixed(1)}h × {tauxEffectif?.toFixed(2)}€)</span>
            <span className="font-medium">{fmt(brutBase)}</span>
          </div>

          {totalMajorations > 0 && (
            <div className="flex justify-between">
              <span className="text-muted-foreground">Majorations</span>
              <span className="font-medium text-primary">+{fmt(totalMajorations)}</span>
            </div>
          )}

          <div className="flex justify-between">
            <span className="text-muted-foreground">Total brut</span>
            <span className="font-bold">{fmt(totalBrut)}</span>
          </div>

          {ifm > 0 && (
            <div className="flex justify-between">
              <span className="text-muted-foreground">IFM (10%)</span>
              <span className="font-medium text-primary">+{fmt(ifm)}</span>
            </div>
          )}
          {icp > 0 && (
            <div className="flex justify-between">
              <span className="text-muted-foreground">ICP (10%)</span>
              <span className="font-medium text-primary">+{fmt(icp)}</span>
            </div>
          )}

          {(ifm > 0 || icp > 0) && (
            <div className="flex justify-between border-t border-border pt-2">
              <span className="text-muted-foreground">Super brut</span>
              <span className="font-bold">{fmt(superBrut)}</span>
            </div>
          )}

          <div className="flex justify-between text-destructive/80">
            <span>Cotisations salariales estimées (~22%)</span>
            <span className="font-medium">-{fmt(cotisationsEstimees)}</span>
          </div>
        </div>

        <div className="border-t-2 border-primary/30 pt-3">
          <div className="flex justify-between items-center">
            <span className="font-bold text-foreground flex items-center gap-1">
              NET ESTIMÉ*
              <TooltipProvider>
                <Tooltip>
                  <TooltipTrigger asChild>
                    <Info className="h-3.5 w-3.5 text-muted-foreground cursor-help" />
                  </TooltipTrigger>
                  <TooltipContent className="max-w-xs text-xs">
                    Estimation après cotisations salariales (~22%). Le montant exact dépend de votre situation personnelle et sera calculé par l'établissement sur votre bulletin de paie.
                  </TooltipContent>
                </Tooltip>
              </TooltipProvider>
            </span>
            <span className="text-2xl font-bold text-primary">{fmt(netEstime)}</span>
          </div>
        </div>
      </div>

      <p className="text-[10px] text-muted-foreground/60 italic mt-4">
        Simulation à titre indicatif. Seuls les montants calculés par le moteur de paie font foi.
        Montants indicatifs hors charges patronales légales (CFP, taxe d'apprentissage). L'établissement reste responsable de ses déclarations sociales.
      </p>
    </div>
  );
}