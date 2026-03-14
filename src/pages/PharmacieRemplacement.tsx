import React from 'react';
import { SEOHead } from '@/components/SEOHead';
import { SEOPageLayout } from '@/components/SEOPageLayout';
import { Badge } from '@/components/ui/badge';
import { Building2, Clock, UserCheck, ShieldCheck } from 'lucide-react';

const typesMissions = [
  { titre: 'Remplacement de titulaire', desc: 'Congés, maladie, formation : trouvez un pharmacien diplômé pour assurer la continuité de votre officine.', badge: 'Pharmacien' },
  { titre: 'Renfort préparateur', desc: 'Pics d\'activité, inventaires, périodes de vaccination : renforcez votre équipe avec des préparateurs qualifiés.', badge: 'Préparateur' },
  { titre: 'Garde et astreinte', desc: 'Gardes de nuit, week-ends et jours fériés : assurez le service de garde avec des professionnels fiables.', badge: 'Garde' },
];

export default function PharmacieRemplacement() {
  return (
    <>
      <SEOHead
        title="Remplacement pharmacie | Trouvez un pharmacien | Soin Direct"
        description="Trouvez un pharmacien remplaçant ou un préparateur en pharmacie rapidement. Soin Direct, partenaire du Groupe Leader Santé, simplifie le remplacement en officine."
        url="https://app.soindirect.com/pharmacie-remplacement"
      />
      <SEOPageLayout
        heroTitle="Trouvez un pharmacien remplaçant rapidement"
        heroSubtitle="Soin Direct simplifie le remplacement en pharmacie d'officine : pharmaciens titulaires, préparateurs et gardes, disponibles en quelques heures."
        ctaText="Créer mon espace pharmacie"
        ctaHref="/inscription/etablissement"
      >
        {/* Contexte */}
        <section className="py-16 md:py-20">
          <div className="max-w-4xl mx-auto px-4">
            <h2 className="text-2xl md:text-3xl font-bold text-foreground text-center mb-6">Le remplacement en pharmacie d'officine</h2>
            <div className="grid md:grid-cols-2 gap-8 mt-10">
              <div>
                <h3 className="font-semibold text-foreground text-lg mb-3">Un secteur sous tension</h3>
                <p className="text-muted-foreground leading-relaxed">
                  La pharmacie d'officine fait face à une pénurie croissante de professionnels. En 2025, plus de 30% des pharmacies déclarent avoir des difficultés à trouver des remplaçants, notamment en zone rurale et semi-rurale.
                </p>
              </div>
              <div>
                <h3 className="font-semibold text-foreground text-lg mb-3">L'urgence du remplacement</h3>
                <p className="text-muted-foreground leading-relaxed">
                  Sans pharmacien titulaire présent, une officine ne peut pas ouvrir. Chaque jour de fermeture représente une perte de chiffre d'affaires et un risque pour la santé publique de la zone desservie.
                </p>
              </div>
            </div>
          </div>
        </section>

        {/* Soin Direct pour les pharmacies */}
        <section className="py-16 md:py-20 bg-muted/50">
          <div className="max-w-4xl mx-auto px-4">
            <h2 className="text-2xl md:text-3xl font-bold text-foreground text-center mb-12">Soin Direct pour les pharmacies</h2>
            <div className="grid md:grid-cols-2 lg:grid-cols-4 gap-6">
              {[
                { icon: UserCheck, titre: 'Pharmaciens vérifiés', desc: 'Diplôme, inscription à l\'Ordre et assurance RCP contrôlés.' },
                { icon: Clock, titre: 'Disponibilité rapide', desc: 'Candidatures en quelques heures, même pour les urgences.' },
                { icon: Building2, titre: 'Partenaire Leader Santé', desc: 'Tarifs préférentiels pour les groupements et réseaux de pharmacies.' },
                { icon: ShieldCheck, titre: 'Contrats conformes', desc: 'CDD de remplacement générés automatiquement et signés en ligne.' },
              ].map((item) => (
                <div key={item.titre} className="text-center">
                  <div className="w-14 h-14 rounded-2xl bg-primary/10 flex items-center justify-center mx-auto mb-4">
                    <item.icon className="h-7 w-7 text-primary" />
                  </div>
                  <h3 className="font-semibold text-foreground mb-2 text-sm">{item.titre}</h3>
                  <p className="text-xs text-muted-foreground leading-relaxed">{item.desc}</p>
                </div>
              ))}
            </div>
          </div>
        </section>

        {/* Types de missions */}
        <section className="py-16 md:py-20">
          <div className="max-w-4xl mx-auto px-4">
            <h2 className="text-2xl md:text-3xl font-bold text-foreground text-center mb-12">Types de missions</h2>
            <div className="grid md:grid-cols-3 gap-6">
              {typesMissions.map((m) => (
                <div key={m.titre} className="bg-card border border-border rounded-xl p-6">
                  <Badge variant="secondary" className="mb-4">{m.badge}</Badge>
                  <h3 className="font-semibold text-foreground mb-2">{m.titre}</h3>
                  <p className="text-sm text-muted-foreground leading-relaxed">{m.desc}</p>
                </div>
              ))}
            </div>
          </div>
        </section>
      </SEOPageLayout>
    </>
  );
}
