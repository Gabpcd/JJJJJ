import React from 'react';
import { SEOHead } from '@/components/SEOHead';
import { SEOPageLayout } from '@/components/SEOPageLayout';
import { Badge } from '@/components/ui/badge';
import { Clock, Euro, ShieldCheck, TrendingUp, UserPlus, ClipboardList, Rocket } from 'lucide-react';
import { PROFESSIONS } from '@/lib/constantes';

const FAQ = [
  { q: "L'inscription est-elle vraiment gratuite ?", r: "Oui, l'inscription est entièrement gratuite pour les soignants, sans aucune commission prélevée sur votre rémunération." },
  { q: "Comment suis-je payé ?", r: "En libéral, l'établissement règle vos honoraires selon le délai indiqué sur la mission ; un paiement accéléré n'est proposé que lorsqu'il est explicitement affiché. En salarié, le salaire est versé par l'établissement employeur." },
  { q: "Quelles professions peuvent s'inscrire ?", r: "Infirmiers, aides-soignants, AES, kinésithérapeutes, pharmaciens, préparateurs en pharmacie, sages-femmes et d'autres professions de santé." },
  { q: "Quels documents dois-je fournir ?", r: "Selon votre profession : pièce d'identité, diplôme, et le cas échéant numéro RPPS et assurance. Tout est vérifié pour rassurer les établissements." },
  { q: "Suis-je obligé d'accepter des missions ?", r: "Non. Vous choisissez librement vos missions, vos dates et votre taux horaire, sans aucune obligation." },
  { q: "Puis-je cumuler avec mon emploi actuel ?", r: "Oui, de nombreux soignants complètent leur planning avec des missions ponctuelles selon leurs disponibilités." },
];

const faqJsonLd = {
  "@context": "https://schema.org",
  "@type": "FAQPage",
  mainEntity: FAQ.map((f) => ({
    "@type": "Question",
    name: f.q,
    acceptedAnswer: { "@type": "Answer", text: f.r },
  })),
};

const avantages = [
  { icon: Euro, titre: 'Rémunération transparente', desc: 'Taux horaire affiché avant de postuler, zéro frais cachés pour le soignant.' },
  { icon: Clock, titre: 'Flexibilité totale', desc: 'Choisissez vos missions, vos horaires et vos établissements. Vous êtes libre.' },
  { icon: ShieldCheck, titre: 'Cadre contractuel vérifiable', desc: 'Type de contrat indiqué avant candidature, document généré et signatures électroniques tracées.' },
  { icon: TrendingUp, titre: 'Parcours vers le libéral', desc: 'Pour les professions infirmières concernées : suivi du seuil de 3 200 heures ; pour les autres métiers, affichage des règles qui leur sont propres.' },
];

const etapes = [
  { num: '1', titre: 'Créez votre compte', desc: 'Inscription gratuite en 2 minutes, par email ou avec votre carte CPS via Pro Santé Connect. Le numéro RPPS n\'est demandé que si votre profession en possède un.' },
  { num: '2', titre: 'Complétez votre profil', desc: 'Téléversez vos documents (diplôme, pièce d\'identité — assurance RCP pour les libéraux). Les contrôles automatiques accélèrent le dossier ; les cas réglementaires sensibles passent en revue humaine.' },
  { num: '3', titre: 'Postulez aux missions', desc: 'Parcourez les missions disponibles près de chez vous et postulez en un clic.' },
];

// Dérivée des constantes produit (source de vérité) — la liste codée en dur
// omettait notamment chirurgien-dentiste, médecin, IADE, IBODE et AES.
const professions = PROFESSIONS.map((p) => p.label);

export default function DevenirSoignant() {
  return (
    <>
      <SEOHead
        title="Devenir soignant remplaçant | Jolene Santé"
        description="Missions de remplacement santé pour infirmiers, aides-soignants et professionnels de santé. Inscription gratuite, rémunération transparente et contrat indiqué avant candidature."
        url="https://jolene.app/devenir-soignant"
        jsonLd={faqJsonLd}
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
            <h2 className="text-2xl md:text-3xl font-bold text-foreground text-center mb-12">Pourquoi rejoindre Jolene</h2>
            <div className="grid md:grid-cols-2 lg:grid-cols-4 gap-4 md:gap-8">
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
            <p className="text-center text-muted-foreground mb-8">Jolene recrute des professionnels de santé diplômés dans toutes les spécialités.</p>
            <div className="flex flex-wrap justify-center gap-3">
              {professions.map((p) => (
                <Badge key={p} variant="secondary" className="text-sm py-1.5 px-3">{p}</Badge>
              ))}
            </div>
          </div>
        </section>

        {/* FAQ */}
        <section className="py-16 bg-card">
          <div className="max-w-3xl mx-auto px-4">
            <h2 className="text-2xl md:text-3xl font-bold text-foreground text-center mb-10">Questions fréquentes</h2>
            <div className="space-y-4">
              {FAQ.map((item, i) => (
                <details key={i} className="group rounded-xl border border-border bg-background p-5">
                  <summary className="cursor-pointer list-none font-semibold text-foreground flex items-center justify-between gap-2">
                    {item.q}
                    <span className="text-primary transition-transform group-open:rotate-45 text-xl leading-none">+</span>
                  </summary>
                  <p className="mt-3 text-muted-foreground leading-relaxed">{item.r}</p>
                </details>
              ))}
            </div>
          </div>
        </section>

      </SEOPageLayout>
    </>
  );
}
