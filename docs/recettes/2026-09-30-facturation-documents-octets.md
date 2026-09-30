# F1 — génération et téléchargement des octets PDF/XML

Le banc exécute le module `generate-invoice/index.ts` entier et ses helpers
actuels, avec le vrai SDK Supabase et `pdf-lib`. Seuls l'hôte Deno et les IO
REST/RPC/Storage/email sont remplacés par des réponses fictives en mémoire.
Les imports, variables d'environnement, origines et opérations attendues sont
énumérés ; un appel inconnu fait échouer le test, même si le handler le capture.
Ce remplacement lexical est un banc de test du code lu, pas une sandbox de
sécurité permettant d'exécuter un code arbitraire non fiable.

Il complète la [recette SQL F1](2026-09-30-facturation-f1-sql.md), dont les
références documentaires fictives ne prouvaient pas la génération des fichiers.
Aucun SQL, compte cloud, fichier Storage réel, email ou fournisseur n'est appelé.
L'ancien script `test-generate-invoice.ts`, avec son fallback production, n'est
pas utilisé. Les dépendances partagées locales sont restées intactes ; fontkit
est acquis dans un dossier externe et ajouté au manifeste/lock pour la CI.

## Défaut observé et correction bornée

La vraie facture et le vrai avoir dessinaient la mention subrogative sur une
ligne dépassant la page A4. L'extraction partielle du texte pouvait masquer ce
défaut ; le rendu et une assertion géométrique l'ont montré. La correction
replie la mention selon la largeur réelle de la police, réserve la hauteur du
pied de page et, si nécessaire, reporte le bloc sur une nouvelle page portant
le numéro du document. Les tampons existants concernent toutes les pages.
Le texte, les règles, les calculs, les destinataires, le XML et les IO métier
restent inchangés. Aucun backfill ou régénération de document existant.

Un second témoin sur le vrai handler a confirmé une réponse500 pour les
prénoms `Łukasz` et `İpek` pourtant acceptés par l'inscription : Helvetica ne
peut pas les encoder en WinAnsi. Le PDF utilise désormais Noto Sans Regular et
Bold embarquées, via `npm:@pdf-lib/fontkit@1.1.1` (MIT). Les fichiers Noto
originaux, sous SIL OFL1.1, sont figés au commit
`ffebf8c1ee449e544955a7e813c54f9b73848eac` ; leurs sources, tailles et SHA256
sont dans [provenance.json](../../supabase/functions/generate-invoice/fonts/provenance.json).
Les 1 144 948 octets TTF sont encodés dans un module TS (~1,6Mo), vérifiés par
SHA256 et incorporés en sous-ensembles dans chaque PDF. Aucun téléchargement
de police à l'exécution. Ce choix conserve les déploiements `--use-api`, qui
[ne prennent pas en charge static_files](https://supabase.com/docs/guides/functions/limits).

Les deux styles possèdent les mêmes 2841 points de code : blocs Latin étenduA
128/128, B208/208, grec121/144, grec étendu233/256, cyrillique256/256 (ces
dénominateurs incluent les positions réservées). Ce n'est pas Unicode universel :
`李` et `😀` sont notamment absents. Un caractère absent provoque422 avec le
code `CARACTERE_PDF_NON_PRIS_EN_CHARGE` ; une police vide/corrompue provoque500
`POLICE_PDF_INVALIDE`. Aucun nom n'est translittéré, supprimé ou remplacé par
un carré. Le contrôle intervient avant consommation du numéro pour une nouvelle
facture, et sur les snapshots canoniques avant upload lors d'une régénération.
La réparation idempotente d'une commission existante reste possible même si
le profil courant contient ensuite un nom non pris en charge.
La réponse sépare `error`/`code` stables, `message` français exploité par
`stripeMissionPay` et le point de code technique dans `details`. Le message
demande de contacter l'assistance sans modifier l'identité ; il n'affiche pas
le code Unicode brut. Une police invalide possède un message distinct.

Avant édition, lecture seule de la fonction LIVE `generate-invoice` v676,
ACTIVE : les trois fichiers étaient strictement identiques à la base
`ed402c3277d634691acc43a1a2cbeec93a126092`. SHA256 de l'index :
`a7a0ae34b0a9a73e6bd2c41bae6ffc4c97246919984717759830020f13629d1d`.
La source reçue est conservée localement dans
`/private/tmp/jolene-f1-generate-invoice-live-676.json` ; aucune valeur de secret
n'a été lue. La nouvelle version nécessite la CI de déploiement Supabase après
revue et merge. Ce lot local ne prouve pas son déploiement.

## Assertions exécutées

- Handler réel : facture hebdomadaire 4h ×20€ =80€, avoir 1h ×20€ =20€.
  Identités fictives avec accents, apostrophe et `&`. XML analysé par DOMParser :
  racine CII et namespaces, profil annoncé, numéros, types380/381, identités et
  identifiants, dates, devise, quantité/prix, totaux ligne/en-tête, référence et
  date de la facture d'origine. Le PDF présente l'avoir à −20€, le XML381 garde
  ses montants positifs. Les deux empreintes XML capturées avant correction
  restent identiques. Cela ne constitue pas une validation fiscale du profil.
- Quatre uploads fictifs avec MIME exacts, clés sans écrasement, deux registres
  liés aux bons IDs/chemins, SHA256 des vrais octets PDF/XML. Panne d'upload XML :
  réponse500 et `ERREUR_GENERATION`, aucune émission/notification ni registre.
- Unicode : facture et avoir avec `Łukasz İpek D'Été`, adresse grecque et
  établissement cyrillique, texte exact extrait du PDF normal/gras et du XML.
  Refus des caractères absents et octets de polices vides/corrompus : aucun
  numéro, insert/update, upload, registre, émission, commission ou email.
  Régénération sur snapshots conservés et refus sans remplacer les documents ;
  doublon existant testé séparément pour préserver sa réparation de commission.
- PDF extrait et rendu par PDF.js installé : titre, numéros, identités, SIRET,
  dates, période/quantités, totaux, référence de l'avoir et mention subrogative
  complète identique au XML. Géométrie horizontale/verticale dans la page.
  Cas de stress distinct : identité composée et description longue, deux pages
  sur facture et avoir, mention et pied de page préservés. Ce cas ne prouve pas
  la pagination de toutes les combinaisons de textes arbitrairement longs.
- Soignant : connexion → Revenus → Factures → PDF de la facture puis de l'avoir,
  vrai événement `download`, nom attendu et empreinte identique à l'upload du
  handler. Rechargement puis deux nouveaux téléchargements identiques.
- Établissement : connexion → Facturation → Commissions → PDF. Le vrai
  générateur client jsPDF produit la commission de période : assiette80€,
  HT12€, TVA2,40€, TTC14,40€. Même parcours après rechargement. Cette commission
  est générée côté client ; elle n'est pas un PDF serveur archivé dans ce banc.
- Refus expliqué : depuis Facturation, clic réel « Payer via Stripe » ; le
  premier appel Edge **simulé** répond `FACTURE_NON_GENEREE`, puis la réponse422
  issue du vrai handler fictif est renvoyée à `generate-invoice`. Le toast
  affiche le français attendu, l'identité reste exacte et aucun nouvel appel
  de paiement/checkout n'est effectué. Même refus après rechargement. Le témoin
  avant correction échouait sur le message absent. Aucun paiement Stripe n'est
  lancé : les deux endpoints locaux sont interceptés et les autres interdits.
- Cinq formats : iPhone390×844, Android Pixel7, iPad820×1180 et1180×820,
  ordinateur1440×900. Erreurs page/console, requêtes inconnues et opérations
  métier inattendues bloquantes. Le cas de refus accepte seulement les messages
  navigateur de ressource correspondant aux deux URL locales exactes et aux
  statuts409/422 attendus ; aucune erreur applicative n'est filtrée.
  Stripe est un stub qui lève si utilisé.
  WebSockets fermés, HTTP extérieur et redirections de navigation interdits.

Les téléchargements WebKit sont bien réalisés par WebKit. PDF.js6 nécessite
`ReadableStream` itérable, absent du WebKit installé : les octets téléchargés
sont analysés dans un Chromium séparé, dont seules trois ressources fictives
locales sont autorisées. Aucun polyfill ni analyseur n'est injecté dans l'app.

## Résultats et reproduction

Sur la source corrigée avec Noto et message français : **9/9 Node, 20/20 parcours frontend**, sans retry,
skip, erreur console/page inattendue ou requête inconnue. `tsc -b`, typecheck E2E isolé,
17guards et actionlint passent. Le build neuf utilise uniquement une URL
Supabase loopback et une clé publique fictive ; aucun upload Sentry.

```sh
node --test tests/node/facturation-documents.node.mjs
VITE_SUPABASE_URL=http://127.0.0.1:54321 VITE_SUPABASE_PUBLISHABLE_KEY=recette-fictive SENTRY_UPLOAD_ENABLED=false VITE_SENTRY_DSN='' node_modules/.bin/vite build --outDir /private/tmp/jolene-f1-documents-dist
VITE_SUPABASE_URL=http://127.0.0.1:54321 VITE_SUPABASE_PUBLISHABLE_KEY=recette-fictive SENTRY_UPLOAD_ENABLED=false VITE_SENTRY_DSN='' node_modules/.bin/vite preview --host 127.0.0.1 --port 18481 --strictPort --outDir /private/tmp/jolene-f1-documents-dist
PLAYWRIGHT_BASE_URL=http://127.0.0.1:18481 RECETTE_RESULTS_DIR=/private/tmp/jolene-f1-documents-ui-valide node_modules/.bin/playwright test -c e2e/playwright.recette-complete.config.ts e2e/recette-complete-facturation-documents.spec.ts --trace=off --workers=1
```

Dans ce checkout aux dépendances partagées non modifiables, préfixer Node et
Playwright par `NODE_PATH=/private/tmp/jolene-f1-unicode-deps-20260930/node_modules`.
Sur une installation CI normale, fontkit1.1.1 provient du lockfile.

Le workflow `validate-pr` ajoute l'exécution Node et un contrôle Deno2.9.7,
[version publiée](https://github.com/denoland/deno/releases/tag/v2.9.7), avec
setup-deno figé au SHA22d081ff2d3a40755e97629de92e3bcbfa7cf2ed. Une étape acquiert
uniquement les modules npm sans credentials ; le test suivant utilise le cache
seul et refuse les permissions net/env/read/write/run/ffi/sys. Il charge le
vrai index en capturant `Deno.serve`, exerce OPTIONS et incorpore les deux
fontes dans un PDF minimal. C'est un contrôle de chargement/embedding, distinct
de l'exécution complète du handler par Node. **Deno absent localement : ce
contrôle doit encore passer en CI**, sans bootstrap ni base cloud. Aucun
changement au routage SQL, aux suites staging ou aux fixtures v11.

Les [preuves compactes](../../recette/2026-09-30/facturation-documents/) contiennent
les résultats par format, ARIA avant/après, écrans iPhone/ordinateur et rendus
PDF avant/après, témoin500 Unicode et rendus Noto. Les pages de facture, avoir, commission et pagination ont été
inspectées visuellement. Les fichiers complets restent dans
`/private/tmp/jolene-f1-documents-final-ui` (20 cas actuels), le témoin de message
absent dans `/private/tmp/jolene-f1-documents-erreur-rouge`, les premiers 15 cas
Unicode dans `/private/tmp/jolene-f1-documents-unicode-ui`, et la première
recette sans Noto dans `/private/tmp/jolene-f1-documents-ui-valide` ; le témoin rouge géométrique dans
`/private/tmp/jolene-f1-documents-ui-debordement-rouge`. Les tentatives précédentes
ont identifié le routage local de PDF.js, son API de fermeture, un taux fictif
exprimé initialement en ratio au lieu de pourcentage, et la limite WebKit ;
elles ne sont pas comptées comme validations produit.

Les cinq scénarios de refus ont ensuite repassé avec une assertion supplémentaire
sur la visibilité complète du message après animation, avant capture :
`/private/tmp/jolene-f1-documents-erreur-final` (5/5). Les captures de refus
commitées proviennent de ce dernier contrôle.

## Limites explicites

Ce sont des IO simulées autour des vrais générateurs et composants, sans
intégration Supabase réelle, RLS, Storage cloud, cron, envoi email ou appareil
physique. Le partage natif Filesystem/Share et les autres écrans de téléchargement
ne sont pas prouvés ici. Aucun bouton XML n'existe dans ces interfaces : le XML
est contrôlé directement depuis les octets produits par le handler.
La commission client jsPDF garde sa police actuelle : sa couverture Unicode
hors noms testés ici n'est pas prouvée par la correction du générateur serveur.

Les PDF et XML sont **deux fichiers séparés**. Le profil déclaré dans le XML
n'est pas une certification Factur-X ; aucun validateur XSD/Schematron/PDF-A-3
ni conformité d'un fichier hybride embarquant le XML n'est établi. Aucune
nouvelle règle juridique/contractuelle, aucun barème et aucune preuve de
capacité de lancement national ne sont ajoutés par ce lot.
