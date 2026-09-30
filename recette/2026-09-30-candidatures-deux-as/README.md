# Lot D — deux candidatures AS, simulation frontend bornée

Base produit : `1e898d4ba9bcf9714568818039ac743d6743333c`. Branche de recette distincte, à remettre au lot D; **ne pas intégrer à #1000**. Aucun fichier produit, migration, règle de qualification, texte juridique ou workflow n'est modifié.

## Contrat de simulation

Deux profils fictifs AS/SALARIE ont leurs prénom, nom, date de naissance et téléphone renseignés; identité, diplôme, RPPS et documents restent non validés. L'établissement fictif CLINIQUE_PRIVEE est `EN_ATTENTE`, `peut_publier=false`, sans contrat de service signé. Tous sont des comptes test simulés en mémoire; aucune création Auth distante.

La mission synthétique est déjà `OUVERTE`, en mode `CANDIDATURE`, non urgente, sans soignant assigné, avec un créneau du 2 octobre 2026 de 09h à 13h Paris (07h–11h UTC, quatre heures). La recette ne prouve ni n'autorise sa publication par un établissement non vérifié.

Ces identifiants, messages et horaires sont des fixtures frontend indépendantes du préparateur SQL lot D (qui utilise son propre marqueur de run et 09h–13h UTC). Aucune correspondance entre les objets distants et cette simulation n'est revendiquée.

L'interface appelle seulement `fn_confirmer_action_planning_v1` pour l'action `POSTULER`, avec mission, créneau exact, message, choix de contrat `null` et candidature `null`. Le mock répond `choix_contrat='SALARIE'`, `profession_requise='AS'`, `docs_a_completer=true`, `documents_requis_pour='SALARIE'`. La résolution métier de `null` vers SALARIE est une réponse simulée, pas un calcul serveur validé par ce test.

## Assertions réalisées par la spec

1. Chacun des deux AS ouvre la mission, écrit son message, lit et confirme les dates/heures exactes. Le succès rappelle les documents avec l'action « Mes documents ». Après rechargement, la candidature reste en attente et le bouton de nouvel envoi a disparu. Exactement un POSTULER par soignant.
2. L'établissement voit les deux noms, messages, documents non validés et deux candidatures `EN_ATTENTE`, puis les retrouve après rechargement. Aucun bouton d'acceptation n'est actionné.
3. La panne 503 persistante de lecture absorbe les deux tentatives automatiques puis expose « Réessayer ». Après rétablissement simulé, une panne 503 d'envoi affiche une erreur sans candidature ni succès. Un planning changé depuis le chargement est ensuite refusé; recharger puis confirmer les nouveaux horaires permet un seul enregistrement.
4. Un établissement tiers reçoit l'absence de mission simulée (`PGRST116`), voit « Mission introuvable », n'accède pas aux profils candidats, avant et après rechargement.
5. À chaque fin : aucune requête inconnue/externe ni erreur JavaScript, aucun appel d'acceptation/signature/contrat/paiement; mission toujours ouverte, non assignée, régime appliqué nul; qualifications test inchangées.

Les mêmes trois scénarios sont exécutés sur iPhone, Android, iPad portrait/paysage et ordinateur avec WebKit/Chromium. Captures, arbres d'accessibilité et journaux JSON sont conservés hors dépôt. Les captures vérifient aussi l'absence de débordement horizontal.

Résultat final du 30 septembre 2026, 09:54 UTC : **15/15 réussis**, aucun skip/retry/flaky, 15 journaux avec zéro appel inconnu, externe ou erreur JavaScript. `tsc -b` et le typecheck ciblé E2E réussissent. Le fichier `validation.json` contient les résultats individuels et les SHA256 des sources et du rapport Playwright; artefacts complets : `/private/tmp/jolene-candidatures-deux-as-5formats-final`. Captures iPad portrait (AS et établissement) et iPhone établissement inspectées visuellement. Aucun constat produit nécessitant un patch dans ce périmètre.

## Reproduction locale sans réseau distant

Avec les dépendances existantes, lancer depuis ce checkout :

```sh
VITE_SUPABASE_URL=http://127.0.0.1:8891 \
VITE_SUPABASE_PUBLISHABLE_KEY=sb_publishable_simulation_candidatures \
node node_modules/vite/bin/vite.js --host 127.0.0.1 --port 18460 --strictPort

PLAYWRIGHT_BASE_URL=http://127.0.0.1:18460 \
RECETTE_RESULTS_DIR=/private/tmp/jolene-candidatures-deux-as-5formats-final \
node node_modules/@playwright/test/cli.js test \
  --config=e2e/playwright.recette-complete.config.ts recette-complete-candidatures-deux-as.spec.ts

node node_modules/typescript/bin/tsc -b --pretty false
node node_modules/typescript/bin/tsc --noEmit --target ES2022 --module ESNext \
  --moduleResolution bundler --esModuleInterop --skipLibCheck \
  e2e/helpers/recette-candidatures-deux-as.ts e2e/recette-complete-candidatures-deux-as.spec.ts
```

Le routeur Playwright intercepte toute API et refuse toute requête distante. Les WebSockets sont fermés; le mode dégradé des notifications est donc attendu, sans validation de Realtime. Les hints externes et la feuille Google Fonts sont retirés du HTML de test (police système de repli). Un stub Stripe local jette s'il est invoqué, évitant l'auto-chargement du SDK lors de l'import du détail établissement. Aucun endpoint financier n'est prévu par les mocks.

Le premier banc incomplet n'exposait pas `content-range` via CORS: l'interface a correctement refusé de confirmer un planning non vérifiable. Le mock a été corrigé, sans retrait de garde produit. Les assertions d'horaires et d'erreur ont été alignées sur les textes réellement rendus (`09h00`, préfixe `Erreur:`), et les captures attendent la fermeture animée du dialogue. Les artefacts des passes intermédiaires sont conservés sous `/private/tmp/jolene-candidatures-deux-as-ordinateur*` et `/private/tmp/jolene-candidatures-deux-as-5formats`.

## Limites explicites

Il s'agit d'une **simulation avec réponses simulées**, pas d'une intégration Supabase/RLS, d'une qualification documentaire, d'un envoi réel de notification ou d'un appareil physique. Aucun profil personnel, fichier, contrat, donnée de paiement ou fournisseur réel n'est lu ou modifié. Les refus serveur et la persistance sont simulés; les preuves SQL/API du lot D doivent les compléter séparément. Aucun engagement sur l'acceptation, le contrat ou le paiement n'est testé dans ce lot.
