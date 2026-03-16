import React from 'react';
import { SEOHead } from '@/components/SEOHead';
import { SEOPageLayout } from '@/components/SEOPageLayout';
import { Badge } from '@/components/ui/badge';
import { Clock, Euro, ShieldCheck, TrendingUp, UserPlus, ClipboardList, Rocket, Quote } from 'lucide-react';

const avantages = [
  { icon: Euro, titre: 'Rémunération transparente', desc: 'Taux horaire affiché avant de postuler, zéro frais cachés pour le soignant.' },
  { icon: Clock, titre: 'Flexibilité totale', desc: 'Choisissez vos missions, vos horaires et vos établissements. Vous êtes libre.' },
  { icon: ShieldCheck, titre: 'Conformité garantie', desc: 'Contrats générés automatiquement, conformes au Code du Travail et signés électroniquement.' },
  { icon: TrendingUp, titre: 'Parcours vers le libéral', desc: 'Cumulez vos 3 200 heures et bénéficiez de notre programme Free Transition.' },
];

const etapes = [
  { num: '1', titre: 'Créez votre compte', desc: 'Inscription gratuite en 2 minutes. Renseignez votre profession et votre numéro RPPS.' },
  { num: '2', titre: 'Complétez votre profil', desc: 'Téléversez vos documents (diplôme, RCP, pièce d\'identité). Vérification sous 24h.' },
  { num: '3', titre: 'Postulez aux missions', desc: 'Parcourez les missions disponibles près de chez vous et postulez en un clic.' },
];

const professions = [
  'Infirmier(ère) diplômé(e) d\'État', 'Aide-soignant(e)', 'Pharmacien(ne)', 'Préparateur(trice) en pharmacie',
  'Masseur-kinésithérapeute', 'Sage-femme', 'Ergothérapeute', 'Psychomotricien(ne)',
  'Orthophoniste', 'Manipulateur(trice) radio', 'Diététicien(ne)', 'Technicien(ne) de laboratoire',
  'Auxiliaire de puériculture', 'Ambulancier(ère)', 'Opticien(ne)-lunetier(ère)',
];

export default function DevenirSoignant() {
  return (
    <>
      <SEOHead
        title="Devenir soignant remplaçant | Jolene"
        description="Rejoignez Jolene et accédez à des missions de remplacement en santé près de chez vous. Inscription gratuite, rémunération transparente, parcours vers le libéral."
        url="https://app.joleneapp.com/devenir-soignant"
      />
      <SEOPageLayout
        heroTitle="Devenir soignant sur Jolene"
        heroSubtitle="Accédez à des centaines de missions de remplacement en santé, choisissez vos horaires et construisez votre parcours professionnel."
        ctaText="Créer mon compte gratuitement"
        ctaHref="/inscription/soignant"
      >
        {/* Avantages */}
        <section className="py-16 md:py-20">
          <div className="max-w-6xl mx-auto px-4">
            <h2 className="text-2xl md:text-3xl font-bold text-foreground text-center mb-12">Pourquoi rejoindre Soin Direct</h2>
            <div className="grid md:grid-cols-2 lg:grid-cols-4 gap-8">
              {avantages.map((a) => (
                <div key={a.titre} className="text-center">
                  <div className="w-14 h-14 rounded-2xl bg-primary/10 flex items-center justify-center mx-auto mb-4">
                    <a.icon className="h-7 w-7 text-primary" />
                  </div>
                  <h3 className="font-semibold text-foreground mb-2">{a.titre}</h3>
                  <p className="text-sm text-muted-foreground leading-relaxed">{a.desc}</p>
                </div>
              ))}
            </div>
          </div>
        </section>

        {/* Comment ça marche */}
        <section className="py-16 md:py-20 bg-muted/50">
          <div className="max-w-4xl mx-auto px-4">
            <h2 className="text-2xl md:text-3xl font-bold text-foreground text-center mb-12">Comment ça marche</h2>
            <div className="space-y-8">
              {etapes.map((e) => (
                <div key={e.num} className="flex gap-5 items-start">
                  <div className="w-10 h-10 rounded-full bg-primary text-primary-foreground flex items-center justify-center font-bold text-lg shrink-0">{e.num}</div>
                  <div>
                    <h3 className="font-semibold text-foreground text-lg">{e.titre}</h3>
                    <p className="text-muted-foreground mt-1">{e.desc}</p>
                  </div>
                </div>
              ))}
            </div>
          </div>
        </section>

        {/* Professions */}
        <section className="py-16 md:py-20">
          <div className="max-w-4xl mx-auto px-4">
            <h2 className="text-2xl md:text-3xl font-bold text-foreground text-center mb-8">Professions recherchées</h2>
            <p className="text-center text-muted-foreground mb-8">Soin Direct recrute des professionnels de santé diplômés dans toutes les spécialités.</p>
            <div className="flex flex-wrap justify-center gap-3">
              {professions.map((p) => (
                <Badge key={p} variant="secondary" className="text-sm py-1.5 px-3">{p}</Badge>
              ))}
            </div>
          </div>
        </section>

        {/* Témoignage */}
        <section className="py-16 md:py-20 bg-muted/50">
          <div className="max-w-3xl mx-auto px-4 text-center">
            <Quote className="h-10 w-10 text-primary/30 mx-auto mb-6" />
            <blockquote className="text-lg md:text-xl text-foreground italic leading-relaxed mb-6">
              « Grâce à Soin Direct, j'ai pu choisir mes missions librement tout en cumulant mes heures vers le libéral. L'inscription a pris 5 minutes et ma première mission était validée le lendemain. Je recommande à tous mes collègues ! »
            </blockquote>
            <p className="font-semibold text-foreground">Marie D.</p>
            <p className="text-sm text-muted-foreground">Infirmière diplômée d'État — Île-de-France</p>
          </div>
        </section>
      </SEOPageLayout>
    </>
  );
}
