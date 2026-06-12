import React from 'react';
import { SEOHead } from '@/components/SEOHead';
import { SEOPageLayout } from '@/components/SEOPageLayout';
import { Accordion, AccordionContent, AccordionItem, AccordionTrigger } from '@/components/ui/accordion';
import { CheckCircle, Gift } from 'lucide-react';

// Jalons du compteur 3 200 h — ce que Jolene fait réellement à chaque étape.
// Les promesses de prise en charge financière « Free Transition » (25/50/75/
// 100 % des frais) ont été retirées : aucun programme de ce type n'est
// implémenté dans le produit.
const jalons = [
  { heures: '800 h', titre: 'Premier quart du parcours', desc: 'Votre compteur progresse à chaque mission validée — suivi heure par heure depuis votre tableau de bord.' },
  { heures: '1 600 h', titre: 'Mi-parcours', desc: "Vous pouvez déclarer vos heures effectuées hors Jolene (justificatifs à l'appui) pour compléter votre compteur." },
  { heures: '2 400 h', titre: 'Dernière ligne droite', desc: 'Préparez vos démarches : Ordre, CPAM, URSSAF, assurance RCP, compte professionnel — guidées étape par étape.' },
  { heures: '3 200 h', titre: 'Éligibilité atteinte', desc: 'Vous justifiez des heures requises par la convention nationale — attestation de vos heures Jolene disponible.' },
];

const etapesInstallation = [
  { titre: 'Inscription à l\'Ordre Infirmier', desc: 'Demande d\'inscription au tableau de l\'Ordre National des Infirmiers de votre département.' },
  { titre: 'Enregistrement CPAM', desc: 'Obtention de votre numéro de facturation auprès de la Caisse Primaire d\'Assurance Maladie.' },
  { titre: 'Immatriculation URSSAF', desc: 'Création de votre statut professionnel libéral et obtention de votre numéro SIRET.' },
  { titre: 'Assurance RCP', desc: 'Souscription d\'une assurance Responsabilité Civile Professionnelle obligatoire.' },
  { titre: 'Compte bancaire professionnel', desc: 'Ouverture d\'un compte dédié à votre activité libérale.' },
];

const faq = [
  { q: 'Combien de temps faut-il pour atteindre 3 200 heures ?', a: 'En effectuant des remplacements réguliers via Jolene, vous pouvez atteindre 3 200 heures en 18 à 24 mois. Notre tableau de bord vous permet de suivre votre progression en temps réel.' },
  { q: 'Les heures effectuées en dehors de Jolene comptent-elles ?', a: 'Oui. Vous pouvez déclarer vos heures externes en fournissant les justificatifs (attestations employeur, bulletins de paie). Elles sont vérifiées sur justificatifs avant d\'être ajoutées à votre compteur.' },
  { q: "Comment Jolene m'aide-t-il à passer en libéral ?", a: "Jolene suit votre compteur 3 200 heures en temps réel (missions Jolene + heures externes déclarées), vous fournit une attestation de vos heures et vous guide pas à pas dans les démarches d'installation (Ordre, CPAM, URSSAF, RCP, banque)." },
  { q: 'Faut-il un diplôme spécifique pour s\'installer en libéral ?', a: 'Vous devez être titulaire du Diplôme d\'État d\'Infirmier (DEI) et justifier de 3 200 heures d\'exercice en tant que salarié sur les 6 dernières années (ou 2 400h sur 4 ans dans certains cas).' },
  { q: "Jolene m'accompagne-t-il après l'installation ?", a: "Oui. Une fois installé·e en libéral, vous continuez d'accéder aux missions Jolene ouvertes à l'exercice libéral, avec la facturation de vos honoraires gérée par la plateforme." },
];

export default function InfirmiereLiberal() {
  return (
    <>
      <SEOHead
        title="Devenir infirmière libérale | Guide complet"
        description="Découvrez comment passer infirmière libérale avec Jolene : parcours 3 200 h suivi heure par heure, étapes d'installation CPAM, Ordre, URSSAF. Guide complet."
        url="https://jolene.app/infirmiere-liberale"
      />
      <SEOPageLayout
        heroTitle="Passer infirmière libérale avec Jolene"
        heroSubtitle="Cumulez vos 3 200 heures, suivez votre progression heure par heure et installez-vous en libéral en toute sérénité."
        ctaText="Commencer mon parcours"
        ctaHref="/inscription/soignant"
      >
        {/* Parcours 3200h */}
        <section className="py-16 md:py-20">
          <div className="max-w-4xl mx-auto px-4">
            <h2 className="text-2xl md:text-3xl font-bold text-foreground text-center mb-6">Le parcours vers le libéral</h2>
            <p className="text-center text-muted-foreground max-w-2xl mx-auto mb-10">
              Pour exercer en libéral, un(e) infirmier(ère) doit justifier de <strong className="text-foreground">3 200 heures d'exercice salarié</strong> sur les 6 dernières années. Jolene vous aide à atteindre cet objectif en vous proposant des missions de remplacement et en suivant votre progression heure par heure.
            </p>
            <div className="bg-card border border-border rounded-xl p-6 md:p-8">
              <div className="relative">
                <div className="absolute left-5 top-0 bottom-0 w-0.5 bg-border" />
                <div className="space-y-8">
                  {jalons.map((p, i) => (
                    <div key={p.heures} className="flex gap-5 relative">
                      <div className="w-10 h-10 rounded-full bg-primary text-primary-foreground flex items-center justify-center font-bold text-base shrink-0 z-10">{i + 1}</div>
                      <div>
                        <h3 className="font-semibold text-foreground">{p.heures} — {p.titre}</h3>
                        <p className="text-sm text-muted-foreground mt-1">{p.desc}</p>
                      </div>
                    </div>
                  ))}
                </div>
              </div>
            </div>
          </div>
        </section>

        {/* Accompagnement Jolene */}
        <section className="py-16 md:py-20 bg-muted/50">
          <div className="max-w-4xl mx-auto px-4">
            <h2 className="text-2xl md:text-3xl font-bold text-foreground text-center mb-8">Comment Jolene vous accompagne</h2>
            <div className="grid md:grid-cols-3 gap-4">
              <div className="bg-card border border-border rounded-xl p-5 text-center">
                <p className="text-sm font-semibold text-foreground mb-2">Compteur en temps réel</p>
                <p className="text-xs text-muted-foreground">Chaque mission validée alimente votre compteur 3 200 h, visible heure par heure depuis votre tableau de bord.</p>
              </div>
              <div className="bg-card border border-border rounded-xl p-5 text-center">
                <p className="text-sm font-semibold text-foreground mb-2">Heures externes comptabilisées</p>
                <p className="text-xs text-muted-foreground">Déclarez vos heures effectuées hors Jolene avec vos justificatifs (attestations employeur, bulletins de paie).</p>
              </div>
              <div className="bg-card border border-border rounded-xl p-5 text-center">
                <p className="text-sm font-semibold text-foreground mb-2">Guide des démarches</p>
                <p className="text-xs text-muted-foreground">Ordre, CPAM, URSSAF, assurance RCP, compte professionnel : les étapes détaillées, dans le bon ordre.</p>
              </div>
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
