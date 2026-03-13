import React from 'react';
import { LayoutApp } from '@/components/LayoutApp';
import { Crown, Zap, BarChart3, Award, CheckCircle2 } from 'lucide-react';
import { Card, CardContent } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';

const AVANTAGES = [
  { icone: Zap, titre: 'Accès prioritaire aux missions', description: 'Recevez les nouvelles missions avant les autres soignants et postulez en premier.' },
  { icone: BarChart3, titre: 'Statistiques avancées', description: 'Visualisez vos gains par mois, taux d\'acceptation, et évolution de votre score de fiabilité.' },
  { icone: Award, titre: 'Badge doré Premium', description: 'Un badge distinctif visible par les établissements pour maximiser vos chances de sélection.' },
  { icone: Crown, titre: 'Support prioritaire', description: 'Assistance dédiée avec un temps de réponse garanti sous 24h.' },
];

export default function PremiumSoignant() {
  return (
    <LayoutApp role="SOIGNANT">
      <div className="max-w-2xl mx-auto space-y-8">
        {/* Hero */}
        <div className="text-center space-y-3">
          <div className="inline-flex items-center justify-center w-16 h-16 rounded-2xl bg-warning/10 mx-auto">
            <Crown className="h-8 w-8 text-warning" />
          </div>
          <h1 className="text-2xl font-bold text-foreground">Soin Direct Premium</h1>
          <p className="text-muted-foreground text-sm max-w-md mx-auto">
            Boostez votre visibilité et accédez à des fonctionnalités exclusives pour décrocher plus de missions.
          </p>
        </div>

        {/* Avantages */}
        <div className="grid gap-4">
          {AVANTAGES.map((a) => (
            <Card key={a.titre}>
              <CardContent className="flex items-start gap-4 pt-5 pb-5">
                <div className="rounded-xl bg-primary/10 p-2.5 shrink-0">
                  <a.icone className="h-5 w-5 text-primary" />
                </div>
                <div>
                  <h3 className="font-semibold text-foreground text-sm">{a.titre}</h3>
                  <p className="text-xs text-muted-foreground mt-1 leading-relaxed">{a.description}</p>
                </div>
                <CheckCircle2 className="h-4 w-4 text-primary shrink-0 mt-1 ml-auto" />
              </CardContent>
            </Card>
          ))}
        </div>

        {/* Prix + CTA */}
        <Card className="border-warning/30 bg-warning/5">
          <CardContent className="pt-6 text-center space-y-4">
            <div>
              <span className="text-3xl font-bold text-foreground">9,99 €</span>
              <span className="text-muted-foreground text-sm"> / mois</span>
            </div>
            <Button disabled size="lg" className="w-full gap-2 opacity-70">
              <Crown className="h-4 w-4" />
              S'abonner — 9,99 €/mois
            </Button>
            <Badge variant="secondary" className="text-xs">
              🚀 Bientôt disponible
            </Badge>
            <p className="text-[11px] text-muted-foreground">Sans engagement. Annulation à tout moment.</p>
          </CardContent>
        </Card>
      </div>
    </LayoutApp>
  );
}
