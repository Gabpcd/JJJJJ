# Capacité SMS de signature STAGING — mode opératoire (lot 2 S1, 2 novembre 2026)

Allocateur : `scripts/ci/allouer-capacite-sms-signature-staging.mjs`. Workflow de
la séance appareil : `.github/workflows/sms-signature-capacite-staging.yml`.
Supplément relu : `scripts/ci/sms-signature-staging.sql` (recette fermée du
14 octobre, `docs/recettes/2026-10-14-signature-sms-staging-fermee.md`).

Catégorie **B9** : secrets STAGING, fonctions `SECURITY DEFINER` du supplément,
données STAGING. Chaque dispatch demande le go explicite de Gabrielle. Projet
`mejpriaetwgtcstbgfid` seulement : tout autre ref est refusé avant le réseau.

## Ce que l'allocateur écrit, et rien d'autre

- une ligne `private.signature_sms_test_capacities` (insertion fermée, puis
  activation sous le périmètre `private.fn_signature_sms_test_scope`, puis
  révocation irréversible) ;
- le secret Edge `SIGNATURE_SMS_STAGING_TEST_RUN`, écrit puis retiré.

Aucun profil, préférence, contrat, signature ni appel fournisseur. Téléphones et
identifiants Twilio restent des secrets d'environnement ; aucun reçu ne les
contient, ni aucune valeur qui en dérive.

## Trois modes, trois étapes

| Mode | Rôle | Issue réussie (code 0) | Autres issues (code 1) |
|---|---|---|---|
| `allouer` | preuves (main exact, projet, sources `send-sms`, secrets Edge, supplément, préconditions), insertion fermée, secret Edge, **délai de propagation de 60 s**, relecture des secrets, activation | `active` : capacité ouverte, reçu écrit | `echec` (refermé), `incertain` (fermeture non confirmée) |
| `attendre` | lecture seule, horloge du serveur, jusqu'à la fin attendue ou l'échéance | `succes` : fin attendue **et** signature relue sur l'empreinte inchangée | `termine_sans_preuve` (échéance, lectures en échec, document modifié, contrat non signable, capacité fermée), `echec` |
| `revoquer` | révoque la ligne de **ce** run (`run_id`) et retire le secret **écrit par ce run** ; relit l'état final | `succes` | `incertain`, `echec` |

La fin attendue (`fin_apres`) et la durée sont lues dans le manifeste haché du
reçu d'allocation, jamais ressaisies. `revoquer` ne ferme jamais la capacité ni
le secret d'un autre run : sans reçu exploitable, il retrouve sa propre ligne par
`run_id` et ne retire le secret que si cette ligne existe.

## Prérequis (Gabrielle)

1. Supplément installé (`install-sms-staging-closed.yml`), MD5 de
   `fn_envoyer_otp_signature` STAGING relu en lecture seule avant l'installation.
2. Secrets Edge Twilio de recette posés sur le projet STAGING
   (`TWILIO_ACCOUNT_SID`, `TWILIO_AUTH_TOKEN`, `TWILIO_FROM_NUMBER`).
3. Environnement protégé `staging-sms-signature` (relecteur requis, branche
   `main`) portant `SMS_RECETTE_TELEPHONE_SOIGNANT`,
   `SMS_RECETTE_TELEPHONE_ETABLISSEMENT`, `SMS_RECETTE_TWILIO_ACCOUNT_SID`,
   `SMS_RECETTE_TWILIO_EXPEDITEUR`.
4. Comptes TEST de la fixture portant ces numéros, `auth.users` confirmés à
   `est_compte_test = true`, contrat rendu (empreinte relue), `canal_sms` activé
   dans l'interface pour le soignant, **et pour l'établissement si
   `fin_apres = signature_complete`** (l'allocateur le refuse sinon).
5. Aucune autre campagne STAGING ouverte : `CONNECT_STAGING_TEST_RUN`,
   `INVOICE_STAGING_TEST_RUN`, `HONORAIRES_STAGING_TEST_RUN`,
   `INVOICE_EMAIL_STAGING_TEST_RUN` absents (refus `AUTRE_CAPACITE_OUVERTE`).

## Séance appareil (T12) : workflow S1

1. Dispatcher sur `main` avec `expected_sha` (SHA exact de `main`),
   `contrat_id` (contrat de la fixture appareil), `duree_minutes`, `fin_apres`,
   puis approuver le job « Allouer et activer la capacité ».
2. Attendre la **fin de ce job** avant tout envoi : l'admission reste fermée
   tant que la capacité n'est pas activée, et l'activation suit la confirmation
   du secret de 60 s.
3. Signer dans l'app. Le job « Attendre la signature » (hors verrou) se termine
   à la signature attendue ou à l'échéance ; il ne révoque jamais.
4. Le job « Révoquer » s'exécute toujours ensuite, sans nouvelle approbation.
   Preuve : artefacts `…-allocation-…`, `…-attente-…`, `…-revocation-…` et
   relecture SQL de `signatures_contrats`.

**Verrou** : seuls les jobs d'allocation et de révocation prennent le groupe
`jolene-supabase-staging-writes` (quelques minutes). L'attente n'en prend pas :
une séance de 60 min ne bloque plus `sql-transaction` de `validate-pr.yml` ni les
merges sériels. Pendant la séance, les autres campagnes STAGING refusent de
s'ouvrir (secret présent) et une allocation T11 est refusée
(`CAPACITE_EDGE_DEJA_OUVERTE`) : ne dispatchez pas T11 pendant une séance
appareil. La révocation peut attendre son tour dans la file du groupe ;
l'échéance serveur (`expires_at`) ferme de toute façon le périmètre.

## Intégration T11 (`ios-swift-lot2-staging.yml`)

T11 n'appelle pas ce workflow (il resterait en file derrière T11, qui détient le
même groupe). Dans **son** job, sous le groupe `jolene-supabase-staging-writes` :

1. Contrats, temps 1 (rendu du contrat C) ;
2. `node scripts/ci/allouer-capacite-sms-signature-staging.mjs allouer` avec
   `EXPECTED_SHA` (SHA relu, égal à `GITHUB_SHA`), `SUPABASE_PROJECT_REF`,
   `CONTRAT_ID`, `DUREE_MINUTES` (10 à 60), `FIN_APRES=signature_soignant`,
   `STAGING_SUPABASE_ACCESS_TOKEN`, `GITHUB_TOKEN` et les quatre secrets
   `SMS_RECETTE_*` (l'environnement de T11 doit les porter) ; l'étape rend la
   main capacité active ;
3. Contrats, temps 3 (envoi, statut `otp_envoye`) ;
4. `… revoquer` avec `if: always()` et le seul `STAGING_SUPABASE_ACCESS_TOKEN`,
   puis publication de `recu.json` et `revocation.json` (`$RUNNER_TEMP/sms-signature-capacite`).

Le checkout doit rester propre pour `allouer` (sorties de build hors dépôt ou
ignorées) ; `revoquer` tourne même si le checkout a été modifié. Le script
n'accepte que ces deux workflows, sur `main`, au premier essai.

## Nettoyage de la cohorte (T11, T12)

Le supplément ne pose qu'un trigger `BEFORE UPDATE` : la révocation est
irréversible, mais le propriétaire `postgres` peut supprimer une ligne (Management
API). Les clés étrangères de la ligne, sans `ON DELETE`, vers `missions`,
`contrats_mission`, `soignants` et `etablissements` bloquent toute suppression de
la cohorte tant qu'elle existe. Ordre attendu du nettoyage :

1. vérifier que la ligne de la cohorte est révoquée (`revoked_at` non nul,
   `enabled = false`) ; sinon, ne rien supprimer et lancer `revoquer` ;
2. supprimer cette ligne en `postgres` (Management API ; `service_role` n'a
   aucun droit sur la table) ;
3. supprimer ensuite la cohorte.

Ne jamais supprimer une ligne non révoquée, remettre un compteur à zéro ni
réactiver une capacité usagée.

## Limites connues

- Le délai de 60 s est une borne, pas une preuve de propagation du secret Edge.
- Un job relancé (`GITHUB_RUN_ATTEMPT` 2) est refusé, et un run ne révoque que sa
  propre ligne. Après une révocation `incertain`, le périmètre se ferme à
  l'échéance serveur, mais la ligne restée `enabled` bloque toute nouvelle
  allocation (index « une capacité active par projet ») et le secret resté
  présent bloque les autres campagnes : les refermer à la main (révocation SQL
  en `postgres`, secret retiré depuis le tableau de bord Supabase), sous go B9.
- Fin `signature_soignant` : la préférence SMS de l'établissement est relevée
  sans bloquer (seul le soignant envoie), écart déclaré au blueprint S1 qui la
  demandait pour chaque acteur.
