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
pas utilisé. Aucune dépendance n'a été installée ou modifiée.

## Défaut observé et correction bornée

La vraie facture et le vrai avoir dessinaient la mention subrogative sur une
ligne dépassant la page A4. L'extraction partielle du texte pouvait masquer ce
défaut ; le rendu et une assertion géométrique l'ont montré. La correction
replie la mention selon la largeur réelle de la police, réserve la hauteur du
pied de page et, si nécessaire, reporte le bloc sur une nouvelle page portant
le numéro du document. Les tampons existants concernent toutes les pages.
Le texte, les règles, les calculs, les destinataires, le XML et les IO métier
restent inchangés. Aucun backfill ou régénération de document existant.

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
- Cinq formats : iPhone390×844, Android Pixel7, iPad820×1180 et1180×820,
  ordinateur1440×900. Erreurs page/console, requêtes inconnues et opérations
  métier inattendues bloquantes. Stripe est un stub qui lève si utilisé.
  WebSockets fermés, HTTP extérieur et redirections de navigation interdits.

Les téléchargements WebKit sont bien réalisés par WebKit. PDF.js6 nécessite
`ReadableStream` itérable, absent du WebKit installé : les octets téléchargés
sont analysés dans un Chromium séparé, dont seules trois ressources fictives
locales sont autorisées. Aucun polyfill ni analyseur n'est injecté dans l'app.

## Résultats et reproduction

Sur la source corrigée : **4/4 Node, 10/10 parcours frontend**, sans retry,
skip, erreur console/page ou requête inconnue. `tsc -b`, typecheck E2E isolé,
17guards et actionlint passent. Le build neuf utilise uniquement une URL
Supabase loopback et une clé publique fictive ; aucun upload Sentry.

```sh
node --test tests/node/facturation-documents.node.mjs
VITE_SUPABASE_URL=http://127.0.0.1:54321 VITE_SUPABASE_PUBLISHABLE_KEY=recette-fictive SENTRY_UPLOAD_ENABLED=false VITE_SENTRY_DSN='' node_modules/.bin/vite build --outDir /private/tmp/jolene-f1-documents-dist
VITE_SUPABASE_URL=http://127.0.0.1:54321 VITE_SUPABASE_PUBLISHABLE_KEY=recette-fictive SENTRY_UPLOAD_ENABLED=false VITE_SENTRY_DSN='' node_modules/.bin/vite preview --host 127.0.0.1 --port 18481 --strictPort --outDir /private/tmp/jolene-f1-documents-dist
PLAYWRIGHT_BASE_URL=http://127.0.0.1:18481 RECETTE_RESULTS_DIR=/private/tmp/jolene-f1-documents-ui-valide node_modules/.bin/playwright test -c e2e/playwright.recette-complete.config.ts e2e/recette-complete-facturation-documents.spec.ts --trace=off --workers=1
```

Le workflow `validate-pr` ajoute uniquement l'exécution Node hors réseau.
Aucun changement au routage SQL, aux suites staging ou aux fixtures v11.

Les [preuves compactes](../../recette/2026-09-30/facturation-documents/) contiennent
les résultats par format, ARIA avant/après, écrans iPhone/ordinateur et rendus
PDF avant/après. Les pages de facture, avoir, commission et pagination ont été
inspectées visuellement. Les fichiers complets restent dans
`/private/tmp/jolene-f1-documents-ui-valide` ; le témoin rouge géométrique dans
`/private/tmp/jolene-f1-documents-ui-debordement-rouge`. Les tentatives précédentes
ont identifié le routage local de PDF.js, son API de fermeture, un taux fictif
exprimé initialement en ratio au lieu de pourcentage, et la limite WebKit ;
elles ne sont pas comptées comme validations produit.

## Limites explicites

Ce sont des IO simulées autour des vrais générateurs et composants, sans
intégration Deno/Supabase réelle, RLS, Storage cloud, cron, envoi email ou appareil
physique. Le partage natif Filesystem/Share et les autres écrans de téléchargement
ne sont pas prouvés ici. Aucun bouton XML n'existe dans ces interfaces : le XML
est contrôlé directement depuis les octets produits par le handler.

Les PDF et XML sont **deux fichiers séparés**. Le profil déclaré dans le XML
n'est pas une certification Factur-X ; aucun validateur XSD/Schematron/PDF-A-3
ni conformité d'un fichier hybride embarquant le XML n'est établi. Aucune
nouvelle règle juridique/contractuelle, aucun barème et aucune preuve de
capacité de lancement national ne sont ajoutés par ce lot.
