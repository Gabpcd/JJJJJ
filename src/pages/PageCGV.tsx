import { usePageTitle } from '@/hooks/usePageTitle';
import React from 'react';
import LayoutLegal from '@/components/LayoutLegal';

const TOC = [
  { id: 'art1', label: 'Article 1 — Objet' },
  { id: 'art2', label: 'Article 2 — Nature des frais de service' },
  { id: 'art3', label: 'Article 3 — Tarification' },
  { id: 'art4', label: 'Article 4 — Bonus de Fidélité Annuel (BFA)' },
  { id: 'art5', label: 'Article 5 — Facturation et paiement' },
  { id: 'art6', label: 'Article 6 — Programme Free Transition' },
  { id: 'art7', label: 'Article 7 — Secteur public et affacturage' },
  { id: 'art8', label: 'Article 8 — Non-sollicitation' },
];

export default function PageCGV() {
  usePageTitle('CGV');
  return (
    <LayoutLegal
      titre="Conditions Générales de Vente"
      dateMaj="12 mars 2026"
      toc={TOC}
      seoDescription="Conditions Générales de Vente de Jolene. Frais de service, tarification, Bonus de Fidélité Annuel, facturation et conditions de paiement."
    >
      {/* Article 1 */}
      <section id="art1">
        <h2 className="text-xl sm:text-2xl font-bold text-foreground mb-4">Article 1 — Objet</h2>
        <p className="mb-3">Les présentes Conditions Générales de Vente (ci-après « CGV ») définissent les conditions financières applicables à l'utilisation de la Plateforme Jolene par les Établissements de santé.</p>
        <p className="mb-3">Elles complètent les Conditions Générales d'Utilisation (CGU) et s'appliquent à toute mission réalisée via la Plateforme.</p>
        <p>L'inscription et l'utilisation de la Plateforme par un Établissement impliquent l'acceptation sans réserve des présentes CGV.</p>
      </section>

      {/* Article 2 */}
      <section id="art2">
        <h2 className="text-xl sm:text-2xl font-bold text-foreground mb-4">Article 2 — Nature des frais de service</h2>
        <p className="mb-3">Jolene facture à l'Établissement des frais de service (commission) calculés en pourcentage du montant brut de chaque mission réalisée. Ces frais rémunèrent l'intermédiation technique, la gestion administrative automatisée (contrats, pointage, conformité) et la mise à disposition de la Plateforme.</p>
        <div className="bg-muted/50 border-l-4 border-primary p-4 rounded-r-xl my-4">
          <p className="font-semibold text-foreground">Mention obligatoire :</p>
          <p>Il ne s'agit en aucun cas d'un prélèvement sur le salaire du Soignant. Les frais de service sont exclusivement à la charge de l'Établissement et facturés en sus de la rémunération du Soignant.</p>
        </div>
        <p>Le Soignant perçoit l'intégralité de sa rémunération brute telle que définie dans le contrat de mission, sans aucune déduction par Jolene.</p>
      </section>

      {/* Article 3 */}
      <section id="art3">
        <h2 className="text-xl sm:text-2xl font-bold text-foreground mb-4">Article 3 — Tarification</h2>
        <p className="mb-4">L'utilisation de la Plateforme donne lieu à une commission de <strong>15 % (HT)</strong> du montant brut de chaque mission réalisée, facturée à l'Établissement. Aucun abonnement ni frais d'inscription n'est dû.</p>
        <p className="mb-4">En cas de négociation commerciale, un taux différent peut être convenu contractuellement entre l'Éditeur et l'Établissement (notamment pour les groupes d'établissements) ; il est alors précisé dans les conditions particulières.</p>
        <p>Aucun frais n'est facturé au Soignant, quel que soit le type de contrat.</p>
      </section>

      {/* Article 4 */}
      <section id="art4">
        <h2 className="text-xl sm:text-2xl font-bold text-foreground mb-4">Article 4 — Bonus de Fidélité Annuel (BFA)</h2>
        <p className="mb-4">Les Établissements ayant réalisé un volume significatif de missions sur l'année civile bénéficient d'un Bonus de Fidélité Annuel (BFA), versé sous forme d'avoir sur les factures de janvier de l'année suivante :</p>

        <div className="overflow-x-auto mb-4">
          <table className="w-full border-collapse text-sm">
            <thead>
              <tr className="bg-primary text-primary-foreground">
                <th scope="col" className="px-4 py-3 text-left font-semibold rounded-tl-xl">Palier BFA</th>
                <th scope="col" className="px-4 py-3 text-left font-semibold">Missions / an</th>
                <th scope="col" className="px-4 py-3 text-left font-semibold rounded-tr-xl">Taux BFA</th>
              </tr>
            </thead>
            <tbody>
              <tr className="border-b border-border bg-card">
                <td className="px-4 py-3 font-medium">🥉 Bronze</td>
                <td className="px-4 py-3">120 à 359</td>
                <td className="px-4 py-3 font-semibold">2 %</td>
              </tr>
              <tr className="border-b border-border bg-muted/30">
                <td className="px-4 py-3 font-medium">🥈 Argent</td>
                <td className="px-4 py-3">360 à 719</td>
                <td className="px-4 py-3 font-semibold">3,5 %</td>
              </tr>
              <tr className="bg-card">
                <td className="px-4 py-3 font-medium rounded-bl-xl">🥇 Or</td>
                <td className="px-4 py-3">720+</td>
                <td className="px-4 py-3 font-semibold rounded-br-xl">5 %</td>
              </tr>
            </tbody>
          </table>
        </div>

        <p>Le BFA est calculé sur le montant total HT des commissions facturées durant l'année civile. Il est automatiquement crédité en janvier N+1.</p>
      </section>

      {/* Article 5 */}
      <section id="art5">
        <h2 className="text-xl sm:text-2xl font-bold text-foreground mb-4">Article 5 — Facturation et paiement</h2>

        <h3 className="text-lg font-semibold text-foreground mt-6 mb-2">5.1 — Émission des factures</h3>
        <p className="mb-3">Les factures sont émises mensuellement et regroupent l'ensemble des missions réalisées au cours du mois écoulé. Chaque facture détaille le nombre de missions, les montants bruts, le taux de commission appliqué et le montant HT, TVA et TTC.</p>

        <h3 className="text-lg font-semibold text-foreground mt-6 mb-2">5.2 — Modes de paiement</h3>
        <p className="mb-3">Trois modes de paiement sont disponibles :</p>
        <ul className="list-disc pl-6 space-y-2 mb-3">
          <li><strong>Paiement par carte bancaire (Stripe)</strong> : paiement en ligne sécurisé, traitement immédiat. Mode par défaut pour les établissements privés.</li>
          <li><strong>Paiement par virement bancaire</strong> : l'Établissement effectue un virement sur le compte de Jolene SAS en indiquant le numéro de facture en référence. Délai de traitement : 2 à 5 jours ouvrés.</li>
          <li><strong>Dépôt sur Chorus Pro</strong> : pour les établissements publics soumis à l'obligation de facturation électronique (ordonnance n° 2014-697 du 26 juin 2014). La facture est déposée automatiquement sur Chorus Pro.</li>
        </ul>

        <h3 className="text-lg font-semibold text-foreground mt-6 mb-2">5.3 — Délais de paiement</h3>
        <p className="mb-3">Les factures sont payables à 30 jours date de facture pour les établissements privés, et à 50 jours pour les établissements publics (conformément à l'article L.2192-10 du Code de la commande publique).</p>
        <p>Tout retard de paiement entraîne de plein droit l'application de pénalités de retard au taux de la BCE majoré de 10 points, ainsi qu'une indemnité forfaitaire de recouvrement de 40 € (articles L.441-10 et D.441-5 du Code de commerce).</p>
      </section>

      {/* Article 6 */}
      <section id="art6">
        <h2 className="text-xl sm:text-2xl font-bold text-foreground mb-4">Article 6 — Programme Free Transition</h2>
        <p className="mb-3">Le programme Free Transition permet aux Soignants ayant atteint 3 200 heures cumulées de bénéficier d'un accompagnement vers l'exercice libéral.</p>
        <p className="mb-3">L'accompagnement comprend :</p>
        <ul className="list-disc pl-6 space-y-2 mb-3">
          <li>Le suivi en temps réel du compteur d'heures (missions réalisées via la Plateforme et heures externes déclarées sur justificatifs)</li>
          <li>La génération d'un guide personnalisé des démarches (URSSAF, ARS, Ordre professionnel, CPAM)</li>
          <li>Une attestation récapitulative des heures effectuées via la Plateforme</li>
        </ul>
        <p>Ce programme est proposé à titre gracieux et peut être modifié ou interrompu à tout moment. Il ne comporte aucun engagement de prise en charge financière de l'Éditeur.</p>
      </section>

      {/* Article 7 */}
      <section id="art7">
        <h2 className="text-xl sm:text-2xl font-bold text-foreground mb-4">Article 7 — Secteur public et affacturage</h2>
        <p className="mb-3">Pour les établissements publics de santé (hôpitaux, CHU, CH, ESPIC), Jolene propose des conditions adaptées :</p>
        <ul className="list-disc pl-6 space-y-2 mb-3">
          <li><strong>Facturation Chorus Pro</strong> : dépôt automatique des factures conformément aux obligations réglementaires.</li>
          <li><strong>Délais de paiement étendus</strong> : 50 jours conformément au Code de la commande publique.</li>
          <li><strong>Affacturage</strong> : Jolene se réserve le droit de recourir à l'affacturage pour les créances sur le secteur public, sans impact pour l'Établissement. En cas de cession de créance, l'Établissement en sera informé conformément aux dispositions des articles L.313-23 et suivants du Code monétaire et financier (cession Dailly).</li>
        </ul>
        <p>Les frais de service applicables au secteur public sont identiques à ceux du secteur privé (grille de l'article 3).</p>
      </section>

      {/* Article 8 */}
      <section id="art8">
        <h2 className="text-xl sm:text-2xl font-bold text-foreground mb-4">Article 8 — Non-sollicitation</h2>
        <p className="mb-3">L'Établissement s'engage à ne pas recruter, embaucher ou solliciter directement, par quelque moyen que ce soit, un Soignant rencontré par l'intermédiaire de la Plateforme, pendant une durée de douze (12) mois suivant la dernière mission réalisée via Jolene.</p>
        <p>En cas de manquement, l'Établissement sera redevable d'une indemnité forfaitaire de cinq mille (5 000) euros par Soignant sollicité, sans préjudice de dommages et intérêts complémentaires.</p>
      </section>
    </LayoutLegal>
  );
}
