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

Avant toute écriture réelle, un aperçu annulé (`ROLLBACK`) exerce sur STAGING
l'insertion, l'activation, le périmètre **et la révocation** (même texte SQL que
le mode `revoquer`, suivi de sa vérification) : le trigger
`signature_sms_test_immutable` et les `CHECK` du supplément acceptent donc la
révocation avant le premier `COMMIT`.

## Trois modes, trois étapes

| Mode | Rôle | Issue réussie (code 0) | Autres issues (code 1) |
|---|---|---|---|
| `allouer` | preuves (main exact, projet, sources `send-sms`, secrets Edge, supplément, préconditions), aperçu annulé, insertion fermée, secret Edge, **délai de propagation de 60 s**, relecture des secrets, activation | `active` : capacité ouverte, reçu écrit | `echec` (refermé), `incertain` (fermeture non confirmée) |
| `attendre` | lecture seule, horloge du serveur, jusqu'à la fin attendue ou l'échéance | `succes` : fin attendue **et** signature relue sur l'empreinte inchangée | `termine_sans_preuve` (échéance, lectures en échec, document modifié, contrat non signable, capacité fermée), `echec` |
| `revoquer` | révoque la ligne de **ce** run (`run_id`) et retire le secret **écrit par ce run**, sans attendre la sonde d'identité ; relit l'état final, puis l'état prouvé à l'allocation (corps `send-sms`, routines du supplément) | `succes` : fermeture confirmée, identité attestée, relecture conforme | `incertain` (voir ci-dessous), `echec` (refus avant tout appel réseau) |

La fin attendue (`fin_apres`) et la durée sont lues dans le manifeste haché du
reçu d'allocation, jamais ressaisies. `revoquer` ne ferme jamais la capacité ni
le secret d'un autre run : sans reçu exploitable, il retrouve sa propre ligne par
`run_id` et ne retire le secret que si cette ligne existe.

**Sonde d'identité** (`GET /v1/projects/<ref>` : `ACTIVE_HEALTHY`, région, hôte,
PostgreSQL 17) : réessayée partout, jamais un appel unique. En `allouer`, trois
essais avant toute écriture. En `attendre`, six essais espacés de 20 s, comme
les lectures d'état : une sonde ratée ne clôt pas la séance. En `revoquer`, elle
ne conditionne **jamais** la fermeture : l'URL de gestion fige le ref et chaque
écriture reprouve la base STAGING (Vault `supabase_url`, PostgreSQL 17, rôle
`postgres`) ; la ligne et le secret sont refermés d'abord, puis la sonde est
réessayée cinq fois. Son échec persistant donne `incertain`
(`PROJET_IDENTITE_NON_CONFIRMEE`), jamais `echec` sans tentative.

**Lire un reçu de révocation `incertain`** : `revocation.confirmee` dit si la
fermeture est acquise.

- `confirmee = true` (codes `PROJET_IDENTITE_NON_CONFIRMEE`,
  `REATTESTATION_DIFFERENTE`, `REATTESTATION_NON_RELUE`, `RECU_ILLISIBLE`,
  `RECU_INCOHERENT`) : ligne révoquée et secret retiré, **aucun nettoyage
  manuel** ; la preuve de la séance n'est pas acquise (`preuveP5 = false`).
- `confirmee = false` : fermeture non confirmée, nettoyage manuel (voir
  « Limites connues »).

Le reçu `revocation.json` est écrit dès la fermeture, puis à la fin : une étape
interrompue pendant la relecture laisse un reçu `incertain` lisible.

**Relecture finale** (lecture seule, dans `revoquer`, si une ligne de ce run a
existé) : la fermeture `send-sms` déployée est comparée aux sources du commit
relu, et les huit routines du supplément au contrat d'installation, comme à
l'allocation. L'attente étant hors verrou, un `supabase db push` de `main` par
`sql-transaction` ou un redéploiement de `send-sms` pendant la séance apparaît
dans le reçu (`reattestation.edge`, `reattestation.supplement`) et le rend
`incertain`.

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
   puis **approuver ou rejeter immédiatement** le job « Allouer et activer la
   capacité » (voir « Approbation et verrou »).
2. Attendre la **fin de ce job** avant tout envoi : l'admission reste fermée
   tant que la capacité n'est pas activée, et l'activation suit la confirmation
   du secret de 60 s.
3. Signer dans l'app. Le job « Attendre la signature » (hors verrou) se termine
   à la signature attendue ou à l'échéance ; il ne révoque jamais.
4. Le job « Révoquer » s'exécute toujours ensuite, sans nouvelle approbation.
   Preuve : artefacts `…-allocation-…`, `…-attente-…` (`succes`),
   `…-revocation-…` (`succes`, relecture finale conforme) et relecture SQL de
   `signatures_contrats`.

### Approbation et verrou

Le job « Allouer » est le premier du dépôt à combiner un environnement protégé
(relecteur requis) et le groupe `jolene-supabase-staging-writes`. La
documentation GitHub ne dit pas si un job en attente d'approbation tient déjà son
créneau dans le groupe ; un essai public
(`robert-dailey-milliman/test-github-concurrency`) montre qu'un job en attente
bloque les suivants du même groupe. Règle retenue : **il le tient**. Un dispatch
non approuvé bloque `sql-transaction` de `validate-pr.yml`, les merges sériels et
T11 jusqu'à la décision. Donc : ne dispatcher qu'avec la relectrice disponible,
puis approuver ou rejeter immédiatement (« Reject », ou l'annulation du run,
libère le groupe). Sortir l'approbation dans un job sans groupe obligerait à
sortir les secrets `SMS_RECETTE_*` de l'environnement protégé (un secret
d'environnement n'est lisible que par un job qui le référence) : écarté, la
protection des numéros prime.

Seuls les jobs d'allocation et de révocation prennent le groupe (quelques
minutes). L'attente n'en prend pas : une séance de 60 min ne bloque ni
`sql-transaction` ni les merges sériels. La révocation peut attendre son tour
dans la file du groupe ; l'échéance serveur (`expires_at`) ferme de toute façon
le périmètre.

### Exclusivité avec les autres campagnes STAGING

L'allocateur refuse de s'ouvrir si une autre campagne est ouverte
(`AUTRE_CAPACITE_OUVERTE`, relu aussi juste avant l'activation). Dans l'autre
sens, pendant la séance (secret `SIGNATURE_SMS_STAGING_TEST_RUN` présent),
seuls refusent :

- l'assistant `scripts/ci/invoice-emails-staging-test.mjs` (l.207,
  `OTHER_CAPACITY_STILL_OPEN`), qui ne s'ouvre pas ;
- les runtimes `supabase/functions/_shared/honoraires-staging-test.ts` (l.24)
  et `supabase/functions/_shared/invoice-email-staging-test.ts` (l.47), qui
  refusent de servir.

`supabase/functions/_shared/stripe-connect-staging-test.ts` (l.21) et
`supabase/functions/_shared/stripe-invoice-staging-test.ts` (l.21-24)
**ignorent** ce secret : l'exclusivité avec les campagnes Connect et Invoice
repose sur l'opératrice — ne pas ouvrir ces campagnes pendant une séance. Une
garde symétrique dans ces deux assistants relève d'une PR séparée (paiements,
B9), non faite ici. Une allocation T11 pendant une séance appareil est refusée
(`CAPACITE_EDGE_DEJA_OUVERTE`) : ne dispatchez pas T11 pendant une séance.

## Intégration T11 (`ios-swift-lot2-staging.yml`)

T11 n'appelle pas ce workflow (écart S1-E2 ci-dessous). Dans **son** job, sous
le groupe `jolene-supabase-staging-writes` :

1. Contrats, temps 1 (rendu du contrat C) ;
2. `node scripts/ci/allouer-capacite-sms-signature-staging.mjs allouer` avec
   `EXPECTED_SHA` (SHA relu, égal à `GITHUB_SHA`), `SUPABASE_PROJECT_REF`,
   `CONTRAT_ID`, `DUREE_MINUTES` (10 à 60), `FIN_APRES=signature_soignant`,
   `STAGING_SUPABASE_ACCESS_TOKEN`, `GITHUB_TOKEN` et les quatre secrets
   `SMS_RECETTE_*` (l'environnement de T11 doit les porter) ; l'étape rend la
   main capacité active ;
3. Contrats, temps 3 (envoi, statut `otp_envoye`) ;
4. `… revoquer` avec `if: always()`, le seul `STAGING_SUPABASE_ACCESS_TOKEN` et
   un délai d'étape d'au moins 12 min (comme le job « Révoquer » de S1), puis
   publication de `recu.json` et `revocation.json`
   (`$RUNNER_TEMP/sms-signature-capacite`).

**Checkout** : aucune exigence de propreté. Les sources `send-sms` et le contrat
d'installation comparés au déployé sont lus dans le commit `HEAD`
(`git ls-tree` puis `git cat-file`, fichiers ordinaires suivis seulement),
jamais dans l'arbre de travail ; seul `HEAD` doit rester égal à `GITHUB_SHA`.
Les sorties de build et de test de T11 n'empêchent donc ni `allouer` ni
`revoquer`.

**`main` inchangé jusqu'à l'activation** : `allouer` relit `refs/heads/main`
deux fois (provenance, puis juste avant l'insertion) et refuse `MAIN_DEPLACE` si
`main` a bougé depuis le dispatch. Règle voulue, comme `mainMatches` de
l'installateur : une capacité SMS réelle ne s'ouvre qu'avec l'allocateur, la
fermeture `send-sms` et le contrat du supplément de la tête de `main` ; un
correctif mergé entre-temps l'emporte sur un run plus ancien. `attendre` et
`revoquer` n'exigent jamais `main` inchangé. Conséquence pour T11 et T12 :
**gel des merges sur `main` du dispatch jusqu'à la fin de l'étape `allouer`**.
La file de merge sérielle suspend ses merges pendant cette fenêtre — pour T11,
elle couvre les XCUITest qui précèdent l'allocation (pointage avec attente de
125 s, documents, contrats temps 1) — puis reprend dès que l'étape a rendu la
main. Un `MAIN_DEPLACE` survient avant toute écriture (rien à refermer), mais le
run ne peut pas être rejoué (premier essai seulement) : redispatcher.

**Approbation** : si le job de T11 porte, comme celui de S1, un environnement
protégé et le groupe `jolene-supabase-staging-writes`, la même règle vaut :
approuver ou rejeter immédiatement (voir « Approbation et verrou »).

Le script n'accepte que ces deux workflows, sur `main`, au premier essai.

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

## Écarts au blueprint S1 (à reporter dans `docs/mobile-swift/DECISIONS_LOT2.md`)

La règle 1 des décisions des lots 2 à 5 consigne les critères amendés dans
`docs/mobile-swift/DECISIONS_LOT2.md`. Ce fichier est créé par la tranche T0 du
lot 2, non mergée au moment de cette PR : T0 (ou, à défaut, T11) y reporte ces
deux écarts, sous « S1 », avec renvoi à ce mode opératoire.

- **S1-E1 — `canal_sms` de l'établissement.** Le blueprint (§3 S1) demande
  `preferences_notifications.canal_sms` vrai « pour chaque acteur ». La portée
  du supplément (`scripts/ci/sms-signature-staging.sql` l.115) ne l'exige que
  pour l'acteur qui envoie. Fin `signature_soignant` (P5, seul le soignant
  envoie) : la préférence du soignant bloque, celle de l'établissement est
  relevée dans le reçu (`preconditions.canalSmsEtablissement`) sans bloquer.
  Fin `signature_complete` : elle est exigée.
- **S1-E2 — intégration T11.** Le blueprint (§3 S1) décrit le workflow S1
  « appelé par T11 entre le rendu et l'envoi ». T11 détient le groupe
  `jolene-supabase-staging-writes` pendant tout son job : un workflow S1 lancé
  depuis T11 attendrait derrière lui dans la file du groupe et ne passerait
  jamais. T11 lance donc les modes `allouer` puis `revoquer` (`always()`) du
  même script dans son propre job (liste fermée `WORKFLOWS_APPELANTS`) ; le
  workflow S1 reste celui de la séance appareil (T12).

## Limites connues

- Le délai de 60 s est une borne, pas une preuve de propagation du secret Edge.
- La relecture finale atteste l'état à la fin de la séance, identique à celui de
  l'allocation ; elle ne prouve pas l'absence d'un changement aller-retour
  pendant la séance.
- Un job relancé (`GITHUB_RUN_ATTEMPT` 2) est refusé, et un run ne révoque que sa
  propre ligne. Après une révocation `incertain` avec `revocation.confirmee =
  false`, le périmètre se ferme à l'échéance serveur, mais la ligne restée
  `enabled` bloque toute nouvelle allocation (index « une capacité active par
  projet ») et le secret resté présent bloque les campagnes qui le lisent : les
  refermer à la main (révocation SQL en `postgres`, secret retiré depuis le
  tableau de bord Supabase), sous go B9.
- Fin `signature_soignant` : la préférence SMS de l'établissement est relevée
  sans bloquer (écart S1-E1).
