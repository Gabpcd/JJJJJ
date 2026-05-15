import React, { useState } from 'react';
import { LayoutApp } from '@/components/LayoutApp';
import { Building2, FileSpreadsheet, BarChart3, Globe, Plug, Headphones, FileText, CheckCircle2, Crown } from 'lucide-react';
import {
  CardY2K,
  CardY2KHeader,
  CardY2KTitle,
  CardY2KContent,
} from '@/components/y2k/CardY2K';
import { BoutonY2K } from '@/components/y2k/BoutonY2K';
import { Badge } from '@/components/ui/badge';
import { Input } from '@/components/ui/input';
import { supabase } from '@/integrations/supabase/client';
import { toast } from 'sonner';

const PRO_FEATURES = [
  { icone: FileSpreadsheet, label: 'Export paie automatique (Silae, Sage, ADP)' },
  { icone: BarChart3, label: 'Tableau de bord RH (turnover, coût moyen, prévisions)' },
  { icone: Globe, label: 'Gestion multi-sites' },
  { icone: Plug, label: 'API SIRH' },
  { icone: Headphones, label: 'Support dédié' },
  { icone: FileText, label: 'Rapport PDF mensuel automatique' },
];

export default function PremiumEtablissement() {
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
    const { error } = await (supabase.from('liste_attente_premium' as any) as any).insert({ email: trimmed, type_offre: 'PRO_ETABLISSEMENT', utilisateur_id: user?.id });
    setSubmitting(false);
    if (error) { toast.error('Une erreur est survenue. Veuillez réessayer.'); return; }
    toast.success('Inscrit(e) à la liste d\'attente !');
    setEmail('');
  };

  return (
    <LayoutApp role="ADMIN_ETABLISSEMENT">
      <div className="max-w-2xl mx-auto space-y-8">
        {/* Hero */}
        <div className="text-center space-y-3">
          <div className="inline-flex items-center justify-center w-16 h-16 rounded-2xl bg-primary/10 mx-auto">
            <Building2 className="h-8 w-8 text-primary" />
          </div>
          <h1 className="text-2xl font-bold text-foreground">Jolene Pro</h1>
          <p className="text-muted-foreground text-sm max-w-lg mx-auto">
            Des outils avancés pour piloter vos recrutements et simplifier votre gestion administrative.
          </p>
        </div>

        {/* Card */}
        <CardY2K variant="holographic" noPadding className="relative overflow-hidden">
          <div className="absolute top-0 left-0 right-0 h-1 bg-primary" />
          <CardY2KHeader className="pb-2">
            <Badge variant="secondary" className="w-fit text-xs mb-2">Pack Établissement</Badge>
            <CardY2KTitle className="text-lg">Pack Établissement Pro</CardY2KTitle>
            <div className="mt-1">
              <span className="text-3xl font-bold text-foreground">49,99 €</span>
              <span className="text-muted-foreground text-sm"> / mois</span>
            </div>
          </CardY2KHeader>
          <CardY2KContent className="space-y-4">
            <ul className="space-y-2.5">
              {PRO_FEATURES.map((f) => (
                <li key={f.label} className="flex items-start gap-2.5 text-sm">
                  <CheckCircle2 className="h-4 w-4 text-primary shrink-0 mt-0.5" />
                  <span className="text-foreground">{f.label}</span>
                </li>
              ))}
            </ul>
            <BoutonY2K disabled className="w-full opacity-60" aria-label="Offre Pro non disponible pour le moment">
              🚀 Bientôt disponible
            </BoutonY2K>
            <p className="text-xs text-muted-foreground text-center">Disponible prochainement — inscrivez-vous ci-dessous pour être informé(e)</p>
          </CardY2KContent>
        </CardY2K>

        {/* Waitlist */}
        <CardY2K noPadding>
          <CardY2KContent className="pt-6 text-center space-y-4">
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
              <BoutonY2K onClick={inscrire} disabled={submitting} loading={submitting} className="shrink-0">
                S'inscrire
              </BoutonY2K>
            </div>
            <p className="text-[11px] text-muted-foreground">Sans engagement. Annulation à tout moment.</p>
          </CardY2KContent>
        </CardY2K>
      </div>
    </LayoutApp>
  );
}
