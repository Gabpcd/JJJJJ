import { useNavigate } from 'react-router-dom';
import { ArrowLeft, Check } from 'lucide-react';
import { SEOHead } from '@/components/SEOHead';
import { usePageTitle } from '@/hooks/usePageTitle';
import { BoutonY2K } from '@/components/y2k/BoutonY2K';

const INCLUS = [
  'Publication de missions illimitée',
  'Soignants vérifiés (identité, diplômes, RPPS, RCP)',
  'Contrats générés et signés électroniquement',
  'Pointage GPS et suivi des présences',
  'Facturation automatique (Chorus Pro pour le secteur public)',
  'Aucun abonnement, aucun frais caché',
];

export default function Tarifs() {
  usePageTitle('Tarifs');
  const navigate = useNavigate();

  return (
    <>
      <SEOHead
        title="Tarifs Jolene | Commission unique de 15 %"
        description="Une commission unique de 15 % sur le montant de la mission, sans abonnement ni frais caché. Taux négocié possible pour les groupes."
        url="https://jolene.app/tarifs"
      />
      <div className="min-h-[100dvh] bg-background flex flex-col">
        <header className="py-4 px-4 border-b border-border bg-card">
          <div className="max-w-6xl mx-auto flex items-center justify-between">
            <button onClick={() => navigate('/')} className="flex items-center gap-2 text-sm text-muted-foreground hover:text-foreground transition-colors">
              <ArrowLeft className="h-4 w-4" /> Retour
            </button>
            <button onClick={() => navigate('/inscription/etablissement')} className="btn-primary text-sm">
              S'inscrire gratuitement
            </button>
          </div>
        </header>

        <main className="flex-1 max-w-3xl mx-auto px-4 py-16 w-full">
          <div className="text-center mb-12">
            <h1 className="text-3xl md:text-4xl font-black text-foreground mb-3">
              Nos tarifs — Transparence totale
            </h1>
            <p className="text-lg text-muted-foreground max-w-2xl mx-auto">
              Une commission unique sur le montant de la mission. Pas d'abonnement, pas de frais caché, pas de surprise.
            </p>
          </div>

          <div className="card-base text-center p-8 md:p-10">
            <p className="text-sm font-semibold uppercase tracking-widest text-muted-foreground mb-2">Commission Jolene</p>
            <p className="text-6xl font-black text-primary mb-2">15 %</p>
            <p className="text-sm text-muted-foreground mb-8">
              du montant brut de la mission, facturée à l'établissement.
              <br />Taux négocié possible pour les groupes — <a href="mailto:support@jolene.app" className="text-primary underline">contactez-nous</a>.
            </p>
            <ul className="text-left max-w-md mx-auto space-y-2.5">
              {INCLUS.map((item) => (
                <li key={item} className="flex items-start gap-2.5 text-sm text-foreground">
                  <Check className="h-4 w-4 text-success shrink-0 mt-0.5" />
                  {item}
                </li>
              ))}
            </ul>

            {/* CTA en bas de carte : l'étab vient de lire toute la valeur,
                il peut agir immédiatement sans remonter au header */}
            <div className="mt-8 flex flex-col items-center gap-2">
              <BoutonY2K variant="primary" onClick={() => navigate('/inscription/etablissement')}>
                S'inscrire gratuitement
              </BoutonY2K>
              <p className="text-xs text-muted-foreground">Sans engagement · 2 minutes</p>
            </div>
          </div>

          <p className="text-center text-xs text-muted-foreground mt-6">
            Aucun frais pour les soignants, quel que soit le contrat.
          </p>
        </main>

        <footer className="py-8 text-center text-sm text-muted-foreground border-t border-border bg-card">
          <p>© 2026 Jolene SAS — Conforme RGPD · Code du Travail</p>
        </footer>
      </div>
    </>
  );
}
