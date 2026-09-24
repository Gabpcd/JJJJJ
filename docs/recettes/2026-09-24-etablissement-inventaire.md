# Recette établissement — 24 septembre 2026

## Périmètre et méthode

Base : main 5f88e981, branche `fix/recette-complete-tablette`.

Parcours UI d’entrée : connexion email/mot de passe et inscription rapide établissement. Dans la matrice générale « inscription → compte complet », le changement de statut serveur est simulé après l’inscription rapide : ce scénario ne constitue pas une preuve de soumission du formulaire de complétion. Le complément dédié `recette-complete-completion-etablissement.spec.ts` exerce ce formulaire et le retour au brouillon ; ses résultats sont à distinguer de ceux de la matrice générale. Aucune identité réelle ni donnée de production utilisée.

Le helper déclare chaque endpoint. Les appels inconnus obtiennent 501 et font échouer la recette, au lieu de répondre arbitrairement par une liste vide. Auth, parcours, profil, état d’équipe, préférences et réponses métier sont en mémoire. Polices Google neutralisées (police de repli) et chargement Stripe remplacé par un objet inerte : cette recette ne valide ni les pixels de la police distante ni les champs hébergés Stripe. La recette native et les flux financiers sont couverts séparément.

Formats exécutés : WebKit iPad 820×1180, iPad 1180×820, iPhone 390×844 ; Chromium desktop 1440×900 et Pixel 7. Les résultats ci-dessous portent sur les parcours frontend simulés, sans prétendre prouver les services distants ni toutes les configurations réelles possibles.

## Routes canoniques

L’inventaire couvre les 31 routes canoniques préfixées `/etablissement/` et leurs 12 alias. Pour chaque ligne, le contrôle porte sur l’ouverture et un état précis, souvent vide ou inaccessible au compte minimal ; il ne signifie pas que toutes les données, actions et erreurs possibles de cette page ont été exercées. Les onglets et mutations effectivement testés sont détaillés plus bas.

| Route | Composant | Contrôle |
|---|---|---|
| `/etablissement/score` | `PageScoreEtablissement` | Matrice inscription/connexion, minimal/complet ; valeur ou état précis |
| `/etablissement/mes-reclamations` | `MesReclamationsEtab` | Matrice inscription/connexion, minimal/complet ; valeur ou état précis |
| `/etablissement/tableau-de-bord` | `DashboardEtablissement` | Matrice inscription/connexion, minimal/complet ; valeur ou état précis |
| `/etablissement/mon-compte` | `MonCompteEtablissement` | Matrice inscription/connexion, minimal/complet ; valeur ou état précis |
| `/etablissement/activer` | `ActiverEtablissement` | Matrice inscription/connexion, minimal/complet ; valeur ou état précis |
| `/etablissement/parametres/notifications` | `PageParametresNotifications` | Matrice inscription/connexion, minimal/complet ; valeur ou état précis |
| `/etablissement/parametres/recherches-sauvegardees` | `PageRecherchesSauvegardees` | Matrice inscription/connexion, minimal/complet ; valeur ou état précis |
| `/etablissement/parametres` | `Parametres` | Matrice inscription/connexion, minimal/complet ; valeur ou état précis |
| `/etablissement/soignants` | `RechercheSoignantsEtab` | Matrice inscription/connexion, minimal/complet ; valeur ou état précis |
| `/etablissement/soignants/:id` | `ProfilSoignantEtablissement` | Matrice inscription/connexion, minimal/complet ; valeur ou état précis |
| `/etablissement/missions` | `ListeMissions` | Matrice inscription/connexion, minimal/complet ; valeur ou état précis |
| `/etablissement/missions/creer` | `CreerMission` | Matrice inscription/connexion, minimal/complet ; valeur ou état précis |
| `/etablissement/missions/:id` | `DetailMission` | Matrice inscription/connexion, minimal/complet ; valeur ou état précis |
| `/etablissement/missions/:id/modifier` | `ModifierMission` | Matrice inscription/connexion, minimal/complet ; valeur ou état précis |
| `/etablissement/presences` | `PresencesEtablissement` | Matrice inscription/connexion, minimal/complet ; valeur ou état précis |
| `/etablissement/contrats` | `ListeContrats` | Matrice inscription/connexion, minimal/complet ; valeur ou état précis |
| `/etablissement/facturation` | `FacturationEtablissement` | Matrice inscription/connexion, minimal/complet ; valeur ou état précis |
| `/etablissement/facturation/:id` | `DetailFacture` | Matrice inscription/connexion, minimal/complet ; valeur ou état précis |
| `/etablissement/export-paie` | `ExportPaie` | Matrice inscription/connexion, minimal/complet ; valeur ou état précis |
| `/etablissement/rh` | `DashboardRH` | Matrice inscription/connexion, minimal/complet ; valeur ou état précis |
| `/etablissement/notifications` | `PageNotifications` | Matrice inscription/connexion, minimal/complet ; valeur ou état précis |
| `/etablissement/premium` | `PremiumEtablissement` | Matrice inscription/connexion, minimal/complet ; valeur ou état précis |
| `/etablissement/chorus-config` | `ChorusConfig` | Matrice inscription/connexion, minimal/complet ; valeur ou état précis |
| `/etablissement/pool-urgence` | `PoolUrgenceEtablissement` | Matrice inscription/connexion, minimal/complet ; valeur ou état précis |
| `/etablissement/mes-favoris` | `MesFavorisEtablissement` | Matrice inscription/connexion, minimal/complet ; valeur ou état précis |
| `/etablissement/parrainage` | `PageParrainageEtablissement` | Matrice inscription/connexion, minimal/complet ; valeur ou état précis |
| `/etablissement/equipe` | `EquipeEtablissement` | Matrice inscription/connexion, minimal/complet ; valeur ou état précis |
| `/etablissement/evaluations-a-faire` | `EvaluationsAFaireEtab` | Matrice inscription/connexion, minimal/complet ; valeur ou état précis |
| `/etablissement/messagerie` | `PageMessagerie` | Matrice inscription/connexion, minimal/complet ; valeur ou état précis |
| `/etablissement/litiges` | `LitigesEtablissement` | Matrice inscription/connexion, minimal/complet ; valeur ou état précis |
| `/etablissement/presences/mission/:id` | `DetailPresencesMission` | Matrice inscription/connexion, minimal/complet ; valeur ou état précis |

## Alias historiques

`finaliser-inscription` et `verification` → activation ; `profil` → paramètres/profil ; `analytics` → RH/analytics ; `assurance` et `contrat-plateforme` → contrats ; `mon-groupe` et `exclusions` → paramètres/opérations ; `api` → paramètres/sécurité ; `dashboard` → tableau de bord ; `obligations` → facturation ; `reclamations` → litiges/réclamations générales.

Le compte minimal ouvre volontairement le dossier depuis les liens profil/activation. Les autres rubriques restent explorables. Les cibles des alias sont vérifiées par URL et état actif du contenu/onglet, pas seulement par chargement de page.

## Onglets et actions

- Missions : toutes les catégories de statut, recherche/détail de mission présente, recommandations vides, modification sans perte du titre/date/07–19.
- Présences : À valider, En cours, Validées, Alertes.
- Contrats : Tous, En attente, Signés, Annulés ; 503 explicite puis réessai.
- RH : statistiques et analytics, changement à 12 mois.
- Litiges : litiges mission et réclamations générales.
- Paramètres : Profil, Facturation, Opérations, Notifications, Sécurité & RGPD.
- Messagerie : actives/archivées, sans envoi de message.
- Notifications : cinq catégories ; modification du canal email, enregistrement simulé et persistance au rechargement.
- Équipe : refus réel de rôle simulé sans bouton d’invitation ; invitation en mémoire Pointage uniquement et présence dans la liste.
- Chorus : normalisation des espaces d’un numéro ; indisponibilité technique clairement distincte d’une structure introuvable. Aucun accès Chorus réel.
- Menu compte : 19 destinations internes par clic, URL attendue puis retour navigateur.
- Recherche sauvegardée : Créer une recherche ouvre l’annuaire ; sauvegarde de dix critères, liste de gestion, réapplication des valeurs et contrôle des types envoyés à la recherche. La nouvelle sauvegarde établissement n’active pas d’email.
- Fiche soignant présente : note, ancienneté, documents et téléphone masqué ; retour annuaire ; panne de lecture distincte puis réessai. Favori : ajout/rechargement/retrait simulés, échecs 503 sans inversion mensongère de l’étoile.
- Complétion réelle du formulaire depuis l’inscription minimale : champs obligatoires, SIRET invalide, sauvegarde partielle et reprise, réponse 503 sans perte de saisie, réessai puis navigation dans l’équipe. L’identité reste en attente de vérification après enregistrement.
- Préparation de mission avant le dossier : titre, description, IDE salarié, 15 octobre 2030, créneau 07–19, 30 €/h. Retour du dossier au même brouillon ; publication verrouillée tant que l’établissement et son contrat de service ne sont pas validés. Après un événement serveur explicitement simulé, récapitulatif 12 h / 360 €, création 503 puis succès, modification 503 puis succès, rechargement et vérification des valeurs persistées en mémoire.
- Complément d’onglets : planning Semaine/Liste/Mois (Mois volontairement masqué sur téléphone), cinq sections facturation et leur contenu, export vers Paie, retour aux Détails après Recommandés, aux Statistiques RH après Analytics et aux Litiges mission après Réclamations générales. Mes réclamations : Toutes/En attente/Traitées avec vérification des trois paramètres RPC null/PENDING/TRAITEE.

Les contrats, OTP, mission→présences→facturation et les états financiers avec données sont dans `recette-complete-mission.spec.ts`, autre lot de la même recette. Le présent fichier ne prétend pas reproduire leur backend.

## Limites de couverture à conserver au bilan

- Les onglets listés ci-dessus sont exercés dans les états décrits, principalement vides. Il ne s’agit pas d’une couverture exhaustive de chaque sous-formulaire, filtre, combinaison de rôle et état métier.
- La matrice principale vérifie les valeurs du formulaire de modification de mission sans l’enregistrer. Le complément de complétion ajoute des mutations de création et modification explicitement simulées ; le lot mission/contrat démarre, lui, avec une mission déjà créée.
- Compléter l’identité de l’établissement ne vaut pas vérification ni signature du contrat de service. Le complément vérifie que la publication reste bloquée, puis injecte explicitement la décision serveur autorisant la publication. Les contrôles externes et la signature du contrat de service ne sont pas accomplis par ce lot.
- L’invitation depuis l’équipe est enregistrée en mémoire. La route distincte `/etab/invitation/:token`, l’acceptation par le destinataire et l’envoi réel d’email ne sont pas couverts par ce fichier ; le lot invitation doit être apprécié séparément. Les espaces groupe et administration ne sont pas dans cet inventaire.
- Les documents à téléverser, paiements/mandats Stripe hébergés, validations INSEE/FINESS/Chorus réelles, alertes email, notifications push, effets asynchrones et protections SQL/RLS réelles ne sont pas prouvés par ces simulations. Les erreurs et autorisations testées sont des réponses serveur préparées ; elles vérifient la réaction de l’interface.

## Défauts établis et corrections

1. Un compte établissement minimal ouvrant directement un profil soignant restait en chargement permanent. `ProfilSoignantEtablissement` utilise maintenant la frontière de compte existante : préparation facultative, navigation libre, aucune lecture métier sans rattachement.
2. « Créer une recherche » dans les recherches sauvegardées établissement renvoyait au tableau de bord. Le bouton mène maintenant à l’annuaire des soignants ; destination soignant inchangée.
3. Une recherche établissement existante n’était pas réappliquée et l’annuaire n’offrait pas de sauvegarde. Il utilise désormais le composant et les RPC existants ; les valeurs réappliquées sont limitées aux types, professions et bornes du formulaire. Les trois tests unitaires de normalisation et le scénario navigateur Save → liste → réappliquer couvrent les dix critères.
4. Une panne de lecture du profil soignant était traitée comme un profil indisponible, sans reprise. Les erreurs des trois lectures sont maintenant distinguées, avec un bouton Réessayer. Reproduction unitaire rouge avant correction puis verte après ; aucun élargissement d’accès.
5. Le bouton Favori confirmait visuellement l’ajout ou le retrait même si le serveur les refusait. Il attend maintenant le succès, conserve l’état antérieur en cas d’erreur et propose de recharger si l’état initial n’a pas pu être lu. Trois tests ciblés couvrent lecture, ajout et retrait en panne.
6. La checklist de première mission affichait « Validé » quand `peut_publier_missions` était nul ou absent, tandis que la bannière indiquait une vérification en cours. Elle exige maintenant `true`, comme le formulaire existant. Aucun droit de publication n’a été changé et le formulaire reste accessible. Quatre tests unitaires couvrent false/null/undefined/true ; le scénario navigateur vérifie les trois valeurs JSON possibles. La fixture complète fournit désormais explicitement true.
7. Avec une mission présente, le dashboard complet plaçait quatre cartes KPI dans la largeur résiduelle de l’iPad portrait, après la barre latérale. La carte « Terminées » s’étendait de 681 à 824,8125 px dans une fenêtre de 820 px ; le conteneur masquait le dépassement et le scrollWidth seul restait 820. La grille conserve maintenant deux colonnes avant le grand écran et chaque carte remplit sa cellule. L’assertion compare les bords réels des quatre cartes au viewport et à leur cellule, en complément de la largeur du document. La preuve rouge précède la correction ; la reprise sur le nouveau bundle est documentée ci-dessous.

Limite préexistante : `fn_compter_nouveaux_pour_filtre` et `fn_obtenir_apercu_filtre` ne prennent que la profession en compte pour les alertes ETAB. Aucun changement backend n’est inclus. L’annuaire explique que sa sauvegarde sert à retrouver ses filtres et ne crée pas d’alerte : `p_alerte_active=false`. La gestion centrale empêche également toute nouvelle activation ETAB, y compris depuis Modifier. Elle conserve les alertes actives, autorise leur désactivation et renomme sans réécrire leur activation. Le comportement soignant demeure inchangé. Sept tests dédiés couvrent les deux interfaces et leurs contrats RPC ; un scénario navigateur supplémentaire couvre la gestion centrale.

## Résultats

Découverte sur Vite8890 : les quatre matrices iPad portrait connexion/inscription × minimal/complet, les onglets/droits/503 et la mission présente sont verts (6/6). Les actions d’invitation, préférences, Chorus et sauvegarde/réapplication sont vertes ; les 19 destinations du menu et retours aussi. Tests unitaires ciblés : 41/41 (24 exploration/profil, 3 normalisation, 3 sauvegarde/alertes, 3 favori, 4 gestion centrale, 4 vérification dashboard). ESLint : aucune erreur, avertissements préexistants uniquement.

La matrice finale de 50 tests (10 × 5 formats) sur le build statique8893 a terminé avec 49 réussites et un arrêt environnemental : le disque plein empêchait l’écriture du dump ARIA `inscription-complet-missions-creer.txt`, puis celle de la trace et du contexte d’erreur (`ENOSPC`, conservé dans le JSON). Aucune assertion UI n’était en échec à cet instant. Après libération d’espace, le scénario entier « inscription complet » iPad portrait a été rejoué sur8895 : 1/1 vert en 55 secondes, avec toutes les assertions sur les 31 routes, les 12 alias et les erreurs intactes.

Le complément de gestion centrale des alertes est vert sur les cinq formats sur le build8894 (5/5), ainsi que le scénario dashboard trois états sur le build8895 (5/5). Les **60 scénarios distincts** du fichier (12 × 5 formats) ont ainsi chacun un résultat vert. La première matrice n’est pas présentée comme un passage 50/50 sans incident. Aucun défaut produit non résolu n’a été constaté dans ces scénarios ; cela ne constitue pas une garantie de perfection de l’application.

Le fichier de complétion ajoute **15 scénarios distincts** (3 × 5 formats), tous verts sur8895 : deux parcours de complétion/mutation et le complément des onglets. Son helper respecte les méthodes autorisées et le contrat de pagination PostgREST : le total `Content-Range` est fourni aux lectures de créneaux. Une omission initiale de cet en-tête dans la fixture provoquait, correctement, l’état d’erreur de lecture du planning ; ce défaut du banc a été corrigé avant la passe 15/15. Aucun succès serveur n’est simulé pour une mission avant que les prérequis soient explicitement préparés.

Après la correction de grille, le scénario d’onglets enrichi de l’assertion géométrique a été rejoué sur le bundle8898 : **5/5 verts**, sans retry, en une minute. Les quatre cartes restent dans leurs cellules et dans le viewport sur les cinq formats ; aucun bouton mesuré du dashboard ne déborde. La capture iPad portrait après correction a également été inspectée. Le lot établissement totalise donc **75 scénarios distincts validés**, plus les reprises ciblées des incidents et du dernier correctif. Il n’affirme pas avoir tout exécuté sur un même bundle ni prouver les systèmes externes.

Preuves de grille archivées dans le dépôt : [iPad avant](assets/2026-09-24-etablissement/dashboard-ipad-avant.png), [iPad après](assets/2026-09-24-etablissement/dashboard-ipad-apres.png), [géométrie avant/après](assets/2026-09-24-etablissement/dashboard-geometrie-avant-apres.json). Sur iPad portrait, la carte « Terminées » passe du bord droit 824,8125 px au bord droit 804 px, dans sa cellule 546–804 px et dans le viewport 820 px. Les vues téléphone et ordinateur conservent également leurs quatre cartes accessibles.

ARIA pour chaque état, captures iPad des rubriques du compte complet et des actions principales. Les captures dashboard, mission, équipe et gestion centrale ont également été inspectées visuellement. Preuves locales conservées :

| Exécution | Résultats et journal | ARIA et captures |
|---|---|---|
| Matrice principale | `/private/tmp/jolene-recette-complete-preuves/etablissement/final-8893/results.json` ; `/private/tmp/jolene-etab-final-8893.log` | `/private/tmp/jolene-recette-complete-preuves/etablissement/final-aria-8893/` |
| Rejeu après ENOSPC | `/private/tmp/jolene-recette-complete-preuves/etablissement/reprise-enospc-8895/results.json` ; `/private/tmp/jolene-etab-reprise-enospc-8895.log` | `/private/tmp/jolene-recette-complete-preuves/etablissement/reprise-aria-8895/` |
| Gestion centrale des alertes | `/private/tmp/jolene-recette-complete-preuves/etablissement/alertes-8894/results.json` ; `/private/tmp/jolene-etab-alertes-8894.log` | `/private/tmp/jolene-recette-complete-preuves/etablissement/alertes-aria-8894/` |
| Vérification dashboard | `/private/tmp/jolene-recette-complete-preuves/etablissement/dashboard-8895/results.json` ; `/private/tmp/jolene-etab-dashboard-8895.log` | `/private/tmp/jolene-recette-complete-preuves/etablissement/dashboard-aria-8895/` |
| Complétion et derniers onglets (15/15) | `/private/tmp/jolene-recette-complete-preuves/etablissement/completion-et-onglets-final-8895/results.json` ; `/private/tmp/jolene-etab-completion-et-onglets-final-8895.log` | `/private/tmp/jolene-recette-complete-preuves/etablissement/completion-et-onglets-final-aria-8895/` |
| Débordement dashboard rempli, preuve rouge avant correction | `/private/tmp/jolene-recette-complete-preuves/etablissement/dashboard-rempli-avant-rouge-8895/results.json` ; `/private/tmp/jolene-etab-dashboard-rempli-avant-rouge-8895.log` | Géométrie JSON jointe au résultat, trace et capture de l’assertion en échec |
| Grille corrigée et derniers onglets (5/5) | `/private/tmp/jolene-recette-complete-preuves/etablissement/onglets-geometrie-final-8898/results.json` ; `/private/tmp/jolene-etab-onglets-geometrie-final-8898.log` | `/private/tmp/jolene-recette-complete-preuves/etablissement/onglets-geometrie-final-aria-8898/` ; mesures avant/après : `/private/tmp/jolene-recette-complete-preuves/etablissement/dashboard-geometrie-avant-apres.json` |

Échecs du banc analysés : le scénario inscription→compte complet et certaines transitions de document détruisaient la page avant ses lectures secondaires. `networkidle` peut être déjà acquis avant une navigation SPA. Le helper suit désormais explicitement les requêtes API en vol, leur achèvement et une fenêtre calme avant chaque `page.goto`/rechargement. Aucune erreur de navigateur n’est filtrée. Les tables de lecture refusent toute mutation non préparée par une réponse501, inscrite dans les écritures/inconnues ; les WebSockets et les connexions anticipées externes sont neutralisés.
