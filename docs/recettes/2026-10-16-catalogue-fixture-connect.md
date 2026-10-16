# Revue du catalogue du témoin Connect sous rollback

Le 16 octobre 2026, les trois empreintes de `REVIEWED_CATALOGUE` sont renouvelées
manuellement pour le staging `mejpriaetwgtcstbgfid`. Le témoin s'exécute avant les
migrations de la PR : son verrou du 2 octobre ne décrivait plus la base déployée.
Cette revue ne change ni le seed, ni les barrières de contexte et de quiescence,
ni le contrat de préparation des acteurs, qui reste fermé (`ready:false`).

## Lectures et rapprochement

Trois requêtes explicites `BEGIN READ ONLY` ont été exécutées via le CLI lié au
seul staging, le 16 octobre à partir de 13:50 UTC. Elles lisent des métadonnées,
empreintes et compteurs ; elles n'appellent aucun métier ni fournisseur.

Le constructeur exact `catalogueSqlFixture()` donne :

| Élément | Empreinte MD5 relue |
| --- | --- |
| routines | `c9d5fa4245eea2bf374c213a2d4544a3` |
| triggers | `62e9482e5965040e763888baa8078bed` |
| columns | `90e5efeb01de258eda706210903145e1` |

Les trois compteurs `queuedRequests`, `activeCrons`, `runningCrons` sont zéro ;
`generationUrlAbsent` et `supportStagingExact` sont vrais. L'empreinte du helper
de commission reste `c736c66d76001b64ba425484f77c6ea2`.

Le catalogue détaillé est comparé à
`audits/2026-10-07-cloture-nationale/catalogue-staging.json` : 1 091 des 1 107
fonctions initiales sont identiques (corps, définition, ACL, propriétaire,
configuration). Les différences sont explicitées :

- les corps de `fn_calculer_montant_periode` et `fn_lister_missions_a_facturer`
  correspondent exactement à la migration versionnée `20261006144619` ;
- le corps de `fn_signer_contrat_otp` correspond exactement à la migration
  versionnée `20261006144554` ;
- `fn_envoyer_otp_signature` et les cinq fonctions nouvelles correspondent au
  supplément SMS installé puis réconcilié du run `38699509552` ;
- douze fonctions conservent leur définition et leurs autres métadonnées, avec
  le seul retrait du droit EXECUTE de PUBLIC ; aucun droit n'est ajouté.

Les 136 définitions et états des triggers de la projection du 7 octobre sont
inchangés. Ses 505 colonnes sont inchangées, hormis la qualification textuelle
de sept defaults `extensions.uuid_generate_v4()` par le search_path de lecture.
Cette projection partielle n'est pas utilisée seule pour accepter le catalogue.

Le snapshot canonique de l'installateur SMS est également relu, sans installer
quoi que ce soit. Ses **huit** routines correspondent à toutes les métadonnées
attendues du contrat versionné. Il donne `closed:true` et `quiet:true`. Les quatre
invariants complets et la cible sont strictement égaux au reçu réconcilié du
15 octobre `sms-sql-only-38699509552-postcommit-readonly.json` :

| Élément | MD5 identique au reçu réconcilié |
| --- | --- |
| structure hors supplément SMS | `d349e5b21984b03eedbfb22e897a85c0` |
| routines hors supplément SMS | `bf4f1bda1997824bdad1bf442e810354` |
| inventaire hors supplément SMS | `40ca9434c5f6074ea2664565c844744a` |
| registre des migrations | `5a8c3b616fa94d919a5c7556bcdb2c6d` |
| cible SMS complète | `4afa782ee97ecdfbc9e28fd3b0255474` |

Le digest des lignes métier a évolué ; il n'est ni accepté comme preuve
d'immutabilité ni épinglé par cette modification. Le témoin doit toujours créer
son propre instantané avant exécution et exiger sa restauration exacte après
rollback. Le run SMS initial reste historiquement en échec ; seule sa relecture
indépendante a réconcilié le commit, sans rejouer son SQL.

## Preuves conservées et limites

Les reçus bruts de ces nouvelles lectures sont conservés dans le dossier local
`audits/2026-10-14-reprise/preflight-fournisseurs/catalogue-fixture-20261016/` :

| Fichier | SHA256 |
| --- | --- |
| `catalogue-detail-readonly.json` | `e196f80d88d1e24df50f39f30897c41359190d33fe38abaa809529c7939e2e89` |
| `sms-snapshot-readonly.json` | `c358824c4cf3bfdcf401cd76c4cd9c5ad853f02cb9f81ad2b7f657785ea5cabb` |
| `catalogue-exact-readonly.json` | `dda41c42b7bc56cc8090d86dd65d0f30fa30b31268df61a772766e88011720cd` |

Ces lectures autorisent uniquement ce renouvellement manuel des trois valeurs
du verrou. Elles ne prouvent pas l'exécution du seed sous rollback avec la PR
actuelle, ni une recette frontend, un SMS reçu ou un paiement Stripe TEST. La CI
doit encore exécuter le témoin. Aucun contrôle n'est ignoré et aucun repin
automatique n'est introduit ; un prochain écart sera à nouveau refusé.

## Addition après installation des cinq migrations et du supplément V2

Cette seconde observation ne remplace pas la preuve de 13:50 UTC ci-dessus.
Les cinq migrations de la PR1063 au commit
`e3fd34005c86cccc903b110ff18c425f45c9a605` ont depuis été appliquées manuellement
sur le staging, puis le supplément fermé Connect TEST V2 a été installé. Les
sources SQL de ces cinq migrations ont déjà passé les bancs PostgreSQL 17 et
la transaction complète des 61 suites sur ce commit. Les autres vérifications
de cette révision ne sont pas pour autant toutes vertes : son ancien contrat
Auth-only expiré est corrigé séparément, sans réécrire sa preuve historique.

La lecture détaillée du catalogue après installation est datée
`2026-10-16T14:14:22.078065+00:00`. Elle donne les nouveaux verrous :

| Élément | MD5 après les cinq migrations et V2 |
| --- | --- |
| routines | `8e51417eabb5ac4376d1bec27aed5a04` |
| triggers | `3d6ef14ab83acb02a8ca0df3bc36231d` |
| columns | `b715fc97721c97f9a788b8cdc45a5e09` |

Le rapprochement avec le catalogue de 13:50 constate 23 fonctions ajoutées,
9 corps modifiés, aucune fonction retirée. Les 32 corps correspondent exactement
aux sources des cinq migrations ou au SQL V2 installé ; les métadonnées des
fonctions préexistantes restent identiques hors corps et définition de ces neuf
fonctions. Les six nouvelles fonctions privées restent exécutables seulement
par leur propriétaire ; les nouvelles RPC publiques sont réservées au service,
à l'exception de `fn_modalites_reglement_commission(uuid)`, également accordée à
`authenticated` conformément à sa vérification interne de l'établissement.
Les propriétaires, configurations et ACL ont été relus. Aucun droit PUBLIC ou
anon n'a été ajouté.

Les seuls autres écarts sont six triggers ajoutés (émission commission,
émission honoraires, onboarding serveur, claim de virement commission, admission
payout et réception des mouvements TEST), et 39 entrées ajoutées dans la
projection des colonnes, qui comprend aussi les colonnes d'index. Aucune entrée
existante de colonne ou de trigger n'est modifiée ou supprimée. Le helper de
commission et les cinq contrôles de quiescence et de routage restent identiques.

Les 79 statements conservés dans `supabase_migrations.schema_migrations` ont
été comparés en ordre, octet pour octet, aux fichiers suivants. Seuls le point-
virgule séparateur et les espaces entre statements sont consommés : aucun corps
de fonction n'est normalisé.

| Version | Statements | SHA256 du fichier appliqué |
| --- | --- | --- |
| `20261016125441` | 8 | `3d3de03113eab292b81f6ae04c7e82cf932f3e6ca6b8c29c816e72ec42512c2c` |
| `20261016125451` | 7 | `ed5f1ae477f221ebd32a5088b769fb533fd4527695e4d3dcc8e0fa009fe255d6` |
| `20261016125516` | 26 | `e53564c6a2107299e25822d91569cbc6f3b4a9f9eefe038deeb8a6611bcba810` |
| `20261016125521` | 18 | `a929e9f09e3265da6e7499497952339c2992d77914bec9599bd69f4531dd4e94` |
| `20261016125632` | 20 | `7ac23bfd7885839c78d106eb3dddf82f29f45eeb287ae7a9d3454e9438880b13` |

Le rendu V2 installé a pour SHA256
`25ef9895a8c7ea2b5032fb6c3b45c46532b1e676bafe7e3638a0bfaa127d12db`,
identique au rendu du banc PG17 vert du même commit. Le reçu d'installation
atteste la conservation des capacités, opérations et fonction de démarrage LIVE,
ainsi que la fermeture des accès. Ces observations ne créent aucune capacité.

Le helper `paiements-staging-installed.mjs` a ensuite effectué une nouvelle
lecture `BEGIN READ ONLY` : toutes les versions de la base
`d9146f3b31ffbe92834f407f6a3f6770360c8bd0` et ces cinq versions seulement sont
présentes. Le retour réel satisfait ses gardes de statements, de catalogue, de
canaux fermés et de capacités révoquées. Son mode `installed` évite uniquement
le bootstrap persistant et le rejeu des cinq migrations déjà appliquées ; les
61 suites restent exécutées sous SAVEPOINT/ROLLBACK et les bancs PG17 conservent
le rejeu des sources. Une relecture indépendante est imposée même après échec
SQL. Une version étrangère, une installation partielle, une source modifiée ou
un écart de catalogue sont refusés. Le contrôle général du bootstrap main reste
inchangé pour les autres cas. Cette exception ne permet ni déploiement ni repair.

Les preuves supplémentaires sont conservées dans le même dossier local :

| Fichier | SHA256 |
| --- | --- |
| `catalogue-apres-cinq-v2-readonly.json` | `670af8ebba9cb7ac189cd80c02b63f684ebcbe4b3b8899d740cbc776ddc951a7` |
| `catalogue-exact-apres-cinq-v2-readonly.json` | `5270d3157f3afc46a133921d81f6af2cdeaa5a01964d87f8216ad8126cfd7b97` |
| `catalogue-apres-cinq-v2-sources.json` | `12271ff573936c8eb36f0522d267daef3f9d36743903dd0e8ce153b6acf130e0` |
| `cinq-migrations-registre-readonly.json` | `a850a6975a6a79c2378ff0332099b2ec45ce20321a5f363744c06d0d803ed57e` |
| `cinq-migrations-comparaison.json` | `8a13bb2dc9407a1de1d01f2e39171c649cdc162fa4bd5008ed8c5979e71d49a6` |
| `reconnaissance-cinq-readonly.json` | `5a872a3584a16da205c4c63e0320e4a143ed91c3cfe1fadb668900c657b2d890` |
| `reconnaissance-cinq-validation.json` | `4addcbf199fed0eb9e9b95b39ad10bd8838f0e4fb749079220f3a113cfb2185a` |
| `reconnaissance-cinq-readonly.sql` | `7b89b5b0752365f49872541da89f3124e19cf3f98317810e596f2ed43098a573` |

Les données métier ne sont toujours pas épinglées comme immuables. Chaque banc
conserve ses instantanés et ses relectures de restauration. Ni cette seconde
reconnaissance ni le repin du témoin seed ne valent recette utilisateur intégrée,
paiement Stripe TEST, versement ou remboursement réellement exécuté.


## Correction additive après relecture indépendante

Le commit `204d352df7998f820f7f3437c5ed4c9476d625d9` ajoute la migration
`20261016144756`, sans modifier les cinq sources déjà installées. Les 61 suites
SQL passent avec ses trois fonctions sous ROLLBACK. La relecture indépendante
après annulation retrouve exactement les 1 135 routines, leurs propriétaires
et droits, les triggers, les colonnes et les compteurs initiaux.

Après le dry-run limité à cette migration, le CLI l'a appliquée au seul staging.
Les sept statements conservés dans le registre correspondent octet pour octet
à la source SHA256 `dc3fe609b61c25d64bdb171e96687b7e83cf3bd0c7bbfa64e13be9cfbcaec202`.
Le total de la PR est donc de six migrations et 86 statements. Seuls les corps
de `fn_connect_payout_constater`, `private.fn_admission_virement_commission` et
`private.mettre_emission_facture_en_file` changent ; les propriétaires et ACL
des 1 135 routines restent identiques. Aucun trigger ou colonne n'est modifié.

Le nouveau verrou routines est `f5a1148c69cd5d79f5447829d218b3b8`. Les verrous
triggers `3d6ef14ab83acb02a8ca0df3bc36231d` et colonnes
`b715fc97721c97f9a788b8cdc45a5e09` restent inchangés. Les trois compteurs sont
zéro ; le routage staging et l'absence d'URL de génération sont confirmés.

Preuves locales conservées dans le sous-dossier `revue-finale` du dossier
`audits/2026-10-14-reprise/preflight-fournisseurs/corrections-paiements-20261016` :

| Lecture | SHA256 |
| --- | --- |
| `jolene-1063-review6-before.private.json` | `72e7a1562ccc9a714f179372e20e47c49c09431ed21efe8f9972738dfb189052` |
| `jolene-1063-review6-after-preview.private.json` | `72e7a1562ccc9a714f179372e20e47c49c09431ed21efe8f9972738dfb189052` |
| `jolene-1063-review6-installed.private.json` | `69590b9d5bb6649893012b3c0b44086d9e3ae7941ecad9cdd5b99cf8eac40e89` |
| `jolene-1063-review6-61-preview.private.json` | `d82801be2657ca0963219cb91598b59ce6f5170199737c0acc28f138fb704608` |

Cette preuve de déploiement SQL ne remplace ni les simulations frontend finales
ni le parcours de paiement chez le fournisseur TEST. Aucun contrôle n'est
désactivé : les 61 suites et la comparaison exacte des six sources restent exigées.


## Complément salarié distinct après paiement carte de l’initiale

La revue indépendante de `2b81fa7` a identifié un cas où le claim de mission
de l’initiale salariée payée empêchait le virement d’une facture complémentaire.
Le commit `be0673dbe5533d2b4dc63b687fdb6f8a1f7f34ec` ajoute la seule migration
`20261016151740`, SHA256 `b82d79b009e09a3079d1126e9003e88b4548f33b4734699d435dcadf6cbc2efe`.
L’exception exige l’initiale canonique PAYEE du même établissement, son flux
CHECKOUT_INVOICE, ses claims FACTURE/MISSION et leurs références cohérentes.
Tout claim sur le complément lui-même demeure bloquant. Aucune ancienne pièce
ou claim n’est réécrit.

Les 61 suites SQL passent sous ROLLBACK avec ce seul corps supplémentaire.
La relecture après annulation est identique à la lecture précédente. Le dry-run
CLI ne proposait que cette migration ; après application au staging, les quatre
statements du registre correspondent exactement à la source. Les sept migrations
de la PR représentent désormais 90 statements, tous relus par le contrôle
`checkInstallation` en mode installé. Seul le corps de
`private.fn_admission_virement_commission(uuid)` change parmi les 1 135 routines ;
les propriétaires, ACL, triggers et colonnes restent identiques.

Le verrou routines devient `487105aa42c50a5127ad408d5b62a249`. Les canaux
restent fermés (aucun cron ni requête réseau en file), gate général Connect fermé
et capacités TEST révoquées. Preuves dans le même sous-dossier `revue-finale` :

| Lecture | SHA256 |
| --- | --- |
| `jolene-1063-review7-before.private.json` | `63eb58c0ecfb8cc360a76a7e5865e88f57251ceffb3a0b939d32b526f996a858` |
| `jolene-1063-review7-after-preview.private.json` | `63eb58c0ecfb8cc360a76a7e5865e88f57251ceffb3a0b939d32b526f996a858` |
| `jolene-1063-review7-installed.private.json` | `e3e0371c423cf64ccd151d62f1f1e66a5f805f7cc6e91127c1fd9da8c3a4851f` |
| `jolene-1063-review7-61-preview.private.json` | `eec1f731c58fbd74df67d798dee1c736f115cacf91e40fd522fe62508171b135` |
| `jolene-1063-review7-all-installed.private.json` | `dad33e8c925ca70456f0dfbe701aeb22fadbe3ea11e7ca30f65f9615d4d4a7a1` |

Cette relecture du staging n’atteste ni paiement Stripe, ni virement bancaire,
ni validation complète du parcours. Le témoin PG17 couvre séparément les claims
et la simulation frontend couvre la déclaration du complément avec réponses
simulées. Leurs résultats doivent être vérifiés sur le candidat final.
