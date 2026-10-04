# Références canoniques Apple — lecteur GET, sans mutation

Le workflow manuel existant `mobile-store-status.yml` reçoit l’option booléenne
`apple_canonical_reference` (défaut false). Le mode ordinaire reste identique.
Le mode Apple ne charge pas les credentials Google et n’appelle aucun script de
confinement, soumission, livraison, compte ou paiement.

Avant tout token/API : tests sans credentials, certificat public conforme à son
SHA256 DER et valide encore vingt minutes, OpenSSL 3, dépôt `Gabpcd/JJJJJ`, événement
`workflow_dispatch`, ref `refs/heads/main`, égalité SHA40 entre `GITHUB_SHA`, HEAD
et `refs/remotes/origin/main`. Une avance de main entre le dispatch et le checkout
provoque un refus ; ne pas contourner par une autre ref. Les secrets restent ceux
déjà configurés : ASC_KEY_ID, ASC_ISSUER_ID, ASC_PRIVATE_KEY_BASE64.

Le lecteur résout uniquement `app.jolene`, parcourt les versions de toutes
plateformes et états sans filtre, puis leur `appStoreReviewDetail` et le
`betaAppReviewDetail` de TestFlight. Trois attributs seulement :
`demoAccountName,demoAccountRequired,notes`. Les pièces jointes ne sont jamais
téléchargées : seul `fileSize` sert à constater leur présence. Aucun mot de passe,
contact, corps de pièce jointe, URL de téléchargement ou autre application n’est
demandé. Les URLs retournées ne sont pas suivies librement.

Chaque collection suit au plus vingt pages ; seul un curseur sur le même chemin
et les mêmes paramètres est accepté. Toute boucle, duplication, différence de
total déclaré, page manquante détectable, type inattendu, ressource absente,
403/404/429/redirect ou limite atteinte rend la lecture indisponible. La borne
globale est 250 requêtes/300 secondes, sans retry. La liste des versions est relue
à la fin et doit rester identique. Ce n’est pas un snapshot transactionnel : les
notes/comptes peuvent encore changer entre lectures. L’inventaire doit rester
récent et aucune édition stores concurrente ne doit être ignorée.

Les noms sont retenus comme références seulement s’ils sont une adresse email
entière ou un UUID ; ils sont normalisés en minuscules, dédupliqués, bornés à 100.
Un nom opaque, un compte requis absent, toute note non vide ou pièce jointe garde
`appleComplete=false`. Une note n’est jamais interprétée par une extraction regex
pour proclamer la complétude. TestFlight est contrôlé séparément ; ses détails
n’ont pas de relation de pièces jointes dans le schéma Apple documenté.

## Confidentialité et résultat

`apple-review-public.json` contient seulement le SHA du code, des compteurs,
booléens, codes constants, la date et le SHA de l’enveloppe chiffrée. Aucun nom,
hash de nom devinable, note, titre, URL, corps de réponse, token ni stderr fournisseur.
Le CLI neutralise stdout/stderr des bibliothèques ; une erreur fatale n’émet
qu’un diagnostic constant. Les appels OpenSSL reçoivent un environnement fermé,
sans variable ASC, et leur stdout/stderr ne sont jamais publiés.

En cas de refus, le champ optionnel `diagnostic` contient exactement trois valeurs
issues de listes fermées : `endpoint`, `check`, `observed`. Elles identifient l’une
des cinq lectures, le contrôle déjà existant et un type/constat (`null`, `missing`,
`extra_keys`, `missing_keys`, `mismatch`, etc.). Aucun nom de champ inattendu, ID,
valeur d’attribut, URL ou message fournisseur n’y figure. La liste est vérifiée à
la création de l’erreur puis de nouveau avant écriture du reçu. Une coordonnée
inconnue supprime le diagnostic entier ; elle ne modifie jamais le refus.
`response_invalid` reste le motif des réponses de structure invalide ; les autres
motifs et les conditions d’acceptation restent inchangés. Une erreur JSON garde
notamment `read_failed`, avec le seul constat fermé `json/malformed`.

Le premier run réel `37234417053` a seulement produit `response_invalid`, sans
enveloppe CMS. Ce reçu ne permet pas de connaître sa cause. Ces diagnostics doivent
être relus après une nouvelle exécution autorisée du lecteur ; aucune hypothèse
sur le contenu Apple ne justifie d’assouplir les gardes de champs, de pagination
ou de périmètre.

Le JSON privé sélectionné (références exactes et notes pour revue) reste en mémoire
jusqu’au chiffrement. Les notes sont traitées comme potentiellement sensibles,
même si les attributs mot de passe/contact ne sont jamais demandés.
`apple-review-reference.cms` est une enveloppe CMS **AuthEnvelopedData**, chiffrée
par OpenSSL AES-256-GCM, clé transportée par RSA-OAEP/SHA256 et MGF1/SHA256.
Il n’existe aucune solution de repli en clair/CBC. Le certificat X.509 public et
son empreinte DER sont épinglés dans `apple-review-recipient.json`, jamais dans un
input dispatch. Aucune clé privée de transport n’est présente sur le runner.

Seuls le reçu fermé et l’enveloppe CMS peuvent être uploadés, avec rétention d’un
jour. Le répertoire de sortie est nouveau/0700, fichiers0600. La durée limitée ne
remplace pas le chiffrement : le dépôt public rend ses artefacts accessibles aux
personnes disposant de l’accès GitHub correspondant. Le certificat ne protège pas
contre la compromission du runner ou de la clé privée locale.

Le chiffrement standard assure la confidentialité et l’intégrité de l’enveloppe ;
il ne constitue pas une signature du fournisseur. L’origine est liée au run CI,
au SHA main relu et au reçu contenant le SHA de l’enveloppe. Après téléchargement
ciblé, vérifier ce SHA avant déchiffrement local. N’accepter le résultat qu’après
exit0 d’OpenSSL : une erreur d’authentification peut laisser des octets partiels
dans la sortie privée, qui ne doivent jamais être importés ni affichés.

`appleComplete=true` n’est **jamais** une autorisation de confinement :
`confinementReady=false` et `googleChecked=false` restent constants. Après lecture
privée des références, il faut encore la preuve canonique Google, la revue des
notes/pièces éventuelles, les métadonnées GitHub récentes, et le rapprochement de
l’ensemble exact avec les 1088 UUID/emails conservés. Ce lecteur ne fabrique pas
`COHORT_REVIEW_REFERENCE_JSON` ; son `source` distinct est refusé par le mutateur.

## Vérification préalable

```sh
bundle exec ruby scripts/mobile/store-status.test.rb
bundle exec ruby scripts/mobile/apple-review-reference.test.rb
bundle exec ruby scripts/mobile/apple-review-reference.cms.test.rb
```

Les deux premières suites utilisent uniquement des fixtures. La troisième crée
une clé synthétique jetable, vérifie un vrai roundtrip CMS, un tag GCM altéré, une
mauvaise empreinte et un second certificat. Aucun fournisseur/compte n’est utilisé.
Sur le Mac déjà équipé, le dernier script accepte l’unique argument
`/opt/homebrew/bin/openssl` ; le CLI de collecte utilise `/usr/bin/openssl` sur CI.
La qualification réelle de cette version OpenSSL runner reste requise avant API.

## Sources officielles consultées le 4 octobre 2026

- [Versions de toutes plateformes](https://developer.apple.com/documentation/appstoreconnectapi/get-v1-apps-_id_-appstoreversions).
- [Détails App Review d’une version](https://developer.apple.com/documentation/appstoreconnectapi/get-v1-appstoreversions-_id_-appstorereviewdetail).
- [Détails TestFlight](https://developer.apple.com/documentation/appstoreconnectapi/get-v1-apps-_id_-betaappreviewdetail).
- [Pièces jointes App Review](https://developer.apple.com/documentation/appstoreconnectapi/get-v1-appstorereviewdetails-_id_-appstorereviewattachments).
- [Nature des pièces jointes](https://developer.apple.com/documentation/appstoreconnectapi/appstorereviewattachment) : elles peuvent contenir des instructions ou identifiants.
- [Curseurs et portée de token](https://developer.apple.com/documentation/appstoreconnectapi/generating-tokens-for-api-requests).
- [CMS OpenSSL 3.0](https://docs.openssl.org/3.0/man1/openssl-cms/) et [3.5](https://docs.openssl.org/3.5/man1/openssl-cms/) : AES-GCM et paramètres RSA-OAEP documentés.
