import React, { useState } from 'react';
import { LayoutApp } from '@/components/LayoutApp';
import { Crown, Zap, BarChart3, Award, Bell, FileText, Calculator, Receipt, ClipboardList, HelpCircle, CheckCircle2, Loader2 } from 'lucide-react';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Button } from '@/components/ui/button';
import { Badge } from '@/components/ui/badge';
import { Input } from '@/components/ui/input';
import { supabase } from '@/integrations/supabase/client';
import { toast } from 'sonner';

const PREMIUM_FEATURES = [
  { icone: Zap, label: 'Accès prioritaire aux missions' },
  { icone: BarChart3, label: 'Statistiques avancées de vos gains' },
  { icone: Award, label: 'Badge doré visible par les établissements' },
  { icone: Bell, label: 'Alertes missions personnalisées' },
];

const LIBERAL_FEATURES = [
  { icone: Zap, label: 'Tout Premium inclus' },
  { icone: FileText, label: 'Génération automatique des notes d\'honoraires' },
  { icone: Receipt, label: 'Export comptable compatible Indy' },
  { icone: Calculator, label: 'Tableau de bord charges sociales (URSSAF, CARPIMKO)' },
  { icone: ClipboardList, label: 'Rappels déclarations fiscales' },
  { icone: HelpCircle, label: 'Assistant TVA' },
];

export default function PremiumSoignant() {
  const [email, setEmail] = useState('');
  const [submitting, setSubmitting] = useState(false);

  const inscrire = async () => {
    const trimmed = email.trim();
    if (!trimmed || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(trimmed)) {
      toast.error('Email invalide');
      return;
    }
    setSubmitting(true);
    const { data: { user } } = await supabase.auth.getUser();
    const { error } = await (supabase.from('liste_attente_premium' as any) as any).insert({ email: trimmed, type_offre: 'PREMIUM', utilisateur_id: user?.id });
    setSubmitting(false);
    if (error) { toast.error('Erreur lors de l\'inscription. Veuillez réessayer.'); return; }
    toast.success('Inscrit(e) à la liste d\'attente !');
    setEmail('');
  };

  return (
    <LayoutApp role="SOIGNANT">
      <div className="max-w-4xl mx-auto space-y-8">
        {/* Hero */}
        <div className="text-center space-y-3">
          <div className="inline-flex items-center justify-center w-16 h-16 rounded-2xl bg-warning/10 mx-auto">
            <Crown className="h-8 w-8 text-warning" />
          </div>
          <h1 className="text-2xl font-bold text-foreground">Jolene Premium</h1>
          <p className="text-muted-foreground text-sm max-w-lg mx-auto">
            Boostez votre carrière avec des outils exclusifs pour décrocher plus de missions et gérer votre activité.
          </p>
        </div>

        {/* Two cards side by side */}
        <div className="grid md:grid-cols-2 gap-6">
          {/* Premium */}
          <Card className="border-primary/20 relative overflow-hidden">
            <div className="absolute top-0 left-0 right-0 h-1 bg-primary" />
            <CardHeader className="pb-2">
              <Badge variant="secondary" className="w-fit text-xs mb-2">Premium</Badge>
              <CardTitle className="text-lg">Premium</CardTitle>
              <div className="mt-1">
                <span className="text-3xl font-bold text-foreground">9,99 €</span>
                <span className="text-muted-foreground text-sm"> / mois</span>
              </div>
            </CardHeader>
            <CardContent className="space-y-4">
              <ul className="space-y-2.5">
                {PREMIUM_FEATURES.map((f) => (
                  <li key={f.label} className="flex items-start gap-2.5 text-sm">
                    <CheckCircle2 className="h-4 w-4 text-primary shrink-0 mt-0.5" />
                    <span className="text-foreground">{f.label}</span>
                  </li>
                ))}
              </ul>
              <Button disabled className="w-full opacity-60 cursor-not-allowed">
                🚀 Bientôt disponible
              </Button>
            </CardContent>
          </Card>

          {/* Pack Libéral */}
          <Card className="border-warning/30 relative overflow-hidden">
            <div className="absolute top-0 left-0 right-0 h-1 bg-warning" />
            <CardHeader className="pb-2">
              <Badge className="w-fit text-xs mb-2 bg-warning/10 text-warning border-warning/30">Recommandé</Badge>
              <CardTitle className="text-lg">Pack Libéral</CardTitle>
              <div className="mt-1">
                <span className="text-3xl font-bold text-foreground">19,99 €</span>
                <span className="text-muted-foreground text-sm"> / mois</span>
              </div>
            </CardHeader>
            <CardContent className="space-y-4">
              <ul className="space-y-2.5">
                {LIBERAL_FEATURES.map((f) => (
                  <li key={f.label} className="flex items-start gap-2.5 text-sm">
                    <CheckCircle2 className="h-4 w-4 text-warning shrink-0 mt-0.5" />
                    <span className="text-foreground">{f.label}</span>
                  </li>
                ))}
              </ul>
              <Button disabled className="w-full opacity-60 cursor-not-allowed">
                🚀 Bientôt disponible
              </Button>
            </CardContent>
          </Card>
        </div>

        {/* Waitlist */}
        <Card>
          <CardContent className="pt-6 text-center space-y-4">
            <p className="font-semibold text-foreground">📬 Inscrivez-vous à la liste d'attente</p>
            <p className="text-xs text-muted-foreground">Soyez parmi les premiers informés du lancement.</p>
            <div className="flex gap-2 max-w-md mx-auto">
              <Input
                type="email"
                placeholder="votre@email.com"
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                onKeyDown={(e) => e.key === 'Enter' && inscrire()}
              />
              <Button onClick={inscrire} disabled={submitting} className="shrink-0 gap-2">
                {submitting && <Loader2 className="h-4 w-4 animate-spin" />}
                S'inscrire
              </Button>
            </div>
            <p className="text-[11px] text-muted-foreground">Sans engagement. Annulation à tout moment.</p>
          </CardContent>
        </Card>
      </div>
    </LayoutApp>
  );
}
