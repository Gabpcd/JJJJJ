# Préparation employeur du contrat salarié

Le nouveau CDD n'est plus produit à partir d'un motif alternatif générique ou d'un essai automatique d'un jour. Dans `/contrat/:id`, un représentant disposant de la permission existante `contrats` renseigne et confirme ses informations avant le premier rendu. La saisie reste dans cette page jusqu'à sa confirmation ; elle n'est pas sauvegardée comme brouillon.

Deux choix utilisent le même original HTML, le même stockage immuable et les mêmes signatures CANVAS/OTP :

- **CDD privé à terme précis** : motif précis, nom et qualification du remplacé le cas échéant, représentant, poste et qualification, lieu, risques éventuels, renouvellement, temps partiel éventuel, CCN, essai explicitement choisi, rémunération et accessoires, retraite et prévoyance avec adresses. Le taux enregistré de la mission est le taux **brut** salarié affiché par `FormulaireMission`, pas un net reconverti. Aucun taux d'indemnité ni plafond d'essai nouveau n'est calculé par ce correctif.
- **Texte complet employeur** : pour un engagement public, un terme non précis ou un autre cadre, l'employeur déclare le cadre et fournit son contrat intégral. Le texte est échappé, sans clause du modèle privé ajoutée. Les parties et les dates de la mission sont rappelées pour le rapprochement. Cette conservation du texte ne constitue pas une validation juridique automatique de son contenu.

Les mentions structurées reposent sur [L1242-12](https://www.legifrance.gouv.fr/codes/article_lc/LEGIARTI000006901206/2022-05-03) ; le choix d'essai ne lui attribue aucune durée par défaut ([L1242-10](https://www.legifrance.gouv.fr/codes/section_lc/LEGITEXT000006072050/LEGISCTA000006177866/2026-01-02/)). Les informations de temps partiel doivent être fournies par l'employeur lorsqu'applicables ([L3123-6](https://www.legifrance.gouv.fr/codes/article_lc/LEGIARTI000033020080/2026-07-01)). Aucun régime privé n'est déduit d'une profession ou du type d'établissement.

Le serveur vérifie la permission employeur, la présence des champs et la confirmation avant tout upload. Le HTML figé conserve le cadre, la version de préparation, l'auteur authentifié (ou la provenance technique du service existant) et sa date. Le mécanisme antérieur d'écriture conditionnelle empêche d'écraser un rendu ou une signature concurrente. Un original déjà rendu ou signé est relu exactement : aucun changement de texte, de hash, de preuve ni de signature historique. Le parcours libéral conserve son modèle existant.

## Compatibilité des clients

Un ancien client mobile qui tente de préparer un **nouveau** CDD sans ces informations reçoit un refus422 ; aucune valeur générique n'est réintroduite pour le laisser passer. L'employeur peut préparer l'original depuis le web actualisé ou un client intégrant le formulaire. L'ancien client peut ensuite relire et signer cet original avec ses mécanismes existants. Voir le formulaire dans l'application installée nécessite d'y charger le nouveau frontend ; ce correctif n'effectue aucune livraison mobile. L'application du serveur et le parcours libéral ne nécessitent pas, à eux seuls, un rebuild mobile.

Les données synthétiques ajoutées à `seedContratMissionSigne` restent limitées aux profils Playwright éphémères vérifiés TEST. Elles ne servent jamais de valeurs par défaut en production. Les bancs existants chargent le véritable helper pur et conservent leurs contrôles d'accès, d'empreinte et de concurrence.

## Décision et vérifications bornées

Le 19 octobre, Gabrielle a explicitement demandé de corriger le CDD au mieux, de fusionner les corrections validées puis d'arrêter les nouvelles recettes. Ce correctif applique cette délégation : aucun nouvel audit de paiement, de mandat, d'identité ou d'appareil physique n'est lancé.

Vérifications locales du correctif : compilation web de simulation sans secrets, `tsc -b`, 17 garde-fous et 58 contrôles existants/ciblés du rendu, des accès, de la concurrence et des fixtures de contrat réussis. La revue indépendante à contexte vierge conclut CLÔTURABLE après correction du traitement des deux-points par le filtre SQL et du mock de réaffectation. Les 15 simulations ciblées du formulaire passent sur iPhone, Android, iPad portrait/paysage et ordinateur : conditions privées, texte intégral avec refus puis reprise explicite, et interdiction de préparer pour le soignant ou un membre non autorisé. Les réponses backend sont simulées ; aucune signature ni formalité officielle n’est déduite de cette preuve. Les contrôles CI restent requis avant fusion.

Le Kbis fourni confirme le SIREN mais ne fournit pas le numéro fiscal de TVA. L'EUID auparavant affiché comme TVA est retiré des mentions et des PDF de commission téléchargés. Le numéro reste non renseigné, sans changement de taux, de montant ni de régime fiscal. Aucun document historique stocké n'est réécrit ; le numéro officiel reste à obtenir auprès du SIE ou du comptable.

Dans le nouveau mode « texte employeur », les mentions de DPAE et le pied de page sont présentés selon le cadre déclaré, sans lui attribuer automatiquement le régime privé. Les boutons de préparation et de suivi de la DPAE restent accessibles ; ce choix ne vaut jamais dispense de formalités. Le CDD privé structuré et les contrats historiques conservent leur présentation.
