# Profil soignant : lecture indisponible et reprise

Le formulaire ne se monte plus à partir d’une réponse vide, étrangère ou invalide.
Une erreur RPC, un rejet ou une lecture dépassant 10 secondes laisse un état
explicite avec « Réessayer ». Chaque tentative possède son AbortController ;
expiration, remplacement de tentative et démontage invalident les réponses tardives.
Les lectures annexes du profil suivent la même durée de vie. Aucun retry automatique.

Le validateur contrôle l’ID Auth, les quatre clés historiques prénom/nom/email/
profession, les types des champs consommés et les spécialités JSON. Les valeurs
nulles, chaînes vides et colonnes optionnelles absentes restent admises. Une
consultation invalide ne déclenche pas l’audit de consultation du profil.

Les onglets restent accessibles pendant la lecture. Confidentialité utilise
uniquement `useAuth().user.id`, sous les protections de route existantes, et peut
ouvrir puis annuler la confirmation de suppression sans attendre les données du
profil. Ni RouteProtegee ni SectionConfidentialite ni leurs RPC/Edge ne changent.
Les formulaires principal/préférences sont masqués jusqu’à une réponse valide.

## Cause établie et limite du diagnostic CI

Le run connecté 36847134987 montre un spinner au bout de 10 s dans la suppression
annulée. La seule trace conservée est celle du retry réussi (RPC profil 200 en
508 ms). Elle n’établit donc pas la cause du premier blocage, ni une panne réseau.
Les preuves initiales restent dans `/private/tmp/jolene-1009-suppression-flake`.

Le témoin local utilise le build UI 6bc862cc : son blob ProfilSoignant est identique
à celui de la base 3be123c0 (`1e8dada11d638f52f3551dcb8fbac9181034e181`).
L’enveloppe `{error:'Indisponible'}` ouvre l’ancien formulaire vide sans état erreur.
Les deux iPads ont reproduit ce rouge ; la campagne a ensuite été interrompue pour
la pause disque. Ces résultats ne sont pas présentés comme cinq rouges complets.
La lecture du code établit aussi l’absence de catch/finally sur le RPC principal
et le parsing non protégé des spécialités. La correction couvre ces défaillances,
sans prétendre identifier la cause précise de la CI ni augmenter son timeout.

## Validation locale

- 23 tests unitaires : erreurs RPC et rejets, données invalides/étrangères,
  spécialités historiques, délai, retry, réponse périmée, changement d’acteur,
  démontage et absence de session.
- Typecheck application et E2E ciblé, compilation web avec URL/API fictives.
- 15 parcours compilés, trois pannes × iPhone, Android, iPad portrait/paysage et
  ordinateur : ouverture Confidentialité, confirmation activée puis vrai clic
  Annuler, absence de suppression, état erreur, retry réussi et reload.
- Chaque parcours vérifie trois lectures profil, zéro appel delete-account,
  zéro écriture de profil, zéro requête inconnue/externe et zéro erreur JS/console.
  Le délai est avancé par l’horloge Playwright ; la réponse ancienne est libérée
  après le retry pour vérifier qu’elle ne remplace pas le profil courant.
- 30 captures ciblées, sans trace vidéo ou archive lourde ; pas de CSS masqué.

Réponses Auth/REST simulées et WebSockets fermés. Aucun compte distant, SQL,
paiement, suppression effective, notification Realtime ou appareil physique testé.
La cause CI restera à confronter à une future trace du premier échec si elle récidive.

Les preuves, résultats JSON, sources et empreintes du build sont conservés dans
`/private/tmp/jolene-profil-soignant-preuves-20261001`. Les erreurs de préparation
(ResizeObserver de jsdom absent, compatibilité ES2020 de hasOwn) et la pause disque
sont archivées séparément des succès finaux. Le seuil de 5 Gio a été contrôlé avant
chaque nouvelle compilation/campagne ; les vérifications ont été séquentielles.

Résultat final SHA256 : `9d9ed23dc324868526330038d5e3ba40ed5c147b198f95e00130afa3892d6ad8`.

Complément après revue : le message final est « Ton profil n’a pas pu être chargé.
Tu peux réessayer. ». Il ne nie pas un éventuel enregistrement déjà réussi avant
un refresh en échec. Seule cette phrase produit a changé après la matrice 15/15.
Typecheck et build sont repassés ; le parcours erreur iPhone est rejoué 1/1
(Annuler, retry, reload), avec nouvelle capture. Les 30 captures précédentes sont
conservées et montrent la version longue, distincte de cette capture finale.
