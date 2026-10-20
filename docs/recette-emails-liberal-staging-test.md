# Réception des factures libérales en TEST

Cette recette transmet les trois reçus d'émission canoniques de deux pièces déjà
générées pour une même mission libérale TEST : honoraires au soignant,
honoraires à l'établissement, commission à l'établissement. Les trois messages
sont adressés exclusivement à `gabrielle@jolene.app`, avec sujet `[TEST]` et
bannière explicite. Elle ne crée ni facture, ni contrat, ni paiement.

Le projet autorisé est `mejpriaetwgtcstbgfid`. Les profils et identités Auth de
la cohorte existante restent marqués TEST. La génération des honoraires doit
être terminée, puis sa capacité SQL révoquée et son secret temporaire supprimé
avant l'ouverture de l'admission email. Les admissions paiement/Connect doivent
également être fermées. Les crons STAGE restent arrêtés pendant cette recette.

## Préparation et activation par l'opérateur

1. Lire les trois reçus `private.facturation_email_livraisons` de la nouvelle
   mission et les trois lignes `email_queue`. Confirmer l'événement `EMISSION`,
   les familles/rôles ci-dessous, le même corps, les clés canoniques, zéro
   tentative, aucune réservation et aucune trace fournisseur. Une tentative
   ancienne demande un rapprochement, jamais un reset.
2. Configurer `RESEND_API_KEY` uniquement sur STAGE via l'accès fournisseur
   autorisé. Garder les valeurs secrètes en mémoire, hors argv, logs ou fichiers
   de preuve. La liste des secrets Supabase fournit une présence/empreinte,
   pas une clé réutilisable. Configurer `APP_URL=http://127.0.0.1:8085`, où la
   version frontend de recette doit être disponible pour ouvrir les liens.
3. Après revue, commit et déploiement de `send-email`, relire officiellement le
   bundle et chacun de ses imports locaux via
   `GET /v1/projects/{project}/functions/send-email/body`. Comparer les bytes au
   commit ciblé et conserver une attestation publique (`sourcePins`,
   `allExact`, `targetSha`, métadonnées de fonction). Un SHA indiqué dans un
   secret ne constitue pas une preuve de déploiement.
4. Construire `INVOICE_EMAIL_STAGING_TEST_RUN` avec les vraies nouvelles
   identités de pièces/files et une fenêtre de 60 minutes maximum :

```json
{
  "serverSha": "<commit relu>",
  "manifestSha256": "<empreinte du manifeste d'activation public>",
  "missionId": "<mission libérale TEST>",
  "honorairesId": "<facture honoraires originale>",
  "commissionId": "<commission liée à cette facture honoraires>",
  "createdAt": "<date ISO courante>",
  "expiresAt": "<date ISO au plus 60 minutes plus tard>",
  "events": [
    {"family":"HONORAIRES","recipientRole":"SOIGNANT","emailId":"<file 1>","bodySha256":"<empreinte 1>"},
    {"family":"HONORAIRES","recipientRole":"ETABLISSEMENT","emailId":"<file 2>","bodySha256":"<empreinte 2>"},
    {"family":"COMMISSION","recipientRole":"ETABLISSEMENT","emailId":"<file 3>","bodySha256":"<empreinte 3>"}
  ]
}
```

Les empreintes utilisent `invoiceEmailBodySha256` sur le corps durable
`{type,destinataire_id,data}` : tri récursif des clés, tableaux inchangés,
`JSON.stringify`, UTF-8, SHA256. Ne pas réécrire les reçus, leurs adresses
logiques ou leurs clés. Tous les événements sont `FACTURE_EMISE` ; les
confirmations de paiement sont hors périmètre.

## Exécution bornée

`scripts/ci/invoice-emails-staging-test.mjs` reste fermé sans `--execute` et
contrat public revu. Ce contrat comprend :

- `schemaVersion: 1`, `ready: true`, `project: "mejpriaetwgtcstbgfid"`;
- `checkout` absolu, `targetSha` commité et checkout suivi propre;
- `runtimePath`, `runtimeSha256`, `activationManifestPath`;
- `sourceAttestationPath`, `sourceAttestationSha256`;
- `queueHelperSha256` pour le helper ordinaire `facturation-email-queue.ts`;
- `intentPath` absolu, inédit, hors des sources suivies.

La source de l'attestation doit être exactement
`Supabase Management API GET /v1/projects/{project}/functions/send-email/body`.
L'objet `function` conserve `slug: "send-email"`, `id`, `version`,
`status: "ACTIVE"`, `verifyJwt: false`, `ezbrSha256`; `sourcePins` couvre la
fermeture exacte des imports locaux sous `supabase/functions/`.

Le JSON du runtime, trim des extrémités, doit être créé depuis moins de cinq
minutes et disposer d'au moins cinq minutes restantes au démarrage. Les secrets
temporaires sont relus par métadonnées et comparés aux seules valeurs publiques.
Le token Management existant passe en JSON sur stdin (`managementToken`), jamais
dans la commande. Le runner conserve la clé service_role obtenue en mémoire.

Avant chaque message, le runner vérifie le projet, le déploiement, la fenêtre,
les pièces EMISE non payées, les trois reçus et l'absence de cron/requête en
cours. Il prépare une ancre `emails_envoyes` en `ERREUR`, provider NULL, avec
`cree_le` créé par le serveur. Ce n'est pas un email envoyé. La réservation,
l'envoi et l'acquittement utilisent les mécanismes existants.

Chaque email conserve sa clé canonique. Une relecture de l'admission précède
immédiatement Resend. Le message suivant attend le rapprochement du précédent.
Toute réponse ambiguë arrête la recette ; aucune relance automatique, nouvelle
clé ou suppression du fichier d'intention n'est admise. L'ancre conserve une
borne de 20 heures même si la fenêtre temporaire est renouvelée.

## Preuves et clôture

Le rapport conserve trois identités fournisseur distinctes sous empreintes et
les acquittements des files. `PROVIDER_ACCEPTED_AWAITING_INBOX_PROOF` signifie
acceptation Resend, pas réception dans la boîte. Lire ensuite les trois messages
dans la boîte autorisée, relever sujets/numéros/montants et rapprocher les
identités fournisseur. Ouvrir les liens authentifiés dans les deux rôles, puis
les PDF correspondants. Les emails ordinaires d'émission contiennent des liens
vers l'espace authentifié ; ils n'ajoutent pas automatiquement les factures en
pièces jointes.

Retirer `INVOICE_EMAIL_STAGING_TEST_RUN` après la preuve, y compris en cas
d'arrêt, et confirmer son absence. Conserver l'intention et les traces ; les
ancres STAGE apparaissent dans le compteur brut d'emails même en `ERREUR`.
Ne pas présenter les simulations, l'acceptation fournisseur et la réception
réelle comme une seule preuve.

Contrôles ciblés à lancer par root dans la campagne coordonnée :
`tests/node/invoice-email-staging-test.node.mjs` et
`tests/node/invoice-emails-staging-runner.node.mjs`.
