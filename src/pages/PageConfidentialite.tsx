import React from 'react';
import LayoutLegal from '@/components/LayoutLegal';
import { ENTREPRISE } from '@/constantes/entreprise';

const TOC = [
  { id: 'art1', label: 'Article 1 — Responsable du traitement' },
  { id: 'art2', label: 'Article 2 — Données collectées' },
  { id: 'art3', label: 'Article 3 — Hébergement sécurisé' },
  { id: 'art4', label: "Article 4 — Journaux d'audit" },
  { id: 'art5', label: 'Article 5 — Durées de conservation' },
  { id: 'art6', label: 'Article 6 — Droits des personnes' },
];

export default function PageConfidentialite() {
  return (
    <LayoutLegal titre="Politique de Confidentialité" dateMaj="12 mars 2026" toc={TOC}>
      {/* Article 1 */}
      <section id="art1">
        <h2 className="text-xl font-bold text-primary mb-4">Article 1 — Responsable du traitement</h2>
        <p className="mb-3">Le responsable du traitement des données à caractère personnel collectées via la Plateforme Jolene est :</p>
        <div className="bg-muted/50 border border-border rounded-xl p-4 mb-3">
          <p className="font-semibold text-foreground">{ENTREPRISE.nom}</p>
          <p className="text-muted-foreground">SIRET : {ENTREPRISE.siret}</p>
          <p className="text-muted-foreground">Siège social : {ENTREPRISE.adresse}</p>
          <p className="text-muted-foreground">E-mail : {ENTREPRISE.email}</p>
          <p className="text-muted-foreground mt-2">Délégué à la protection des données (DPO) : <a href="mailto:dpo@joleneapp.com" className="text-primary hover:underline">dpo@joleneapp.com</a></p>
        </div>
        <p>Le traitement des données est réalisé conformément au Règlement (UE) 2016/679 du 27 avril 2016 (RGPD) et à la loi n° 78-17 du 6 janvier 1978 modifiée (loi Informatique et Libertés).</p>
      </section>

      {/* Article 2 */}
      <section id="art2">
        <h2 className="text-xl font-bold text-primary mb-4">Article 2 — Données collectées</h2>
        <p className="mb-4">La Plateforme collecte les catégories de données suivantes, selon le profil de l'utilisateur :</p>

        <h3 className="text-base font-semibold text-foreground mt-6 mb-2">2.1 — Données d'identification</h3>
        <p className="mb-3">Nom, prénom, date de naissance, adresse e-mail, numéro de téléphone, adresse postale, photo de profil (facultative). Pour les Soignants : numéro RPPS, numéro ADELI, numéro de sécurité sociale, profession.</p>

        <h3 className="text-base font-semibold text-foreground mt-6 mb-2">2.2 — Données professionnelles</h3>
        <p className="mb-3">Diplômes, habilitations, attestation RCP, statut (salarié/libéral), numéro SIRET le cas échéant, historique des missions réalisées, score de fiabilité, heures cumulées. Les vaccinations et aptitudes médicales sont déclarées sur l'honneur (aucun document de santé n'est stocké).</p>

        <h3 className="text-base font-semibold text-foreground mt-6 mb-2">2.3 — Données de géolocalisation</h3>
        <div className="bg-muted/50 border-l-4 border-primary p-4 rounded-r-xl my-4">
          <p>Les coordonnées GPS sont collectées <strong>uniquement au moment du pointage</strong> (arrivée et départ). Il n'y a <strong>aucun tracking continu</strong> de la position des Soignants. Les données GPS comprennent : latitude, longitude, précision du signal, identifiant du terminal, adresse IP.</p>
        </div>

        <h3 className="text-base font-semibold text-foreground mt-6 mb-2">2.4 — Données financières</h3>
        <p className="mb-3">Coordonnées bancaires (IBAN) des Soignants pour le versement des rémunérations. Données de facturation des Établissements. Les données de carte bancaire sont traitées exclusivement par Stripe (certifié PCI-DSS niveau 1) et ne sont jamais stockées sur nos serveurs.</p>

        <h3 className="text-base font-semibold text-foreground mt-6 mb-2">2.5 — Données de connexion</h3>
        <p>Adresse IP, type et version du navigateur, système d'exploitation, date et heure de connexion, pages consultées, durée de session. Ces données sont collectées à des fins de sécurité et d'amélioration du service.</p>
      </section>

      {/* Article 3 */}
      <section id="art3">
        <h2 className="text-xl font-bold text-primary mb-4">Article 3 — Hébergement sécurisé</h2>
        <p className="mb-3">Les données sont hébergées par Supabase Inc. sur des serveurs localisés au sein de l'Union européenne. Les données sont chiffrées au repos (AES-256) et en transit (TLS 1.3).</p>
        <div className="bg-muted/50 border border-border rounded-xl p-4 mb-3">
          <p className="font-semibold text-foreground">Supabase Inc.</p>
          <p className="text-muted-foreground">Infrastructure : Amazon Web Services (AWS) — Région eu-west-3 (Paris)</p>
          <p className="text-muted-foreground">Sécurité : Chiffrement AES-256 au repos, TLS 1.3 en transit, SOC 2 Type II, ISO 27001</p>
        </div>
        <div className="bg-muted/50 border-l-4 border-primary p-4 rounded-r-xl my-4">
          <p><strong>Jolene ne stocke aucune donnée de santé à caractère personnel</strong> au sens de l'article L.1111-8 du Code de la santé publique. Les vaccinations et aptitudes médicales sont déclarées sur l'honneur par le Soignant et vérifiées en présentiel par l'Établissement lors de la première mission.</p>
        </div>
        <p className="mb-3">L'ensemble des données sont stockées sur des serveurs situés dans l'Union européenne (France). Les sauvegardes sont chiffrées (AES-256) et répliquées sur un site secondaire au sein de l'UE.</p>
        <p>Les transferts de données hors UE, s'ils devaient avoir lieu dans le cadre de prestations techniques de sous-traitants, sont encadrés par des clauses contractuelles types approuvées par la Commission européenne (décision 2021/914).</p>
      </section>

      {/* Article 4 */}
      <section id="art4">
        <h2 className="text-xl font-bold text-primary mb-4">Article 4 — Journaux d'audit</h2>
        <p className="mb-3">La Plateforme maintient des journaux d'audit détaillés pour chaque action critique :</p>
        <ul className="list-disc pl-6 space-y-2 mb-3">
          <li>Connexion et déconnexion des utilisateurs (date, heure, IP, navigateur)</li>
          <li>Consultation, création, modification et suppression de données</li>
          <li>Téléversement et vérification de documents</li>
          <li>Signature électronique de contrats</li>
          <li>Opérations de pointage (avec coordonnées GPS)</li>
          <li>Opérations de facturation et de paiement</li>
        </ul>
        <p className="mb-3">Les journaux d'audit sont conservés pendant 5 ans conformément aux recommandations de la CNIL. Ils sont accessibles uniquement aux administrateurs habilités de Jolene et peuvent être communiqués aux autorités judiciaires sur réquisition.</p>
        <p>Les journaux ne contiennent pas de données de santé des patients. Seules les métadonnées administratives (qui a fait quoi, quand, depuis où) sont enregistrées.</p>
      </section>

      {/* Article 5 */}
      <section id="art5">
        <h2 className="text-xl font-bold text-primary mb-4">Article 5 — Durées de conservation</h2>
        <p className="mb-4">Les données personnelles sont conservées pendant les durées suivantes :</p>

        <div className="overflow-x-auto mb-4">
          <table className="w-full border-collapse text-sm">
            <thead>
              <tr className="bg-primary text-primary-foreground">
                <th className="px-4 py-3 text-left font-semibold rounded-tl-xl">Catégorie de données</th>
                <th className="px-4 py-3 text-left font-semibold">Durée active</th>
                <th className="px-4 py-3 text-left font-semibold rounded-tr-xl">Archivage</th>
              </tr>
            </thead>
            <tbody>
              <tr className="border-b border-border bg-card">
                <td className="px-4 py-3">Données d'identification</td>
                <td className="px-4 py-3">Durée du compte</td>
                <td className="px-4 py-3">3 ans après suppression</td>
              </tr>
              <tr className="border-b border-border bg-muted/30">
                <td className="px-4 py-3">Documents professionnels</td>
                <td className="px-4 py-3">Durée de validité</td>
                <td className="px-4 py-3">5 ans</td>
              </tr>
              <tr className="border-b border-border bg-card">
                <td className="px-4 py-3">Données de géolocalisation (pointage)</td>
                <td className="px-4 py-3">Durée de la mission</td>
                <td className="px-4 py-3">3 ans</td>
              </tr>
              <tr className="border-b border-border bg-muted/30">
                <td className="px-4 py-3">Contrats de mission</td>
                <td className="px-4 py-3">Durée de la mission</td>
                <td className="px-4 py-3">5 ans</td>
              </tr>
              <tr className="border-b border-border bg-card">
                <td className="px-4 py-3">Factures</td>
                <td className="px-4 py-3">Année fiscale</td>
                <td className="px-4 py-3">10 ans (obligation fiscale)</td>
              </tr>
              <tr className="border-b border-border bg-muted/30">
                <td className="px-4 py-3">Journaux d'audit</td>
                <td className="px-4 py-3">—</td>
                <td className="px-4 py-3">5 ans</td>
              </tr>
              <tr className="bg-card">
                <td className="px-4 py-3 rounded-bl-xl">Données de connexion</td>
                <td className="px-4 py-3">—</td>
                <td className="px-4 py-3 rounded-br-xl">1 an</td>
              </tr>
            </tbody>
          </table>
        </div>

        <p>À l'expiration des durées de conservation, les données sont supprimées de manière irréversible ou anonymisées de façon à rendre toute identification impossible.</p>
      </section>

      {/* Article 6 */}
      <section id="art6">
        <h2 className="text-xl font-bold text-primary mb-4">Article 6 — Droits des personnes</h2>
        <p className="mb-4">Conformément au RGPD (articles 15 à 22), vous disposez des droits suivants sur vos données personnelles :</p>
        <ul className="list-disc pl-6 space-y-3 mb-4">
          <li><strong>Droit d'accès</strong> (article 15) : obtenir la confirmation que des données vous concernant sont traitées et en recevoir une copie.</li>
          <li><strong>Droit de rectification</strong> (article 16) : demander la correction de données inexactes ou incomplètes.</li>
          <li><strong>Droit à l'effacement</strong> (article 17) : demander la suppression de vos données, sous réserve des obligations légales de conservation.</li>
          <li><strong>Droit à la limitation du traitement</strong> (article 18) : demander la suspension du traitement de vos données dans certains cas.</li>
          <li><strong>Droit à la portabilité</strong> (article 20) : recevoir vos données dans un format structuré, couramment utilisé et lisible par machine (JSON ou CSV).</li>
          <li><strong>Droit d'opposition</strong> (article 21) : vous opposer au traitement de vos données pour des motifs légitimes.</li>
        </ul>
        <p className="mb-3">Pour exercer vos droits, adressez votre demande à : <a href="mailto:dpo@soindirect.com" className="text-primary hover:underline font-medium">dpo@soindirect.com</a></p>
        <p className="mb-3">L'Éditeur s'engage à répondre dans un délai d'un mois. Ce délai peut être prolongé de deux mois en cas de complexité ou de nombre élevé de demandes.</p>
        <p>En cas de difficulté dans l'exercice de vos droits, vous pouvez introduire une réclamation auprès de la Commission Nationale de l'Informatique et des Libertés (CNIL) : <a href="https://www.cnil.fr" target="_blank" rel="noopener noreferrer" className="text-primary hover:underline font-medium">www.cnil.fr</a></p>
      </section>
    </LayoutLegal>
  );
}
