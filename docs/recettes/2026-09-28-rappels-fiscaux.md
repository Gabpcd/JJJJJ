# Rappels fiscaux et page Mes charges

Le compte médecin fictif de staging affichait la CARPIMKO et des dates fixes
calculées à partir du jour courant. Aucun échéancier individuel n'était
synchronisé pour justifier ces dates ou les badges d'urgence.

La carte utilise maintenant les liens officiels de la matrice de professions
existante (par exemple CARMF pour MEDECIN), sans modifier cette matrice. La
requête de la page charge explicitement la profession. Un régime absent n'est
plus remplacé côté interface par Micro-BNC ; un régime enregistré mais non
confirmé conserve le libellé « à confirmer ».

## Vérifications

- TypeScript, lint ciblé et six tests unitaires réussis.
- Dix simulations Playwright réussies : médecin sans régime, IDE en déclaration
  contrôlée confirmée, sur iPhone, Android, iPad portrait/paysage et ordinateur.
  La simulation respecte les colonnes demandées à PostgREST pour détecter un
  oubli dans le SELECT ; contrôles après rechargement, erreurs et débordement.
- Cinq vérifications supplémentaires avec Auth et base staging réels sur le
  compte médecin isolé de recette : CARMF visible, aucun rappel CARPIMKO ni
  échéance calculée, accès et rechargement sans erreur HTTP/JavaScript.
  Ce profil possède en base Micro-BNC non confirmé. La première assertion
  supposait à tort un régime NULL ; elle a été corrigée après observation,
  sans modifier les données. Les traces initiales sont conservées.
- Capture iPhone réelle de staging relue visuellement. Les appareils physiques
  et les déclarations auprès des organismes ne sont pas couverts.

Preuves locales hors dépôt :
`audits/2026-09-28-finalisation/finance-ui/rappels-simules/` et
`audits/2026-09-28-finalisation/finance-ui/rappels-staging-reel/`.

## Page Mes charges corrigée dans le même lot

La simulation de la page liée a retrouvé le même défaut : taux URSSAF uniforme,
forfait/part CARPIMKO, RCP de 400 €, calendrier et revenu net estimé appliqués
sans connaître la situation individuelle. Ces projections, leur graphique et
leur CSV sont retirés. Aucun nouveau barème ou conseil fiscal n'est introduit.

Le récapitulatif des missions libérales terminées reste consultable et
exportable. Son total brut n'est plus nommé chiffre d'affaires encaissé. La
caisse vient de la matrice existante ; la date RCP vient du document vérifié.
Le régime fiscal reste modifiable. Aucun choix n'est présélectionné si absent,
et une sauvegarde n'est annoncée qu'après lecture du profil mis à jour. Une
panne affiche une erreur et permet de réessayer, sans faux état vide.

Les simulations complémentaires couvrent les missions mixtes et leur export,
les erreurs de lecture avec reprise, la sauvegarde refusée/incomplète/lente,
les clics concurrents, le rechargement et la RCP valide puis expirée. Les
simulations initiales attendaient l’ancienne route Documents ; la vérification
a été corrigée pour sa destination canonique, sans modification de la route.

Cinq parcours supplémentaires avec le backend de staging réel passent :
Revenus → Mes charges → enregistrement Déclaration contrôlée → rechargement.
Seul le profil fictif de recette a été modifié. Son régime final est
DECLARATION_CONTROLEE, confirmé. Les autres profils n'ont pas été modifiés.

La synchronisation d'échéanciers individuels et un moteur d'estimation fiscale
validé ne sont pas implémentés. Les liens officiels restent disponibles. Aucun
paiement/remboursement, règle d'éligibilité libérale ou moteur de paie n'est
modifié ou validé par ces corrections. Simulations et navigateurs de staging ne
constituent pas un essai sur appareil physique ni une livraison en production.

## Mandat SEPA et reprise réseau — 29 septembre

La recette réelle a créé un mandat avec l'IBAN officiel Stripe TEST depuis
Facturation & contrat. Le même client, moyen de paiement et mandat actif ont
été retrouvés dans le staging et chez Stripe TEST. Le mandat reste visible
après rechargement ; aucun paiement ni remboursement n'a été exécuté.

Une panne réseau révélait le message anglais du SDK Supabase. Le helper
traduit désormais cette erreur de transport en français, sans changer les
messages métier ni les traitements financiers. Réessayer relit le mandat
existant sans demander sa recréation. Le bouton Enregistrer reste dans le flux
du formulaire mobile pour ne recouvrir ni les erreurs ni la navigation ; son
comportement desktop est conservé.

La simulation coupe uniquement la lecture `get_sepa_status`, puis rétablit
l'accès au staging réel. Le service worker est désactivé dans ce contexte de
test pour que WebKit permette cette interception ; aucun service worker
produit n'est modifié. Les preuves locales sont conservées dans
`audits/2026-09-28-finalisation/finance-ui/sepa-reel/` : rapprochement Stripe,
captures, lectures après reprise et rechargement, contrôle du bouton mobile.
Ces vérifications ne prouvent pas le débit ni le remboursement intégré.
