# Qualification PG17 de la réutilisation des acteurs TEST

Branche temporaire sans PR : `ci/qualification-pg17-refund-20261004`, produit exact `01b135471e1e6ee7ee31439ffc248c8b8519260c`. Ce banc reprend les fichiers de préparation de `97afce0a0640df93862572e811cd1c8f06eaf2be` et conserve ses protections. Il ne doit pas être fusionné tel quel. Aucun SQL staging, fournisseur, frontend ou livraison n'est exécuté par ce job.

Le seul témoin est `tests/security/refund-reuse-fixture-pg17.test.sql`, SHA256 `9de82691b08f94f4d2bc1581f11aca6e634aa043c479875cc562afbe2aa4e4fb`. Il est nouveau sur la branche CI : le driver lit ce chemin exact dans le checkout et vérifie son hash constant. Les migrations restent toutes lues depuis PRODUCT_SHA et comparées octet par octet au checkout. Aucun changement de migration, helper factice ou trigger désactivé. Un échec interrompt le job, sans retry ni saut de fichier.

## Portée du témoin

Une seule transaction globale BEGIN/ROLLBACK crée N et A entièrement synthétiques dans le vrai schéma Auth/Storage/applicatif. Le seed Connect initial est inclus sans modification, avec mandat fictif et TVA par les RPC canoniques. Les liens Stripe `PG17SyntheticN`, la readiness déclarée et l'histoire financière fermée/révoquée sont des fixtures SQL locales, pas des observations fournisseur. Le registre documentaire contient des chemins `no-file` et aucun faux hash PDF/XML. Les empreintes d'évidence obligatoires sont explicitement celles de déclarations `PG17_SYNTHETIC_ONLY`, jamais des preuves externes ou autorisations de staging.

Le DO exact du préparateur est exécuté dans quatre sous-transactions : positif (nouvelle mission, 3 créneaux, TVA confirmée par A puis S, A désactivé), puis refus d'une N non révoquée, d'un mauvais propriétaire A et d'un chevauchement. Les codes doivent correspondre exactement. Chaque sous-transaction est annulée et la restauration vérifiée. Les dates techniques S/suivi sont vieillies avant le positif : leur mise à jour canonique est attendue, tous les autres champs métier sont comparés, puis leurs anciennes dates sont restaurées par rollback.

Le test ne qualifie ni génération PDF, ni KYC, ni Auth API, ni paiement/refund Stripe, ni deux rôles et cinq formats frontend. Une réponse fournisseur perdue et sa duplication éventuelle restent à traiter dans la recette intégrée distincte.

## Isolation inchangée

Les images/digests, neuf extensions, réseau interne sans port publié, deux DB et arrêt des huit services applicatifs sont conservés. Les accès SQL utilisent seulement le socket local de la DB source nommée, PG17, postgres, workers0 et crons arrêtés. Les seuls secrets sont ceux aléatoires du bootstrap local ; aucun secret GitHub métier. Le témoin place uniquement une URL publique dans Vault, sans credential, et l'annule.

Les réconciliations natives précédemment qualifiées (propriétaire de la DB locale, ACL par défaut attendues et nettoyage de l'unique clé locale historique issue du replay) gardent leurs préconditions exactes. Les sondes d'inventaire et les migrations inchangées restent bloquantes. Les 14 compteurs de quiescence sont exigés à zéro avant/après le témoin. Une erreur SQL conserve seulement SQLSTATE, ligne et code borné CAND_MULTI/REUSE/WITNESS ou catégorie historique, jamais le message libre.

Le workflow existant est manuel, contents:read, sans secrets ni appel à d'autres workflows. Vercel est désactivé uniquement pour cette branche et la comparaison intégrale de sa configuration refuse tout autre delta. Ne pas ouvrir de PR de cette branche. Après revue du commit, le parent peut lancer `restore-local-bootstrap.yml` sur cette référence exacte. Aucun push ni dispatch n'est effectué dans cette préparation.

Diagnostics filtrés, double nettoyage et vérification indépendante de l'absence restent en always(). L'artefact ne contient ni compose privé, clé, JWT, SQL brut ni dump. Les noms historiques `canonical_test_sha256` et `canonical_test_passed` du rapport désignent maintenant ce témoin explicitement marqué `test_kind=PINNED_LOCAL_SYNTHETIC` ; ils n'affirment pas sa présence dans PRODUCT_SHA. Aucun PASS PG17 n'est acquis avant exécution.
