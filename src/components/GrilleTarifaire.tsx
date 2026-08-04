import { Check, Crown } from 'lucide-react';
import { useNavigate } from 'react-router-dom';

interface Palier {
  id: string;
  nom: string;
  taux_commission: number;
  missions_min: number;
  missions_max: number | null;
  ordre: number;
}

interface GrilleTarifaireProps {
  paliers: Palier[];
}

const descriptionsParPalier: Record<string, { cible: string; cta: string }> = {
  'Découverte': { cible: 'Idéal pour débuter', cta: "S'inscrire" },
  'Fidèle': { cible: 'Cliniques actives', cta: "S'inscrire" },
  'Premium': { cible: "Réseaux d'EHPAD", cta: "S'inscrire" },
  'Partenaire': { cible: 'Grands groupes', cta: 'Nous contacter' },
};

export function GrilleTarifaire({ paliers }: GrilleTarifaireProps) {
  const navigate = useNavigate();

  // Déterminer le palier "populaire" (ordre 3 = Premium, ou le 3e)
  const palierPopulaire = paliers.find(p => p.nom === 'Premium') ?? paliers[2];

  return (
    <div>
      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
        {paliers.map((p) => {
          const isPopular = p.id === palierPopulaire?.id;
          const desc = descriptionsParPalier[p.nom] ?? { cible: '', cta: "S'inscrire" };
          const tauxTtc = new Intl.NumberFormat('fr-FR', { maximumFractionDigits: 2 }).format(p.taux_commission * 1.2);

          return (
            <div
              key={p.id}
              className={`relative rounded-2xl border p-6 flex flex-col items-center text-center transition-all hover:shadow-lg ${
                isPopular
                  ? 'border-primary bg-primary/5 shadow-md scale-[1.02]'
                  : 'border-border bg-card'
              }`}
            >
              {isPopular && (
                <div className="absolute -top-3 left-1/2 -translate-x-1/2 px-3 py-0.5 bg-primary text-primary-foreground text-xs font-bold rounded-full flex items-center gap-1">
                  <Crown className="h-3 w-3" /> POPULAIRE
                </div>
              )}

              <h3 className="text-lg font-bold text-foreground mt-2">{p.nom}</h3>

              <div className="mt-4 mb-2">
                <span className="text-4xl font-black text-primary">{p.taux_commission}% HT</span>
                <p className="text-xs text-muted-foreground mt-1">{tauxTtc}% TTC avec TVA à 20%</p>
              </div>

              <p className="text-sm text-muted-foreground mb-4">
                {p.missions_max
                  ? `${p.missions_min}–${p.missions_max} missions/mois`
                  : `${p.missions_min}+ missions/mois`}
              </p>

              <p className="text-sm text-foreground font-medium mb-6">{desc.cible}</p>

              <button
                onClick={() => {
                  if (p.nom === 'Partenaire') {
                    window.location.href = 'mailto:support@jolene.app?subject=Partenariat';
                  } else {
                    navigate('/inscription/etablissement');
                  }
                }}
                className={`w-full py-2.5 rounded-xl text-sm font-semibold transition-colors ${
                  isPopular
                    ? 'bg-primary text-primary-foreground hover:bg-primary/90'
                    : 'bg-secondary text-secondary-foreground hover:bg-secondary/80'
                }`}
              >
                {desc.cta}
              </button>
            </div>
          );
        })}
      </div>

      {/* Garanties */}
      <div className="mt-12 grid grid-cols-1 sm:grid-cols-2 gap-3 max-w-2xl mx-auto">
        {[
          'Gratuit pour les soignants — toujours',
          'Le soignant reçoit l\'intégralité de sa rémunération',
          'La commission est un frais de mise en relation facturé à l\'établissement',
          'Les groupes de santé cumulent les missions de tous leurs établissements pour le palier',
        ].map((txt, i) => (
          <div key={i} className="flex items-start gap-2 text-sm text-foreground">
            <Check className="h-4 w-4 text-success mt-0.5 shrink-0" />
            <span>{txt}</span>
          </div>
        ))}
      </div>
    </div>
  );
}
