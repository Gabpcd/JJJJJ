# Filiation documentaire d’une facture de remplacement

Base du témoin : `9ac91fa18c756208423c36d4276f33c3504cc988`.

Le handler chargeait le numéro et la date de la facture précédente, mais les deux rendus réservaient leur utilisation aux avoirs. Une `FACTURE` de nature `REMPLACEMENT` pouvait donc être émise sans cette filiation dans son PDF et son XML.

Le correctif ajoute au remplacement la référence CII `InvoiceReferencedDocument` et la mention factuelle PDF « Facture rectificative remplaçant la facture n° … du … ». Le texte passe à la ligne suivant la largeur de la police. Le remplacement reste de type XML **380**, avec des montants positifs. Le rendu des avoirs **381**, les calculs, les décisions d’émission et les appels de commission restent inchangés.

Avant tout upload, un remplacement exige une facture précédente distincte, trouvée sans erreur, de type `FACTURE`, appartenant à la même mission, au même soignant et au même établissement, avec un numéro non vide et une date calendaire ISO valide. Un refus renvoie `400 FILIATION_REMPLACEMENT_INVALIDE` sans écriture documentaire, émission, commission ni email.

## Preuves locales

- Les trois nouveaux tests ciblés échouent avec le handler de la base : référence XML absente et refus attendus remplacés par des succès HTTP200.
- La suite Node complète exécute le vrai module Edge, ses vrais générateurs PDF/XML et le client Supabase, avec uniquement les IO remplacées par un transport fictif fermé. Elle vérifie la facture originale80€, le remplacement4h×18€ =72€, la référence numéro/date, le type380, les empreintes des octets uploadés et l’absence de modification des fichiers et de la version de l’original.
- Les négatifs couvrent parent absent/erreur de lecture, auto-référence, autre mission ou acteur, mauvais type, numéro vide et date absente/invalide. Un banc neuf par cas conserve le véritable garde de fréquence.
- Les contrôles déjà présents sur facture/avoir, Unicode, pagination, police indisponible, échec Storage et doublon restent exécutés. Les deux empreintes XML historiques facture/avoir sont identiques.
- Une analyse PDF.js dans Chromium, avec toutes les requêtes locales interceptées, compare les vrais PDF avant/après. Elle vérifie numéro/date précédents,72€, taux18€, identité Unicode, texte dans la page et rendu de la référence sur une ou deux lignes. Les PNG ont été inspectés.

Commande CI déjà raccordée : `node --test tests/node/facturation-documents.node.mjs`.

Fixture réutilisable pour la simulation frontend : `genererDocuments({ remplacement: true, unicode: true })`. Elle produit les vrais octets du handler ; l’état SQL canonique du remplacement est représenté à la frontière du transport, sans exécuter le résolveur SQL. `pagination: true` conserve aussi la preuve de deux pages.

Les preuves détaillées et le témoin rouge sont conservés sous `/private/tmp/jolene-f1-remplacement-documentaire-20261001/preuves`, avec un manifeste SHA256 associé au patch candidat.

## Limites

Cette validation locale ne prouve ni le résolveur financier SQL, ni une invocation Edge distante, ni un objet Storage réel ou un envoi fournisseur. Elle ne certifie pas le XML au moyen d’un validateur XSD/Schematron.

## Simulation intégrée dans les écrans

Après intégration avec le correctif d’accès, les quinze scénarios de remplacement passent sur iPhone, Android, iPad portrait, iPad paysage et ordinateur. Ils couvrent « À payer », le détail établissement et le détail soignant assigné, un téléchargement refusé avec un message français, sa reprise puis un rechargement. Cinquante téléchargements PDF correspondent aux octets archivés du banc ; vingt-cinq analyses de PDF et XML vérifient la filiation, les identités, le type 380, les montants et le taux. Le XML est analysé à sa source : aucun bouton de téléchargement XML n’est revendiqué dans l’interface.

Les détails affichent l’original à 80 € « Remplacée » et la nouvelle facture à 72 € « Émise », avec un net facturé de 72 €. « À payer » présente uniquement cette nouvelle facture. L’ancienne pièce reste téléchargeable depuis les détails, sans régénération ni modification de ses octets. Les trois anciens cas d’accès sur ordinateur ont aussi été rejoués et passent ; leur matrice initiale de quinze cas est conservée séparément.

Le navigateur sert les trois pages du commit local `6bc862cc91e5f5a989cfc165b803964f596defb2`. Le vrai handler s’exécute dans Node avec le transport simulé fermé ; Vite ne compile pas ce handler Edge. Les appels automatiques de chat sont explicitement inertes, les WebSockets fermées et toute action financière interdite. Ces preuves ne valent donc pas une intégration distante SQL → Edge → Storage.

Preuves : `/private/tmp/jolene-f1-remplacement-documentaire-20261001/preuves-ui/validation-ui.json`, captures et manifeste `SHA256SUMS-frontend`. Patch du spec : SHA256 `77b056bfb66371bb2e91b5b6a0814859abf643bc531a292b7c677e820f2955da`.
