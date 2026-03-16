import React from 'react';
import { useNavigate } from 'react-router-dom';
import { SEOHead } from '@/components/SEOHead';
import { SEOPageLayout } from '@/components/SEOPageLayout';
import { ShieldCheck, Scale, PercentCircle, Receipt, PlusCircle, UserCheck, FileText, ArrowRight } from 'lucide-react';

const garanties = [
  { icon: ShieldCheck, titre: 'RPPS vérifié', desc: 'Chaque soignant est vérifié via le Répertoire Partagé des Professionnels de Santé. Diplômes et assurance RCP contrôlés.' },
  { icon: Scale, titre: 'Conformité Code du Travail', desc: 'Contrats CDD d\'usage générés automatiquement, durées maximales respectées, repos obligatoires vérifiés.' },
  { icon: PercentCircle, titre: 'Commission dégressive', desc: 'Plus vous publiez de missions, plus votre taux de commission baisse. Jusqu\'à -40% pour les grands volumes.' },
  { icon: Receipt, titre: 'Facturation automatique', desc: 'Factures mensuelles consolidées, compatibles Chorus Pro pour le secteur public. Paiement par carte ou virement.' },
];

const etapes = [
  { num: '1', titre: 'Créez votre espace', desc: 'Inscription gratuite avec SIRET et FINESS. Votre espace est opérationnel en 10 minutes.' },
  { num: '2', titre: 'Publiez une mission', desc: 'Renseignez la profession, les dates, les horaires et le taux horaire. La mission est visible immédiatement.' },
  { num: '3', titre: 'Recevez des candidatures', desc: 'Les soignants vérifiés postulent. Vous validez, le contrat est généré et signé électroniquement.' },
];

export default function RecruterSoignants() {
  const navigate = useNavigate();

  return (
    <>
      <SEOHead
        title="Recruter des soignants qualifiés | Jolene"
        description="Publiez vos missions de remplacement médical et recevez des candidatures de soignants vérifiés en quelques heures. Commission dégressive, facturation automatique."
        url="https://app.joleneapp.com/recruter-soignants"
      />
      <SEOPageLayout
        heroTitle="Recrutez des soignants qualifiés en quelques heures"
        heroSubtitle="Fini les appels aux agences d'intérim. Publiez vos missions et recevez des candidatures de professionnels vérifiés, en toute conformité."
        ctaText="Créer mon espace établissement"
        ctaHref="/inscription/etablissement"
      >
        {/* Problème / Solution */}
        <section className="py-16 md:py-20">
          <div className="max-w-4xl mx-auto px-4">
            <h2 className="text-2xl md:text-3xl font-bold text-foreground text-center mb-12">Le staffing médical simplifié</h2>
            <div className="grid md:grid-cols-2 gap-8">
              <div className="bg-destructive/5 border border-destructive/20 rounded-xl p-6">
                <h3 className="font-semibold text-destructive mb-3">😤 Le problème</h3>
                <ul className="space-y-2 text-sm text-muted-foreground">
                  <li>• Agences d'intérim coûteuses (20-30% de marge)</li>
                  <li>• Délais de recrutement de plusieurs jours</li>
                  <li>• Paperasse administrative chronophage</li>
                  <li>• Aucune garantie sur les qualifications</li>
                </ul>
              </div>
              <div className="bg-primary/5 border border-primary/20 rounded-xl p-6">
                <h3 className="font-semibold text-primary mb-3">✅ La solution Soin Direct</h3>
                <ul className="space-y-2 text-sm text-muted-foreground">
                  <li>• Commission dégressive à partir de 8%</li>
                  <li>• Candidatures en quelques heures</li>
                  <li>• Contrats et pointage automatisés</li>
                  <li>• Soignants RPPS vérifiés</li>
                </ul>
              </div>
            </div>
          </div>
        </section>

        {/* Garanties */}
        <section className="py-16 md:py-20 bg-muted/50">
          <div className="max-w-6xl mx-auto px-4">
            <h2 className="text-2xl md:text-3xl font-bold text-foreground text-center mb-12">Nos garanties</h2>
            <div className="grid md:grid-cols-2 lg:grid-cols-4 gap-8">
              {garanties.map((g) => (
                <div key={g.titre} className="text-center">
                  <div className="w-14 h-14 rounded-2xl bg-primary/10 flex items-center justify-center mx-auto mb-4">
                    <g.icon className="h-7 w-7 text-primary" />
                  </div>
                  <h3 className="font-semibold text-foreground mb-2">{g.titre}</h3>
                  <p className="text-sm text-muted-foreground leading-relaxed">{g.desc}</p>
                </div>
              ))}
            </div>
          </div>
        </section>

        {/* Étapes */}
        <section className="py-16 md:py-20">
          <div className="max-w-4xl mx-auto px-4">
            <h2 className="text-2xl md:text-3xl font-bold text-foreground text-center mb-12">Comment publier une mission</h2>
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

        {/* Tarification */}
        <section className="py-16 md:py-20 bg-muted/50">
          <div className="max-w-3xl mx-auto px-4 text-center">
            <h2 className="text-2xl md:text-3xl font-bold text-foreground mb-4">Tarification transparente</h2>
            <p className="text-muted-foreground mb-8">
              Une commission dégressive qui récompense votre fidélité. Plus vous publiez de missions, moins vous payez. Aucun abonnement, aucun frais cachés.
            </p>
            <button
              onClick={() => navigate('/tarifs')}
              className="inline-flex items-center gap-2 bg-primary text-primary-foreground font-semibold px-6 py-3 rounded-lg hover:bg-primary/90 transition-colors"
            >
              Voir nos tarifs <ArrowRight className="h-4 w-4" />
            </button>
          </div>
        </section>
      </SEOPageLayout>
    </>
  );
}
