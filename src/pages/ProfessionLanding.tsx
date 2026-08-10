import React from 'react';
import { useParams, useNavigate } from 'react-router-dom';
import { SEOHead } from '@/components/SEOHead';
import { SEOPageLayout } from '@/components/SEOPageLayout';
import { Accordion, AccordionContent, AccordionItem, AccordionTrigger } from '@/components/ui/accordion';
import { getProfessionBySlug, PROFESSIONS_SEO } from '@/lib/seo-data';
import { MissionsPubliquesSEO } from '@/components/MissionsPubliquesSEO';
import { Euro, Clock, ShieldCheck, TrendingUp, Stethoscope, ArrowRight } from 'lucide-react';

const avantages = [
  { icon: Euro, titre: 'Rémunération transparente', desc: 'Taux et modalités de paiement affichés avant candidature. Zéro frais pour le soignant.' },
  { icon: Clock, titre: 'Flexibilité des horaires', desc: 'Choisissez vos missions, vos jours et vos créneaux. Vous gardez le contrôle de votre emploi du temps.' },
  { icon: ShieldCheck, titre: 'Cadre contractuel traçable', desc: 'Type de contrat affiché, document généré et signatures électroniques tracées.' },
  { icon: TrendingUp, titre: 'Évolution de carrière', desc: 'Missions variées et accompagnement vers le libéral selon les conditions propres à chaque profession.' },
];

const faqParProfession: Record<string, { q: string; a: string }[]> = {
  'infirmier-ide': [
    { q: 'Quel est le taux horaire moyen pour un IDE intérimaire ?', a: 'Le taux horaire moyen pour un(e) IDE intérimaire se situe entre 25 et 35\u20AC brut de l\'heure, selon l\'établissement (public/privé), la zone géographique et les majorations (nuit, week-end, férié). Sur Jolene, le taux est toujours affiché avant la candidature.' },
    { q: 'Quels documents faut-il pour s\'inscrire en tant qu\'IDE ?', a: 'Vous aurez besoin de votre Diplôme d\'État Infirmier, de votre numéro RPPS et d\'une pièce d\'identité. Une assurance RCP en cours de validité est en plus requise pour les missions libérales.' },
    { q: 'Les heures sur Jolene comptent-elles pour le passage en libéral ?', a: 'Les heures validées sur Jolene alimentent votre suivi. Pour les IDE concernés, elles peuvent contribuer au repère de 3 200 heures, sous réserve des règles et justificatifs applicables ; ce compteur ne remplace aucune autorisation professionnelle.' },
    { q: 'Peut-on choisir entre missions en hôpital et en EHPAD ?', a: 'Absolument. Vous pouvez filtrer les missions par type d\'établissement (hôpital public, clinique privée, EHPAD, SSIAD, HAD, etc.) et ne postuler qu\'aux missions qui vous intéressent.' },
  ],
  'aide-soignant': [
    { q: 'Quel est le salaire d\'un aide-soignant intérimaire ?', a: 'Un(e) aide-soignant(e) intérimaire gagne en moyenne entre 16 et 22\u20AC brut de l\'heure, hors majorations. Les missions de nuit et de week-end sont mieux rémunérées.' },
    { q: 'Faut-il un RPPS pour s\'inscrire en tant qu\'AS ?', a: 'Le RPPS reste optionnel à l’inscription pour les aides-soignants. Si vous disposez déjà d’une identité RPPS, Jolene la vérifie dans l’Annuaire Santé ; le DEAS et la pièce d’identité restent obligatoires.' },
    { q: 'Quels types d\'établissements recrutent des AS ?', a: 'Les EHPAD, hôpitaux publics, cliniques privées, SSIAD et HAD recrutent activement des aides-soignants. Sur Jolene, les EHPAD représentent la majorité des missions AS disponibles.' },
    { q: 'Peut-on cumuler des missions en tant qu\'AS ?', a: 'Oui, vous pouvez accepter plusieurs missions dans différents établissements, tant que les horaires ne se chevauchent pas. Jolene vérifie automatiquement les conflits de planning.' },
  ],
  'pharmacien': [
    { q: 'Quelles missions de pharmacien sont proposées ?', a: 'Jolene propose uniquement des missions salariées d’établissement, notamment en pharmacie à usage intérieur (PUI). Le remplacement d’un titulaire d’officine n’entre pas dans le périmètre de la plateforme.' },
    { q: 'Faut-il un numéro RPPS ?', a: 'Oui. Le numéro RPPS et les justificatifs correspondant au poste salarié sont vérifiés avant l’attribution de la mission.' },
    { q: 'Quel contrat est généré ?', a: 'Les missions pharmacien proposées sur Jolene donnent lieu à un contrat salarié et à un bulletin de paie, jamais à une note d’honoraires.' },
  ],
};

const defaultFaq = [
  { q: 'Comment s\'inscrire sur Jolene ?', a: 'L\'inscription est gratuite et prend moins de 2 minutes. Renseignez votre profession, puis téléversez votre diplôme, votre identifiant professionnel lorsqu’il existe et les pièces demandées pour le contrat visé. La RCP est requise pour les missions libérales.' },
  { q: 'Quels types de contrats sont proposés ?', a: 'Jolene propose des missions salariées en CDD, y compris des CDD courts, et des missions en exercice libéral lorsqu’elles sont explicitement ouvertes. Le type de contrat est précisé sur chaque annonce.' },
  { q: 'Comment est calculée la rémunération ?', a: 'Le taux horaire brut est affiché sur chaque mission. S\'y ajoutent les majorations légales (nuit, week-end, férié), l\'IFM (10%) et l\'ICP (10%) pour les CDD. Le détail complet est visible avant la candidature.' },
  { q: 'Dans quels établissements puis-je travailler ?', a: 'Jolene référence des hôpitaux publics, cliniques privées, EHPAD, SSIAD, HAD, centres de santé, laboratoires et établissements médico-sociaux (IME, MAS, FAM).' },
];

export default function ProfessionLanding() {
  const { profession: professionSlug } = useParams<{ profession: string }>();
  const navigate = useNavigate();
  const profession = professionSlug ? getProfessionBySlug(professionSlug) : undefined;

  const professionLabel = profession?.label || (professionSlug ? professionSlug.replace(/-/g, ' ') : 'Profession');
  const professionDesc = profession?.description || 'Trouvez des missions adaptées à votre profession sur Jolene Santé.';
  const salaire = profession?.salaire_moyen || '20-40\u20AC/h';

  const faq = (professionSlug && faqParProfession[professionSlug]) ? faqParProfession[professionSlug] : defaultFaq;

  return (
    <>
      <SEOHead
        title={`Missions ${professionLabel} — remplacements & CDD courts | Jolene Santé`}
        description={`${professionDesc} Taux horaire moyen : ${salaire}. Inscription gratuite, profils vérifiés et modalités de paiement affichées avant candidature.`}
        url={`https://jolene.app/metier/${professionSlug}`}
      />
      <SEOPageLayout
        heroTitle={`Missions ${professionLabel}`}
        heroSubtitle={professionDesc}
        ctaText="M'inscrire gratuitement"
        ctaHref="/inscription/soignant"
      >
        {/* Benefits grid */}
        <section className="py-16 md:py-20">
          <div className="max-w-6xl mx-auto px-4">
            <h2 className="text-2xl md:text-3xl font-bold text-foreground text-center mb-12">
              Pourquoi choisir Jolene pour vos missions
            </h2>
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

        {/* Salary / Rate info */}
        <section className="py-16 md:py-20 bg-muted/50">
          <div className="max-w-4xl mx-auto px-4">
            <h2 className="text-2xl md:text-3xl font-bold text-foreground text-center mb-8">
              Rémunération {professionLabel}
            </h2>
            <div className="bg-card border border-border rounded-xl p-6 md:p-8">
              <div className="grid md:grid-cols-3 gap-6 text-center">
                <div>
                  <p className="text-3xl font-extrabold text-primary mb-1">{salaire}</p>
                  <p className="text-sm text-muted-foreground">Taux horaire brut moyen</p>
                </div>
                <div>
                  <p className="text-3xl font-extrabold text-primary mb-1">+10%</p>
                  <p className="text-sm text-muted-foreground">IFM (Indemnité de Fin de Mission)</p>
                </div>
                <div>
                  <p className="text-3xl font-extrabold text-primary mb-1">+10%</p>
                  <p className="text-sm text-muted-foreground">ICP (Congés Payés)</p>
                </div>
              </div>
              <div className="border-t border-border mt-6 pt-6">
                <p className="text-sm text-muted-foreground text-center leading-relaxed">
                  Les taux affichés sont indicatifs et varient selon l'établissement, la zone géographique et les majorations applicables (nuit +25%, dimanche +40%, férié +100%).
                  Sur Jolene, le taux horaire exact est toujours affiché <strong className="text-foreground">avant</strong> votre candidature.
                </p>
              </div>
            </div>
          </div>
        </section>

        {/* FAQ Accordion */}
        <section className="py-16 md:py-20">
          <div className="max-w-3xl mx-auto px-4">
            <h2 className="text-2xl md:text-3xl font-bold text-foreground text-center mb-10">
              Questions fréquentes — {professionLabel}
            </h2>
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

        {/* Other professions */}
        <section className="py-16 md:py-20 bg-muted/50">
          <div className="max-w-5xl mx-auto px-4">
            <h2 className="text-2xl md:text-3xl font-bold text-foreground text-center mb-8">
              Découvrir d'autres métiers
            </h2>
            <div className="flex flex-wrap justify-center gap-3">
              {PROFESSIONS_SEO.filter(p => p.slug !== professionSlug).slice(0, 10).map((p) => (
                <a
                  key={p.slug}
                  href={`/metier/${p.slug}`}
                  className="inline-flex items-center gap-1.5 bg-card border border-border rounded-lg px-4 py-2 text-sm font-medium text-foreground hover:border-primary/40 hover:text-primary transition-colors"
                >
                  <Stethoscope className="h-3.5 w-3.5" />
                  {p.label}
                </a>
              ))}
            </div>
          </div>
        </section>
        <MissionsPubliquesSEO profession={profession?.valeur} campagne={`seo-metier-${professionSlug || ''}`} />
      </SEOPageLayout>
    </>
  );
}
