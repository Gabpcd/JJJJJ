import { Trophy, TrendingDown, Sparkles } from 'lucide-react';

interface Palier {
  id: string;
  nom: string;
  taux_commission: number;
  missions_min: number;
  missions_max: number | null;
  ordre: number;
}

interface WidgetPalierFideliteProps {
  etab: {
    taux_commission_negocie: number;
    palier_commission_id: string | null;
    missions_mois_precedent: number;
    paliers_commission?: { nom: string; taux_commission: number; missions_min: number; missions_max: number | null } | null;
  };
  paliers: Palier[];
  missionsCeMois: number;
}

export function WidgetPalierFidelite({ etab, paliers, missionsCeMois }: WidgetPalierFideliteProps) {
  if (!paliers || paliers.length === 0) return null;

  const tauxActuel = etab.taux_commission_negocie ?? 15;
  const palierActuel = paliers.find(p => p.id === etab.palier_commission_id) ?? paliers[0];
  const indexActuel = paliers.findIndex(p => p.id === palierActuel.id);

  // Prochain palier
  const prochainPalier = paliers.find(p => p.missions_min > missionsCeMois);
  const missionsRestantes = prochainPalier ? prochainPalier.missions_min - missionsCeMois : 0;

  // Économie vs taux Découverte (15%)
  const tauxDecouverteMax = paliers.length > 0 ? Math.max(...paliers.map(p => p.taux_commission)) : 15;
  const economiePourcent = tauxDecouverteMax - tauxActuel;

  return (
    <div className="bg-gradient-to-r from-accent/10 to-primary/5 border border-accent/30 rounded-2xl p-5 mb-6">
      <div className="flex items-center gap-2 mb-4">
        <Trophy className="h-5 w-5 text-accent-foreground" />
        <h3 className="font-bold text-foreground">
          Votre palier : {palierActuel.nom} ({tauxActuel}% HT)
        </h3>
      </div>

      <p className="text-sm text-muted-foreground mb-4">
        Mois en cours : <span className="font-semibold text-foreground">{missionsCeMois} mission{missionsCeMois > 1 ? 's' : ''} terminée{missionsCeMois > 1 ? 's' : ''}</span>
      </p>

      {/* Barre de progression paliers */}
      <div className="relative flex items-center justify-between mb-6 px-2">
        {/* Ligne de fond */}
        <div className="absolute left-6 right-6 top-1/2 -translate-y-1/2 h-1 bg-muted rounded-full" />
        {/* Ligne remplie */}
        {indexActuel > 0 && (
          <div
            className="absolute left-6 top-1/2 -translate-y-1/2 h-1 bg-primary rounded-full transition-all duration-700"
            style={{ width: `calc(${(indexActuel / (paliers.length - 1)) * 100}% - 48px * ${indexActuel / (paliers.length - 1)})` }}
          />
        )}

        {paliers.map((p, i) => {
          const isActuel = i === indexActuel;
          const isAtteint = i < indexActuel;
          return (
            <div key={p.id} className="relative z-10 flex flex-col items-center" style={{ width: `${100 / paliers.length}%` }}>
              <div
                className={`w-8 h-8 rounded-full flex items-center justify-center text-xs font-bold border-2 transition-all ${
                  isActuel
                    ? 'bg-primary text-primary-foreground border-primary shadow-md scale-110'
                    : isAtteint
                    ? 'bg-muted-foreground text-white border-muted-foreground'
                    : 'bg-card border-border text-muted-foreground'
                }`}
              >
                {p.taux_commission}% HT
              </div>
              <span className={`text-[10px] mt-1.5 font-medium text-center leading-tight ${isActuel ? 'text-primary' : 'text-muted-foreground'}`}>
                {p.nom}
              </span>
              <span className="text-[9px] text-muted-foreground">
                {p.missions_max ? `${p.missions_min}-${p.missions_max}` : `${p.missions_min}+`}
              </span>
              {isActuel && (
                <span className="text-[9px] text-primary font-bold mt-0.5">▲ Vous</span>
              )}
            </div>
          );
        })}
      </div>

      {/* Prochain palier */}
      {prochainPalier && missionsRestantes > 0 && (
        <div className="flex items-start gap-2 bg-card/60 rounded-xl p-3 mb-3 border border-border">
          <Sparkles className="h-4 w-4 text-primary mt-0.5 shrink-0" />
          <p className="text-sm text-foreground">
            Encore <span className="font-bold text-primary">{missionsRestantes} mission{missionsRestantes > 1 ? 's' : ''}</span> pour atteindre le palier{' '}
            <span className="font-bold">{prochainPalier.nom} ({prochainPalier.taux_commission}% HT)</span> !
            Publiez plus pour économiser.
          </p>
        </div>
      )}

      {!prochainPalier && (
        <div className="flex items-start gap-2 bg-card/60 rounded-xl p-3 mb-3 border border-border">
          <Trophy className="h-4 w-4 text-primary mt-0.5 shrink-0" />
          <p className="text-sm text-foreground font-medium">
            🎉 Vous êtes au palier maximum ! Profitez du meilleur taux.
          </p>
        </div>
      )}

      {/* Économie */}
      {economiePourcent > 0 && (
        <div className="flex items-center gap-2 text-sm text-muted-foreground">
           <TrendingDown className="h-4 w-4 text-success" />
           <span>
             Vous économisez <span className="font-bold text-success">{economiePourcent.toFixed(1)}%</span> par rapport au taux Découverte
          </span>
        </div>
      )}
    </div>
  );
}
