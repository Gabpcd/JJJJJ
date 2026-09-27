# Suivi commun de mission — 25 et 27 septembre 2026

Le détail de mission soignant et le détail établissement présentent le même suivi. Le complément du 27 septembre expose sept repères : dossier et conformité, contrat Jolene, planification, présence, validation des heures, document financier et règlement. L’attribution et le statut d’exécution restent dans le contexte détaillé et dans le résumé prioritaire ; aucune information précédente n’est supprimée. Le titre de la mission reste placé avant ce suivi. Le suivi affiche un résumé compact par défaut ; « Afficher le détail du suivi » déplie le contexte, les sept cartes et leurs raccourcis. Cela regroupe des informations auparavant réparties entre plusieurs écrans ; les documents, présences et finances existants restent leurs espaces de consultation détaillée.

## Complément du 27 septembre : étapes distinctes et planning repris

La réconciliation des exigences a retrouvé une omission de portée dans la première version : les six repères initiaux ne rendaient pas explicitement le dossier et la planification, et regroupaient pointage/validation sous « Heures ». Le résumé conserve maintenant sept repères sur une seule rangée. Ouvrir le détail expose aussi attribution et exécution ; la priorité annulation/litige est préservée.

- **Dossier et conformité** : « Contrôles à consulter » et lien vers le dossier existant du rôle concerné. Cette synthèse n’a pas de verdict global chargé ; elle ne dit ni « profil incomplet » ni « dossier validé ». L’attribution, les signatures, un planning exact ou le booléen du contrôle repos/chevauchement ne rendent jamais ce repère vert. Les gardes de candidature et les contrôles métier existants restent inchangés.
- **Planification** : dérivée des créneaux prévisionnels et des erreurs déjà chargés par la page, avec `construirePlanningCandidat`. Chargement, panne, créneaux incomplets et planning exact restent distincts. « Créneaux prévus disponibles » ne certifie aucune présence. Le lien ouvre le bloc de planning de cette mission par une ancre avec cible focalisable ; côté établissement, il réouvre aussi l’onglet Détails si les recommandations étaient sélectionnées. Une panne est visible même replié ; « Actualiser le suivi » relance aussi la lecture du parent.
- **Lecture sans réponse** : les lectures facultatives soignant des créneaux et de la TVA sont indépendantes, chacune bornée à huit secondes avec annulation de requête et garde contre une réponse obsolète. Une TVA lente ne bloque plus l’affichage du planning. Une lecture planning sans réponse passe à indisponible et reste réessayable ; elle ne désactive pas l’actualisation des autres données du suivi.
- **Présence / validation** : mêmes lignes `presences`, deux repères. Arrivée et départ de toutes les présences consultées confirment leurs pointages ; la validation exige en plus le flag de chaque présence. Départ manquant et validation déclarée restent en attente. Un litige garde la validation à vérifier sans effacer les pointages enregistrés. Aucun calcul d’heures, de paie ou nouvelle mutation.
- **Accès et coût réseau** : aucun nouveau RPC, table ou droit ; le planning est transmis par les parents. Déplier/replier et actualiser les seules données planning reçues ne déclenchent aucune lecture supplémentaire du suivi. Les liens financiers conservent leur contrôle de permission.

Les preuves du 25 septembre ci-dessous décrivent la version initiale à six repères et ses corrections de volume ; elles ne sont pas recomptées comme nouvelles preuves. Les résultats du complément sont consignés en fin de document.

## Correction du volume visuel — historique du 25 septembre

La première version affichait systématiquement les six cartes : sur mobile, ce bloc repoussait trop bas le statut, la rémunération et les informations de mission. Le résumé replié expose maintenant un état prioritaire et six repères indépendants, sans pourcentage, nombre d’étapes achevées ni confirmation financière globale. Une annulation ou une étape à vérifier passe avant une étape simplement en cours. Les pannes, litiges et accès limités restent visibles sans ouvrir le panneau ; l’actualisation reste accessible.

Le bouton expose `aria-expanded` et `aria-controls`, garde une cible tactile d’au moins 44 px et permet aussi de refermer le détail. Ouvrir/fermer ne déclenche aucune lecture supplémentaire. Les données canoniques, contrôles d’accès et liens n’ont pas changé. Le suivi reste destiné aux rôles soignant et administrateur d’établissement ; il n’est pas ajouté à l’interface administrateur plateforme.

Hauteurs mesurées dans la recette compilée, en pixels CSS, identiques pour les deux rôles dans ces états :

| Format | Candidature/attribution | Règlement déclaré | Panne de lecture | Litige + accès limité établissement |
|---|---:|---:|---:|---:|
| iPhone 390 × 844 | 184 | 208 | 256 | 264 |
| Android Pixel | 184,84 | 208,84 | 256,84 | 264,84 |
| iPad portrait 820 × 1180 | 197 | 217 | 265 | 273 |
| iPad paysage 1180 × 820 | 197 | 217 | 245 | 273 |
| Ordinateur 1440 × 900 | 197 | 217 | 245 | 273 |

Le scénario initial vérifie que la rémunération soignant et les candidatures établissement sont dans le viewport avec le résumé fermé. Les captures des cinq formats ont été inspectées ; aucun débordement horizontal n’est constaté. Il s’agit de géométrie et de navigation, pas d’une mesure de FPS.

### Rémunération prioritaire : reprise de la régression CI

La recette historique de lisibilité a ensuite révélé que le résumé compact, encore placé avant les blocs de mission, repoussait la rémunération mobile à `y=540,84 px`, au-delà du seuil existant de `422 px` pour un écran de 844 px. La largeur 1440 passait déjà avec le résumé compact. Le montage soignant a été déplacé après les blocs mission/rémunération et avant les informations secondaires ; les bandeaux d’action prioritaire restent en tête. Aucun seuil ni montant n’a été modifié.

La reprise compilée est verte : **30 cas, zéro échec, zéro retry, 123,40 s**. Elle comprend les 20 parcours du suivi sur les cinq formats habituels et 10 cas du test historique de lisibilité (largeurs imposées 390 et 1440, répétées sous les cinq profils navigateur). Chaque cas de lisibilité traverse salariat, honoraires libéraux et rétrocession ; la rémunération doit commencer dans la première moitié de l’écran, son montant reste visible, et le suivi doit venir après son bloc. Les tests du suivi contrôlent cette position initiale avant de faire défiler vers le suivi pour le capturer. Les captures finales mobile et grand écran ont été inspectées.

Résultat machine : `/private/tmp/jolene-lisibilite-compact-final/results.json`, copie permanente `audits/2026-09-25-lancement-national/resultats/lisibilite-et-suivi-30-cas.json`. Cette reprise corrige la position du suivi ; les 30 tests unitaires du composant et de sa synthèse précédemment verts portent sur une logique inchangée.

## Sources et limites de chaque étape

| Étape | Source existante | Confirmation affichée et garde-fou |
|---|---|---|
| Attribution | `missions.soignant_assigne_id`, candidature déjà chargée côté soignant | L’affectation confirme l’attribution. Une candidature enregistrée ne prouve ni acceptation ni refus. Le suivi n’ajoute pas un historique des décisions de candidature. |
| Dossier et conformité | Raccourci vers les justificatifs soignant ou le profil professionnel autorisé côté établissement | « Contrôles à consulter » reste neutre. Aucun résultat global de conformité n’est chargé ou déduit ; aucun profil déjà validé n’est présenté comme incomplet. |
| Contrat Jolene | Dernier `contrats_mission`, statut et deux indicateurs de signature | « Deux signatures enregistrées » exige `SIGNE_COMPLET` et les deux signatures vraies. En salariat, ce contrat Jolene ne prouve pas la signature du contrat de travail employeur, qui reste distinct. |
| Planification | `mission_creneaux` prévisionnels, repli ponctuel métier existant et `construirePlanningCandidat`, déjà chargés dans les pages | L’exactitude et un nombre entier positif de créneaux confirment leur disponibilité. Une panne reste indisponible, même si des horaires indicatifs subsistent ailleurs. Aucun pointage n’est déduit du planning. |
| Mission | `missions.statut` | L’exécution terminée ou annulée est explicite. Une fin de mission ne valide pas les heures. |
| Présence | `presences`, arrivée et départ | Tous les pointages consultés doivent avoir arrivée et départ. Ce repère ne confirme pas leur validation. |
| Validation des heures | Mêmes `presences` et `valide_par_etablissement` | Les présences consultées doivent toutes avoir arrivée, départ et validation. Un litige actif affiche un état à vérifier. Aucun calcul de paie ou de durée n’est ajouté. |
| Document | `factures_honoraires` pour un régime appliqué `LIBERAL`, `bulletins_paie` pour `SALARIE` | Une facture active émise est distincte d’un avoir, brouillon, document remplacé ou annulé. Un bulletin exige son PDF et un statut `EMIS` ou `PAYE`. Le régime absent reste inconnu, sans repli arbitraire sur le salariat. |
| Règlement | `paiements_soignant`, statut, confirmation du soignant et contestation | `DECLARE` reste « Déclaré, à confirmer ». `RESOLU`, une facture payée ou la mission terminée ne prouvent pas la réception. `CONFIRME` exige aussi `confirme_par_soignant=true`, sans contestation. Le suivi ne calcule pas le solde de la mission. |

Les transferts Stripe, l’escrow et les avances ne sont pas réinterprétés comme une réception bancaire dans cette synthèse. En l’absence de confirmation dans `paiements_soignant`, elle indique « Règlement non confirmé » et propose les finances. Il s’agit d’une limite volontaire de la synthèse, et non d’une affirmation qu’aucun autre mouvement financier n’existe.

Le composant ne crée aucune API, règle financière, mutation ou document. Les liens ouvrent les véritables écrans de contrat, présences, documents ou finances du rôle connecté. Un établissement doit obtenir la permission financière pour la mission concernée avant les lectures financières. Une panne reste indisponible, un refus d’accès reste limité et une collection vide ne devient pas une étape validée.

Les lectures sont limitées à la mission et à quelques colonnes, sans persistance disque. Le composant est remonté à chaque changement de compte, rôle, mission ou établissement. Les requêtes sont annulées au démontage et bornées à dix secondes ; le bouton d’actualisation permet de reprendre une source en échec.

## Vérification fonctionnelle

- **30 tests unitaires verts** : 24 règles de synthèse et 6 tests de composant (réponse obsolète, délai dépassé, permissions d’un autre établissement, changement de compte non assigné, ouverture/fermeture sans relecture, alertes visibles repliées).
- **20 simulations UI vertes du rendu compact** : deux scénarios, deux rôles, cinq formats — WebKit iPad portrait et paysage, WebKit iPhone, Chromium Android et ordinateur. Passe finale de 87,98 s, zéro échec et zéro retry automatique. Les tests ouvrent réellement le détail avant les assertions des six étapes, puis le referment et contrôlent sa hauteur.
- Chaque rôle traverse candidature/attribution, contrat incomplet puis deux signatures, mission terminée avec heures encore non validées, validation, document émis, règlement déclaré puis réception confirmée. Les raccourcis contrat et présences sont réellement cliqués et les écrans de destination contrôlés.
- Second parcours : salariat, bulletin sans PDF puis PDF disponible, erreur HTTP 503 puis actualisation réussie, mission annulée avec litige, règlement contesté. Le rôle établissement limité ne lit aucune des sources financières du suivi et n’obtient pas leur raccourci.
- Les mutations sensibles, signatures, SMS et emails restent absents de ce test de lecture. Les endpoints inattendus échouent ; les accès externes et WebSocket sont bloqués. Les requêtes sont authentifiées par des jetons fictifs et contrôlées sur la mission attendue.
- Compilation de production, typecheck global `tsc -b` et `git diff --check` verts.

Les probes de la première version ont corrigé le banc : utilisation du véritable titre du détail des présences, fermeture par son bouton de l’évaluation post-mission et ajout du contrat explicite `fn_presences_detail_mission` avec un créneau effectif fictif cohérent. Pour le rendu compact, une première tentative a été arrêtée après refus système du port local ; une seconde a révélé une attente manquante du montage SPA dans le helper. Ce helper attend maintenant le vrai bouton avant de lire `aria-expanded`. La passe finale complète utilise cette version ; aucun échec du navigateur n’a été filtré.

Ces simulations valident le rendu et les interactions du frontend sur réponses API contrôlées. Elles ne constituent pas un test RLS SQL, une signature de fournisseur, un virement réel, une preuve de paie, un benchmark de fluidité ou une mesure sur appareil physique.

## Fichiers et preuves

- Produit : `src/components/SuiviMission.tsx`, `src/lib/suiviMission.ts`, intégrations dans `DetailMissionSoignant.tsx` et `DetailMission.tsx`.
- Unités : `src/lib/__tests__/suiviMission.test.ts`, `src/components/__tests__/SuiviMission.test.tsx`.
- Parcours : `e2e/recette-complete-suivi-mission.spec.ts`, contrat strict `e2e/helpers/recette-complete-suivi-mission.ts`.
- Résultat machine initial : `/private/tmp/jolene-suivi-final/results.json`. Résultat du rendu compact : `/private/tmp/jolene-suivi-compact-final/results.json` ; copie permanente `audits/2026-09-25-lancement-national/resultats/suivi-mission-compact-20-cas.json` du projet Jolene.
- Les captures pleine page incluent une barre de navigation fixe à la position du viewport lors de la capture ; elles ne mesurent pas les animations.

![Soignant iPhone : rémunération avant le résumé fermé](assets/2026-09-25-suivi-compact/soignant-iphone.png)

![Soignant grand écran : rémunération avant le résumé fermé](assets/2026-09-25-suivi-compact/soignant-ipad-paysage.png)

![Établissement iPhone : litige et accès limité restent visibles sans déplier](assets/2026-09-25-suivi-compact/etablissement-iphone-acces-limite.png)

## Résultats du complément G03 — 27 septembre

- **39 tests unitaires verts** : 31 règles de synthèse et 8 tests de composant. Ajouts : planning exact/incomplet/en erreur, aucune conformité globale inventée, présence distincte de sa validation, sept repères et reprise du planning sans relecture à l’ouverture.
- **40 simulations vertes, 121,74 s**, zéro échec, retry ou cas ignoré, sur iPhone, Android, iPad portrait/paysage et ordinateur. En plus des parcours historiques, chaque rôle reprend un planning en panne et ouvre réellement le dossier cible. Deux lectures soignant volontairement sans réponse (planning puis TVA) sont exercées avec avancement de l’horloge : indisponibilité bornée, planning indépendant de la TVA et actualisation utilisable.
- **5 simulations additionnelles vertes, 11,65 s** sur les mêmes formats, après le dernier ajustement du raccourci planning : l’onglet Recommandations démontait sa cible. Le lien réouvre maintenant Détails, garde l’ancre et place le focus sur le planning. Le test part réellement de la cible absente et contrôle onglet, URL, visibilité et focus.
- **10 contrôles historiques de lisibilité verts, 36,99 s** après le passage à sept repères (avant le complément de délai et de navigation) : salariat, honoraires libéraux et rétrocession. La rémunération reste prioritaire et aucun débordement horizontal n’est introduit. Les hauteurs du résumé compact restent celles du tableau historique ci-dessus. Les captures iPhone et iPad ont été inspectées.
- ESLint ciblé, build de production, TypeScript global `tsc -b` et vérification des espaces du diff passent. Les deux relectures indépendantes des corrections de délai puis de navigation ne signalent plus d’anomalie. Le typecheck porte sur le checkout partagé avec le lot natif ; une erreur transitoire du test natif en cours d’édition a été corrigée par son responsable avant la relance verte.

Preuves locales privées : `/private/tmp/jolene-g03-final-simulation/results.json` (40), `/private/tmp/jolene-g03-planning-onglet-final/results.json` (5), `/private/tmp/jolene-g03-lisibilite-simulation/results.json` (10), `/private/tmp/jolene-g03-reconciliation-unites.log`. Les passes 40 et 5 sont distinctes, pas une passe unique de 45. Les premières probes corrigées restent conservées ; aucun cas n’a été rendu permissif pour masquer un échec.

Ce complément clôt le manque de repères de la synthèse G03 dans la portée frontend. Il ne certifie pas une conformité métier globale, la réception d’un fournisseur ni l’exécution d’un cycle financier réel.
