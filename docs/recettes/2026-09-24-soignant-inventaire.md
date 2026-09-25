# Recette soignant — 24 septembre 2026

Cette recette vérifie le frontend avec des données fictives et des réponses API contrôlées. Elle couvre les 32 routes canoniques soignant déclarées dans `App.tsx` et leurs 18 alias. Elle ne constitue pas une validation de la base de production, des paiements réels ou d'un appareil physique.

## Entrées et formats

Les 29 pages sans paramètre sont parcourues dans trois états distincts, chacun à partir des formulaires visibles : inscription d'un compte minimal ; connexion d'un compte minimal existant ; connexion d'un compte professionnel complet existant. Dans cette matrice de navigation, le compte complet est fourni par la fixture. Un complément distinct remplit et soumet réellement le formulaire professionnel depuis une inscription minimale ; il est détaillé ci-dessous et ne valide pas les justificatifs professionnels.

Les cinq formats sont iPad WebKit 820×1180, iPad WebKit 1180×820, iPhone WebKit 390×844, Android Chromium Pixel 7 et ordinateur Chromium 1440×900. Le navigateur est automatisé ; ces formats ne sont pas des mesures de performances d'appareils physiques.

Le fichier `e2e/recette-complete-soignant.spec.ts` contient 40 scénarios exécutés sur chacun de ces formats, soit 200 cas. Deux scénarios supplémentaires dans `e2e/recette-complete-soignant-compte.spec.ts` portent le lot à 210 cas : export JSON/CSV et suppression de compte. `e2e/recette-complete-soignant-tablette.spec.ts` ajoute deux scénarios sur les cinq formats : proportions du deck Swipe, puis Carte et filtres. Les dimensions 1032×1376 et 1376×1032 sont également contrôlées dans le scénario Swipe sur les projets iPad. Deux parcours de dossier dans `e2e/recette-complete-completion-soignant.spec.ts`, chacun exécuté sur les cinq formats, portent le lot total à 230 cas uniques.

La configuration dédiée n'exécute aucun globalSetup connecté à un compte réel. Le helper `e2e/helpers/recette-complete-soignant.ts` refuse les endpoints inconnus, bloque les domaines externes et toutes les connexions WebSocket, supprime les hints preconnect/dns-prefetch des documents de test et conserve l'historique des appels simulés. Les RPC attendues sont nommées explicitement. Les tableaux vides sont des états de fixture déclarés, pas une réponse générique pour toute requête inconnue. Les écritures de tables non modélisées sont refusées même si un jeu de données de lecture existe pour cette table.

## Inventaire des pages

Tous les chemins du tableau ont le préfixe `/soignant/`. « Rendu » signifie assertion de contenu et absence d'exception, avec dump ARIA ; cela ne signifie pas que chaque opération métier de la page a été exécutée.

| Route canonique | État et vérification complémentaire |
| --- | --- |
| `tableau-de-bord` | Rendu minimal après inscription et connexion ; professionnel salarié sans mission ; arrivée par l'onglet Accueil. |
| `mon-compte` | Rendu ; coordonnées bancaires ; modale de contact ; déconnexion puis refus d'une route protégée et reconnexion. |
| `profil` | Minimal redirigé vers la préparation facultative ; trois onglets du profil complet ; bio modifiée puis relue après rechargement ; exports JSON/CSV et refus explicite de limite ; suppression annulée, refus HTTP 503 puis succès simulé et déconnexion. |
| `recherche-missions` | Vide et mission présente ; après finalisation du dossier, refus du questionnaire facultatif avec « Plus tard », retours Carte → Swipe et Liste → Swipe avec carte présente ; détail Swipe en modale ; passage Liste puis détail de mission ; Carte, popup et lien vers le détail ; retour conservant la vue ; filtre ville sans résultat puis réinitialisation restaurant la mission ; aucune candidature automatique. |
| `missions` | Vide ; onglets et alias des missions passées/à venir. Les actions métier sont dans le lot mission partagé. |
| `missions/:id` | Mission présente, description et accès candidature ; arrivée depuis Explorer et Favoris ; retour. |
| `missions/serie/:serieId` | Pack présent, sélection/désélection locale ; devenu vide après retour ; erreur HTTP 503 puis réessai ; lecture par compte minimal avec préparation du profil avant acceptation. |
| `mes-documents` | Minimal ; justificatif présent ; onglets Justificatifs/Contrats/DPAE ; segments DPAE Validées/En attente/Tous cliqués après finalisation, sans contrat salarié ; erreur HTTP 503/réessai ; choix d'un PDF et téléversement refusé ; document précédent conservé ; annulation puis confirmation de suppression simulée. |
| `disponibilites` | Calendrier ; bascule jour et appel RPC exact ; relecture ; échec d'enregistrement et restauration de l'état précédent ; erreur de lecture et réessai. |
| `conformite` | Vide ; contrôle présent ; copie de l'historique exacte ; refus du presse-papier signalé ; erreur de lecture distincte de l'absence de contrôles. |
| `presences` | Quatre onglets vides. Les pointages et validations effectifs sont dans le lot mission. |
| `presences/mission/:id` | Mission assignée future, absence de créneau effectif correctement annoncée et retour vers l'écran précédent. |
| `mes-gains` | Revenus sans activité ; onglet Simulations salarié ; Factures mixte vide ; intégrité géométrique du texte des cartes KPI sur iPad. Pas de virement réel. |
| `mandat-facturation` | Minimal sans activité ; salarié non concerné ; mixte : lecture du mandat, signature désactivée tant que les conditions ne sont pas remplies, fermeture. Aucune signature juridique. |
| `score` | État minimal et professionnel sans mission ; alias fiabilité. |
| `evaluations` | Aucune évaluation reçue. Les évaluations présentes et leur publication ne sont pas validées par ce lot. |
| `prevoyance` | Rendu ; calculateur à 5 000 € de revenu et niveau OR affichant 4 000 €. Aucun abonnement. |
| `attestation-heures` | Quatre périodes ; absence d'heures ; génération indisponible. Un PDF réel d'attestation n'est pas produit dans ce lot. |
| `passer-en-liberal` | Minimal : proposition facultative accessible sans boucle de chargement ni création de parcours métier ; professionnel existant : parcours affiché. |
| `exclusions` | Onglets exclusions reçues et envoyées vides. Aucune exclusion réelle. |
| `premium` | Page de gratuité pour les soignants ; aucun achat. |
| `charges` | Salarié/minimal : contexte libéral nécessaire ; mixte actif sans mission : état vide explicite et choix de régime fiscal visible. Pas de déclaration fiscale. |
| `notifications` | Vide ; notification Document présente ; filtres Missions/Documents ; clic vers le document. Les erreurs de lecture et autres actions partagées sont dans le lot communications. |
| `parrainage` | Vide ; filleul présent et code ; erreur HTTP 503 et récupération. Aucune invitation envoyée. |
| `messagerie` | État vide et navigation ; transition Archivées → Actives cliquée après finalisation du dossier. La conversation présente, recherche, archivage et erreurs sont dans le lot communications. |
| `litiges` | Deux onglets vides ; alias réclamations. Aucun litige réel. |
| `stripe-connect` | Salarié ; mixte avec compte de test : Stripe explicitement désactivé, aucun bouton de connexion bancaire. |
| `classement` | Vide et ligne présente ; filtre profession avec paramètre RPC contrôlé. |
| `parametres/notifications` | Préférences visibles ; email désactivé, sauvegardé et relu. Aucun envoi réel. |
| `parametres/recherches-sauvegardees` | Vide et recherche présente ; activation alerte, renommage, application des filtres vers Explorer. Aucun email d'alerte réel. |
| `pool-urgence` | Rendu sans mission ; aucun envoi SMS ou déclenchement d'urgence. |
| `mes-favoris` | Vide et favoris présents ; mission ouverte au clic puis retirée ; établissement retiré après confirmation. |

## Alias

Chaque alias est ouvert directement, sa destination exacte est contrôlée et son contenu est enregistré en ARIA. Le compte est professionnel mixte pour exposer les variantes financières.

| Alias | Destination |
| --- | --- |
| `swipe-missions` | `recherche-missions?vue=swipe` |
| `mes-matches` | `missions` |
| `documents` | `mes-documents?tab=justificatifs` |
| `planning` | `missions?tab=a-venir` |
| `calendrier-sync` | `missions?tab=a-venir` |
| `reputation` | `profil` |
| `mes-factures-honoraires` | `mes-gains?tab=factures` |
| `mes-avances` | `mes-gains?tab=avances` ; fonctionnalité désactivée dans cette fixture, repli sur Aperçu |
| `bulletins-paie` | `mes-gains?tab=bulletins` |
| `historique-missions` | `missions?tab=passees` |
| `fiabilite` | `score` |
| `fiabilite-legacy` | `score` |
| `parcours-3200h` | `passer-en-liberal` |
| `dpae` | `mes-documents?tab=dpae` |
| `reclamations` | `litiges?tab=reclamations` |
| `contrats` | `mes-documents?tab=contrats` |
| `parametres-complet` | `mon-compte` |
| `parametres` | `mon-compte` |

## Dossier réellement rempli depuis une inscription minimale

Le helper distinct `e2e/helpers/recette-complete-completion-soignant.ts` démarre sans identité professionnelle, coordonnées, date de naissance, numéro RPPS ni justificatifs validés. Le compte ne devient professionnel qu'après réception d'une soumission `register-soignant` dont le contenu exact est contrôlé. Les scénarios utilisent une IDE fictive salariée, Camille Recette.

- **Validation et finalisation** : inscription visible, mission présente, clic Candidater, dossier professionnel, champs obligatoires vides puis téléphone/date de naissance invalides. Un RPPS correspondant au nom mais à une autre profession affiche une erreur, sans confirmation verte ni appel de finalisation. Un second RPPS concordant débloque la suite. Le premier enregistrement est refusé HTTP 503 ; saisie et choix Salarié restent présents. Le réessai réussit et revient à la mission choisie ; le profil contient l'identité soumise, sans candidature automatique. Explorer permet de fermer le questionnaire facultatif, de passer Carte → Swipe et Liste → Swipe ; la messagerie permet Archivées → Actives.
- **Brouillon et reprise** : saisie partielle, sauvegarde pour plus tard, retour à Explorer, nouvelle ouverture du dossier depuis Candidater et restauration des champs. Le refus de sauvegarde du parcours est affiché sans appeler la finalisation. Après réessai réussi, retour à la mission ; les segments DPAE Validées, En attente puis Tous affichent correctement l'absence de contrat.

`verify-rpps`, `register-soignant` et Auth sont simulés. La recette valide leur intégration frontend et les contenus soumis, pas une consultation réelle de l'Annuaire Santé ni Pro Santé Connect. Les justificatifs restent explicitement non validés et les données DPAE incomplètes après finalisation. La finalisation du dossier n'est donc pas présentée comme une autorisation globale de candidater ou de signer.

## Corrections issues de la simulation

- `PasserEnLiberal` : un compte minimal ne possède pas encore de ligne métier soignant. L'écran attendait indéfiniment cette ligne. Il explique maintenant la préparation facultative et permet de poursuivre Explorer ; le hook créant un parcours libéral n'est pas appelé dans cet état.
- `MesGains` : les deux cartes de revenus utilisaient quatre colonnes dès 768 px. À 820 px avec la navigation latérale, leur texte était comprimé. La grille conserve deux colonnes jusqu'au grand écran, où leur nombre suit les cartes réellement présentes.
- `MesDisponibilites` : une lecture HTTP 503 produisait un calendrier vide éditable. Le chargement en erreur est maintenant explicite et doit réussir avant d'autoriser une modification.
- `ConformiteSoignant` : une erreur de lecture devenait « aucun contrôle » ; un refus du presse-papier pouvait annoncer un export réussi. Les erreurs sont affichées et le réessai est disponible ; le succès de copie attend la résolution effective de l'API navigateur.
- `DetailSerieSoignant` : un pack vide faisait formater une date absente et déclenchait l'écran d'erreur global. Le vide et l'indisponibilité sont distingués, un réessai est proposé, le compte minimal peut consulter les créneaux et préparer son profil avant acceptation. Les résultats d'une ancienne requête sont ignorés après changement de série ou sortie de page.
- `MandatFacturation` : les vues de lecture et de succès comportaient un second élément `main` dans celui de l'application. Les conteneurs internes deviennent des `div` ; texte contractuel, défilement et conditions de signature sont inchangés. Le scénario mixte exige une seule région principale.
- `VueSwipeMissions` : la carte, large de 448 px, s'étirait à environ 1 070 px de haut dans le conteneur iPad natif 1032×1376. Le deck est borné à 720 px dès 768 px de largeur (tablette et colonne bureau), tout en restant réductible en paysage. Les règles mobiles et métier ne changent pas. Le contrôle dédié exige le contenu entier, les trois boutons dans le viewport et l'ouverture/fermeture du détail.

- `InscriptionSoignant` : une identité RPPS concordante produisait une confirmation verte malgré une profession incompatible. Le succès exige désormais les deux concordances et un annuaire disponible. Une nouvelle vérification efface l'ancien résultat immédiatement et suspend la soumission ; une requête ouverte plus de dix secondes rejoint l'état existant d'annuaire indisponible. Les résultats obsolètes et annulations de navigation sont ignorés.

Les règles serveur, le calcul financier et les autorisations métier n'ont pas été assouplis.

## Preuves et limites

Les tests unitaires `PasserEnLiberal.test.tsx`, `SoignantLecturesSecondaires.test.tsx` et `InscriptionSoignant.rpps.test.tsx` passent : sept comportements ciblés, dont trois couvrent la profession incompatible, le remplacement du numéro RPPS et le délai maximal. Les builds statiques locaux ont permis de valider les 230 cas uniques du lot, après les reprises détaillées ci-dessous. Ce résultat est une consolidation de plusieurs exécutions, pas un run unique de 230 tests sans échec.

| Format | Passe principale | Cas uniques validés, compléments et reprises inclus |
| --- | --- | --- |
| iPad portrait | 39/42 | 46/46 |
| iPad paysage | 42/42 | 46/46 |
| iPhone | 40/42 | 46/46 |
| Android | 41/42 | 46/46 |
| Ordinateur | 42/42 | 46/46 |

La passe principale sur le build statique 8893 a terminé avec 204 succès et six échecs. Un échec est explicitement `ENOSPC` pendant l'écriture d'un artefact : le disque local était plein. Deux échecs provenaient d'une navigation ou d'un rechargement demandé par le banc avant la fin des requêtes de la page précédente. Trois attentes utilisaient le mauvais élément responsive : le titre du menu au lieu de l'ancre bancaire réellement ciblée sur iPhone, et le bouton Retour inline masqué au lieu de celui de l'en-tête sur iPhone/Android. Ces six cas ont été repris avec succès sur le build 8894 ; le parcours bancaire Android a aussi été contrôlé avec le sélecteur corrigé. Aucune erreur navigateur n'a été filtrée pour obtenir ce résultat.

Les contrôles des proportions Swipe passent sur les cinq formats. Le scénario Carte/Filtres a été rejoué sur les cinq formats après correction d'une attente : le compteur « 0 résultat » est masqué sur tablette et ordinateur, tandis que le titre visible « Aucune mission trouvée » exprime bien l'état attendu. Les cinq scénarios de suppression de compte ont ensuite été rejoués avec une assertion plus stricte : le refus exige « Une erreur est survenue. Veuillez réessayer. » et interdit `non-2xx`/`status code`.

Le total consolidé est de 259 exécutions pour 230 cas uniques, donc 29 répétitions. Les 17 répétitions du lot initial sont cinq reprises Carte/Filtres, sept reprises ciblées et cinq contrôles supplémentaires du message français. Les dix parcours de dossier, initialement verts sur 8897, ont ensuite été enrichis avec les derniers onglets et réexécutés : cinq finalisations avec Explorer/Messagerie et cinq brouillons avec segments DPAE. Deux anciens cas iPad (navigation du compte complet et Explorer minimal peuplé) ont été repris après correction du contrat de fixture Swipe. Les passes de découverte antérieures ne sont pas comprises dans ce total. Le manifeste local `jolene-recette-soignant-cas-uniques.json` identifie chaque cas par projet, fichier et scénario et conserve la source JSON de son dernier résultat.

Les résultats bruts sont disponibles dans `/private/tmp/jolene-recette-soignant-final-8893/results.json`, puis les dossiers `jolene-recette-soignant-tablette-final`, `jolene-recette-soignant-carte-final2`, `jolene-recette-soignant-reprises-ipad`, `jolene-recette-soignant-reprises-mobile` et `jolene-recette-soignant-suppression-fr`, sous `/private/tmp`. Le build 8894 inclut le dernier plafond de hauteur Swipe ; son contrôle géométrique est séparé de la passe principale. Le complément dossier utilise le build 8897 : dix succès initiaux dans `jolene-recette-completion-soignant-final`, puis cinq succès enrichis chacun dans `jolene-recette-completion-soignant-transitions-final` et `jolene-recette-completion-soignant-dpae`. Les deux anciens cas réexécutés sont dans `jolene-recette-soignant-contrat-swipe-final`. Tous ces dossiers se trouvent sous `/private/tmp` et contiennent leur `results.json`.

La mise au point du complément dossier a aussi produit six passes de découverte conservées (`probe`, `probe2`, `probe3`, `transitions`, `transitions2`, `transitions3`). Elles ont corrigé un sélecteur RPPS, une attente sur une ancienne confirmation, la fermeture réelle du questionnaire facultatif et un sélecteur de paragraphe de messagerie. Le contrat de fixture `fn_obtenir_missions_swipe` était auparavant un tableau brut ; il renvoie maintenant l'objet `{ missions: [...] }` avec les champs du contrat SQL, tandis que `fn_explorer_missions_inscription` conserve son tableau. L'ancien deck professionnel vide ne constitue donc **pas** une preuve d'affichage d'une mission présente : cette preuve vient des cinq scénarios enrichis finaux, qui exigent une carte après retour depuis Carte et Liste. Les assertions du parcours minimal peuplé existant sont conservées. Ces passes de découverte, parfois interrompues, ne sont pas présentées comme des validations finales.

Les captures principales et dumps ARIA sont produits par projet ; les appels API simulés sont attachés à chaque scénario. Les assertions contrôlent le texte, les états ARIA, les appels attendus et l'absence d'exception JavaScript. Les images aident à juger le rendu mais ne remplacent pas ces assertions.

Une première passe statique a été arrêtée après reproduction d'une course du banc : le test ouvrait une nouvelle URL complète pendant une requête de la transition SPA précédente. WebKit émettait alors une erreur de chargement liée au document détruit. Le helper final attend la fin des requêtes API réellement observées avant ces sauts de navigation ; il ne filtre aucune erreur JavaScript. Les résultats de cette passe interrompue ne sont pas comptés comme recette finale.

Limites exactes : stockage et Auth sont simulés ; aucune validation de RLS, de livraison email/SMS/push, de paiement, de KYC, de déclaration fiscale, de signature réelle, de publication store ou de performance matérielle. Les mocks de lecture appliquent les filtres simples utilisés par les scénarios ; ils ne réimplémentent pas toute la sémantique SQL/PostgREST. La Carte est contrôlée pour ses marqueurs, sa popup et sa navigation ; les tuiles OpenStreetMap externes restent bloquées, donc leur disponibilité réelle n'est pas validée. Les contrats, doubles signatures, OTP, pointages et facturation sont vérifiés dans un autre lot, pas certifiés par les simples pages vides de cet inventaire. Le compte IDE sert de référence et ne démontre pas toutes les règles propres à chaque profession.
