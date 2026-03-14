import React from 'react';
import { SEOHead } from '@/components/SEOHead';
import { SEOPageLayout } from '@/components/SEOPageLayout';
import { Accordion, AccordionContent, AccordionItem, AccordionTrigger } from '@/components/ui/accordion';
import { CheckCircle, Gift } from 'lucide-react';

const paliers = [
  { heures: '800h', taux: '25%', desc: 'Prise en charge de 25% des frais d\'installation (RCP, comptabilité).' },
  { heures: '1 600h', taux: '50%', desc: 'Prise en charge de 50% incluant les frais bancaires professionnels.' },
  { heures: '2 400h', taux: '75%', desc: 'Prise en charge de 75% avec accompagnement personnalisé.' },
  { heures: '3 200h', taux: '100%', desc: 'Prise en charge totale. Transition gratuite vers le libéral.' },
];

const etapesInstallation = [
  { titre: 'Inscription à l\'Ordre Infirmier', desc: 'Demande d\'inscription au tableau de l\'Ordre National des Infirmiers de votre département.' },
  { titre: 'Enregistrement CPAM', desc: 'Obtention de votre numéro de facturation auprès de la Caisse Primaire d\'Assurance Maladie.' },
  { titre: 'Immatriculation URSSAF', desc: 'Création de votre statut professionnel libéral et obtention de votre numéro SIRET.' },
  { titre: 'Assurance RCP', desc: 'Souscription d\'une assurance Responsabilité Civile Professionnelle obligatoire (partenaire MACSF).' },
  { titre: 'Compte bancaire professionnel', desc: 'Ouverture d\'un compte dédié à votre activité libérale (partenaire Qonto).' },
];

const faq = [
  { q: 'Combien de temps faut-il pour atteindre 3 200 heures ?', a: 'En effectuant des remplacements réguliers via Soin Direct, vous pouvez atteindre 3 200 heures en 18 à 24 mois. Notre tableau de bord vous permet de suivre votre progression en temps réel.' },
  { q: 'Les heures effectuées en dehors de Soin Direct comptent-elles ?', a: 'Oui. Vous pouvez déclarer vos heures externes en fournissant les justificatifs (attestations employeur, bulletins de paie). Elles sont validées par notre équipe sous 48h.' },
  { q: 'Qu\'est-ce que le programme Free Transition ?', a: 'Free Transition est notre programme exclusif qui prend en charge progressivement vos frais d\'installation en libéral (comptabilité, assurance, banque) en fonction de vos heures cumulées sur la plateforme.' },
  { q: 'Faut-il un diplôme spécifique pour s\'installer en libéral ?', a: 'Vous devez être titulaire du Diplôme d\'État d\'Infirmier (DEI) et justifier de 3 200 heures d\'exercice en tant que salarié sur les 6 dernières années (ou 2 400h sur 4 ans dans certains cas).' },
  { q: 'Soin Direct m\'accompagne-t-il après l\'installation ?', a: 'Oui. Nos partenaires Indy (comptabilité), MACSF (assurance) et Qonto (banque) proposent des offres préférentielles aux soignants Soin Direct, avec un accompagnement dédié.' },
];

export default function InfirmiereLiberal() {
  return (
    <>
      <SEOHead
        title="Devenir infirmière libérale | Guide complet | Soin Direct"
        description="Découvrez comment passer infirmière libérale avec Soin Direct : parcours 3200h, programme Free Transition, étapes d'installation CPAM, Ordre, URSSAF. Guide complet."
        url="https://app.soindirect.com/infirmiere-liberale"
      />
      <SEOPageLayout
        heroTitle="Passer infirmière libérale avec Soin Direct"
        heroSubtitle="Cumulez vos 3 200 heures, bénéficiez de notre programme Free Transition et installez-vous en libéral en toute sérénité."
        ctaText="Commencer mon parcours"
        ctaHref="/inscription/soignant"
      >
        {/* Parcours 3200h */}
        <section className="py-16 md:py-20">
          <div className="max-w-4xl mx-auto px-4">
            <h2 className="text-2xl md:text-3xl font-bold text-foreground text-center mb-6">Le parcours vers le libéral</h2>
            <p className="text-center text-muted-foreground max-w-2xl mx-auto mb-10">
              Pour exercer en libéral, un(e) infirmier(ère) doit justifier de <strong className="text-foreground">3 200 heures d'exercice salarié</strong> sur les 6 dernières années. Soin Direct vous aide à atteindre cet objectif en vous proposant des missions de remplacement et en suivant votre progression heure par heure.
            </p>
            <div className="bg-card border border-border rounded-xl p-6 md:p-8">
              <div className="relative">
                <div className="absolute left-5 top-0 bottom-0 w-0.5 bg-border" />
                <div className="space-y-8">
                  {paliers.map((p, i) => (
                    <div key={p.heures} className="flex gap-5 relative">
                      <div className="w-10 h-10 rounded-full bg-primary text-primary-foreground flex items-center justify-center font-bold text-sm shrink-0 z-10">{p.heures}</div>
                      <div>
                        <h3 className="font-semibold text-foreground">Palier {i + 1} — {p.taux} pris en charge</h3>
                        <p className="text-sm text-muted-foreground mt-1">{p.desc}</p>
                      </div>
                    </div>
                  ))}
                </div>
              </div>
            </div>
          </div>
        </section>

        {/* Free Transition */}
        <section className="py-16 md:py-20 bg-muted/50">
          <div className="max-w-4xl mx-auto px-4">
            <div className="flex items-center justify-center gap-3 mb-8">
              <Gift className="h-8 w-8 text-primary" />
              <h2 className="text-2xl md:text-3xl font-bold text-foreground">Free Transition</h2>
            </div>
            <p className="text-center text-muted-foreground max-w-2xl mx-auto mb-10">
              Notre programme exclusif prend en charge progressivement vos frais d'installation en libéral : comptabilité, assurance RCP, compte bancaire professionnel et accompagnement administratif.
            </p>
            <div className="grid md:grid-cols-4 gap-4">
              {paliers.map((p, i) => (
                <div key={p.heures} className="bg-card border border-border rounded-xl p-5 text-center">
                  <p className="text-2xl font-extrabold text-primary mb-1">{p.taux}</p>
                  <p className="text-sm font-semibold text-foreground mb-2">à {p.heures}</p>
                  <p className="text-xs text-muted-foreground">{p.desc}</p>
                </div>
              ))}
            </div>
          </div>
        </section>

        {/* Étapes installation */}
        <section className="py-16 md:py-20">
          <div className="max-w-4xl mx-auto px-4">
            <h2 className="text-2xl md:text-3xl font-bold text-foreground text-center mb-12">Les étapes de l'installation</h2>
            <div className="space-y-6">
              {etapesInstallation.map((e) => (
                <div key={e.titre} className="flex gap-4 items-start">
                  <CheckCircle className="h-6 w-6 text-primary shrink-0 mt-0.5" />
                  <div>
                    <h3 className="font-semibold text-foreground">{e.titre}</h3>
                    <p className="text-sm text-muted-foreground mt-1">{e.desc}</p>
                  </div>
                </div>
              ))}
            </div>
          </div>
        </section>

        {/* FAQ */}
        <section className="py-16 md:py-20 bg-muted/50">
          <div className="max-w-3xl mx-auto px-4">
            <h2 className="text-2xl md:text-3xl font-bold text-foreground text-center mb-10">FAQ — Passage en libéral</h2>
            <Accordion type="single" collapsible className="space-y-2">
              {faq.map((f, i) => (
                <AccordionItem key={i} value={`faq-${i}`} className="bg-card border border-border rounded-lg px-4">
                  <AccordionTrigger className="text-left text-foreground">{f.q}</AccordionTrigger>
                  <AccordionContent className="text-muted-foreground">{f.a}</AccordionContent>
                </AccordionItem>
              ))}
            </Accordion>
          </div>
        </section>
      </SEOPageLayout>
    </>
  );
}
