# Recherches sauvegardées et alertes — 25 septembre 2026

## État de livraison

Correctifs implémentés et vérifiés localement. **La validation SQL sur le staging complet, la CI de la PR et le déploiement restent nécessaires : ce document ne déclare pas la production corrigée.** Aucun email utilisateur réel ni donnée persistante en production n’a été créé par cette recette.

## Source de vérité examinée avant modification

Lecture seule sur `flripxtsyegjshnhzjkz` : définitions LIVE de `fn_evaluer_alertes_filtres`, `fn_compter_nouveaux_pour_filtre`, `fn_obtenir_apercu_filtre`, `fn_rechercher_soignants_etab`, RPC de sauvegarde, résolveur d’établissement, cohortes, exclusions, colonnes/contraintes/indexes, ACL/RLS et code déployé de `email-cron` et `send-email`. Un comptage agrégé des recherches existantes, sans lire leurs valeurs personnelles, a trouvé une seule alerte soignant active avec les clés historiques valides `profession` et `rayonKm`, et aucune recherche ETAB. Les valeurs par défaut conservent ce format ancien.

Les anciens compteur et aperçu ETAB ne traitaient que la profession et imposaient des documents valides. Ils ignoraient neuf choix du formulaire ainsi que plusieurs règles d’exclusion. Côté soignant, profession/taux/urgence étaient pris en compte mais ville, rayon, contrat et horaires étaient ignorés. L’ancien worker construisait l’aperçu depuis 1970 et avançait le watermark avant l’envoi : un échec transport pouvait perdre définitivement le lot. L’interface annonçait aussi 8 h Paris et lundi matin, que le cron ne garantissait pas.

## Comportement corrigé

- **Annuaire et alertes établissement** : même source privée pour profession, type d’exercice, ville, distance, note, score, expérience, disponibilité urgente, documents, recherche libre. Les spécialités du RPC annuaire existant restent prises en charge. Profils supprimés, suspendus ou bannis exclus ; destinataire actif et rattachement courant requis. Le demandeur de l’annuaire doit lui aussi avoir un compte actif. Aucun nouveau droit aux profils n’est accordé.
- **Alertes soignant** : sept clés réellement enregistrées par Explorer — `profession`, `rayonKm`, `tauxMin`, `typeContrat`, `urgentesOnly`, `horaire`, `villeRecherche`. Ville ou préfixe postal, arrondi de distance à 0,1 km, préférences de contrat et hiérarchie IADE/IBODE → IDE reproduits. Missions ouvertes/futures seulement, cohortes et exclusions respectées, établissement non supprimé avec compte actif. Il n’existe pas de filtre de date enregistré dans ce formulaire.
- **Compte soignant minimal** : après inscription sans ligne `soignants`, les alertes se limitent au périmètre public déjà autorisé par Explorer : mission publiquement visible, non assignée et hors comptes de test. Le helper global de cohorte et les droits des profils complets ne sont pas élargis. Une simple sauvegarde sans parcours soignant ne suffit pas.
- **Horaires** : vrais créneaux prévisionnels hors pauses, repli ponctuel seulement, rejet du planning incomplet, nuit 20 h–7 h et week-end en heure de Paris. Le changement d’heure est couvert.
- **Alerte rapide soignant** : conserve les sept critères affichés. Ne réactive une sauvegarde existante que si tous ses critères sont identiques ; un simple nom identique ne suffit plus. Une panne de lecture ou d’écriture reste une erreur avec nouvel essai.
- **Fenêtre et envoi** : un lot immutable est enregistré dans `email_queue` dans la même transaction que le watermark, avec aperçu issu de `(dernier_check_le, maintenant]`. Le filtre est verrouillé par `FOR UPDATE SKIP LOCKED`. Le retour de l’ancien RPC reste compatible et vide, pour éviter un deuxième envoi par l’ancienne boucle.
- **Reprise** : même ID de file et même contenu, donc même identité idempotente au transport. Un état `pending` reste en attente. Une panne d’envoi est reprise après 1 h, 2 h, 4 h, etc., jusqu’à un délai de 24 h entre tentatives ; aucune limite silencieuse de tentatives. Une panne de marquage après envoi conserve le lot pour acquittement idempotent. Les erreurs restent dans les compteurs de supervision du cron.
- **Statut fidèle au transport** : un acquittement `idempotency_already_sent` confirme la livraison antérieure. Les refus de préférence et les garde-fous de comptes de test donnent `ANNULE`, avec `envoye: false`, jamais un faux succès.
- **Préférences email ETAB** : les clés historique et actuelle sont lues ensemble ; un refus dans l’une suffit à couper l’envoi. L’interface est alignée par le lot notifications pour refléter ce refus et synchroniser les deux clés lors d’un nouveau choix explicite ; ce complément a passé 11 tests unitaires et 20 simulations navigateur dans son lot distinct. Aucun consentement historique n’est effacé.
- **Revalidation avant transport** : une recherche désactivée/modifiée, un destinataire devenu invalide ou un élément de l’aperçu devenu inaccessible annule le lot ; une panne de validation n’est pas assimilée à une annulation. Les autres types de messages de `email_queue` conservent leur traitement.
- **Ordre des déploiements** : l’interface ETAB n’active les alertes que si `fn_capacite_alertes_recherches` confirme le compte/rattachement et un passage du nouveau worker depuis moins de trois heures. Une RPC absente ou en panne laisse la sauvegarde sans alerte disponible, avec « Vérifier à nouveau ». Les anciennes alertes sont conservées et peuvent être désactivées.
- **Cadence affichée** : traitement horaire, au moins 24 h entre vérifications quotidiennes, au moins sept jours entre vérifications hebdomadaires. Aucun horaire précis ni délai maximal de livraison n’est promis.

## Preuves reproductibles

Migration : `supabase/migrations/20260925093121_alertes_recherches_etablissement_exactes.sql`.
Suite SQL : `tests/security/alertes-recherches-etablissement.test.sql`, ajoutée à `SQL_TESTS` dans `validate-pr.yml`.

Toutes les identités SQL sont synthétiques (`example.invalid`, UUID réservés au scénario), dans une transaction annulée ; aucun transport Edge n’est appelé. Les assertions couvrent les dix critères ETAB séparés/ensemble, les sept soignant, inconnues/malformations, booléens décochés, masquage des évaluations insuffisantes, cohortes, comptes bannis/supprimés/suspendus, membre détaché et propriétaire historique, limites exactes, aperçu, cadence, déduplication, métadonnées de file, reprise avec payload inchangé et ACL privées. Les contraintes LIVE connues, notamment l’ordre unique des créneaux, sont respectées.

La connexion MCP du staging canonique `mejpriaetwgtcstbgfid` est en lecture seule : la compilation transactionnelle initiale a été refusée (`25006`) sans appliquer de définition. La CI existante utilisera l’exécuteur transactionnel Management API pour valider ce schéma complet. La branche historique de juillet n’a pas été modifiée.

### Vérifications locales exécutées

- PostgreSQL embarqué PGlite 0.5.8, sous `/private/tmp/jolene-alertes-sql-local` : migration et suite SQL du dépôt exécutées sans modification, compilation et assertions vertes. Fonctions LIVE de périmètre/cohorte et de mission publique utilisées, y compris l’inscription minimale. **Schéma de diagnostic partiel et quelques dépendances substituées : ce résultat ne prouve pas les triggers/RLS du staging complet.**
- Vitest initial : **38/38** dans sept fichiers (capacité, sauvegarde, gestion centrale, alerte rapide, transport, garde du déploiement cron), puis **11/11** dans les deux suites UI enrichies contre les erreurs de lecture. Logs : `/private/tmp/jolene-alertes-vitest-20260925.log` et `/private/tmp/jolene-alertes-erreurs-vitest-20260925.log`. Les deux lots se recouvrent et ne doivent pas être additionnés.
- Après revue : **60/60** dans cinq fichiers — transport de file (12), compatibilité des préférences (6), garde cron (10), sécurité Edge (16), isolation des comptes de test (16). Log : `/private/tmp/jolene-alertes-review-vitest-20260925.log`. Ce lot inclut les refus de préférence/test, l’acquittement idempotent et les erreurs de vérification.
- TypeScript global `tsc -b` vert, log `/private/tmp/jolene-alertes-typecheck-20260925.log` ; ESLint du lot sans erreur ni avertissement.
- Playwright final sur build statique local `8902`, **10/10**, dans `e2e/recette-complete-alertes-nationales.spec.ts`. Deux scénarios sur iPad portrait 820×1180, iPad paysage 1180×820, iPhone 390×844, Android Pixel et ordinateur 1440×900. APIs strictement simulées, appels inconnus signalés, WebSockets et réseau externe bloqués. Log `/private/tmp/jolene-alertes-final-e2e-20260925.log`, JSON `/private/tmp/jolene-alertes-final-e2e-20260925/results.json`.
- Le scénario ETAB vérifie connexion, erreur 503 de liste distincte d’une liste vide, nouvel essai, dix critères et payload exact, fréquence horaire, 503 d’enregistrement sans faux succès ni perte de saisie, création, gestion centrale avec panne/reprise, désactivation/réactivation, fréquence hebdomadaire, et capacité indisponible puis rétablie.
- Le scénario soignant applique réellement les sept critères d’une recherche via l’interface ; il vérifie les choix nuit/urgence visibles, un 503 de lecture empêchant toute création, le nouvel essai avec les sept critères exacts et l’absence de doublon à la répétition.
- Après inspection visuelle de la capture iPhone, la dernière phrase suggérant un email immédiat a été remplacée par la vérification horaire. La confirmation et le dialogue annonçaient déjà cette cadence. Le même scénario soignant a été rejoué après reconstruction : **5/5** sur les cinq formats, sans nouvelle tentative. Log `/private/tmp/jolene-alertes-cadence-finale-e2e-20260925.log`, résumé `assets/2026-09-25-alertes/resultats-cadence-finale.json`. Il s’agit des cinq scénarios déjà comptés dans les dix, et non de cinq parcours supplémentaires.
- Les captures et instantanés ARIA des cinq formats sont conservés dans les répertoires de résultats. Les pièces représentatives et le résumé compact sont copiés dans `docs/recettes/assets/2026-09-25-alertes/`. Ces simulations de sauvegarde ne valident pas un véritable email délivré.

La relecture indépendante des trois correctifs finaux (compte minimal, statut réel du transport, compatibilité des préférences) a fermé les trois constats sans nouveau défaut bloquant démontré. Cette revue ne remplace pas la validation SQL complète en CI.

## Limites à conserver dans le bilan

1. La nouveauté est la **création** du profil ou de la mission. Modifier un ancien profil ou rouvrir une ancienne mission ne le transforme pas en nouveau résultat ; cette sémantique n’est pas changée.
2. Comme dans l’interface, une distance impossible à calculer ne suffit pas à exclure le résultat. Le rayon ne garantit donc pas que tous les résultats sans coordonnées sont proches.
3. Notes et scores ne deviennent filtrables/affichables qu’après leurs seuils existants de trois évaluations/missions. Les règles métier de candidature/publication et leurs permissions restent distinctes des alertes.
4. Les horaires quotidiens/hebdomadaires sont relatifs au dernier contrôle, pas fixés à 8 h ou au lundi. L’indisponibilité du cron, un débit de file limité ou une panne transport peuvent retarder un email.
5. Le contenu est un instantané de la fenêtre évaluée. Si la recherche ou un résultat affiché devient invalide avant l’envoi, le lot est annulé ; aucun contenu élargi ni nouvelle recherche implicite n’est envoyé à sa place.
6. La simulation et les transactions annulées ne prouvent pas la délivrabilité du fournisseur email ni l’état post-déploiement. Aucun envoi réel n’a été utilisé pour cette recette.
