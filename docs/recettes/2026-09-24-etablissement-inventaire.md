# Recette établissement — 24 septembre 2026

## Périmètre et méthode

Base : main 5f88e981, branche `fix/recette-complete-tablette`.

Parcours UI d’entrée : connexion email/mot de passe et inscription rapide établissement. Pour le scénario « inscription → compte complet », le changement de statut serveur est simulé après l’inscription rapide ; le formulaire de complétion lui-même appartient à la recette transversale. Aucune identité réelle ni donnée de production utilisée.

Le helper déclare chaque endpoint. Les appels inconnus obtiennent 501 et font échouer la recette, au lieu de répondre arbitrairement par une liste vide. Auth, parcours, profil, état d’équipe, préférences et réponses métier sont en mémoire. Polices Google neutralisées (police de repli) et chargement Stripe remplacé par un objet inerte : cette recette ne valide ni les pixels de la police distante ni les champs hébergés Stripe. La recette native et les flux financiers sont couverts séparément.

Formats prévus : WebKit iPad 820×1180, iPad 1180×820, iPhone 390×844 ; Chromium desktop 1440×900 et Pixel 7. Les résultats seront renseignés après exécution ; cet inventaire ne constitue pas une affirmation de validation.

## Routes canoniques

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

Les contrats, OTP, mission→présences→facturation et les états financiers avec données sont dans `recette-complete-mission.spec.ts`, autre lot de la même recette. Le présent fichier ne prétend pas reproduire leur backend.

## Défauts établis et corrections

1. Un compte établissement minimal ouvrant directement un profil soignant restait en chargement permanent. `ProfilSoignantEtablissement` utilise maintenant la frontière de compte existante : préparation facultative, navigation libre, aucune lecture métier sans rattachement. Test page ajouté ; 23 tests unitaires de la famille passent.
2. « Créer une recherche » dans les recherches sauvegardées établissement renvoyait au tableau de bord. Le bouton mène maintenant à l’annuaire des soignants ; destination soignant inchangée.
3. Une recherche établissement existante n’était pas réappliquée et l’annuaire n’offrait pas de sauvegarde. Il utilise désormais le composant et les RPC existants ; les valeurs réappliquées sont limitées aux types, professions et bornes du formulaire. Les trois tests unitaires de normalisation et le scénario navigateur Save → liste → réappliquer couvrent les dix critères.
4. Une panne de lecture du profil soignant était traitée comme un profil indisponible, sans reprise. Les erreurs des trois lectures sont maintenant distinguées, avec un bouton Réessayer. Reproduction unitaire rouge avant correction puis verte après ; aucun élargissement d’accès.
5. Le bouton Favori confirmait visuellement l’ajout ou le retrait même si le serveur les refusait. Il attend maintenant le succès, conserve l’état antérieur en cas d’erreur et propose de recharger si l’état initial n’a pas pu être lu. Trois tests ciblés couvrent lecture, ajout et retrait en panne.

Limite préexistante : `fn_compter_nouveaux_pour_filtre` et `fn_obtenir_apercu_filtre` ne prennent que la profession en compte pour les alertes ETAB. Aucun changement backend n’est inclus. L’annuaire explique que sa sauvegarde sert à retrouver ses filtres et ne crée pas d’alerte : `p_alerte_active=false`. La gestion centrale empêche également toute nouvelle activation ETAB, y compris depuis Modifier. Elle conserve les alertes actives, autorise leur désactivation et renomme sans réécrire leur activation. Le comportement soignant demeure inchangé. Sept tests dédiés couvrent les deux interfaces et leurs contrats RPC ; un scénario navigateur supplémentaire couvre la gestion centrale.

## Résultats

Découverte sur Vite8890 : les quatre matrices iPad portrait connexion/inscription × minimal/complet, les onglets/droits/503 et la mission présente sont verts (6/6). Les actions d’invitation, préférences, Chorus et sauvegarde/réapplication sont vertes ; les 19 destinations du menu et retours aussi. Tests unitaires ciblés : 37/37 (24 exploration/profil, 3 normalisation, 3 sauvegarde/alertes, 3 favori, 4 gestion centrale). ESLint : aucune erreur, deux avertissements `reload` préexistants.

Une matrice de 45 tests (9 × 5 formats) s’exécute sur le build statique8891 figé. Un dixième scénario par format a ensuite été ajouté pour fiche présente/favori/503 et sera exécuté sur la dernière révision. Résultats finaux non encore conclus. ARIA pour chaque état ; captures iPad des rubriques du compte complet et des actions principales, ainsi que capture automatique de chaque défaut sur tous les formats.

Échecs du banc analysés : le scénario inscription→compte complet et certaines transitions de document détruisaient la page avant ses lectures secondaires. `networkidle` peut être déjà acquis avant une navigation SPA. Le helper suit désormais explicitement les requêtes API en vol, leur achèvement et une fenêtre calme avant chaque `page.goto`/rechargement. Aucune erreur de navigateur n’est filtrée. Les tables de lecture refusent toute mutation non préparée par une réponse501, inscrite dans les écritures/inconnues ; les WebSockets et les connexions anticipées externes sont neutralisés.
