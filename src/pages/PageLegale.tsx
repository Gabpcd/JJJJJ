import React from 'react';
import { useLocation } from 'react-router-dom';
import { HeartPulse } from 'lucide-react';
import { FooterLegal } from '@/components/FooterLegal';

const PAGES: Record<string, { titre: string; contenu: string }> = {
  '/cgu': {
    titre: 'Conditions Générales d\'Utilisation',
    contenu: 'Les CGU de Soin Direct sont en cours de rédaction par notre cabinet juridique spécialisé HealthTech. Elles seront publiées avant le lancement officiel de la plateforme. Pour toute question : contact@soindirect.com',
  },
  '/cgv': {
    titre: 'Conditions Générales de Vente',
    contenu: 'Les CGV de Soin Direct sont en cours de rédaction par notre cabinet juridique spécialisé HealthTech. Elles seront publiées avant le lancement officiel de la plateforme. Pour toute question : contact@soindirect.com',
  },
  '/confidentialite': {
    titre: 'Politique de Confidentialité',
    contenu: 'La politique de confidentialité de Soin Direct est en cours de rédaction par notre cabinet juridique spécialisé HealthTech et DPO. Elle sera publiée avant le lancement officiel de la plateforme. Pour toute question : dpo@soindirect.com',
  },
  '/mentions-legales': {
    titre: 'Mentions Légales',
    contenu: 'Les mentions légales de Soin Direct sont en cours de rédaction. Elles seront publiées avant le lancement officiel de la plateforme. Pour toute question : contact@soindirect.com',
  },
};

export default function PageLegale() {
  const { pathname } = useLocation();
  const page = PAGES[pathname] || { titre: 'Page non trouvée', contenu: '' };

  return (
    <div className="min-h-screen bg-background flex flex-col">
      <header className="border-b border-border bg-card">
        <div className="max-w-4xl mx-auto px-4 py-4 flex items-center gap-2">
          <a href="/" className="flex items-center gap-2">
            <HeartPulse className="h-6 w-6 text-primary" />
            <span className="text-lg font-bold text-foreground">Soin Direct</span>
          </a>
        </div>
      </header>
      <main className="flex-1 max-w-4xl mx-auto px-4 py-12">
        <h1 className="text-2xl font-bold text-foreground mb-6">{page.titre}</h1>
        <div className="card-base">
          <p className="text-sm text-muted-foreground leading-relaxed">{page.contenu}</p>
          <p className="text-xs text-muted-foreground mt-6">Dernière mise à jour : Mars 2026</p>
        </div>
      </main>
      <FooterLegal />
    </div>
  );
}
