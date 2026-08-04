import { usePageTitle } from '@/hooks/usePageTitle';
import React from 'react';
import LayoutLegal from '@/components/LayoutLegal';

const TOC = [
  { id: 'art1', label: 'Article 1 — Objet' },
  { id: 'art2', label: 'Article 2 — Nature des frais de service' },
  { id: 'art3', label: 'Article 3 — Tarification' },
  { id: 'art4', label: 'Article 4 — Bonus de Fidélité Annuel (BFA)' },
  { id: 'art5', label: 'Article 5 — Facturation et paiement' },
  { id: 'art6', label: 'Article 6 — Accompagnement vers l\'exercice libéral' },
  { id: 'art7', label: 'Article 7 — Secteur public et affacturage' },
  { id: 'art8', label: 'Article 8 — Non-contournement et frais de recrutement' },
];

export default function PageCGV() {
  usePageTitle('CGV');
  return (
    <LayoutLegal
      titre="Conditions Générales de Vente"
      dateMaj="4 août 2026"
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
        <p className="mb-3">Jolene facture à l'Établissement des frais de service (commission) calculés en pourcentage de la rémunération brute totale due au Soignant pour chaque mission (base, majorations et indemnités le cas échéant). Ces frais rémunèrent l'intermédiation technique, la gestion administrative automatisée (contrats, pointage, conformité) et la mise à disposition de la Plateforme.</p>
        <div className="bg-muted/50 border-l-4 border-primary p-4 rounded-r-xl my-4">
          <p className="font-semibold text-foreground">Mention obligatoire :</p>
          <p>Il ne s'agit en aucun cas d'un prélèvement sur le salaire du Soignant. Les frais de service sont exclusivement à la charge de l'Établissement et facturés en sus de la rémunération du Soignant.</p>
        </div>
        <p>Le Soignant perçoit l'intégralité de sa rémunération brute telle que définie dans le contrat de mission, sans aucune déduction par Jolene.</p>
      </section>

      {/* Article 3 */}
      <section id="art3">
        <h2 className="text-xl sm:text-2xl font-bold text-foreground mb-4">Article 3 — Tarification</h2>
        <p className="mb-4">L'utilisation de la Plateforme donne lieu à une commission de <strong>15 % HT</strong> de la rémunération brute totale due au Soignant pour chaque mission réalisée, facturée à l'Établissement. La TVA au taux en vigueur s'ajoute à cette commission ; avec une TVA de 20 %, elle représente <strong>18 % TTC</strong> de la rémunération brute. Aucun abonnement ni frais d'inscription n'est dû.</p>
        <p className="mb-4">En cas de négociation commerciale, un taux différent peut être convenu contractuellement entre l'Éditeur et l'Établissement (notamment pour les groupes d'établissements) ; il est alors précisé dans les conditions particulières.</p>
        <p>Aucun frais n'est facturé au Soignant, quel que soit le type de contrat.</p>
      </section>

      {/* Article 4 */}
      <section id="art4">
        <h2 className="text-xl sm:text-2xl font-bold text-foreground mb-4">Article 4 — Bonus de Fidélité Annuel (BFA)</h2>
        <p>Le Bonus de Fidélité Annuel (BFA) est réservé aux groupes d'établissements et établissements ayant signé un contrat BFA spécifique avec Jolene. Son taux est négocié au cas par cas et précisé dans les conditions particulières. Il est calculé sur le montant total HT des commissions facturées par Jolene au titre des missions terminées durant l'année civile, et versé par virement bancaire après validation, en début d'année suivante.</p>
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
          <li><strong>Paiement par virement bancaire</strong> : l'Établissement effectue un virement sur le compte de Jolene SASU en indiquant le numéro de facture en référence. Délai de traitement : 2 à 5 jours ouvrés.</li>
          <li><strong>Dépôt sur Chorus Pro</strong> : pour les établissements publics soumis à l'obligation de facturation électronique (ordonnance n° 2014-697 du 26 juin 2014). La facture est déposée automatiquement sur Chorus Pro.</li>
        </ul>

        <h3 className="text-lg font-semibold text-foreground mt-6 mb-2">5.3 — Délais de paiement</h3>
        <p className="mb-3">Les factures sont payables à 30 jours date de facture pour les établissements privés, et à 50 jours pour les établissements publics (conformément à l'article L.2192-10 du Code de la commande publique).</p>
        <p>Tout retard de paiement entraîne de plein droit l'application de pénalités de retard au taux de la BCE majoré de 10 points, ainsi qu'une indemnité forfaitaire de recouvrement de 40 € (articles L.441-10 et D.441-5 du Code de commerce).</p>
      </section>

      {/* Article 6 */}
      <section id="art6">
        <h2 className="text-xl sm:text-2xl font-bold text-foreground mb-4">Article 6 — Accompagnement vers l'exercice libéral</h2>
        <p className="mb-3">Le programme d'accompagnement vers l'exercice libéral permet aux Soignants ayant atteint 3 200 heures cumulées de bénéficier d'un accompagnement vers l'exercice libéral.</p>
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
        <h2 className="text-xl sm:text-2xl font-bold text-foreground mb-4">Article 8 — Non-contournement et frais de recrutement</h2>

        <h3 className="text-lg font-semibold text-foreground mt-6 mb-2">8.1 — Définition : « Professionnel mis en relation »</h3>
        <p className="mb-3">Est réputé « Professionnel mis en relation » tout professionnel de santé dont l'Établissement a, via la Plateforme : (i) reçu communication nominative du profil dans le cadre d'une candidature ou d'une proposition de mission, (ii) échangé avec lui via la messagerie, ou (iii) bénéficié d'au moins une mission réalisée. La simple apparition d'un profil dans des résultats de recherche ne constitue pas une mise en relation.</p>

        <h3 className="text-lg font-semibold text-foreground mt-6 mb-2">8.2 — Non-contournement</h3>
        <p className="mb-3">Pendant une durée de <strong>douze (12) mois</strong> à compter du dernier des événements suivants — dernière mission réalisée ou dernier échange via la Plateforme avec le Professionnel concerné — l'Établissement s'engage à conclure <strong>exclusivement via la Plateforme</strong> toute nouvelle collaboration avec un Professionnel mis en relation, quelle qu'en soit la forme : mission ponctuelle, vacation, remplacement, contrat à durée déterminée ou indéterminée, ou toute collaboration équivalente, directe ou par personne ou société interposée.</p>
        <p className="mb-3">À défaut, l'Établissement est redevable de plein droit :</p>
        <ul className="list-disc pl-6 space-y-2 mb-3">
          <li>pour toute <strong>mission réalisée hors Plateforme</strong> pendant cette période : la commission qui aurait été due au titre des présentes CGV (15 % HT des montants versés au Professionnel, TVA en sus), calculée sur justificatifs ou, à défaut de communication de ceux-ci sous quinze (15) jours après demande, sur une base forfaitaire égale au tarif journalier moyen constaté sur la Plateforme pour la profession concernée, par jour de mission constaté ;</li>
          <li>pour toute <strong>embauche</strong> : les frais de recrutement prévus à l'article 8.3.</li>
        </ul>
        <p className="mb-3">L'Établissement s'engage à informer Jolene, sous quinze (15) jours, de toute embauche d'un Professionnel mis en relation intervenant pendant la période visée ci-dessus.</p>
        <p>Le présent article survit à la résiliation des présentes pour toutes les mises en relation antérieures à celle-ci.</p>

        <h3 className="text-lg font-semibold text-foreground mt-6 mb-2">8.3 — Frais de recrutement</h3>
        <p className="mb-3">En cas d'embauche d'un Professionnel mis en relation (contrat à durée indéterminée, ou contrat à durée déterminée d'une durée initiale ou cumulée supérieure à trois (3) mois) pendant la période de l'article 8.2, l'Établissement est redevable de frais de recrutement calculés sur la <strong>rémunération annuelle brute</strong> prévue au contrat de travail, selon la grille dégressive suivante, appréciée à compter de la première mission réalisée (ou, à défaut de mission, de la première mise en relation) :</p>
        <div className="overflow-x-auto my-4">
          <table className="w-full text-sm border-collapse">
            <thead>
              <tr className="border-b border-border">
                <th className="text-left py-2 pr-4 font-semibold text-foreground">Ancienneté de la relation</th>
                <th className="text-left py-2 font-semibold text-foreground">Frais</th>
              </tr>
            </thead>
            <tbody>
              <tr className="border-b border-border/50"><td className="py-2 pr-4">Moins de 6 mois</td><td className="py-2"><strong>15 %</strong></td></tr>
              <tr className="border-b border-border/50"><td className="py-2 pr-4">De 6 à 12 mois</td><td className="py-2"><strong>10 %</strong></td></tr>
              <tr className="border-b border-border/50"><td className="py-2 pr-4">De 12 à 18 mois</td><td className="py-2"><strong>5 %</strong></td></tr>
              <tr><td className="py-2 pr-4">Au-delà de 18 mois</td><td className="py-2"><strong>0 %</strong> — aucun frais</td></tr>
            </tbody>
          </table>
        </div>
        <p className="mb-3">À défaut de communication du contrat de travail sous quinze (15) jours après demande, l'assiette retenue est la rémunération annuelle brute conventionnelle de référence pour le poste et l'ancienneté concernés. Les frais sont exigibles à la date d'effet du contrat de travail et payables à trente (30) jours.</p>
        <div className="bg-muted/50 border-l-4 border-primary p-4 rounded-r-xl my-4">
          <p className="font-semibold text-foreground mb-2">Garantie période d'essai :</p>
          <p>En cas de rupture de la période d'essai, à l'initiative de l'une ou l'autre partie, dans les deux (2) premiers mois du contrat, Jolene émet un avoir de cinquante pour cent (50 %) des frais, imputable sur de nouveaux frais de recrutement ou sur les commissions de missions à venir.</p>
        </div>
        <p>L'Établissement peut à tout moment solliciter la formalisation d'une embauche via la fonctionnalité « Recruter » de la Plateforme ; les frais du présent article valent alors solde de tout compte au titre de la mise en relation du Professionnel concerné.</p>
      </section>
    </LayoutLegal>
  );
}
