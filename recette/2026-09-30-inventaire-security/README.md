# Inventaire explicite — 30 septembre 2026

Base : main `58fda7df712cbc5637e41a9dc06a639288a05554`.

Cette migration change uniquement onze lignes de `private.security_definer_inventory` : neuf empreintes périmées et deux entrées absentes. Elle ne remplace aucune fonction, ne change aucune ACL et ne recapture pas le catalogue. Les onze corps LIVE ont été comparés octet par octet aux migrations indiquées dans `sources.json`, avec vérification indépendante de MD5, propriétaire, SECURITY DEFINER, search_path et EXECUTE. Les lectures LIVE sont limitées aux catalogues et aux définitions ; aucune RPC métier ni donnée utilisateur n'a été appelée/lue.

Gardes relues : identité et administrateur valide avant lecture pour les deux RPC admin ; destinataire actif et propriétaire des filtres pour les alertes ; compte actif et établissement canonique pour la recherche professionnelle ; accès anonyme volontaire avec projection limitée pour la recherche publique ; identité propre et preuve privée pour les quatre suppressions/reprises. Les helpers d'identité, d'administration, de tenant et de preuve ont été relus dans LIVE. Le classement ne certifie pas tous les traitements métier, les délais légaux ou l'effacement physique Storage.

Deux fonctions sont volontairement exclues :

- `fn_terminer_mission` : garde tenant NULL défaillante, correction distincte.
- `fn_admin_resoudre_litige_intelligent` : malgré une provenance expliquée, la lecture du type de litige précède la garde admin. Pour AUCUNE, les erreurs différentes des deux résolveurs divulguent si un UUID correspond à un litige salarié. Défaut établi par lecture du code/ACL, sans appel LIVE ; correction distincte demandée.

La migration refuse les écarts de corps, propriétaire, search_path, SECURITY DEFINER, droits PUBLIC/anon/authenticated/service_role ou inventaire précédent. Les valeurs écrites sont littérales. Tous les contrôles précèdent la première écriture ; le bloc est atomique.

Validation locale : 14 tests Node réussis ; parsing complet SQL et PL/pgSQL des deux fichiers par pglast 7.10 réussi. La suite SQL, raccordée à `validate-pr`, rejoue le bloc exact, vérifie les onze entrées, altère successivement chaque empreinte d'inventaire dans une sous-transaction et exige un refus, puis contrôle que les autres entrées et les fonctions/ACL n'ont pas changé. Le rejeu copié est comparé à la migration par le test Node pour empêcher leur divergence.

Exécution SQL réelle en staging encore à faire par CI, dans sa transaction finale ROLLBACK. Aucun DDL distant exécuté depuis cet audit. Pas de nouvelle simulation frontend pour ce lot de métadonnées sans changement visible. Le correctif du résolveur aura sa propre simulation.

Commandes locales : `node --test tests/node/security-definer-inventory.node.mjs` ; parser les deux fichiers avec `pglast.parse_sql` et `pglast.parse_plpgsql`. La liste `SQL_TESTS` de `validate-pr.yml` inclut `tests/security/security-definer-inventory-explicit.test.sql`.
