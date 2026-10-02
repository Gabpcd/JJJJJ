# Acteurs neufs pour la recette intégrée Connect TEST

Cet opérateur prépare uniquement les acteurs, leur rattachement Stripe TEST et une première facture générée. Le contrat livré est fermé (`ready:false`). Aucun appel distant n'a été exécuté pour vérifier ce code. Les tests Node utilisent un transport simulé ; ni PostgreSQL distant, ni Stripe, ni un parcours frontend ne sont prouvés par leurs résultats.

La préparation produit un nouveau soignant libéral TEST, un nouvel établissement TEST et un troisième acteur admin synthétique. Ce dernier sert seulement à exercer les RPC de revue TVA dans la transaction de préparation ; son accès `equipe_admin` est désactivé avant le COMMIT, aucune session admin n'est ouverte. Les identités, adresses, attestation de mandat et mission portent explicitement leur caractère synthétique. Cette mission `EN_COURS`, ses créneaux effectifs et sa confirmation TVA sont des données de recette : **ils ne prouvent ni publication, ni attribution, ni qualification, ni consentement, ni pointage réel**.

Le seed reprend les validations et RPC utilisés par `f1-cloud-sql/prepare.sql`, dans un nouveau fichier avec marqueur `jolene_connect_fixture_owner`. Le catalogue structurel réutilise seulement le SELECT de F1. Aucun pilote F1 n'est appelé et son verrou `ready:false` reste intact.

## Résultat attendu de la préparation

- Un Customer TEST dédié à l'établissement, avec `metadata.etablissement_id` et le marqueur de cette recette.
- Un compte Connect **Express FR** dédié au soignant, avec `metadata.soignant_id`, le même marqueur et virements manuels. La plateforme doit être exactement `acct_1T9pt0EVhQ7cb53W`. Le compte historique `acct_1UKlZCEVhQI2aaZg` est explicitement exclu. Aucun objet existant n'est adopté, réparé ou reclassé.
- Une facture d'honoraires de 80 € et sa commission de 14,40 €, émises par le vrai endpoint `generate-invoice`, avec documents PDF/XML et version de document. Le script n'insère ni facture, ni statut de facture ; il rapproche la réponse réelle et les lignes produites.
- Zéro PaymentIntent, Checkout, Refund, transfert ou capacité TEST créé par cet opérateur. Le protocole général reste fermé et la table des capacités doit rester vide.

Le compte Express est créé avec le même contrat API que l'intégration (`2026-02-25.clover`). Ses détails, paiements et virements doivent encore être désactivés à la relecture Stripe ; toute évolution inattendue ferme cette préparation. Le compte est conservé `EN_COURS`, jamais rendu artificiellement `COMPLET`. Une lecture du solde connecté sous la clé TEST confirme `livemode:false` ; l'objet Account v1 n'expose pas lui-même ce champ. Aucun lien d'onboarding, acceptation des conditions Stripe, IBAN ou document d'identité n'est créé ici.

## Commandes opérateur

La planification est locale, sans accès réseau. Le dossier ne doit pas déjà exister et doit utiliser son chemin réel (par exemple `/private/tmp`, pas l'alias `/tmp`). Le SHA fourni est celui de la source revue qui devra être sur `main` au moment de la préparation.

```sh
node scripts/ci/connect-test-fixture.mjs plan /private/tmp/connect-test-recette-privee connect-test-recette-20261002 SHA_MAIN_REVU
```

Le dossier est privé (`0700`), ses fichiers sont `0600`. Il contient les identifiants de connexion synthétiques dans `manifest.private.json` et le modèle fermé `contract.private.json`. Ne pas publier, commiter ou verser ce dossier aux artefacts GitHub : le dépôt est public. Les sorties console ne contiennent ni mot de passe, ni token, ni corps d'erreur fournisseur.

Avant d'ouvrir **ce seul contrat privé**, une revue distincte doit renseigner : SHA main exact, SHA256 du seed, expiration de moins de quatre heures, auteur de la revue, les empreintes structurelles et la vérification des canaux (`notificationsTestSkipReviewed`), puis versions/`verify_jwt`/empreintes des trois Edge Functions `generate-invoice`, `send-email`, `notify-support`. Les valeurs ne sont jamais apprises puis acceptées automatiquement. `protocolEnabled` et `capabilityEnabled` doivent rester `false`.

Le preflight relit main, le projet staging sain et son hôte canonique, les empreintes des Edge Functions, les routines/triggers/colonnes, la destination de support staging, les canaux différés, les crons et la barrière financière fermée. Il exige zéro opération et zéro allocation dans les tables privées Connect. Toute différence ferme la commande. La source locale doit être exactement ce SHA et le checkout propre. Le script n'installe ni migration, ni Edge Function, ni clé, ni webhook et ne modifie aucun réglage pour faire passer ce contrôle.

Après cette revue seulement, l'opérateur utilise les variables d'environnement existantes `STAGING_SUPABASE_ACCESS_TOKEN`, `STAGING_SUPABASE_SERVICE_ROLE_KEY`, `STAGING_SUPABASE_ANON_KEY`, `STRIPE_TEST_SECRET_KEY`. La clé Stripe doit être `rk_test_*` ou `sk_test_*`, de préférence restreinte aux seules opérations de préparation et de lecture nécessaires. Ne pas mettre ces valeurs dans la ligne de commande.

```sh
node scripts/ci/connect-test-fixture.mjs prepare /private/tmp/connect-test-recette-privee
```

Une installation fermée du moteur Connect doit déjà avoir eu lieu, et les versions des fonctions qui ignorent les notifications des comptes TEST doivent être revues. Les préférences email/SMS/push/in-app des deux acteurs sont fermées ; leurs profils restent `est_compte_test=true`, SMS et partenaires désactivés. Les appels de génération doivent produire exactement deux traces `NOTIFICATION_SKIPPED` pour les comptes TEST, sans file email ni relance d'émission.

## Reprise et contrôles

Chaque étape écrit son intention dans le journal avant la mutation, puis enregistre son reçu. Les étapes confirmées sont relues à distance et ne sont pas répétées. Les créations Stripe utilisent les clés canoniques par identifiant d'acteur (`customer_etablissement_…`, `connect_account_…`). Le lien en base est un CAS depuis NULL dans une transaction ; tout lien déjà occupé ferme l'opération.

Une intention sans reçu — timeout, réponse refusée, crash, sauvegarde interrompue — ferme toute reprise, même si un objet semble exister. Ne jamais supprimer cette intention ni relancer avec de nouveaux acteurs pour masquer l'incertitude. Rapprocher l'opération lors d'une revue séparée. Un verrou de processus restant après un crash exige également inspection avant toute reprise. Aucun retry automatique, suppression compensatoire ou réaffectation d'un compte historique n'est prévu.

La recette d'onboarding doit ensuite se poursuivre dans l'interface, sur ce même Express TEST, puis le statut doit être relu via `stripe-connect-status`. La fixture terminée ne peut plus être rejouée après un changement de statut d'onboarding : son journal reste une preuve de préparation. L'allocation bornée TEST et la recette frontend Payer → confirmation → remboursement sont des étapes séparées. Le résultat privé rapporte explicitement `onboardingComplete:false`, `uiPaymentVerified:false`, `publicationProven:false`, `assignmentProven:false`.

Cette préparation doit encore être confrontée au vrai PostgreSQL et aux triggers staging avant sa première exécution. La validation fonctionnelle doit inclure la simulation frontend des rôles et formats pertinents, puis le rapprochement backend/Stripe TEST des mêmes objets. Aucune production, aucun appareil physique et aucun mouvement d'argent réel ne sont couverts ici.

Références : [création Auth serveur Supabase](https://supabase.com/docs/reference/javascript/auth-admin-createuser), [comptes Express existants](https://docs.stripe.com/connect/express-accounts), [création de compte Stripe](https://docs.stripe.com/api/accounts/create), [tests Connect](https://docs.stripe.com/connect/testing).

## Preuve locale du 2 octobre 2026

`node --test tests/node/connect-test-fixture.node.mjs` : **9 tests réussis, 0 échec**. Le transport Auth simulé couvre la réponse enveloppée `{user}` du GET admin et la réponse directe du POST, comme la reprise F1 existante. Les tests couvrent la fermeture avant réseau, les pins de provenance/canaux, le refus des acteurs historiques et du mode LIVE, les liens propriétaires, un parcours complet de préparation simulée, la reprise sans double création et le refus après réponse Stripe incertaine.

La vraie commande locale `plan` a aussi créé un dossier privé et rapporté `ready:false, remoteCalls:0`. La commande `prepare` avec ce contrat inchangé a refusé `READINESS_CLOSED`. Aucun secret n'était fourni, aucun appel distant n'a eu lieu. Le contrôle de syntaxe Node a réussi. Aucune exécution PostgreSQL ou Stripe et aucune simulation frontend n'a été réalisée dans cette vérification locale.
