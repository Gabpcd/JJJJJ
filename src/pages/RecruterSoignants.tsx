import React from 'react';
import { useNavigate } from 'react-router-dom';
import { SEOHead } from '@/components/SEOHead';
import { SEOPageLayout } from '@/components/SEOPageLayout';
import { ShieldCheck, Scale, PercentCircle, Receipt, PlusCircle, UserCheck, FileText, ArrowRight } from 'lucide-react';
import { FAQ_RECRUTER_SOIGNANTS } from '@/lib/seo-contenu/recruter-soignants';
import { jsonLdPage, metaRecruterSoignants, urlAbsolue } from '@/lib/seo-routes';

/** Titre, description, H1, accroche et FAQ : mêmes valeurs que le HTML statique (`seo-routes`). */
const meta = metaRecruterSoignants();

const garanties = [
  { icon: ShieldCheck, titre: 'Profil vérifié', desc: 'Identité professionnelle, diplôme, RPPS lorsqu’il existe et pièces requises par le contrat sont contrôlés.' },
  { icon: Scale, titre: 'Conformité Code du Travail', desc: 'Contrats CDD, y compris courts, générés automatiquement, durées maximales respectées et repos obligatoires vérifiés.' },
  { icon: PercentCircle, titre: 'Tarification transparente', desc: 'Commission de 15 % HT, soit 18 % TTC avec la TVA de 20 %, sur le montant de la mission. Aucun abonnement.' },
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
      <SEOHead title={meta.title} description={meta.description} url={urlAbsolue(meta.path)} jsonLd={jsonLdPage(meta)} />
      <SEOPageLayout
        heroTitle={meta.h1}
        heroSubtitle={meta.intro[0]}
        ctaText="Créer mon espace établissement"
        ctaHref="/inscription/etablissement"
      >
        {/* Problème / Solution */}
        <section className="py-16 md:py-20">
          <div className="max-w-4xl mx-auto px-4">
            <h2 className="text-2xl md:text-3xl font-bold text-foreground text-center mb-12">Le staffing médical simplifié</h2>
            <div className="grid md:grid-cols-2 gap-4 md:gap-8">
              <div className="bg-destructive/5 border border-destructive/20 rounded-xl p-6">
                <h3 className="font-semibold text-destructive mb-3">😤 Le problème</h3>
                <ul className="space-y-2 text-sm text-muted-foreground">
                  <li>• Agences de remplacement coûteuses (20-30% de marge)</li>
                  <li>• Délais de recrutement de plusieurs jours</li>
                  <li>• Paperasse administrative chronophage</li>
                  <li>• Aucune garantie sur les qualifications</li>
                </ul>
              </div>
              <div className="bg-primary/5 border border-primary/20 rounded-xl p-6">
                <h3 className="font-semibold text-primary mb-3">✅ La solution Jolene</h3>
                <ul className="space-y-2 text-sm text-muted-foreground">
                  <li>• Commission de 15 % HT (18 % TTC), sans abonnement</li>
                  <li>• Candidatures de soignants vérifiés dès la publication</li>
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
            <div className="grid md:grid-cols-2 lg:grid-cols-4 gap-4 md:gap-8">
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
              Une commission de 15 % HT, soit 18 % TTC avec la TVA de 20 %, sur le montant de la mission — taux HT négocié possible pour les groupes. Aucun abonnement.
            </p>
            <button
              onClick={() => navigate('/tarifs')}
              className="inline-flex items-center gap-2 bg-primary text-primary-foreground font-semibold px-6 py-3 rounded-lg hover:bg-primary/90 transition-colors"
            >
              Voir nos tarifs <ArrowRight className="h-4 w-4" />
            </button>
          </div>
        </section>

        {/* FAQ */}
        <section className="py-16 bg-card">
          <div className="max-w-3xl mx-auto px-4">
            <h2 className="text-2xl md:text-3xl font-bold text-foreground text-center mb-10">Questions fréquentes</h2>
            <div className="space-y-4">
              {FAQ_RECRUTER_SOIGNANTS.map((item, i) => (
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
