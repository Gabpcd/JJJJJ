# Actions soignant — fiabilité après interruption (25 septembre 2026)

## Résultat et périmètre

**15 cas uniques passent sur cinq formats**, sans reprise automatique Playwright : iPad portrait 820 × 1180, iPad paysage 1180 × 820, iPhone 390 × 844 (WebKit), Android 412 × 839 et ordinateur 1440 × 900 (Chromium). Après le dernier correctif de continuité du pointage, les **5 cas pointage affectés ont de nouveau passé**. Après raccord des erreurs RPC de signature au mapping français, les 5 nouveaux cas OTP et les 5 cas OTP existants (session, code incorrect/expiré, reprise) ont également repassé. Ce complément ne remplace pas les 430 cas de la recette précédente.

Le frontend a été compilé et servi sur `http://127.0.0.1:8900`. Authentification, RPC, documents et données sont simulés. Les requêtes externes et WebSocket sont bloquées. Aucun SMS, contrat, pointage, candidature ni paiement réel n’a été créé.

## Corrections démontrées

- **Consentement de signature isolé par contrat et empreinte du document.** Le code reçu et la case cochée du précédent document ne sont plus conservés lors d’un changement de contrat ou de version.
- **Réponse OTP tardive ignorée après sortie de l’écran.** Le SMS déjà demandé au serveur n’est pas annulé ; sa réponse ne fait plus progresser l’ancien écran ni apparaître une notification sur la mission suivante.
- **Refus bloquant réellement bloquant.** Après `HASH_DOCUMENT_CHANGE`, les actions de signature et de renvoi sont désactivées jusqu’au rechargement du document. Les doubles clics pendant une requête produisent une seule demande.
- **Lecture d’un contrat protégé contre les réponses obsolètes.** Une réponse lente du contrat A ne peut plus écraser le contrat B déjà affiché. Les champs de consentement et de signature sont réinitialisés à la navigation.
- **Pointage verrouillé jusqu’à la relecture de l’état serveur.** Un second code ne peut plus être envoyé pendant que le premier scan réussi est suivi d’une relecture lente. Les erreurs libèrent correctement l’action. Après sortie/changement de mission, une réponse tardive ne déclenche plus de notification, vibration ou proposition de notation dans le nouvel écran.
- **Erreurs de session et de réseau compréhensibles.** `PGRST301` / `JWT expired` indiquent en français de se reconnecter. Le message réseau natif de Safari `Load failed` reçoit la même explication de connexion que celui de Chromium.

Sept assertions de régression ont été vues rouges avant correction : trois sur la continuité OTP, une sur le deuxième pointage autorisé avant relecture et une sur la notification après démontage du pointage et deux sur les erreurs JWT brutes lors de l’envoi/signature OTP. Le défaut de message de session a également été reproduit dans le navigateur ; celui de Safari a été confirmé par une requête locale volontairement interrompue.

## Actions effectivement simulées

| Scénario | Assertions d’interface et d’état API |
| --- | --- |
| OTP / interruption / nouveau document | Consentement, double clic sur envoi SMS pendant réponse retenue, retour réel vers la mission, absence de notification parasite, retour au contrat avec consentement décoché, refus d’empreinte modifiée, aucune signature après refus, rechargement et une seule signature après double clic. L’établissement reste non signataire. |
| Pointage de nuit | Passage hors ligne, aucun segment ni faux succès, code conservé, reprise manuelle après reconnexion, mutation unique pendant relecture lente, rejet du code déjà utilisé, départ à 01 h, reprise à 01 h 30, départ à 08 h, fermeture de la proposition de note avec « Plus tard ». Deux segments exacts de 20 h–01 h et 01 h 30–08 h : 11 h 30 dans la fixture, sans validation de paie. |
| Candidature refusée puis reprise | Refus métier sans candidature, HTTP 401 / JWT expiré sans candidature, message français, réouverture du dialogue et nouvelle confirmation explicite, double clic final donnant une seule candidature en attente ; aucun contrat ni signature créé. |

Chaque scénario exige l’absence d’endpoint inconnu et d’erreur JavaScript. Le helper vérifie les verbes HTTP, rôle et jeton fictif des mutations, identifiants de contrat/mission, créneaux soumis et métadonnées du pointage. Le code de pointage est à usage unique dans la fixture. Les captures et arbres ARIA accompagnent les étapes principales ; les notifications temporaires peuvent recouvrir une partie du bas de l’écran sur les images prises immédiatement après action.

## Vérifications automatisées

- `e2e/recette-complete-actions-nationales.spec.ts` : trois scénarios, cinq projets, **15/15 verts** ; puis **5/5 pointages** après dernière garde de continuité.
- `src/components/SignerContratOtp.continuite.test.tsx` : 5 tests.
- `src/pages/ContratMission.continuite.test.tsx` : 1 test.
- `src/components/pointage/PointageRotatifSoignant.continuite.test.tsx` : 2 tests.
- `src/components/pointage/PointageRotatifSoignant.test.tsx` : 2 tests existants, conservés.
- `src/components/pointage/BlocPointageMission.test.tsx` : 4 tests existants, conservés.
- `src/lib/__tests__/erreurs.test.ts` : 27 tests, dont trois variantes JWT et deux variantes Safari ajoutées.

**41 tests unitaires ciblés verts.** Le build de production est vert. Le premier typecheck global n’a identifié que cinq options RTL `exact:true` dans `NotificationsGroupe.continuite.test.tsx`, fichier du lot parallèle ; ces options ont été corrigées puis `tsc -b` global a repassé sur le dernier delta (log `/private/tmp/jolene-actions-nationales-typecheck-final.log`, vide, sortie 0).

Les premières probes ont distingué trois problèmes du banc : deux lectures RPC secondaires manquantes dans la fixture, fermeture du dialogue de notation avant de vérifier le champ sous-jacent, et attente des lectures avant remplacement complet du document sur WebKit. Aucune erreur n’a été filtrée pour rendre les assertions vertes. La première passe cinq formats a été arrêtée dès la répétition du défaut réseau Safari et des annulations de navigation déjà diagnostiquées ; elle ne compte pas comme recette réussie.

## Preuves locales

- Matrice 15/15 : `/private/tmp/jolene-actions-nationales-final2/results.json` (46,1 s).
- Derniers pointages 5/5 : `/private/tmp/jolene-actions-nationales-pointage-final/results.json` (16,2 s).
- Reprise finale OTP nouveaux + existants 10/10 : `/private/tmp/jolene-actions-nationales-otp-final/results.json` (42,7 s).
- Probe initiale desktop : `/private/tmp/jolene-actions-nationales-probe/results.json`.
- Probe desktop OTP + pointage 2/2 : `/private/tmp/jolene-actions-nationales-probe2/results.json`.
- Première passe cinq formats interrompue : `/private/tmp/jolene-actions-nationales-final/results.json`.

Chaque dossier de résultat contient les captures, arbres ARIA et journaux de mutations simulées. Les résultats `final2` et `pointage-final` sont les preuves retenues.

## Ce que cette recette ne prouve pas

- Les réponses API sont des contrats simulés : elles ne démontrent pas l’exécution réelle SQL/RLS, les limites anti-abus ni l’horodatage/empreinte du fournisseur de signature.
- Le SMS réel, la caméra QR physique, le GPS, le réseau d’un téléphone et une interruption matérielle de l’app n’ont pas été exercés.
- Le pointage actif utilise `PointageRotatifSoignant`. Cette recette valide le refus hors ligne puis la **reprise manuelle**, pas une file automatique de pointages hors ligne. Le rejet du code rejoué est simulé ; le cooldown serveur n’est pas évalué ici.
- Le HTTP 401 est injecté sur la candidature. La nouvelle tentative suit le rétablissement de l’API fictive ; ce n’est pas une preuve de reconnexion Auth réelle. Les refus ne sont jamais transformés en succès automatique.
- Les erreurs de disponibilité et leur rollback, l’OTP incorrect/expiré et le flux UI à deux rôles jusqu’au certificat PDF existent déjà dans `recette-complete-soignant.spec.ts` et `recette-complete-mission.spec.ts` (recette du 24 septembre). Les 5 cas OTP ont été rejoués après le changement de traduction ; les autres n’ont pas été recomptés ou rejoués dans ce complément. Le vieux fichier `flows/workflow-mission-complete.spec.ts`, qui contient encore des TODO, n’est pas cité comme preuve.
- Cette validation de comportement frontend ne constitue ni une mesure de FPS ni une garantie de comportement parfait en production.
