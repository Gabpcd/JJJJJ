# Audit admin page par page — Session D (11/06/2026)

> Généré par l'inventaire multi-agents D-0 (17 agents, 43 pages, méthode Sprint 11).
> Verdicts « file de travail » : `deja-fait` = la liste met déjà l'action en premier ·
> `a-faire` = refondu pendant la Session D (PRs D-3/D-4/D-5) · `non-applicable` = pas de cycle de vie.
>
> Les corrections appliquées en Session D sont cochées ; le reste constitue le backlog UX admin.

## Synthèse

| Verdict | Pages |
|---|---|
| File de travail déjà en place | 12 |
| Refondues Session D | 17 |
| Non applicable (config/outils/analytique) | 14 |

**203 problèmes de copy** et **242 quick wins** relevés au total (détail par page ci-dessous).


## PoolUrgenceEtablissement

- **Route** : /admin/pool-urgence (avec isAdmin) et /etablissement/pool-urgence — même composant partagé (App.tsx l.317 et l.372, src/routes/adminRoutes.tsx l.40)
- **Rôle** : Voir les soignants ayant activé le pool d'urgence d'un établissement (sélectionnable côté admin), les alerter en push ou leur proposer une mission ouverte, et consulter l'historique des missions urgentes.
- **File de travail** : a-faire
- **Doublons / chevauchements** : Page bi-rôle : la même UI sert /etablissement/pool-urgence et /admin/pool-urgence (prop isAdmin l.64), donc toute refonte impacte les deux. L'historique des urgences est une vue filtrée (est_urgente=true) des mêmes missions que AdminMissions et AdminCalendrier/AdminPlanningGlobal — une urgence OUVERTE apparaît à 3 endroits admin sans lien croisé.
- **Mobile** : Deux <Table> sans alternative cartes mobile (pool l.462-574 : 10 colonnes ; historique l.599-642 : 5 colonnes). Pas de TableOuCartes ni de pattern hidden md:block. Seule la colonne Bio est masquée sous lg (l.473, l.542). Le conteneur overflow-hidden (l.461) risque de couper le tableau au lieu de permettre le scroll horizontal.

### Listes
- 🔧 **Tableau du pool de soignants** (Section principale (l.452-576))
  - Actionnable : Disponible (badge success l.532) — peut être alerté ou recevoir une proposition
  - Reco : Trier les disponibles en premier (puis par distance ou score décroissant), reléguer les « En mission » en bas ou dans une section repliée. Le switch « Disponibles uniquement » (l.446) existe mais n'est pas activé par défaut et l'ordre reste celui de la RPC.
- 🔧 **Historique des urgences** (Section #historique-urgences en bas de page (l.578-644))
  - Actionnable : OUVERTE (badge error l.632) — urgence non pourvue qui demande une action, mais noyée dans la liste chronologique
  - Reco : Scinder en deux : « Urgences à pourvoir » (statut OUVERTE sans soignant_assigne_id) en tête de page, au-dessus même du tableau du pool puisque c'est la raison d'être de la page, puis « Historique » (TERMINEE/ANNULEE) en dessous. Actuellement une urgence ouverte d'il y a 3 semaines est sous les terminées récentes.

### Copy à corriger
- [ ] l.635 : « {h.statut} » — code technique brut affiché à l'écran (TERMINEE, OUVERTE, ANNULEE, sans accents ni libellé français) dans la colonne Statut
- [ ] l.605 + l.611-613 : colonne « Délai de réponse » = données inventées — le calcul est (debut_le − cree_le), soit le délai entre création et début de mission, pas le délai de réponse du soignant (aucun horodatage d'acceptation utilisé)
- [ ] l.307 : l'email envoyé au soignant indique etablissement: 'Pool d'urgence' au lieu du vrai nom de l'établissement — donnée inventée transmise à l'utilisateur final (idem heure_fin: '—' et taux_horaire: '—' l.310-311)
- [ ] l.230 : toast.error(`ID soignant invalide : ${proposerSoignant.soignant_id}`) — expose un UUID brut et du jargon technique à l'écran
- [ ] l.359 « Pool d'urgence » et l.584 « Historique des urgences » : titres orientés catégorie plutôt qu'action (ex. « Trouvez un remplaçant en urgence »)

### Quick wins
- [ ] l.183 et l.199 : send-push envoyé à destinataire_id: s.id (id de la ligne pool) alors que partout ailleurs la personne est identifiée par s.soignant_id (l.241, l.269, l.284, l.303). Si id ≠ soignant_id, les alertes push partent vers un mauvais destinataire — incohérence à vérifier en priorité
- [ ] l.615 : clic sur une ligne d'historique navigue vers /etablissement/missions/${h.id} même quand isAdmin=true — un admin plateforme atterrit sur une route ADMIN_ETABLISSEMENT (probablement bloquée par RouteProtegee), alors que l.484 gère correctement le cas isAdmin
- [ ] l.632 : ternaire mort — h.statut === 'TERMINEE' ? 'info' : ... : 'info' : les deux branches valent 'info', le test TERMINEE ne sert à rien ; et TERMINEE='info' ici vs 'success' dans AdminPlanningGlobal l.44 (incohérence de couleur inter-pages)
- [ ] l.165-169 : KPI « Urgences pourvues ce mois » compte les TERMINEE du mois dans une liste limitée à 20 lignes (l.133) — sous-compte dès que >20 urgences, et « pourvues » devrait inclure ASSIGNEE/EN_COURS
- [ ] l.676 et l.710 : pour l'admin, le bouton « Créer une nouvelle mission » navigue vers /admin/missions (une liste) et perd le contexte soignant_id/profession transmis côté établissement — label/action incohérents ; blocs dupliqués (l.670-682 vs l.703-716)
- [ ] l.494-496 : si fn_obtenir_conversation échoue, aucun toast d'erreur — le bouton Contacter ne fait rien silencieusement
- [ ] l.402 : le KPI « Disponibles maintenant » active le filtre sans mettre à jour l'URL, contrairement au KPI voisin (l.410-411) qui synchronise searchParams — comportement incohérent
- [ ] l.66-68 : Layout redéfini comme nouveau composant à chaque render — provoque un remontage complet du layout à chaque setState

## AdminAPI

- **Route** : /admin/api (App.tsx L364 ; aussi déclaré dans src/routes/adminRoutes.tsx L35, fichier non importé par App.tsx)
- **Rôle** : Documentation des endpoints de l'API REST v1 et gestion (génération, révocation, suppression) des clés API plateforme.
- **File de travail** : non-applicable
- **Doublons / chevauchements** : APIEtablissement.tsx duplique la même constante ENDPOINTS (ses L13-17) avec des descriptions ET des formats de réponse différents ({ "missions": [...], "count": 1 } côté établissement vs { "data": [...] } ici L16-19), ainsi que la même logique de génération via fn_creer_api_key (sa L67). Deux docs divergentes pour la même API — à unifier en une source partagée.

### Listes
- 🔧 **Clés API** (carte « Clés API » (table desktop L168 + cartes mobile L239))
  - Reco : Pattern non pertinent : page de configuration, aucun statut n'attend une action admin. Au mieux, afficher les clés actives avant les désactivées.

### Copy à corriger
- [ ] L136 : Base URL « https://api.jolene.app/v1 » — donnée inventée : la fonction déployée s'appelle api-v1 (supabase/functions/api-v1) et APIEtablissement.tsx L121 affiche la vraie base https://flripxtsyegjshnhzjkz.supabase.co/functions/v1 ; en plus, concaténer cette base avec les chemins /api-v1/missions donnerait l'URL absurde .../v1/api-v1/missions.
- [ ] L16-19 : exemples de réponse au format { "data": [...] } qui contredisent la doc côté établissement ({ "missions": [...], "count": 1 }) — l'un des deux formats est inventé.
- [ ] L327 : placeholder « Ex: Integration SIRH » — manque l'accent : « Intégration ».
- [ ] L207/L245 vs L217/L275-276 : l'état est étiqueté « Désactivée » mais l'action s'appelle « Révoquer » — deux termes pour le même concept sur la même ligne.
- [ ] Jargon (endpoints, GET/POST, JSON) : acceptable, c'est une page technique dont c'est le sujet ; émoji unique L135 « 📖 Endpoints disponibles » conforme.

### Quick wins
- [ ] L103-105 : copier() écrit dans le presse-papiers sans aucun feedback (pas de toast) — sur 6 boutons de copie (L190, L256, L306, L315) l'admin ne sait pas si la copie a réussi.
- [ ] L82 et L93 : confirm() natif du navigateur pour révoquer/supprimer — incohérent avec les modales custom du reste de l'admin (et AdminLevee qui, lui, ne confirme pas du tout).
- [ ] L321 : « Fermer » réinitialise generatedSecret mais pas generatedKey (remis à null seulement à la réouverture L160) — asymétrie fragile sans bug visible aujourd'hui.
- [ ] L36 : keys: any[] — aucun typage des clés alors que la table api_keys est dans les types générés.
- [ ] src/routes/adminRoutes.tsx (L35) redéclare cette route mais n'est importé nulle part — fichier de routes mort à supprimer ou brancher.

## AdminAcquisition

- **Route** : /admin/fondateur/acquisition
- **Rôle** : Analyser la provenance des inscriptions par canal d'acquisition (parrainage, social, paid, SEO, UTM…) sur une période choisie, avec calcul de CAC par canal à partir d'une dépense pub saisie manuellement.
- **File de travail** : non-applicable
- **Doublons / chevauchements** : Chevauchement partiel avec le Cockpit Fondateur (/admin/fondateur) qui affiche déjà un graphique « Acquisition mensuelle » (AdminCockpitFondateur.tsx lignes 172-189) — angles différents (évolution temporelle vs répartition par canal) mais même thème ; un lien croisé entre les deux éviterait la confusion.
- **Mobile** : Le tableau « Détail + CAC par canal » (lignes 143-187) n'a qu'un overflow-x-auto, sans alternative cartes (pas de hidden md:block ni TableOuCartes) — 6 colonnes dont un Input de 96px, scroll horizontal garanti sur mobile. Les labels du PieChart `Nom (valeur)` (ligne 123) débordent du conteneur sur écrans étroits. La rangée de 5 boutons de période + refresh (lignes 64-71) est en flex gap-2 sans flex-wrap, risque de débordement sous ~360px.

### Listes
- 🔧 **Tableau « Détail + CAC par canal »** (Corps de page, sous les graphiques (lignes 135-192))
  - Reco : Non applicable : page analytique pure, aucun statut à traiter. Le pattern file de travail ne s'applique pas.
- 🔧 **Top campagnes (UTM)** (Carte en bas de page, affichée si campagnes.length > 0 (lignes 195-209))
  - Reco : Non applicable : liste de classement, pas de file de travail.

### Copy à corriger
- [ ] Ligne 62 : « D'où viennent tes inscrits — 90 derniers jours » — tutoiement, violation directe de la règle vouvoiement (« vos inscrits »).
- [ ] Lignes 88-89 : « Partage tes liens avec des paramètres ?utm_source=…&utm_campaign=… pour suivre tes campagnes. » — double violation : tutoiement (« Partage tes liens », « tes campagnes ») et paramètres d'URL techniques affichés en clair dans l'interface (balise <code> ligne 89).
- [ ] Ligne 139 : attribut title « Saisis la dépense pub d'un canal pour calculer son coût d'acquisition réel » — tutoiement (« Saisis »).
- [ ] Ligne 197 : « Top campagnes (UTM) » — anglicisme « Top » + sigle technique UTM dans un titre ; tolérable sur une page acquisition mais « Meilleures campagnes » serait plus conforme au ton.

### Quick wins
- [ ] Ligne 35 : l'état `depenses` (dépense pub par canal) n'est jamais persisté — toutes les saisies sont perdues au rechargement de la page, ce qui rend le calcul de CAC à refaire à chaque visite. À persister (table ou localStorage).
- [ ] Lignes 175-176 : effacer le champ Dépense réinjecte 0 (`Number('') === 0` puis `0 ?? ''` affiche « 0 ») — impossible de revider visuellement le champ une fois saisi.
- [ ] Ligne 109 : couleur Établissements codée en dur `#9B5DE5` alors que la barre Soignants utilise le token `hsl(var(--primary))` (ligne 108) et que le Cockpit utilise `--jolene-mauve-500` pour la même série — trois conventions de couleur pour la même entité.
- [ ] Ligne 149 : en-tête « Établ. » vs « Établissements inscrits » (ligne 77) et « Établissements » dans la légende (ligne 107) — libellés différents pour la même chose dans la même page.
- [ ] Ligne 160 : le taux « Activés » ne couvre que les soignants (soignants_actifs / soignants) alors que le CAC ligne 159 divise par soignants + établissements — colonnes voisines avec deux dénominateurs différents, à clarifier dans la note de bas de tableau ligne 189.

## AdminAlertesPointage

- **Route** : /admin/alertes-pointage (App.tsx l.353)
- **Rôle** : Traiter manuellement les alertes anti-fraude de pointage (téléportation GPS, mock GPS, incohérence temporelle, QR éloigné) : consulter, filtrer, puis statuer via une modale de décision (légitime / avertissement / suspension proposée / ignorer).
- **File de travail** : deja-fait
- **Doublons / chevauchements** : Aucun chevauchement direct identifié avec une autre page admin — domaine anti-fraude pointage distinct. À noter : la décision FRAUDE_SUSPENSION_PROPOSEE crée une « task admin » (l.38) dont le suivi se fait probablement ailleurs (lien de suivi absent de cette page).
- **Mobile** : RAS : liste en cartes empilées (pas de table), KPI en grid-cols-2 sur mobile, le bloc JSON des détails a overflow-x-auto (l.183), la modale a max-h-[90vh] + overflow-y-auto.

### Listes
- ✅ déjà en file **Liste des alertes de pointage (cartes CardY2K)** (Corps de page, sous les 5 cartes KPI et les 2 selects de filtre)
  - Actionnable : OUVERTE (resolu_le null) — bouton « Traiter » affiché (l.189-193)
  - Reco : Déjà une file de travail : le filtre statut est initialisé à OUVERTE (l.51), donc seules les alertes à traiter s'affichent par défaut, et le bouton Traiter n'existe que sur les ouvertes. Améliorations : trier les ouvertes par sévérité (CRITICAL avant WARNING/INFO) ; rendre les 5 cartes KPI cliquables pour pré-filtrer ; en vue « Tous statuts », séparer visuellement Ouvertes (haut) et Résolues (historique) au lieu de la seule opacité.

### Copy à corriger
- [ ] l.90 : « Détections Sprint 4.5 : téléportation, mock GPS, cohérence temporelle. Décision admin manuelle. » — jargon interne « Sprint 4.5 » exposé à l'écran + style télégraphique, pas une phrase adressée à l'utilisateur
- [ ] l.169 : le badge affiche la sévérité brute `{a.severite}` → « CRITICAL » / « WARNING » en anglais, enum technique non traduit
- [ ] l.171 : `{a.type_alerte}` affiché brut en font-mono → « TELEPORTATION_DETECTED », « POINTAGE_INCOHERENT » exposés tels quels
- [ ] l.178 : « source : <code>{a.source}</code> » — valeur technique brute affichée dans une balise code
- [ ] l.306 : placeholder « Justification de la décision (audit trail)… » — anglicisme « audit trail »
- [ ] l.38 : « Création task admin pour suspension manuelle » — franglais « task admin », jargon interne dans un libellé visible
- [ ] l.87 : titre « Alertes pointage anti-triche » — orienté catégorie plutôt qu'action (ex. « Traiter les alertes de pointage ») ; « anti-triche » légèrement familier
- [ ] l.121 : « QR > 1km 7j » — libellé KPI cryptique sans explication

### Quick wins
- [ ] l.141-144 vs l.104-124 : le select de type ne propose que TELEPORTATION_DETECTED et POINTAGE_INCOHERENT alors que deux cartes KPI (« Mock GPS 7j », « QR > 1km 7j ») comptent d'autres types — impossible de filtrer sur ces détections ; et les cartes KPI ne sont pas cliquables
- [ ] l.309 : le compteur affiche `{motif.length} / 10+` (longueur brute) alors que la validation (l.247 et l.314) utilise motif.trim().length — le compteur peut afficher ≥ 10 avec un bouton toujours désactivé si le texte est surtout des espaces
- [ ] l.65-67 : l'erreur éventuelle du RPC KPI (resKpi.error) est silencieusement ignorée — seule resListe.error déclenche une notification (l.71-72)

## AdminAuditLogs

- **Route** : /admin/audit
- **Rôle** : Consultation paginée des journaux d'audit RGPD (table journaux_audit) avec recherche, filtres par action, type d'acteur et événement anti-triche.
- **File de travail** : non-applicable
- **Doublons / chevauchements** : Chevauchement partiel avec /admin/alertes-pointage : les mêmes événements anti-triche (TELEPORTATION_DETECTED, GPS_SPOOFING_DETECTED…) y sont traités, ici seulement consultés — sans lien croisé. Chevauchement léger avec /admin/status qui affiche le compteur « Logs 24h → Audit » sans lien vers cette page. /admin/audit-rls (AdminAuditRLS) partage le mot « audit » dans la nav mais couvre un autre domaine — risque de confusion de nommage.

### Listes
- 🔧 **Journaux d'audit** (corps de page via TableOuCartes (l.153-205), pagination 50/page)
  - Reco : Non applicable — c'est l'historique par définition. Au plus : un lien « Traiter les alertes pointage » vers /admin/alertes-pointage quand le filtre anti-triche est actif, pour ne pas laisser croire que le traitement se fait ici.

### Copy à corriger
- [ ] l.107, l.111, l.115, l.138-139, l.170, l.179 : enums techniques bruts exposés à l'écran — filtres et badges affichent RGPD_SUPPRESSION_COMPTE, DONNEES_PERSO_MODIFICATION, ADMIN_PLATEFORME, TELEPORTATION_DETECTED, QR_SCAN_GPS_ELOIGNE tels quels (SNAKE_CASE franglais) au lieu de libellés humains (« Suppression de compte (RGPD) », « Téléportation détectée »…). Page semi-technique, mais ce sont des codes internes, pas le sujet.
- [ ] l.157 : « Aucun log trouvé » — anglicisme « log » ; « Aucun événement trouvé ».
- [ ] l.84 : « Traçabilité RGPD — conservation 5 ans » — durée codée en dur dans la copy ; à vérifier qu'elle correspond à la politique de rétention réelle (règle « jamais de données inventées »).
- [ ] l.83 : titre « Journaux d'audit » — titre catégorie ; tolérable pour un journal, mais « Consulter les journaux d'audit » serait plus conforme à la règle titres orientés action.

### Quick wins
- [ ] l.66 : la recherche est interpolée directement dans `.or(\`action.ilike.%${search}%,type_ressource.ilike.%${search}%\`)` — une virgule ou parenthèse saisie par l'utilisateur casse la syntaxe du filtre PostgREST (requête malformée, résultats vides).
- [ ] l.68 : `const { data } = await query;` — l'erreur Supabase est totalement ignorée ; en cas d'échec la page affiche « Aucun log trouvé » au lieu d'un message d'erreur.
- [ ] l.99 : Entrée dans la recherche appelle charger() sans remettre page à 0 — chercher depuis la page 3 applique l'offset 150 aux résultats filtrés et peut afficher à tort l'état vide.
- [ ] l.86 : bouton Rafraîchir fait `setPage(0); charger();` — charger() part immédiatement avec l'ancienne valeur de page (state asynchrone), puis le useEffect (l.74) relance un second fetch quand page change : double requête et brève incohérence si on n'était pas page 0.
- [ ] l.131 : `cls.includes('red')` dans actionBadgeVariant — aucune valeur d'ACTIONS_COLORS ne contient 'red', condition toujours fausse (code mort).
- [ ] l.14-27 : les classes Tailwind d'ACTIONS_COLORS ne sont jamais appliquées au rendu — la map ne sert qu'à du string-matching (includes 'destructive'/'success'/'warning') pour choisir le variant du badge ; remplacer par une map action → variant directe.
- [ ] l.211 : « {logs.length} résultats — page N » — affiche la taille de la page courante (50), pas le total ; trompeur, utiliser un count exact ou « 50 affichés ».

## AdminAuditRLS

- **Route** : /admin/audit-rls
- **Rôle** : Outil d'inspection sécurité : exécute la RPC d'audit RLS et affiche un verdict global (OK/KO), 2 compteurs (tables sans RLS, RLS active sans policy) et la liste détaillée des tables à problème — lecture seule, la correction passe par migration SQL.
- **File de travail** : deja-fait
- **Doublons / chevauchements** : Aucun doublon avec une autre page admin (AdminHealthcheck ne couvre pas le RLS). Page technique unique en son genre.

### Listes
- ✅ déjà en file **Détail des problèmes (tables sans RLS / sans policy)** (Card « Détail des problèmes » (l.271-325))
  - Actionnable : RLS_DESACTIVEE (risque critique), RLS_ACTIVE_SANS_POLICY (à vérifier, peut être volontaire)
  - Reco : Déjà une file de travail de fait : seules les tables à problème sont listées, les tables saines n'apparaissent pas. Amélioration possible : trier RLS_DESACTIVEE (critique) avant RLS_ACTIVE_SANS_POLICY (souvent volontaire) au lieu de l'ordre brut RPC.

### Copy à corriger
- [ ] l.128-129 : sous-titre « Sprint 3 — <code>fn_audit_rls_strict</code> » — référence de sprint interne et nom de RPC dans le descriptif de page ; même sur une page technique où RLS est le sujet, le planning interne n'apporte rien à l'écran
- [ ] l.140 : libellé de bouton « Rerun audit » — anglicisme, devrait être « Relancer l'audit »
- [ ] l.160 : « Erreur inconnue côté RPC. » — jargon « RPC » dans un message d'erreur (le RLS est le sujet de la page, pas le mécanisme RPC)
- [ ] l.332-334 : « La RPC <code>fn_audit_rls_strict</code> est exécutée côté serveur… » — nom de RPC exposé ; tolérable sur cette page technique mais à reformuler (« L'audit est exécuté côté serveur… »)

### Quick wins
- [ ] l.49-58 : fonction libelleProbleme jamais appelée nulle part dans le fichier — code mort (badgeProbleme l.60-77 la remplace) ; en plus elle libelle « RLS active sans policy » là où le badge dit « Sans policy » : deux libellés pour la même chose
- [ ] l.115 + l.196-205 : en cas d'erreur RPC (isError), data est undefined donc verdictOK=false → la carte Verdict affiche « KO — 0 problème(s) détecté(s) » alors que l'audit n'a pas tourné ; état trompeur (l'alerte d'erreur s'affiche au-dessus mais les KPI montrent un faux résultat)
- [ ] l.230 et l.260 : même cas d'erreur, les compteurs affichent « 0 » en vert (text-green-700) — faux signal rassurant pendant une erreur
- [ ] l.283-289 : condition « !data || data.problemes.length === 0 » — en cas d'erreur RPC, la card détail affiche le check vert « Aucun problème détecté. Toutes les tables publiques sont protégées » : faux positif de sécurité, la branche !data devrait être distinguée de la branche liste-vide

## AdminCalendrier

- **Route** : /admin/calendrier (App.tsx l.370 + src/routes/adminRoutes.tsx l.38 — déclaration en double)
- **Rôle** : Vue calendrier mensuelle de toutes les missions de la plateforme, avec badges-stats cliquables servant de filtres par statut et mise en évidence des missions non pourvues.
- **File de travail** : non-applicable
- **Doublons / chevauchements** : Fort chevauchement avec /admin/planning-global (AdminPlanningGlobal.tsx : vue hebdomadaire des MÊMES missions groupées par jour, via RPC fn_admin_planning_global) et /admin/missions (vue liste). Calendrier et Planning global sont deux visualisations temporelles de la même donnée — candidats à fusion. Route déclarée deux fois (App.tsx l.370 et adminRoutes.tsx l.38).
- **Mobile** : Grille de 7 colonnes en min-w-[320px] (l.205, 214) sans conteneur overflow-x-auto — risque de débordement sous 320 px ; chips de mission en text-[8px] (l.239) pratiquement illisibles sur mobile ; aucune vue alternative liste/agenda pour petit écran.

### Listes
- ✅ déjà en file **Grille calendrier mensuelle (missions par cellule jour)** (Corps de page, sous la barre de stats, la navigation mois et la légende)
  - Actionnable : OUVERTE sans soignant (« Non pourvue ») — rouge destructive + bordure rouge de la cellule jour (l.34-36, l.225), missions est_urgente — préfixe 🚨 (l.242)
  - Reco : L'actionnable est déjà mis en avant visuellement (badge « non pourvues » en première position, couleur destructive, bordure de cellule). À corriger pour parfaire le pattern : prioriser non pourvues et urgentes dans le slice(0,4) de chaque cellule (l.234) — aujourd'hui le tri par debut_le peut masquer une non pourvue derrière « +N » pendant que des terminées s'affichent ; et ajouter les filtres « Ouverte » et « Annulée » manquants pour aligner badges et légende.

### Copy à corriger
- [ ] l.44 : fallback `label: m.statut` — un statut non mappé (ex. EXPIREE) s'afficherait en enum brut à l'écran
- [ ] l.240 : tooltip « · NON POURVUE » en majuscules criardes, incohérent avec le libellé « Non pourvue » de la légende (l.35, l.121)
- [ ] l.135 : titre « Calendrier des missions » — orienté catégorie (mineur, acceptable pour une visualisation) ; à noter trois libellés différents pour la même page : usePageTitle « Calendrier missions » (l.49), h1 « Calendrier des missions » (l.135), breadcrumb « Calendrier » (l.133)

### Quick wins
- [ ] l.38 : branche OUVERTE avec soignant assigné → libellé « Ouverte » warning — état vraisemblablement impossible (une mission OUVERTE n'a pas de soignant_assigne_id), branche probablement morte ; et aucun badge-filtre « Ouverte » n'existe (l.138-174) alors que la légende l'affiche (l.122)
- [ ] l.120-127 vs l.138-174 : la légende liste 6 statuts mais seuls 4 sont filtrables (pas de filtre Ouverte ni Annulée) — incohérence légende/filtres
- [ ] l.160-166 : badge « terminées » en variant info (bleu) alors que la légende rend Terminée en gris (l.125) ; « assignées » et « terminées » ont la même couleur de badge — deux codages couleur contradictoires pour le même statut
- [ ] l.234 : msDuJour.slice(0, 4) sans priorisation — une mission non pourvue peut être cachée derrière « +N » (voir workQueueSuggestion)
- [ ] l.115-118 : les compteurs de la barre de stats sont calculés sur toute la plage de la grille (semaines débordant sur les mois adjacents, l.58-59) et non sur le mois affiché — les chiffres ne correspondent pas exactement au mois annoncé

## AdminChorusPro

- **Route** : /admin/chorus-pro
- **Rôle** : Piloter l'intégration Chorus Pro (facturation secteur public) : KPIs, suivi des soumissions de factures, configuration par établissement, test de connexion PISTE et synchronisation manuelle des statuts.
- **File de travail** : a-faire
- **Doublons / chevauchements** : L'onglet « Config établissements » gère la même table chorus_pro_config que la page côté établissement /etablissement/chorus-config (App.tsx l.316, composant ChorusConfig, rôle ADMIN_ETABLISSEMENT) — audiences différentes mais double point de saisie de la même config. Léger chevauchement aussi avec /admin/facturation : les soumissions concernent les factures_honoraires qui y sont listées (le statut Chorus, lui, n'est visible qu'ici).

### Listes
- 🔧 **10 dernières submissions (onglet Dashboard)** (Onglet Dashboard, section l.193-249)
  - Actionnable : rejected, error, pending_credentials
  - Reco : Liste purement chronologique tous statuts mélangés. Remplacer « 10 dernières » par « À traiter » : les rejected/error/pending_credentials d'abord (avec lien direct vers le détail pour re-soumettre), et reléguer le flux chronologique en dessous. Les KPIs « Rejetées/Err » et « Erreurs 7j » (l.187-188) signalent le problème mais ne sont pas cliquables et ne mènent nulle part.
- 🔧 **Soumissions Chorus (onglet Submissions)** (Onglet Submissions, l.326-437)
  - Actionnable : rejected, error, pending_credentials
  - Reco : Tri chronologique pur : une facture rejetée d'il y a 3 semaines passe sous les acceptées d'hier. Ajouter une section « À traiter » en tête (rejected + error + pending_credentials, triées par ancienneté) avec le bouton Re-soumettre accessible directement, puis « En cours » (pending/submitted), puis « Historique » (accepted) replié ou paginé.
- 🔧 **Config établissements secteur public** (Onglet Config établissements, l.484-570)
  - Actionnable : non configuré (pas de chorus_pro_config, l.508), configuré mais inactif (cfg.actif = false)
  - Reco : Tri alphabétique : les établissements « non configuré » sont noyés au milieu des actifs. Mettre en tête les étabs secteur public sans config ou inactifs (ceux qui bloquent l'envoi de factures), les configurés actifs en dessous. Le KPI « Étabs configs X/Y » (l.189) donne déjà le ratio mais sans lien vers cette liste.

### Copy à corriger
- [ ] l.124 : onglet « Dashboard » — anglicisme, titre catégorie (préférer « Vue d'ensemble »)
- [ ] l.125 : onglet « Submissions » — mot anglais à l'écran (préférer « Soumissions »)
- [ ] l.184 : KPI « Total submissions » — anglais
- [ ] l.187 : KPI « Rejetées/Err » — abréviation cryptique « Err »
- [ ] l.189 : KPI « Étabs configs » — double abréviation illisible
- [ ] l.153 : message d'erreur « Erreur RPC fn_admin_chorus_stats : … » — jargon « RPC » + nom de fonction SQL exposés à l'écran
- [ ] l.172 : « vérifiez que raw_app_meta_data->>'role' = 'ADMIN_PLATEFORME' (cf. docs/admin-setup.md) » — colonne SQL et chemin de doc interne affichés dans l'UI
- [ ] l.155 : « connectez-vous avec un compte ADMIN_PLATEFORME » — nom technique de rôle exposé
- [ ] l.94 : toast « Mode simulation : credentials PISTE absents » — anglicisme « credentials » (l.339 aussi : option « Credentials manquants »)
- [ ] l.96 : « Sync OK : X vérifiées, Y mises à jour, Z notifs » — télégraphique, « Sync » et « notifs » (idem l.114-117 « Sync… » / « Sync maintenant »)
- [ ] l.299 : confirm « Reset de l'idempotence + re-soumettre cette facture à Chorus Pro ? » — « reset de l'idempotence » est du pur jargon technique présenté à l'admin
- [ ] l.314 et l.318 : toasts « Resubmit OK : … » / « Resubmit erreur : … voir logs » — franglais + « voir logs »
- [ ] l.206, l.361, l.493 : en-tête de colonne « Étab » et l.486 « chaque étab destinataire » — abréviation dans du texte rédigé

### Quick wins
- [ ] l.299 : window.confirm() natif au lieu d'un AlertDialog shadcn — incohérent avec le reste de l'UI admin
- [ ] l.177-179 : le statut pending_credentials (présent dans le filtre l.339) n'est compté dans aucun KPI (« En cours » = pending+submitted seulement) — les soumissions bloquées faute de credentials sont invisibles sur le dashboard
- [ ] l.272-280 et l.446-455 : l'erreur Supabase de charger() est ignorée (seul data est testé) — en cas d'échec la page affiche « Aucune soumission. » / « Aucun établissement secteur public. », état vide trompeur
- [ ] l.159 : idem dans DashboardChorus, rRes.error ignoré pour les 10 dernières soumissions
- [ ] l.333-345 : <select className="input-base"> HTML brut alors que le reste de l'app utilise le Select shadcn — incohérence visuelle
- [ ] l.146, l.274, l.302, l.448, l.466 : casts « as any » généralisés sur les appels Supabase (tables/RPC absents des types générés) — masque toute erreur de typage
- [ ] l.313 : test hétérogène d.success || d.accepted sur la réponse de submit-to-chorus — fragile, deux formats de réponse acceptés

## AdminCockpitFondateur

- **Route** : /admin/fondateur
- **Rôle** : Dashboard stratégique fondateur : KPIs de croissance (soignants, établissements, MRR, missions), graphiques acquisition/revenue, unit economics & runway calculés côté client, et raccourcis vers Équipe, Levée de fonds et Cohortes.
- **File de travail** : non-applicable
- **Doublons / chevauchements** : Page hub assumée, mais trois chevauchements : (1) KPIs GMV/totaux soignants/étabs déjà présents sur AdminDashboard /admin (gmv_total ligne 290 d'AdminDashboard.tsx) ; (2) stats du pipeline investisseurs (lignes 79-84) recalculées côté client à partir de la même table investisseurs_pipeline que AdminLevee /admin/fondateur/levee ; (3) graphique « Acquisition mensuelle » (lignes 172-189) chevauche AdminAcquisition /admin/fondateur/acquisition (angle temporel vs angle canal). Plus la divergence de calcul du coût équipe avec AdminEquipe (voir fiche AdminEquipe).

### Copy à corriger
- [ ] Ligne 235 : « 0 € (organique) » affiché comme valeur de CAC alors que le CAC n'est jamais calculé (toujours 0 en dur, ligne 58) — donnée inventée présentée comme une métrique réelle ; idem le ratio « ∞ » ligne 236.
- [ ] Ligne 120 : label « MRR » — la valeur est en réalité revenue_total ÷ nombre de mois d'historique (ligne 50), soit un revenu mensuel moyen, pas un MRR. Métrique mal étiquetée = donnée trompeuse, surtout sur une page « métriques Série A ». Idem « ARR » ligne 121 (moyenne × 12).
- [ ] Lignes 163, 194, 203 : « Revenue total (commissions) », « Revenue mensuel (commissions HT) », « Revenue HT » — anglicisme « Revenue » dans une app entièrement en français ; écrire « Revenus ».
- [ ] Lignes 17-23 + 227 : charges fixes codées en dur dans le frontend (Supabase 25 €, Resend 20 €, Lovable 20 €, Apple 8 €) et affichées dans « Charges totales /mois » — chiffres figés qui dériveront de la réalité (données potentiellement inventées à terme), et formule Stripe heuristique ligne 52 présentée comme un coût réel.

### Quick wins
- [ ] Ligne 58 : `const cac = data.total_etabs > 0 ? 0 : 0;` — ternaire dont les deux branches valent 0, le CAC est toujours 0. Conséquence : lignes 59, 235 et 236, les branches `cac > 0` sont du code mort (jamais vraies), `ltvCacRatio.toFixed(1)` n'est jamais affiché.
- [ ] Ligne 12 : `LineChart` et `Line` importés de recharts mais jamais utilisés (seuls BarChart et AreaChart sont rendus) — imports morts.
- [ ] Ligne 10 : `BadgeY2K` importé mais jamais utilisé dans le JSX — import mort.
- [ ] Lignes 81 et 83 : `pipelineStats.total` et `pipelineStats.signes` calculés mais jamais affichés — code mort.
- [ ] Lignes 81-82 vs 260-261 : incohérence — le texte affiche « X investisseurs actifs · Y € visés » mais montantVise somme TOUT le pipeline (y compris DECLINE et SIGNE, ligne 82) alors que le compte ne garde que les actifs (ligne 81). Le montant visé devrait être filtré sur les mêmes statuts.
- [ ] Lignes 17-22 : le champ `label` des CHARGES_FIXES_MENSUELLES n'est jamais rendu (seul TOTAL_FIXES l'est, ligne 227) — données mortes.
- [ ] Ligne 56 : `const arr = mrrAnnualise;` — alias redondant.

## AdminCohortEconomics

- **Route** : /admin/cohort (App.tsx:381)
- **Rôle** : Dashboard analytique en lecture seule pour les investisseurs : cohortes mensuelles, rétention soignants, unit economics et GMV/commissions.
- **File de travail** : non-applicable
- **Doublons / chevauchements** : Les métriques GMV/commissions recoupent AdminCockpitFondateur.tsx et AdminDashboard.tsx (seules autres pages admin manipulant la GMV). La vocation « métriques pour les investisseurs » (l.47) est adjacente à AdminLevee.tsx (pipeline investisseurs + data room) — candidate à un regroupement dans un même espace.
- **Mobile** : Aucune table ; graphiques recharts en ResponsiveContainer et KPIs en grid-cols-2 sur mobile — rien de bloquant. Mineur : 24 mois sur l'axe X risque d'être illisible sur écran étroit (pas de rotation/échantillonnage des ticks).

### Copy à corriger
- [ ] l.19 et l.46 : titres en anglais « Cohort & Unit Economics » / « Cohort Analysis & Unit Economics » dans une app entièrement française, et orientés catégorie plutôt qu'action
- [ ] l.67 : « Revenue (commissions) » — anglicisme (« Revenus » attendu)
- [ ] l.84 : « Take rate par transaction » — jargon anglais exposé à l'écran
- [ ] l.87-88 : « Taux complétion » et « Taux annulation » affichent « 0% » quand la valeur est absente (`ue.taux_completion ?? 0`) au lieu de « — » comme le fait fmt() l.13-16 — un 0% inventé est une donnée trompeuse

### Quick wins
- [ ] l.127-128 : les deux barres « Soignants » et « Établissements » du graphique « Inscriptions par cohorte » ont le même fill #E04590 — indistinguables visuellement
- [ ] l.162-163 : même bug sur « Utilisateurs actifs par mois » (« Soignants actifs » et « Étab. actifs » tous deux #E04590)
- [ ] l.109-110, l.127-128, l.145, l.162-163 : couleurs hex codées en dur (#E04590, #10B981) alors que le reste du graphique utilise les variables CSS du thème (var(--border), var(--muted-foreground)) — incohérence en thème sombre
- [ ] l.26 + l.35 : cliquer « Rafraîchir » (l.55) remet loading=true et remplace TOUTE la page par ChargementPage — flash complet au lieu d'un rafraîchissement en place
- [ ] l.22 : data typé any sans validation de la forme du retour RPC — toute évolution du RPC casse silencieusement les graphiques
- [ ] Aucun état vide : si le RPC renvoie 0 cohortes, tous les graphiques disparaissent (conditions l.100/118/135/153) et il ne reste que des cards à « — »/0% sans message
- [ ] Pas de BreadcrumbAdmin contrairement à AdminGroupes (l.250 là-bas) — incohérence de navigation admin
- [ ] La page est absente du nouveau fichier src/routes/adminRoutes.tsx (qui référence AdminGroupes l.13/36 mais pas AdminCohortEconomics) — risque d'oubli si la migration des routes hors App.tsx se poursuit

## AdminConformite

- **Route** : /admin/conformite
- **Rôle** : Tableau de bord conformité réglementaire : 7 indicateurs (violations repos 11h, alertes plafond 48h, documents expirés, documents en attente, CDD répétitifs, soignants sans documents, missions sans contrat) sous forme de cartes-compteurs colorées par sévérité, chaque carte se dépliant en liste détaillée avec liens vers les fiches soignant/mission/établissement.
- **File de travail** : deja-fait
- **Doublons / chevauchements** : « Documents en attente » duplique en lecture seule la file de validation de /admin/moderation (AdminModeration.tsx interroge documents_soignants avec statut_verification = 'EN_ATTENTE', l.100-102, onglet Documents l.315). « Missions sans contrat » chevauche le périmètre de /admin/contrats. Le reste (repos 11h, 48h, CDDU) est propre à cette page.

### Listes
- ✅ déjà en file **Violations repos 11h** (Carte-compteur dépliable (indicateur l.61-73, rendu l.247-316))
  - Actionnable : toutes les lignes (violations détectées à investiguer)
  - Reco : Déjà une file de travail : seules les violations sont listées. Les lignes n'offrent que des liens de navigation, pas d'action de résolution/acquittement — pas de moyen de marquer une violation comme traitée.
- ✅ déjà en file **Alertes 48h** (Carte-compteur dépliable (l.74-86))
  - Actionnable : toutes les lignes (dépassement du plafond hebdomadaire)
  - Reco : Déjà actionnable à 100 %. Suggestion : trier par heures_semaine décroissant pour mettre les pires dépassements en premier.
- ✅ déjà en file **Documents expirés** (Carte-compteur dépliable (l.87-100))
  - Actionnable : toutes les lignes (document à faire renouveler par le soignant)
  - Reco : Déjà actionnable. Suggestion : trier par valide_jusqua croissant (expiré depuis le plus longtemps en premier).
- ✅ déjà en file **Documents en attente** (Carte-compteur dépliable (l.101-114))
  - Actionnable : toutes les lignes (documents EN_ATTENTE de validation admin)
  - Reco : Liste 100 % actionnable mais sans action : la validation se fait sur /admin/moderation (onglet Documents). Lien direct vers la file de modération à ajouter, ou supprimer ce doublon (voir duplicateOverlap).
- ✅ déjà en file **CDD répétitifs (risque requalification CDI)** (Carte-compteur dépliable (l.115-128))
  - Actionnable : toutes les lignes (couples soignant/établissement à surveiller juridiquement)
  - Reco : Déjà actionnable. Suggestion : trier par nb_missions décroissant (risque le plus fort en premier).
- ✅ déjà en file **Soignants sans documents** (Carte-compteur dépliable (l.129-144))
  - Actionnable : toutes les lignes (soignants à relancer, lien mailto fourni l.139-141)
  - Reco : Déjà actionnable (relance par email). Les colonnes Mission/Établissement (l.136-137) sont vraisemblablement toujours vides pour un soignant sans documents — à vérifier côté RPC et retirer si c'est le cas.
- ✅ déjà en file **Missions sans contrat** (Carte-compteur dépliable (l.145-157))
  - Actionnable : toutes les lignes (contrat à générer)
  - Reco : Déjà actionnable mais sans raccourci vers la génération de contrat (/admin/contrats). Suggestion : trier par debut_le croissant (missions qui démarrent le plus tôt en premier).

### Copy à corriger
- [ ] l.70 : badge « Résultat » affiche la valeur brute i.resultat renvoyée par la RPC, sans mapping vers un libellé français — risque d'exposer un code technique à l'écran
- [ ] l.154 : badge « Statut » affiche le statut de mission brut i.statut (enum technique type EN_COURS) sans traduction, contrairement aux autres pages admin
- [ ] l.219 : titre de page « Conformité » — orienté catégorie plutôt qu'action (ex. « Traiter les alertes de conformité »)

### Quick wins
- [ ] l.181-187 : si fn_admin_conformite échoue, l'erreur part en console.warn et data reste null → tous les compteurs affichent 0 en vert « tout va bien » sans aucun message d'erreur à l'écran — faux signal rassurant
- [ ] l.199 : l'erreur de fn_admin_conformite_detail est ignorée (seul data est destructuré) → en cas d'échec, detail = [] et la page affiche « Aucun élément à afficher » alors que le compteur de la carte peut montrer un nombre > 0 — incohérence compteur/détail
- [ ] l.253 : le badge « X élément(s) » du panneau détail utilise le compteur global mappedData[selected] et non detail.length — les deux RPC pouvant diverger, le badge peut contredire la liste affichée
- [ ] l.55-58 : LienEtablissement pointe vers /admin/utilisateurs/${etablissement_id}, exactement comme LienSoignant — à vérifier que l'id d'établissement est bien un id de profil utilisateur, sinon tous les liens établissement sont cassés
- [ ] l.22-27 : champ rpcCle de l'interface Indicateur + double lookup l.209 (data[ind.cle] ?? data[ind.rpcCle]) — béquille défensive qui masque l'incertitude sur la forme de réponse de la RPC ; à figer côté SQL puis simplifier
- [ ] typage any généralisé : render (item: any) l.17, detail any[] l.177, réponse RPC castée any l.181 — aucune sécurité de type sur les 7 formes de lignes

## AdminContrats

- **Route** : /admin/contrats (App.tsx L351)
- **Rôle** : Lister tous les contrats de mission de la plateforme avec recherche, filtre statut et pagination, plus une action valider/refuser le contrat-cadre d'un établissement.
- **File de travail** : a-faire
- **Doublons / chevauchements** : Les boutons Valider/Refuser (L212-220) appellent fn_admin_valider_contrat_etablissement, qui valide le contrat-cadre de l'ÉTABLISSEMENT — fonctionnalité qui appartient à AdminVerificationEtablissements.tsx (qui affiche déjà le badge contrat_valide, L178 de ce fichier). Placer cette action sur chaque ligne de contrat de mission est un doublon trompeur.

### Listes
- 🔧 **Contrats (TableOuCartes)** (Corps de page unique, sous les filtres)
  - Actionnable : EN_ATTENTE_SIGNATURE_SOIGNANT, EN_ATTENTE_SIGNATURE_ETAB, SIGNE_COMPLET avec DPAE manquante sur CDD/SALARIE (badge ⏳ L171)
  - Reco : Section « À traiter » en tête : contrats EN_ATTENTE_SIGNATURE_* triés par ancienneté + contrats CDD/SALARIE signés sans numéro DPAE (obligation légale). Section « Historique » repliée : SIGNE_COMPLET ok, ANNULE, EXPIRE. Le filtre statut actuel (défaut « Tous », L52) peut rester pour l'historique.

### Copy à corriger
- [ ] L135 : le select de filtre affiche les codes bruts « EN_ATTENTE_SIGNATURE_SOIGNANT », « SIGNE_COMPLET », etc. (`<option>{s}</option>`) — codes techniques d'enum SQL exposés à l'écran, aucun libellé français
- [ ] L163 : le badge statut affiche « {statut} » brut (SIGNE_COMPLET, ANNULE…) — même violation jargon dans le tableau et les cartes (L241)
- [ ] L113 : « Consultation de tous les contrats Jolene avec hash SHA-256 + certificat + audit trail. » — « audit trail » est un anglicisme technique, et le sous-titre décrit une catégorie au lieu d'orienter l'action
- [ ] L110 : titre « Contrats » — orienté catégorie, pas action (ex. « Suivre les signatures de contrats »)
- [ ] L172 : « N/A » — anglicisme, préférer « — » ou « Sans objet »

### Quick wins
- [ ] BUG MAJEUR L212-220 : Valider/Refuser s'affichent sur TOUTE ligne dont statut !== 'SIGNE_COMPLET' — y compris ANNULE et EXPIRE où valider le contrat-cadre établissement n'a aucun sens. Pire : cliquer « Valider » sur un contrat en attente de signature ne change pas le statut de CE contrat (le RPC agit sur l'établissement), donc après le toast « Contrat validé » (L97) la ligne reste identique — l'admin croit que l'action a échoué
- [ ] L93 vs L68 : deux systèmes de notification mélangés dans le même fichier — toast (sonner) pour la validation, afficherNotification pour le chargement
- [ ] L57 : commentaire interne « Task 9 » laissé dans le code (aussi L85, L272)
- [ ] L40 : le filtre propose 'EXPIRE' exact alors que le badge teste statut?.startsWith('EXPIRE') (L160), ce qui suggère des variantes (EXPIRE_X) que le filtre ne capturerait pas

## AdminDPIA

- **Route** : /admin/dpia (App.tsx:379)
- **Rôle** : Page documentaire statique : l'analyse d'impact RGPD (DPIA, art. 35) du traitement « vérification automatisée des documents soignants par IA », en 5 sections (description, proportionnalité, risques, droits, conclusion).
- **File de travail** : non-applicable
- **Doublons / chevauchements** : Pas de doublon fonctionnel : la DPIA n'apparaît ni dans AdminRGPDTools.tsx ni dans AdminConformite.tsx (vérifié par grep). Simple adjacence thématique avec /admin/rgpd-tools et /admin/conformite — un regroupement de navigation « Conformité » pourrait les rapprocher, sans fusion nécessaire.

### Listes
- 🔧 **Risques identifiés et mesures** (Section 3 (l.48-106) — tableau desktop + cartes mobile)
  - Reco : Non pertinent : document de conformité figé, aucune ligne n'appelle d'action admin. Le pattern file de travail ne s'applique pas ici.

### Copy à corriger
- [ ] l.116 : « (fn_supprimer_mon_compte) » — nom de fonction SQL exposé à l'écran ; la page est juridique (RGPD est le sujet), pas une page technique base de données.
- [ ] l.117 : « action DOCUMENT_VERIFICATION_AUTO » — code d'action interne brut (majuscules + underscores) dans un document juridique.
- [ ] l.57 et l.58 : « Verdict EN_ATTENTE » — valeur d'enum interne exposée telle quelle ; un libellé humain (« en attente de revue manuelle ») suffirait.
- [ ] l.24 et l.58 : « fallback » — anglicisme/jargon technique (« solution de repli »).
- [ ] l.35 : « cross-check » — anglicisme (« recoupement »).
- [ ] l.54 : « Documents FAIBLE confiance » — enum brut FAIBLE + formulation télégraphique (« documents à faible niveau de confiance »).

### Quick wins
- [ ] l.34-38 et l.53-58 : champ `ok: true` défini sur chaque item mais jamais lu — le CheckCircle est rendu inconditionnellement (l.41, l.80, l.93). Code mort, et si un risque devenait non couvert l'UI serait incapable de l'afficher autrement qu'en vert.
- [ ] l.135 : dates « réalisée le 09/04/2026 — Prochaine révision : 09/04/2027 » codées en dur — aucun rappel automatique à l'échéance de révision, maintenance manuelle.
- [ ] l.51 : IIFE inline dans le JSX pour déclarer les données de risques — à extraire en constante de module pour la lisibilité (même pattern que CHARGES_FIXES côté dashboard).

## AdminDashboard

- **Route** : /admin (App.tsx:342)
- **Rôle** : Tableau de bord global admin : KPI plateforme, alertes urgentes (litiges, impayés), CA/GMV, simulateur de rentabilité SASU, paiements Stripe/Connect, et trois listes de synthèse (inscriptions, litiges, factures).
- **File de travail** : deja-fait
- **Doublons / chevauchements** : Les blocs litiges (l.239 et l.580) naviguent vers /admin/moderation alors qu'une page dédiée /admin/litiges existe (App.tsx:348) — les deux pages traitent les litiges (grep : 49 occurrences dans AdminModeration.tsx, 19 dans AdminLitiges.tsx), doublon Modération/Litiges à arbitrer. Les cartes CA dupliquent en résumé /admin/finances et /admin/facturation (acceptable pour un dashboard : clic = navigation). Le simulateur de rentabilité n'existe nulle part ailleurs (vérifié : absent d'AdminFinances, AdminCockpitFondateur, AdminCohortEconomics).
- **Mobile** : Rien de bloquant : pas de table HTML, listes en cartes flex, grilles responsive (grid-cols-2 → lg:grid-cols-4), graphiques Recharts dans ChartContainer w-full.

### Listes
- 🔧 **Dernières inscriptions (soignants + établissements)** (Grille 3 colonnes en bas de page, 1re carte (l.549-574))
  - Reco : Non nécessaire : aucune action admin attendue sur cette liste. Si la validation des nouveaux établissements demande une action, c'est la page /admin/verification-etablissements qui porte la file, pas ce flux.
- ✅ déjà en file **Litiges ouverts** (Grille 3 colonnes en bas de page, 2e carte (l.576-590) + carte d'alerte en haut (l.238-247))
  - Actionnable : OUVERT, EN_DISCUSSION, EN_MEDIATION, CONTESTEE
  - Reco : Déjà filtré sur les seuls statuts actionnables et remonté en carte d'alerte en haut de page. Raffinement possible : trier par cree_le croissant (le litige qui attend depuis le plus longtemps en premier) et placer OUVERT/CONTESTEE avant EN_DISCUSSION/EN_MEDIATION.
- ✅ déjà en file **Factures impayées** (Grille 3 colonnes en bas de page, 3e carte (l.592-606) + carte d'alerte en haut (l.248-256))
  - Actionnable : EN_RETARD (à relancer), EMISE (suivi — pas encore en retard si non échue)
  - Reco : Déjà une file (filtre EMISE/EN_RETARD, tri par échéance). À affiner : distinguer visuellement EN_RETARD (action : relance) des EMISE non échues (simple suivi) — actuellement tout est présenté comme « impayée / en retard de paiement » (l.252-254).

### Copy à corriger
- [ ] l.268-269 : tutoiement — « Commission Jolene = ce que tu gardes » et « tu ne le touches pas » — violation du vouvoiement, et incohérent avec l.420 « votre revenu total estimé est de … » (mélange tu/vous sur la même page).
- [ ] l.197 : « Dashboard Admin » — anglicisme + titre catégorie non orienté action (attendu : « Tableau de bord » ou mieux, un titre orienté action).
- [ ] l.583 : statuts de litige affichés bruts ({l.statut} → « OUVERT », « EN_DISCUSSION », « EN_MEDIATION », « CONTESTEE ») — valeurs d'enum SQL avec underscores exposées à l'écran sans libellé humain.
- [ ] l.556 et l.567 : badges {s.profession} et {e.type} affichent les valeurs brutes de la base (enums non traduits en libellés).
- [ ] l.252-254 : « X facture(s) impayée(s) » + « En retard de paiement » alors que la requête (l.91) inclut le statut EMISE — une facture émise non échue n'est pas « en retard » : copy factuellement trompeuse.

### Quick wins
- [ ] l.81 : variable `today` calculée puis jamais utilisée — code mort.
- [ ] l.239/l.580 : navigation litiges vers /admin/moderation alors que /admin/litiges existe — incohérence de cible (voir doublon).
- [ ] l.471 : titre « 💳 Paiements Stripe » cumule l'icône CreditCard ET l'émoji 💳 — redondance visuelle (le bloc Stripe Connect l.511 n'a que l'icône : incohérent entre les deux cartes).
- [ ] l.82-151 : aucune des 11 requêtes Supabase ne vérifie .error — en cas d'échec, la page affiche silencieusement 0/« — » sans message.
- [ ] l.94-104 : la rentabilité agrège toutes les missions TERMINEE côté client sans pagination — au-delà de la limite de lignes par défaut de l'API, le CA affiché sera silencieusement faux.
- [ ] l.28-33 + l.158 : charges fixes et formule de frais Stripe (1.4 % + 0,25 €) codées en dur dans le front, mise à jour manuelle requise (le commentaire l.27 le reconnaît).

## AdminDemo

- **Route** : /admin/demo
- **Rôle** : Page outil : charger ou purger un jeu de données de démonstration pour les démos investisseurs, avec rappel des compteurs globaux de la base.
- **File de travail** : non-applicable
- **Doublons / chevauchements** : Les 4 cartes KPI dupliquent les compteurs d'AdminDashboard (même RPC fn_admin_kpi utilisé dans /Users/gabrielle/Documents/GitHub/jolene-v2/src/pages/admin/AdminDashboard.tsx). Doublon mineur et assumé (vérifier l'effet du chargement/purge), mais doublon quand même.

### Listes
- 🔧 **État actuel de la base (4 cartes KPI : soignants, établissements, missions, factures)** (section « État actuel de la base » (lignes 70-107))
  - Reco : Non applicable : pas de liste d'items à traiter, uniquement des compteurs.

### Copy à corriger
- [ ] Ligne 34 : « Données de démo chargées — 4 établissements, 12 soignants, 35 missions » — chiffres codés en dur côté front, pas issus de la réponse du RPC : si le jeu de données seed évolue, le toast affichera des données inventées.

### Quick wins
- [ ] Ligne 65 : « Purger la démo » est destructif et s'exécute sans aucun modal de confirmation (contrairement aux autres actions destructives admin qui passent par ModalConfirmation).
- [ ] Ligne 7 : imports morts — Card, CardContent, CardHeader, CardTitle importés et jamais utilisés.
- [ ] Ligne 20 : l'erreur de fn_admin_kpi est silencieusement ignorée (pas de toast), seul le fallback « Impossible de charger les KPI. » ligne 105 en témoigne.
- [ ] Ligne 34 : compteurs codés en dur dans le toast de succès (voir copyIssues) — le RPC devrait renvoyer les volumes réellement insérés.

## AdminDetailContrat

- **Route** : /admin/contrats/:id (App.tsx L352)
- **Rôle** : Afficher le détail complet d'un contrat : parties, hash d'intégrité, signatures, DPAE, PDF embarqué et journal d'audit.
- **File de travail** : non-applicable
- **Mobile** : Pas de table — cards et grids responsive (grid-cols-1 md:grid-cols-2 L139). L'iframe PDF h-[600px] (L257) est étroite mais utilisable. RAS.

### Listes
- 🔧 **Signatures détaillées (collapsible)** (Card « Signatures », details/summary L218-235)
  - Reco : Non pertinent : liste de preuves, pas de file de travail.
- 🔧 **Audit trail** (Dernière card de la page, L262-287)
  - Reco : Non pertinent : journal historique.

### Copy à corriger
- [ ] L221 : « {n} signature(s) dans signatures_contrats (OTP / PSC) » — nom de table SQL « signatures_contrats » exposé à l'écran, violation directe de la règle
- [ ] L265 : « Audit trail ({n}) » — anglicisme technique en titre de section ; « Historique des actions » conviendrait
- [ ] L203 : « UA : {navigateur} » — abréviation technique user-agent affichée sans explication
- [ ] L279-281 : JSON.stringify(a.details) brut affiché à l'écran — données techniques non mises en forme

### Quick wins
- [ ] L239-249 : la section DPAE affiche « ⏳ DPAE non encore transmise / numéro non saisi » mais n'offre AUCUN bouton pour saisir le numéro URSSAF — cul-de-sac : l'état actionnable est montré sans action possible
- [ ] L100-104 : si createSignedUrl échoue (path présent mais fichier absent), aucun message — la card « PDF contrat » disparaît silencieusement, l'admin ne sait pas qu'un PDF devrait exister
- [ ] L61 : champ acteur_id de AuditRecord typé mais jamais affiché (seul type_acteur l'est, L275) — l'admin ne peut pas savoir QUI a agi
- [ ] L86/L92 : message d'erreur générique « Erreur. » remonté tel quel (error.message brut du RPC, potentiellement en anglais)

## AdminDetailUtilisateur

- **Route** : /admin/utilisateurs/:id
- **Rôle** : Fiche détaillée d'un utilisateur (soignant ou établissement) : infos, documents, missions, score, profil complet et actions admin (suspension, reset mot de passe, RIB, suppression).
- **File de travail** : a-faire
- **Doublons / chevauchements** : Doublon interne : l'onglet « Informations » (lignes 375-408) et l'onglet « Profil complet » (lignes 618-725) affichent en grande partie les mêmes champs (email, téléphone, RPPS, ADELI, rayon, dates, commission…). Chevauchement externe léger : l'onglet Documents recoupe la file de validation de documents d'AdminModeration (consultation ici vs action là-bas) — complémentaire plutôt que doublon.

### Listes
- 🔧 **Documents du soignant** (onglet « Documents » (soignant uniquement))
  - Actionnable : statut_verification en attente (non VALIDE/REJETE), documents expirés (valide_jusqua < aujourd'hui), documents manquants (signalés dans la bannière lignes 343-362, pas dans la liste)
  - Reco : Trier/sectionner : d'abord « À vérifier » (en attente + expirés), puis « Historique » (validés/rejetés). La bannière d'alerte (ligne 343) fait déjà la moitié du travail pour manquants/expirés ; la liste elle-même reste un tri chronologique pur. Nuance : la validation des documents se fait sur une autre page (AdminModeration), ici c'est de la consultation.
- 🔧 **Historique des missions** (onglet « Missions »)
  - Reco : Non pertinent ici : liste purement consultative, aucune action admin par ligne. Le tri antichronologique convient à un historique.

### Copy à corriger
- [ ] Ligne 236 : « La suppression définitive nécessite une action manuelle dans le dashboard Supabase pour des raisons de sécurité. » — jargon technique (Supabase, dashboard) exposé à l'écran dans un toast.
- [ ] Ligne 248 : « Fonctionnalité de promotion admin — utilisez la fonction set-user-claims via le dashboard Supabase. » — nom de fonction technique et Supabase exposés à l'écran.
- [ ] Ligne 805 : « Cette action nécessite une intervention manuelle dans Supabase. » — jargon technique dans le message du modal de suppression.
- [ ] Lignes 768 et 271 : « Forcer re-upload RIB » / « Re-upload RIB forcé » — franglais technique (« re-upload ») ; préférer « re-téléversement ».
- [ ] Ligne 517 (et 529) : les statuts de mission non mappés (ANNULEE, LITIGE…) s'affichent en code brut SQL (m.statut) dans le badge.
- [ ] Ligne 648 : « Statut vérification ARIA » affiche la valeur brute statut_verification_aria (code enum interne) sans libellé.
- [ ] Lignes 384 et 634 : la profession est affichée en valeur enum brute (ex. INFIRMIER) sans libellé formaté.
- [ ] Ligne 638 : « Rayon déplacement » avec fallback `|| 30` invente une valeur (30 km) quand la donnée est nulle — règle « jamais de données inventées ».

### Quick wins
- [ ] BUG MAJEUR — modals jamais rendus : modalLeverSuspension et modalForceRib (états lignes 39-42) sont passés à true par les ActionCards lignes 762 et 771, mais aucun <ModalConfirmation> ne les consomme dans le JSX (seuls modalSuspendre ligne 787 et modalSupprimer ligne 800 sont rendus). Les boutons « Lever la suspension » et « Forcer re-upload RIB » ne font donc rien de visible, et leverSuspension (251-262) / forcerReuploadRib (264-274) sont du code mort inatteignable. Le Textarea importé ligne 25 (prévu pour la raison) n'est jamais rendu non plus.
- [ ] Ligne 235-237 : supprimerCompte ne supprime rien — le modal de confirmation « Supprimer » (ligne 800) débouche sur un simple toast d'erreur. Confirmation trompeuse pour une action qui n'existe pas.
- [ ] Ligne 247-249 : promouvoirAdmin est un bouton sans action réelle (toast.info renvoyant vers Supabase).
- [ ] Lignes 4 et 7 : double import du même client supabase (supabaseClient et supabase depuis @/integrations/supabase/client).
- [ ] Imports morts : Star et Award (ligne 3, jamais utilisés — l'onglet s'appelle « Score & Badges » mais aucun badge n'est affiché), Separator (ligne 19), AdminMissionChatPanel (ligne 26).
- [ ] Ligne 112 vs 388/638 : incohérence rayon de déplacement — ligne 388 affiche `${soignant.rayon_deplacement_km} km` sans fallback (peut afficher « null km »), ligne 638 invente 30 km par défaut.
- [ ] Ligne 843 : VerifRow utilise le variant « info » pour « ✗ Non » — une vérification manquante mérite warning/error, incohérent avec le « ✓ Oui » en success.
- [ ] Ligne 517 : tous les badges de statut mission utilisent variant="info" quel que soit le statut (Terminée, En cours… même couleur).

## AdminEditerTemplateContrat

- **Route** : /admin/templates-contrats/:id (App.tsx L350)
- **Rôle** : Éditer le nom et le contenu HTML d'un modèle de contrat, avec aperçu et insertion de variables.
- **File de travail** : non-applicable
- **Mobile** : Pas de table. La grille lg:grid-cols-[1fr,280px] (L139) s'empile correctement en mobile ; le textarea font-mono min-h-[400px] reste utilisable. RAS.

### Listes
- 🔧 **Variables disponibles (sidebar)** (Aside droit, L176-193)
  - Reco : Non pertinent : page d'édition d'un seul élément.

### Copy à corriger
- [ ] L135 : « Audit complet via journaux_audit (admin + ancienne/nouvelle version). » — nom de table SQL « journaux_audit » exposé à l'écran dans le bandeau d'avertissement
- [ ] L116 : « Type <code>{template.type_contrat}</code> » — code d'enum brut (ex. REMPLACEMENT_LIBERAL) affiché sans libellé ; tolérable sur une page technique mais à harmoniser

### Quick wins
- [ ] BUG L123 : le bouton Enregistrer est disabled quand contenuHtml === template.contenu_html — si l'admin modifie UNIQUEMENT le nom (champ L143), le bouton reste désactivé et le renommage est impossible à sauvegarder alors que le RPC accepte p_nom (L88)
- [ ] L82 : confirm() natif au lieu de ModalConfirmation — incohérence avec le reste de l'admin
- [ ] L24-41 vs L195-202 : deux sources de vérité pour les variables — la liste codée en dur VARIABLES_DISPONIBLES et template.variables venant de la base (« Variables originales ») ; si elles divergent, l'admin insère des variables non supportées par le template
- [ ] L99-101 : insererVariable ajoute toujours en fin de contenu (prev + ' ' + v), jamais au curseur — l'admin doit couper-coller ensuite (le libellé L179 l'assume, mais c'est une ergonomie pauvre)
- [ ] L3 : import Loader2 jamais utilisé
- [ ] L156-160 : aperçu via dangerouslySetInnerHTML du HTML stocké en base — surface XSS si un contenu de template est altéré côté base ; à assainir (DOMPurify) même si seuls les admins éditent

## AdminEmails

- **Route** : /admin/emails (App.tsx L363 ; aussi déclaré dans src/routes/adminRoutes.tsx L34, fichier non importé)
- **Rôle** : Prévisualiser les 14 templates d'emails transactionnels, s'envoyer un email de test, et consulter les 20 derniers envois.
- **File de travail** : a-faire
- **Doublons / chevauchements** : AdminDetailUtilisateur.tsx (sa L105) consulte aussi emails_envoyes mais filtré par utilisateur — complémentaire plutôt que doublon, pas de chevauchement réel.

### Listes
- 🔧 **Templates emails** (haut de page (TableOuCartes, L131))
  - Reco : Pattern non pertinent : catalogue statique de 14 templates avec boutons Prévisualiser/Tester.
- 🔧 **Derniers emails envoyés** (section « Historique » en bas de page (TableOuCartes, L241))
  - Actionnable : tout statut != ENVOYE (échecs d'envoi à investiguer/relancer)
  - Reco : Remonter les envois en erreur dans une section « À traiter » en tête (avec la colonne erreur, déjà sélectionnée L79 mais jamais affichée), reléguer les ENVOYE en historique. La limite de 20 par date peut masquer entièrement des échecs plus anciens.

### Copy à corriger
- [ ] L138, L173, L206, L251, L263 : identifiants de templates bruts en SCREAMING_SNAKE_CASE (« BIENVENUE_SOIGNANT », « MISSION_ACCEPTEE_SOIGNANT ») exposés partout en font-mono — borderline : page technique dont c'est le sujet, mais un libellé français à côté de l'identifiant rendrait la page lisible.
- [ ] L120 : « Prévisualisez et testez les 14 templates transactionnels » — le compte 14 est exact (vérifié, 14 clés L15-30) mais le chiffre est codé en dur : utiliser TEMPLATES.length pour éviter une donnée fausse au prochain ajout.

### Quick wins
- [ ] L86-107 : envoyerTest n'a aucun try/catch — si le fetch L91 rejette (erreur réseau), setSending(null) L100 n'est jamais exécuté : tous les boutons « Envoyer » restent désactivés (disabled={sending !== null}, L158/L188) avec un spinner bloqué jusqu'au rechargement.
- [ ] L234-239 : tout statut différent de 'ENVOYE' est affiché « Erreur » — un éventuel état intermédiaire (file d'attente, en cours) serait faussement présenté en échec.
- [ ] L79 : colonnes sujet, erreur, provider_id, destinataire_id sélectionnées mais jamais affichées — en particulier erreur, qui serait précieuse à côté du badge « Erreur » (sur-fetch + info utile perdue).
- [ ] L99-102 : l'objet error construit avec le code HTTP n'est jamais montré ; le toast L102 reste générique — le diagnostic (HTTP 4xx/5xx) est jeté.
- [ ] L80-81 : limite fixe de 20 sans pagination ni lien « voir plus » — l'historique au-delà est inaccessible depuis cette page.

## AdminEquipe

- **Route** : /admin/fondateur/equipe
- **Rôle** : Gérer les membres de l'équipe admin : création de compte employé (auth + accès RBAC via périmètres), modification, désactivation, et simulateur de coût salarial total.
- **File de travail** : a-faire
- **Doublons / chevauchements** : Chevauchement léger avec le Cockpit Fondateur (/admin/fondateur) : les deux calculent un coût d'équipe, mais avec deux méthodes différentes — AdminEquipe calcule côté client brut × 1,45 (lignes 30, 70-73), le Cockpit affiche charges_equipe_mensuel renvoyé par la RPC fn_admin_cockpit_fondateur (AdminCockpitFondateur.tsx ligne 227). Risque de chiffres divergents entre les deux pages pour la même métrique.
- **Mobile** : Pas de table (cartes partout, OK). Deux grilles non adaptatives : simulateur de coût en grid-cols-3 fixe même sur mobile (ligne 166, trois cellules très étroites < 400px), et formulaire en grid-cols-2 fixe sur mobile (lignes 232 et 253).

### Listes
- 🔧 **Liste des membres de l'équipe** (Corps de page, sous la carte « Coût total de l'équipe » (lignes 184-217))
  - Actionnable : Actif (badge success ligne 192) — modifiable et désactivable
  - Reco : Pattern file de travail peu pertinent ici (page référentiel, rien ne « demande une action »), mais version douce applicable : trier les membres actifs en premier et reléguer les Désactivés dans une section repliée « Anciens membres » au lieu de les laisser mélangés par date d'embauche avec opacité 50%.

### Copy à corriger
- [ ] Ligne 123 : toast « Compte employé créé (auth + accès). » — « auth » est du jargon technique exposé à l'écran ; préférer « Compte et accès créés. »
- [ ] Ligne 122 : toast `Erreur : ${err.message}` — message d'erreur Supabase brut (anglais, technique) affiché tel quel à l'utilisateur ; idem ligne 131 toast.error(error.message).
- [ ] Ligne 150 : titre « Gestion de l'équipe » — titre catégorie plutôt qu'orienté action (mineur).
- [ ] Ligne 26 : description de périmètre « Système : conformité, audits, emails, API » — « API » est du jargon technique affiché dans le formulaire ; acceptable si le périmètre couvre réellement une page API, sinon reformuler.

### Quick wins
- [ ] Lignes 263-266 vs 110-118 : le champ « Date d'embauche » est affiché aussi en mode création, mais la RPC fn_admin_creer_compte_employe ne reçoit aucun paramètre date d'embauche — la valeur saisie est silencieusement perdue à la création. Soit passer la date à la RPC, soit masquer le champ en création.
- [ ] Lignes 129-134 + formulaire 231-285 : désactivation irréversible depuis l'UI — le formulaire d'édition n'expose aucun toggle « actif », donc aucun moyen de réactiver un membre désactivé (le payload ligne 99 conserve juste la valeur existante). Ajouter un bouton « Réactiver » ou un switch dans le formulaire.
- [ ] Ligne 208 : `!m.user_id?.startsWith('09e82688')` — UUID du compte fondateur codé en dur côté frontend pour masquer le bouton Désactiver ; fragile (protection UI uniquement, et magic string). À remplacer par un flag en base ou une vérification serveur.
- [ ] Lignes 129 + 209 : « Désactiver » est destructif mais s'exécute sans aucune confirmation (pas de dialog).
- [ ] Ligne 151 : `membres.filter(m => m.actif).length` calculé trois fois dans le même paragraphe — à factoriser dans une variable.

## AdminFacturation

- **Route** : /admin/facturation (confirmé dans App.tsx:359)
- **Rôle** : Suivre et gérer toutes les factures établissements : génération mensuelle automatique, confirmation/rejet des virements déclarés, prélèvement SEPA, téléchargement PDF et exports comptables (FEC, rapport mensuel).
- **File de travail** : a-faire
- **Doublons / chevauchements** : Chevauchement avec AdminImpayees (/admin/impayees) qui charge aussi factures aux statuts EMISE/EN_RETARD avec actions de relance et « Marquer EN_RETARD » (AdminImpayees.tsx lignes 80-82, 475), et avec AdminFinances qui recalcule les impayées EMISE/EN_RETARD en KPI (AdminFinances.tsx lignes 98, 166). Le cycle de vie d'une facture est éclaté sur 3 pages.

### Listes
- 🔧 **Factures (table desktop lignes 459-609 + cards mobile lignes 612-779, avec sélection bulk et détail missions dépliable)** (Corps de page unique, pas d'onglets — filtres statut + recherche au-dessus)
  - Actionnable : VIREMENT_DECLARE (boutons Confirmer/Rejeter, lignes 532-576 desktop et 702-745 mobile), EN_RETARD (impayée à relancer — mais l'action de relance n'existe pas sur cette page, elle vit dans AdminImpayees)
  - Reco : Liste plate triée par date : une facture VIREMENT_DECLARE (seule à exiger une action admin immédiate) peut être noyée en page 3. Créer une section « À traiter » en tête : d'abord VIREMENT_DECLARE, puis EN_RETARD ; reléguer EMISE/PAYEE/ANNULEE/BROUILLON dans un bloc « Historique » en dessous (tri date_emission desc conservé dans chaque section). Le filtre statut existant (ligne 435) peut rester pour la recherche ponctuelle.

### Copy à corriger
- [ ] Ligne 438 : le filtre statut affiche les valeurs brutes de l'enum SQL — « {s === 'TOUS' ? 'Tous statuts' : s} » rend « VIREMENT_DECLARE », « EMISE », « PAYEE » à l'écran alors que statutLabel (lignes 36-43) existe juste au-dessus. Jargon technique exposé.
- [ ] Ligne 253 : le PDF facture remis au client imprime le statut brut — « addLine('Statut :', facture.statut || '—') » peut afficher « VIREMENT_DECLARE » dans un document officiel.
- [ ] Ligne 383 : idem dans le rapport mensuel PDF — « doc.text(f.statut || '—', 180, y) ».
- [ ] Lignes 527 et 699 : « Réf: {f.virement_reference} » — pas d'espace avant les deux-points, incohérent avec la typographie française utilisée ailleurs dans le même fichier (« Heures : », « Taux : », lignes 92-95).
- [ ] Ligne 397 : titre de page « Facturation » = catégorie, pas orienté action (ex. « Suivre et encaisser les factures »).
- [ ] Ligne 755 : « Masquer missions » / « Voir missions » — articles manquants (« Voir les missions »), style télégraphique.

### Quick wins
- [ ] Ligne 438 : remplacer le statut brut par statutLabel[s] dans le Select — fix d'une ligne.
- [ ] Lignes 296-298 + 316-319 : limit(500) sans pagination — les cartes « Total HT / Total TTC » (lignes 426-427) totalisent au plus 500 factures : chiffres silencieusement faux dès que le volume dépasse 500.
- [ ] Lignes 540-575 vs 710-743 : handlers Confirmer/Rejeter virement copiés-collés intégralement entre desktop et mobile — à factoriser en une fonction (risque de divergence à la prochaine évolution).
- [ ] Lignes 29-34 : statutColor donne la même couleur 'info' à BROUILLON, EMISE et ANNULEE — une facture annulée est visuellement indistinguable d'une facture émise.
- [ ] Lignes 276-277 : toast.success(« Facture … téléchargée ») émis immédiatement alors que telechargerOuPartagerPdf est asynchrone et appelé en void — le succès est annoncé avant (et même si) le téléchargement échoue.
- [ ] Ligne 27 : EN_RETARD est filtrable mais aucune action de relance n'existe sur la page — état actionnable sans handler local (l'action vit dans AdminImpayees), incohérence de périmètre.

## AdminFinances

- **Route** : /admin/finances
- **Rôle** : Tableau de bord financier de la plateforme : KPIs commissions du mois, récap tout temps, graphique 6 mois, diagnostic de cohérence financière (missions/factures/Stripe) et table analytique par établissement.
- **File de travail** : non-applicable
- **Doublons / chevauchements** : Fort chevauchement avec /admin/facturation : mêmes factures, mêmes montants HT/TVA/TTC, et 4 des 5 KPI cards + « CA HT total » naviguent vers /admin/facturation (l.247, 261, 267, 295). Le KPI « Factures impayées » (l.273-283) et la colonne « Impayés » dupliquent /admin/impayees (calcul EMISE/EN_RETARD identique, l.98). Rôle assumé de hub, mais 3 pages calculent chacune leurs impayés de leur côté.
- **Mobile** : RAS : TableOuCartes avec renduCarte dédié (l.447, l.487-533), sélecteur de tri spécifique mobile (l.422-444), grilles KPI en grid-cols-2, graphique en w-full. Pas de table brute sans alternative.

### Listes
- 🔧 **Détail par établissement (TableOuCartes)** (section bas de page « Détail par établissement »)
  - Actionnable : lignes avec impayes > 0 (bouton rouge vers /admin/impayees, l.476-481 et l.519-528)
  - Reco : Table analytique, pas une vraie file de travail — la file impayés vit déjà sur /admin/impayees. Si on applique quand même le pattern : remonter en tête (ou dans un bandeau « À traiter ») les établissements avec impayes > 0, le reste trié par commissions HT comme aujourd'hui.
- ✅ déjà en file **Diagnostic de cohérence — échantillons d'anomalies (missions incohérentes, factures avec écart, transferts Stripe orphelins)** (carte « Diagnostic de cohérence financière », affichée après clic sur « Lancer le diagnostic »)
  - Actionnable : toute anomalie listée (count > 0) est par définition à corriger
  - Reco : Déjà conforme : n'affiche que des anomalies actionnables, avec état vide positif. Seule limite : les échantillons ne sont pas cliquables vers la mission/facture concernée.

### Copy à corriger
- [ ] l.345 : « Lance l'analyse de cohérence entre missions, factures et transferts Stripe. » — tutoiement (« Lance ») au lieu du vouvoiement (« Lancez l'analyse… »).
- [ ] l.286-287 (avec l.117) : « Taux com. moyen » affiche 15,0 % grâce au fallback codé en dur `: 15` même quand aucune donnée n'existe — donnée inventée à l'écran.
- [ ] l.295-300 : « CA HT total », « TVA total », « CA TTC total », « Encaissé TTC » annoncent des totaux tout temps alors que la requête est plafonnée à 200 factures (l.56) — chiffres présentés comme exhaustifs mais potentiellement faux.
- [ ] l.68 : toast « Erreur chargement finances » — style télégraphique, ni chaleureux ni grammatical ; préférer « Impossible de charger les finances ».
- [ ] l.234 : titre « Finances Jolene » — titre catégorie, pas orienté action (mineur pour un dashboard).
- [ ] l.401 : « Mission {t.mission_id?.slice(0, 8)}… » — fragment d'UUID brut affiché à l'écran ; tolérable car la section diagnostic est technique, mais un lien nommé serait mieux.

### Quick wins
- [ ] BUG export CSV : `numero_facture` n'est jamais sélectionné dans la requête factures (l.53-54) mais utilisé à l.193 — la colonne « N° Facture » du CSV est toujours vide.
- [ ] Code mort : `toggleSort` (l.183-186) n'est appelé nulle part — aucun tri par clic d'en-tête sur desktop, seul le select mobile (l.424-443) change le tri.
- [ ] `.limit(200)` sur factures (l.56) et missions (l.60) sans pagination ni `order` côté missions : récap tout temps, graphique 6 mois et table par établissement deviennent silencieusement faux dès 200+ lignes.
- [ ] l.254-257 : quand variationPct === 0, l'icône TrendingUp s'affiche quand même à côté du « — » (état visuel incohérent).
- [ ] Fallback taux commission 15 dupliqué en dur (l.117 et l.155, et encore dans AdminImpayees l.360) — à centraliser dans une constante.
- [ ] l.426 : le select mobile change sortKey sans réinitialiser sortDir en desc, contrairement à la logique de toggleSort — comportement de tri incohérent entre les deux chemins.
- [ ] l.214 : `supabase.rpc('fn_diagnostic_coherence_financiere' as any)` — cast `as any`, types Supabase non régénérés (dette mineure).

## AdminGroupes

- **Route** : /admin/groupes (App.tsx:365 et src/routes/adminRoutes.tsx:36)
- **Rôle** : Fiche CRM par groupe de santé : KPIs missions/CA par groupe, détail par clinique, édition des taux de commission (groupe et clinique) et envoi d'emails ad hoc.
- **File de travail** : a-faire
- **Doublons / chevauchements** : Édition des taux de commission (groupe + clinique) duplique /admin/taux-commission (AdminTauxCommission.tsx, même RPC fn_admin_modifier_taux_commission l.96 là-bas). Les KPIs payé/impayé recoupent AdminFinances, AdminFacturation et AdminImpayees (vers lesquels les KPIs naviguent d'ailleurs, l.332/340/348). L'envoi d'email ad hoc recoupe AdminEmails (même edge function send-email).
- **Mobile** : Rien de bloquant : pattern hidden md:block (l.403) + cartes mobile (l.508) en place, table desktop sous overflow-x-auto. Mineur : les cartes mobile n'affichent pas le nb de missions terminées ni de KPI cliquable.

### Listes
- 🔧 **Cartes groupes de santé** (Corps de page, une CardY2K par groupe (l.260-614))
  - Actionnable : CA impayé > 0 (factures EMISE/EN_RETARD, l.124) — relance à faire, Missions en cours (OUVERTE/ASSIGNEE/EN_COURS, l.118) — suivi
  - Reco : Trier les groupes par CA impayé décroissant (ou badge « À traiter » sur les groupes avec impayés) au lieu de l'ordre alphabétique. Léger : la vraie file de relance vit déjà dans /admin/impayees.
- 🔧 **Tableau « Détail par clinique » (desktop) + cartes cliniques (mobile)** (Dans chaque carte groupe (table l.403-505, cartes l.508-610))
  - Actionnable : ca_impayees > 0 (montant rouge l.439, bordure destructive mobile l.512)
  - Reco : Trier les cliniques par ca_impayees décroissant puis nb_missions_en_cours, le reste en dessous. Le signal visuel existe (rouge/bordure) mais l'ordre reste alphabétique, donc les impayés peuvent être noyés en bas.

### Copy à corriger
- [ ] l.368 : « BFA éligible — projection calculable via fn_calculer_bfa » — nom de fonction SQL/RPC exposé à l'écran, violation directe de la règle « jamais de jargon technique »
- [ ] l.190 et l.213 : toast.error((data as any)?.error || 'Erreur') — le message d'erreur brut du backend est affiché tel quel (risque de jargon technique), et le fallback « Erreur » seul est trop sec
- [ ] l.253 : titre « Groupes de santé » orienté catégorie plutôt qu'action (mineur pour une page fiche)

### Quick wins
- [ ] l.226-235 : envoyerEmail ne vérifie pas l'erreur retournée par supabase.functions.invoke (qui ne throw pas) — toast.success « Email envoyé à N destinataire(s) » même si tous les envois ont échoué
- [ ] l.118 vs l.316 : le KPI « En cours » compte OUVERTE+ASSIGNEE+EN_COURS mais son clic navigue vers ?statut=EN_COURS, qui ne filtre que le statut EN_COURS dans AdminMissions (FILTRES l.18-23 là-bas) — le compte affiché ne correspond pas à la liste obtenue
- [ ] l.330-361 : les KPIs CA commissions/Payées/Impayées/Soignants naviguent vers les pages globales SANS filtre ?groupe=, alors que les 3 premiers KPIs passent bien ?groupe=${g.id} — incohérence de navigation
- [ ] l.291 : le taux « groupe » pré-rempli = taux de la PREMIÈRE clinique (g.cliniques[0]?.taux_commission_negocie ?? 15) car la requête l.76 ne sélectionne pas taux_commission_negocie sur groupes_sante — trompeur si les cliniques ont des taux différents (AdminTauxCommission lit lui le vrai taux groupe)
- [ ] l.443-455 et l.536-548 : l'édition du taux clinique n'a AUCUN bouton Annuler ni gestion d'Escape — une fois en mode édition, impossible de sortir sans enregistrer (l'édition groupe a son Annuler l.288)
- [ ] l.67-68 : emailSubject/emailBody partagés entre tous les formulaires — le texte saisi pour un groupe réapparaît dans le formulaire d'une clinique et inversement
- [ ] l.84-167 : boucle for séquentielle avec await par groupe (3 requêtes × N groupes) — chargement lent dès quelques groupes, parallélisable avec Promise.all

## AdminHealthcheck

- **Route** : /admin/healthcheck
- **Rôle** : Pinger en direct ~11 services externes/internes (DB, Auth, Edge Functions, Stripe, Twilio, Document AI, Resend, PSC, Chorus Pro, RPPS, Sentry) avec latence, plus deux outils manuels : diagnostic Pro Santé Connect isolé et envoi d'un SMS de test.
- **File de travail** : a-faire
- **Doublons / chevauchements** : Fort chevauchement avec /admin/status (AdminStatus.tsx) : deux pages « santé système » côte à côte — healthcheck pinge les services côté client, status agrège DB/crons/webhooks/alertes via RPC. Les deux ont chacune un outil Sentry et un horodatage de dernière vérification. Doublon interne en plus : PSC est testé deux fois sur la même page (card warm psc-authorize l.100-114 ET card diagnostic psc-test-connexion l.314-377). À fusionner ou au minimum lier par navigation croisée.

### Listes
- 🔧 **Grille des services (cards de statut)** (corps de page, grille 1/2/4 colonnes (l.292-312))
  - Actionnable : error (« Erreur »), degraded (« Dégradé »)
  - Reco : Trier error → degraded → ok (ou bandeau « À traiter » listant uniquement les services en alerte sous le résumé l.285-289 qui compte déjà les alertes mais ne les isole pas). Faible priorité : 11 cards max, toutes visibles, code couleur déjà présent.

### Copy à corriger
- [ ] l.20 et l.272 : titre « Healthcheck Services » — franglais et titre catégorie, pas orienté action (ex. « Vérifier la santé des services »). Note : page technique, le jargon HTTP/env vars dans les détails (l.63, 110, 150) est acceptable ici car c'est le sujet.
- [ ] l.212 : fallback anglais exposé à l'écran — `data.error || 'Twilio rejected'` ; devrait être en français.
- [ ] l.388 : « Coût ~0.045€ » — chiffre codé en dur dans la copy, risque de dériver du tarif Twilio réel (règle « jamais de données inventées »).
- [ ] l.388 : « préchargé depuis votre profil si admin = soignant » — formule télégraphique « admin = soignant », pas le ton chaleureux/pro attendu.
- [ ] l.274/279/304 vs l.335/409 : incohérence typographique « Vérification... » (trois points) vs « Vérification… » (caractère ellipse).

### Quick wins
- [ ] l.71-75 : le check Twilio SMS pousse toujours status 'ok' — `supabase.functions.invoke` ne lève pas d'exception sur erreur (il renvoie { error }), or seul `data` est destructuré ; un send-sms en panne s'affiche « Opérationnel » avec détail « Réponse inattendue ».
- [ ] l.94-98 : même bug pour Resend Email — `error` jamais lu, le catch ne se déclenche quasiment jamais, le service est de facto toujours « Opérationnel ».
- [ ] l.103-104 : même bug pour PSC — si invoke échoue, `data` est undefined donc `configured = (undefined !== false) = true` → affiché « ok / Credentials ANS configurés » alors que l'appel a échoué.
- [ ] l.141-151 : verify-rpps — `error` ignoré ; en cas d'échec d'appel le détail affiché est « ESANTE_FHIR_API_KEY manquante », diagnostic faux (la clé n'est pas forcément manquante, l'appel a juste échoué).
- [ ] l.5 : import `Loader2` jamais utilisé (code mort).
- [ ] l.264 : `statusIcon` ne mappe pas 'degraded' (tombe sur Clock par défaut, même icône que 'loading') — un service dégradé affiche une horloge, ambigu.
- [ ] l.54-55 : Edge Functions considérées « ok » pour tout status < 500 — un 404 (fonction supprimée) s'afficherait « Opérationnel ».
- [ ] l.220-221 : une réponse SMS inattendue est stockée `ok: true` et rendue dans le style succès vert (l.413) alors qu'elle devrait être au minimum neutre/avertissement.
- [ ] l.296 : `key={i}` (index) sur la grille des services.

## AdminHeuresExternes

- **Route** : /admin/heures-externes
- **Rôle** : Trancher (valider/rejeter) les déclarations d'heures externes du parcours 3200h laissées EN_ATTENTE par la vérification IA.
- **File de travail** : deja-fait
- **Mobile** : Cartes responsive (flex-col sm:flex-row l. 124), pas de table — RAS.

### Listes
- ✅ déjà en file **Déclarations d'heures externes** (Liste de cartes unique, filtres boutons En attente / Validées / Rejetées / Toutes (l. 97-103))
  - Actionnable : EN_ATTENTE (bouton « Traiter » l. 181-183, carte surlignée ambre l. 121-123)
  - Reco : Déjà une file de travail via le filtre défaut EN_ATTENTE. Amélioration : en vue « Toutes », trier les EN_ATTENTE en tête (aucun tri client l. 117, l'ordre serveur n'est pas garanti) ou les séparer en section « À traiter » au-dessus de l'historique.

### Copy à corriger
- [ ] l. 90 : « Heures externes — parcours 3200h » — titre catégorie, pas orienté action (ex. « Valider les heures externes »)
- [ ] l. 268 : « Motif du rejet * (min 5 chars, visible par le soignant) » — anglicisme « chars » à l'écran (le message d'erreur l. 214 dit correctement « caractères »)

### Quick wins
- [ ] l. 29 + l. 70-84 : le champ s'appelle attestation_url mais contient un chemin storage passé à createSignedUrl — nommage trompeur
- [ ] l. 30 : attestation_nom_fichier déclaré dans l'interface mais jamais affiché (le bouton « Attestation » pourrait montrer le nom du fichier)
- [ ] l. 15 : soignant_id déclaré mais jamais utilisé — aucun lien vers le profil du soignant depuis la carte, l'admin ne peut pas vérifier le dossier
- [ ] l. 117 : en vue « Toutes », les EN_ATTENTE ne remontent pas en tête (aucun tri client)

## AdminImpayees

- **Route** : /admin/impayees
- **Rôle** : File de relance des factures impayées (EMISE/EN_RETARD) : relance email individuelle ou en masse, passage manuel en retard, détail des missions facturées et contact établissement.
- **File de travail** : deja-fait
- **Doublons / chevauchements** : Sous-ensemble de /admin/facturation : AdminFacturation gère déjà les mêmes statuts via ses filtres (STATUTS incluant EMISE et EN_RETARD, AdminFacturation.tsx l.27-41). Chevauchement justifié (page d'action dédiée vs registre complet), mais le calcul « impayé = EMISE + EN_RETARD » est refait à l'identique dans AdminFinances (l.98).
- **Mobile** : RAS : la table des missions a son alternative mobile (hidden md:block l.371 + md:hidden cards l.407), header de carte en flex-col sm:flex-row, KPIs en grid-cols-2. Pas d'overflow identifié.

### Listes
- ✅ déjà en file **Liste des factures impayées (cards accordéon avec niveau d'urgence)** (corps de page, sous les 4 KPIs)
  - Actionnable : EN_RETARD (relance email), EMISE échue — joursRetard > 0 (relance + bouton « Marquer EN_RETARD » l.473-477), EMISE non échue (relance possible, surveiller)
  - Reco : Déjà conforme au pattern : la page ne contient QUE de l'actionnable, trié du plus en retard au moins en retard, avec code couleur d'urgence (critique/haute/moyenne/basse, l.294-298). Amélioration possible : transformer ces 4 niveaux déjà calculés en sections visibles (« Critique ≥ 60 j », etc.) au lieu d'une simple couleur de bordure.
- ✅ déjà en file **Table des missions liées à la facture (vue dépliée)** (détail accordéon de chaque facture)
  - Reco : Liste justificative, pas de file de travail à appliquer.

### Copy à corriger
- [ ] l.475 : bouton « Marquer EN_RETARD » — valeur d'enum SQL brute exposée à l'écran ; devrait être « Marquer en retard ».
- [ ] l.236 : toast « Statut mis à jour : EN_RETARD » — même enum technique exposé à l'utilisateur.
- [ ] l.313-315 : incohérence de traitement du même vocabulaire — le badge humanise « Émise » mais le bouton/toast gardent « EN_RETARD » brut.
- [ ] l.255 : titre « Factures impayées » — titre catégorie ; version orientée action : « Relancer les factures impayées » (mineur).
- [ ] l.173 : toast « Pas d'email de contact pour cet établissement » — un peu sec ; « Aucun email de contact renseigné pour cet établissement » serait plus conforme au ton (mineur).

### Quick wins
- [ ] BUG compteur de relances : compté par établissement (clé destinataire_id, l.125-128) et non par facture — chaque facture affiche le cumul des relances de TOUTES les factures de l'établissement (badge l.316-320).
- [ ] BUG envoyerRelance : le retour de supabase.functions.invoke n'est jamais vérifié (l.178-191) — si send-email échoue côté serveur, le toast succès s'affiche quand même et la notification est insérée à tort.
- [ ] BUG envoyerToutesRelances : envoyerRelance ne throw jamais (catch interne l.205-207), donc ok++ (l.222) compte aussi les échecs ; charger() est rappelé à chaque itération (l.204) puis une dernière fois (l.227) → N+1 rechargements et toasts en double (un par facture + le récapitulatif).
- [ ] Code mort : variable `today` (l.77) jamais utilisée ; imports inutilisés CreditCard, Calendar, User, FileText, Loader2, ExternalLink, MessageCircle, Euro, Ban (l.16-19) et Collapsible/CollapsibleContent/CollapsibleTrigger (l.10).
- [ ] Lien mission affaibli : navigate('/admin/missions') (l.388 et l.411) ignore m.id — renvoie à la liste générique au lieu du détail de la mission cliquée.
- [ ] Incohérence KPI : « En retard » compte joursRetard > 0 (l.243, basé sur date_echeance) alors que le badge se base sur statut === 'EN_RETARD' (l.313) — une facture EMISE échue est comptée en retard mais badgée « Émise ».
- [ ] Aucune gestion d'erreur dans charger() (l.79-112, data destructuré sans error) : en cas d'échec réseau, la page affiche « Aucune facture impayée / Tout est à jour » — faux positif rassurant.
- [ ] Incohérence relance : « Relancer toutes les factures » filtre joursRetard > 0 (l.212) alors que le bouton individuel permet de relancer une facture pas encore échue.
- [ ] Fallback 15 % codé en dur pour le taux de commission (l.360), dupliqué avec AdminFinances l.117/155.

## AdminLevee

- **Route** : /admin/fondateur/levee (App.tsx L387)
- **Rôle** : Outil fondateur : simulateur de levée temps réel, pipeline de suivi des investisseurs et bibliothèque de documents stratégiques (decks, BP, notes).
- **File de travail** : a-faire
- **Doublons / chevauchements** : AdminCockpitFondateur.tsx (/admin/fondateur) charge aussi investisseurs_pipeline (sa L38) pour afficher des stats de levée, et le SimulateurLevee embarqué ici consomme le même RPC fn_admin_cockpit_fondateur que le cockpit. Chevauchement partiel des indicateurs entre les deux pages ; le cockpit pointe vers cette page via une carte (sa L254), donc la navigation est cohérente mais les chiffres sont calculés deux fois.

### Listes
- 🔧 **Pipeline investisseurs** (onglet « Pipeline »)
  - Actionnable : A_CONTACTER, CONTACTE, INTRO_FAITE, PITCH, DUE_DILIGENCE, TERM_SHEET
  - Reco : Le code distingue déjà les « actifs » (L89 : exclut DECLINE et SIGNE) mais uniquement pour des stats jamais affichées. Appliquer le pattern : section « À traiter » avec les 6 statuts actifs triés par avancement (TERM_SHEET et DUE_DILIGENCE en tête, où l'inaction coûte le plus), puis section « Historique » repliable avec SIGNE et DECLINE.
- 🔧 **Documents fondateur** (onglet « Documents »)
  - Reco : Pattern non pertinent ici : bibliothèque de documents sans état actionnable. Un tri/filtre par catégorie suffirait.

### Copy à corriger
- [ ] L227 et L264 : « Suppr. » — abréviation sèche sur un bouton destructif ; écrire « Supprimer ».
- [ ] L121, L128, L149, L156 : toast.error(err.message) expose le message d'erreur Supabase brut (anglais, technique) à l'écran — remplacer par un message français générique.
- [ ] L252 : le badge affiche la constante brute doc.categorie (« BUSINESS_PLAN » avec underscore) alors que le select L350 fait .replace('_',' ') — jargon SQL-like exposé et incohérence entre les deux affichages de la même donnée.
- [ ] L167 : titre « Levée de fonds & Documents » — titre catégorie, pas orienté action (mineur, page fondateur).

### Quick wins
- [ ] L11 : import Rocket jamais utilisé (code mort).
- [ ] L92-93 : stats.actifs et stats.montantVise calculés dans le useMemo mais jamais rendus nulle part (code mort).
- [ ] L126-130 et L154-158 : suppression d'un investisseur ou d'un document sans AUCUNE confirmation — un clic = perte définitive ; incohérent avec AdminAPI qui demande confirmation avant suppression de clé.
- [ ] L221 : {inv.montant_vise && ...} masque la ligne si le montant vaut 0 (falsy) — état limite, et L315 convertit déjà 0 saisi en null (Number(...) || null).
- [ ] L101/L133 : messages de validation « Nom requis. » / « Titre requis. » très secs comparés au ton du reste de l'app.

## AdminLitiges

- **Route** : /admin/litiges
- **Rôle** : Trancher les litiges arrivés en REVUE_ADMIN (médiation 7 jours expirée sans accord) et suivre l'ensemble des litiges ouverts.
- **File de travail** : deja-fait
- **Doublons / chevauchements** : Pas de doublon côté admin (LitigesSoignant et LitigesEtablissement sont les vues des parties, pas de l'admin). Les composants litige (BoutonsActionLitige, FilDiscussionLitige) sont partagés avec ces vues.
- **Mobile** : Cartes dépliables + filtres en overflow-x-auto (l. 80) — RAS.

### Listes
- ✅ déjà en file **Litiges ouverts** (Liste de cartes dépliables, filtres pills À trancher / En médiation / Tous ouverts (l. 80-103))
  - Actionnable : REVUE_ADMIN (filtre défaut « À trancher », pill rouge si count > 0 l. 82, bordure destructive + « ⚠️ À trancher » l. 125-157)
  - Reco : Déjà conforme : défaut sur l'actionnable, compteurs par filtre, tri plus ancien d'abord, urgence visuelle. Reste à corriger le trou EN_MEDIATION (voir quickWins) pour que la vue « En médiation » soit exhaustive.

### Copy à corriger
- [ ] l. 71 : titre « Litiges — Revue admin » — titre catégorie exposant le nom de statut interne « Revue admin » plutôt qu'une action (ex. « Trancher les litiges »)

### Quick wins
- [ ] l. 7 : import Gavel jamais utilisé (1 seule occurrence dans le fichier) — code mort
- [ ] l. 9 : import formatDistanceToNow jamais utilisé (l'âge est calculé à la main l. 121-124) — code mort
- [ ] l. 28-29 vs l. 57 et l. 63 : les statuts EN_MEDIATION et MEDIATION_EN_COURS coexistent dans statutsOuverts, mais le filtre « En médiation » et son compteur ne matchent que MEDIATION_EN_COURS — un litige EN_MEDIATION est chargé mais invisible dans ce filtre, et absent du compteur ; il n'apparaît que sous « Tous ouverts »
- [ ] l. 21 : litiges: any[] — perte totale de typage sur toute la page alors que StatutLitige est importé l. 15

## AdminMandatsFacturation

- **Route** : /admin/mandats-facturation
- **Rôle** : Suivre quels soignants ont signé le mandat de facturation (Article 289 I-2 CGI) et donner un aperçu des factures d'honoraires émises.
- **File de travail** : a-faire
- **Doublons / chevauchements** : Chevauchement léger : le 4e KPI « Factures honoraires émises » (l.95-103) duplique des chiffres de /admin/facturation et y redirige au clic. Le statut de mandat lui-même n'est listé nulle part ailleurs dans l'admin (vérifié par grep sur mandat_facturation).

### Listes
- 🔧 **Liste des soignants et statut de mandat** (Section unique sous les KPIs (table desktop l.140-191, cartes mobile l.193-240))
  - Actionnable : Non signé (mandat_facturation_signe = false) — à relancer pour pouvoir émettre des factures en leur nom
  - Reco : Par défaut « TOUS » mélange signés et non-signés triés par date d'inscription. Les KPIs cliquables (l.76-94) permettent déjà de filtrer mais ne sont pas une vraie file : mettre par défaut les « Non signé » en section « À traiter » en haut (idéalement triés par ancienneté d'inscription ou par activité), et les signés en historique en dessous. Il manque surtout l'action : aucune ligne n'offre de bouton « Relancer » — la seule action possible est d'ouvrir la fiche utilisateur (l.157, l.200).

### Copy à corriger
- [ ] l.41 : toast.error(err?.message || 'Erreur chargement mandats') — message d'erreur technique brut (err.message Supabase) exposé tel quel, et libellé télégraphique sans article
- [ ] l.66-67 : titre « Mandats de facturation » — titre catégorie plutôt qu'orienté action (ex. « Suivre les signatures de mandat »)
- [ ] l.136 : « Aucun soignant trouvé » — sec ; un état vide qui distingue « aucun résultat pour ce filtre » de « aucun soignant » serait plus chaleureux et plus juste

### Quick wins
- [ ] l.34-37 : sRes.error et uRes.error jamais testés (seul .data l'est) — en cas d'erreur RPC (ex. accès refusé), la page affiche silencieusement des KPIs à 0 et une liste vide : données trompeuses au lieu d'un message d'erreur
- [ ] l.76, l.82, l.89 : window.scrollTo({ top: 400 }) — offset magique en dur ; sur mobile les KPIs sont plus hauts (grid-cols-2), le scroll n'atterrit pas sur la liste
- [ ] l.95 : le 4e KPI navigue vers /admin/facturation alors que les 3 autres, visuellement identiques, filtrent la liste en place — incohérence d'interaction
- [ ] l.22-23 : useState<any> pour stats et soignants — aucun typage, toutes les fautes de champ passeraient silencieusement
- [ ] l.30-33 : requête soignants sans limite ni pagination — charge l'intégralité de la table à chaque visite

## AdminMissions

- **Route** : /admin/missions (App.tsx l.369 + src/routes/adminRoutes.tsx l.37 — déclaration en double)
- **Rôle** : Lister toutes les missions de la plateforme (limit 200) avec onglets de filtre par statut et filtre optionnel par groupe de santé (?groupe=), liens vers le détail mission/établissement/soignant, et action « marquer absence sans prévenir ».
- **File de travail** : a-faire
- **Doublons / chevauchements** : Triple vue du même jeu de données missions : /admin/missions (liste), /admin/calendrier (mois), /admin/planning-global (semaine via RPC fn_admin_planning_global). La fonction statutBadge est dupliquée à l'identique dans AdminPlanningGlobal.tsx l.38-47, avec le même bug de clé ANNULEE. Route également déclarée deux fois (App.tsx l.369 et adminRoutes.tsx l.37).

### Listes
- 🔧 **Liste des missions (TableOuCartes)** (Corps de page, sous les 5 onglets de filtre (Toutes / Ouvertes / Assignées / En cours / Terminées))
  - Actionnable : OUVERTE non assignée (à pourvoir — affichée « Non assigné » l.203), OUVERTE assignée / ASSIGNEE imminentes (à surveiller), EN_COURS (action possible : absence sans prévenir)
  - Reco : Vue par défaut TOUTES triée du plus récent au plus ancien : les terminées récentes passent AVANT les ouvertes urgentes. Appliquer le pattern : section « À traiter » en tête = missions OUVERTE non assignées triées par debut_le croissant (les plus imminentes d'abord), puis ASSIGNEE/EN_COURS du jour, et reléguer TERMINEE + ANNULEE_* dans un bloc « Historique » replié. Ajouter un onglet ou bloc « Annulées » aujourd'hui absent.

### Copy à corriger
- [ ] l.38 : les badges affichent l'enum brut `{statut}` → « EN_COURS », « ANNULEE_PAR_ETABLISSEMENT » avec underscores à l'écran, pas de libellés français
- [ ] l.176 : EmptyState « Aucune mission avec le statut "${filtre}" » — expose la valeur d'enum brute, et avec le filtre par défaut donne la phrase absurde « Aucune mission avec le statut "TOUTES" »
- [ ] l.115 : toast « Motif obligatoire (RGPD audit). » — franglais télégraphique, jargon juridique mal formulé
- [ ] l.272 : label « Motif * (RGPD audit) » — même franglais répété
- [ ] l.270 : « Enregistre une absence non justifiée du soignant. Motif tracé RGPD. » — style télégraphique, pas de phrase adressée à l'admin
- [ ] l.136 : titre « Missions » — orienté catégorie plutôt qu'action (mineur)

### Quick wins
- [ ] l.127 : après succès de « marquer absence », `setLoading(true)` est appelé avec le commentaire « // reload missions » mais RIEN ne relance le useEffect (deps [filtre, groupeParam] inchangées, l.103) → la page reste bloquée sur ChargementPage indéfiniment (l.130 retourne le loader tant que loading=true). Bug visible majeur.
- [ ] l.36 : la clé 'ANNULEE' du map statutBadge ne correspond à aucun statut réel — les vrais statuts sont ANNULEE_PAR_ETABLISSEMENT / ANNULEE_PAR_SOIGNANT (cf. AdminCalendrier.tsx l.42-43) → les missions annulées tombent dans le fallback 'info' (bleu) au lieu de 'error'. Code mort + incohérence.
- [ ] l.48 : le filtre est initialisé une seule fois depuis l'URL (useState initializer) — une navigation interne ultérieure avec ?statut= ou ?filtre= (ex. depuis AdminGroupes) ne met pas à jour l'onglet actif si le composant est déjà monté
- [ ] l.83 : limit(200) silencieux — aucune pagination ni mention de troncature, l'admin ne sait pas que des missions manquent
- [ ] l.218-224 et l.248-254 : bouton « Absence » affiché pour TOUTE mission avec soignant assigné, y compris TERMINEE et annulées — aucune garde de statut (EN_COURS/ASSIGNEE attendu)
- [ ] l.51 + l.70 : groupeNom n'est jamais remis à null si groupeParam disparaît de l'URL — le titre peut garder « — NomGroupe » périmé

## AdminModeration

- **Route** : /admin/moderation (App.tsx:345, src/routes/adminRoutes.tsx:30)
- **Rôle** : Hub de modération admin à 6 onglets : litiges ouverts, avoirs/remboursements, recatégorisation des litiges anciens, évaluations en attente, documents soignants à vérifier, incohérences d'identité.
- **File de travail** : a-faire
- **Doublons / chevauchements** : Chevauchement réel avec /admin/litiges (AdminLitiges.tsx) : les deux pages affichent les litiges ouverts. AdminModeration charge OUVERT/EN_DISCUSSION/EN_MEDIATION/CONTESTEE (l.91) ; AdminLitiges charge OUVERT/EN_DISCUSSION/EN_MEDIATION/MEDIATION_EN_COURS/REVUE_ADMIN (AdminLitiges.tsx l.28-31). Résultat : deux files concurrentes sur 3 statuts communs, et des angles morts croisés (REVUE_ADMIN et MEDIATION_EN_COURS invisibles dans Modération ; CONTESTEE invisible dans Litiges). À fusionner ou à séparer explicitement par statut.
- **Mobile** : Rien de bloquant dans ce fichier : onglets Documents (l.447-496) et Identité (l.500-611) ont bien le pattern table desktop (hidden md:block) + cartes mobile (md:hidden) ; TabsList scrollable horizontalement (l.307-308) ; modales avec max-h-[90dvh] overflow-y-auto. Les composants délégués (AvoirsList, LegacyRecategorisation, LitigesList) restent à vérifier séparément.

### Listes
- ✅ déjà en file **Litiges ouverts** (Onglet « Litiges » (l.320-386, composant LitigesList))
  - Actionnable : OUVERT, EN_DISCUSSION, EN_MEDIATION, CONTESTEE
  - Reco : Déjà conforme : que de l'actionnable, trié par gravité, avec MediationBanner (l.294-304) qui remonte les médiations >7 jours en un clic. Rien à changer sur cette liste, hors fusion éventuelle avec /admin/litiges (voir doublons).
- 🔧 **Avoirs** (Onglet « Avoirs » (l.388-390, composant AvoirsList))
  - Actionnable : EMISE (surtout mode_remboursement=VIREMENT_MANUEL : action « rembourser », AvoirsList.tsx l.284)
  - Reco : Appliquer le pattern : section « À rembourser » (statut EMISE, en priorité VIREMENT_MANUEL) en tête, triée du plus ancien au plus récent ; REMBOURSE et ANNULEE relégués dans une section « Historique » repliée.
- ✅ déjà en file **Litiges anciens à recatégoriser** (Onglet « Legacy » (l.392-397, composant LegacyRecategorisation))
  - Actionnable : litiges type_legacy=true et type_litige=AUTRE — toutes les lignes (LegacyRecategorisation.tsx l.56-62)
  - Reco : Que de l'actionnable, donc conforme ; inverser éventuellement le tri (plus ancien d'abord) pour purger la dette dans l'ordre.
- ✅ déjà en file **Évaluations à modérer** (Onglet « Évaluations » (l.399-444))
  - Actionnable : visible=false (en attente de Publier/Supprimer/Masquer)
  - Reco : Déjà conforme (file pure, plus ancien en premier).
- ✅ déjà en file **Documents soignants à vérifier** (Onglet « Documents » (l.446-497))
  - Actionnable : statut_verification=EN_ATTENTE
  - Reco : Déjà conforme.
- ✅ déjà en file **Incohérences d'identité** (Onglet « Identité » (l.499-612))
  - Actionnable : toutes les lignes retournées par fn_admin_incoherences_identite (chaque ligne demande une vérification)
  - Reco : Conforme dans l'esprit (que de l'actionnable) ; on pourrait trier les non-correspondances strictes (X rouge) avant les lignes incomplètes (—).

### Copy à corriger
- [ ] l.312 : onglet « Legacy » — jargon technique exposé à l'écran (mot « legacy » interdit) ; renommer p.ex. « À recatégoriser »
- [ ] l.333 : « Créer litige (bypass) » — franglais technique « bypass » exposé
- [ ] l.638 : « Créer un litige (bypass admin) » — idem
- [ ] l.639 : « Crée un litige sans validation normale. Raison de bypass tracée RGPD. » — « bypass » + style télégraphique, ni vouvoyé ni chaleureux
- [ ] l.642 : placeholder « UUID de la mission » — jargon technique « UUID » ; dire « Identifiant de la mission »
- [ ] l.647-651 : options « PAIEMENT », « ABSENCE », « QUALITE », « CONTRAT », « AUTRE » — valeurs d'enum brutes en majuscules sans accents affichées telles quelles
- [ ] l.674 : « Modifier le gel scope » — franglais « scope » (jargon interne) ; « périmètre de gel »
- [ ] l.678 : placeholder « ex: MONTANT_PARTIEL, TOTAL, AUCUN… » — valeurs techniques brutes exposées au lieu d'un select avec libellés
- [ ] l.276 : toast « Gel scope mis à jour » — même jargon
- [ ] l.623, l.659, l.681 : « Raison * (RGPD audit) » / « Raison bypass * (RGPD audit) » — formulation anglicisée ; préférer « Raison (tracée pour l'audit RGPD) »
- [ ] l.227, l.245, l.267 : toasts « Raison obligatoire (RGPD audit). » / « Raison bypass obligatoire (RGPD audit). » — idem
- [ ] l.462 et l.483 : badge {d.type_document} — valeur brute de l'enum base affichée sans libellé traduit
- [ ] l.290 : h1 « Modération » — titre orienté catégorie plutôt qu'action (mineur, conventionnel pour un hub)

### Quick wins
- [ ] l.311-313 + l.392-396 : le compteur de l'onglet « Legacy (n) » dépend de onCountChange du composant LegacyRecategorisation, qui n'est monté que quand l'onglet est actif (Radix démonte les TabsContent inactifs) — le badge reste vide tant qu'on n'a pas cliqué l'onglet
- [ ] l.647-651 : les types du modal bypass (PAIEMENT/ABSENCE/QUALITE/CONTRAT/AUTRE) ne correspondent pas au référentiel TYPES_LITIGE du front (types.ts l.9-22 : ABSENCE_SOIGNANT, NON_PAIEMENT, …) — un litige créé en bypass aura un type hors libellés et hors filtres de la liste
- [ ] l.109-112 : l'erreur de resIncoherences n'est jamais vérifiée (le toast l.110 ne couvre que litiges/évals/docs) — échec silencieux de l'onglet Identité qui s'affiche alors vide
- [ ] l.309 : compteur d'onglet « Litiges (n) » = litiges.length non filtré, alors que la liste applique les filtres (l.348-349) — le nombre affiché peut différer de ce qu'on voit
- [ ] l.218 : rejet de document avec motif codé en dur « Rejeté par admin » sans champ de saisie — incohérent avec « Masquer » (l.428) qui exige une raison ; le soignant reçoit un motif générique
- [ ] l.516-525 vs l.560-569 : logique de comparaison Profil/RPPS/CNI dupliquée à l'identique entre table desktop et cartes mobile — à factoriser
- [ ] l.14 + l.26 : deux imports lucide-react séparés — trivial à regrouper

## AdminPlanningGlobal

- **Route** : /admin/planning-global (App.tsx l.384)
- **Rôle** : Vue agenda admin de toutes les missions de la plateforme sur une période choisie (semaine courante par défaut), groupées par jour avec horaires, statut et soignant assigné.
- **File de travail** : a-faire
- **Doublons / chevauchements** : Chevauchement net avec AdminCalendrier (/admin/calendrier, src/pages/admin/AdminCalendrier.tsx) : mêmes missions, même période, mêmes statuts et même notion de « non pourvue » (AdminCalendrier l.34, l.109, l.115), présentées en grille mensuelle au lieu de liste par jour ; AdminCalendrier interroge la table missions en direct tandis que cette page passe par la RPC fn_admin_planning_global. Deux pages admin pour la même question « qui travaille quand ». Recouvre aussi partiellement AdminMissions (liste).
- **Mobile** : Pas de <Table> — les lignes sont des flex flex-col sm:flex-row (l.160) qui s'empilent correctement sur mobile. Rien de bloquant ; seuls les min-w fixes (l.162 min-w-[80px], l.185 min-w-[120px]) sont à surveiller sur très petits écrans.

### Listes
- 🔧 **Missions groupées par jour** (Cartes par jour sous les filtres de dates (l.148-195))
  - Actionnable : OUVERTE (badge warning l.41) avec « Non pourvu » (l.187) — créneau à pourvoir, demande une action admin
  - Reco : La chronologie est légitime pour un planning, mais ajouter en tête un bandeau « À pourvoir sur la période » listant les missions OUVERTE/non pourvues (et urgentes en premier), avec lien direct vers chaque mission. Aujourd'hui les trous de planning sont invisibles sans dérouler chaque jour.

### Copy à corriger
- [ ] l.47 : <BadgeY2K>{statut}</BadgeY2K> — codes techniques bruts affichés (OUVERTE, ASSIGNEE, EN_COURS, TERMINEE, ANNULEE), sans libellés français accentués
- [ ] l.84 et l.90 : toast.error(result?.error || …) et toast.error(err?.message || …) — message d'erreur brut de la RPC/Supabase (potentiellement en anglais ou jargon SQL) exposé tel quel à l'écran
- [ ] l.104-107 « Planning global » : titre orienté catégorie plutôt qu'action

### Quick wins
- [ ] l.64-94 : aucun useEffect de chargement initial — la page arrive vide et n'affiche rien tant que l'admin n'a pas cliqué « Charger », alors que la semaine courante est déjà pré-remplie (l.68-69). Auto-charger au montage serait immédiat
- [ ] l.159-189 : lignes de mission non cliquables — aucun lien vers le détail de la mission ; l'admin voit « Non pourvu » mais ne peut rien faire depuis la page (liste cul-de-sac)
- [ ] l.116-130 : pas de validation debut <= fin — une plage inversée part telle quelle à la RPC
- [ ] l.54-62 : missions d'un même jour non triées par heure côté client — l'affichage dépend entièrement de l'ordre de la RPC
- [ ] l.44 vs PoolUrgenceEtablissement l.632 : TERMINEE = 'success' ici, 'info' là-bas ; OUVERTE = 'warning' ici, 'error' là-bas — couleurs de statut incohérentes entre pages
- [ ] Après modification des dates, les résultats précédents restent affichés sans aucun indicateur de péremption tant qu'on ne reclique pas « Charger » (l.140 ne teste que charged)

## AdminRGPDTools

- **Route** : /admin/rgpd-tools
- **Rôle** : Outils RGPD admin : export JSON des 500 dernières demandes RGPD (suppressions + exports) depuis les journaux d'audit, et formulaire de suppression forcée d'un compte (Art. 17) avec double confirmation et motif obligatoire.
- **File de travail** : non-applicable
- **Doublons / chevauchements** : Chevauchement net avec /admin/audit (AdminAuditLogs.tsx) : cette page liste déjà la même table journaux_audit avec RGPD_SUPPRESSION_COMPTE et RGPD_EXPORT_DONNEES dans ses filtres d'action (AdminAuditLogs.tsx l.15-16, 55, 76). La seule valeur ajoutée de la section 1 est le bouton d'export JSON — la liste elle-même est un doublon filtré de la page Journaux d'audit.

### Listes
- 🔧 **Demandes RGPD (50 premières affichées, 500 exportées)** (Section 1 « Export demandes RGPD » — table desktop (l.201-245) + cards mobile (l.248-279))
  - Reco : Non applicable : c'est un journal purement historique d'événements déjà traités (suppressions et exports passés). Aucune ligne ne demande d'action admin — il n'existe pas de notion de « demande RGPD en attente » dans cette table. Pas de découpage À traiter / Historique à faire ici.

### Copy à corriger
- [ ] l.164 : « {EXPORT_LIMIT} dernières demandes (suppressions + exports) depuis <code>journaux_audit</code> » — nom de table SQL exposé à l'écran
- [ ] l.224 et l.257 : le badge affiche la valeur brute d.action, soit « RGPD_SUPPRESSION_COMPTE » / « RGPD_EXPORT_DONNEES » en SCREAMING_SNAKE_CASE au lieu d'un libellé français (« Suppression de compte », « Export de données »)
- [ ] l.228, 234, 266-267, 271 : valeurs brutes type_acteur / type_ressource affichées telles quelles en font-mono, sans traduction
- [ ] l.123-124 : toast « RPC fn_admin_force_supprimer_compte non déployée. À créer Sprint 8. » — jargon « RPC », nom de fonction SQL et référence de sprint interne exposés à l'utilisateur
- [ ] l.127 : toast « Erreur RPC : ${error.message} » — jargon « RPC » + message d'erreur Postgres brut
- [ ] l.297-298 : « Audit légal complet dans <code>journaux_audit</code> » — nom de table SQL exposé
- [ ] l.386-388 : « Note : la RPC <code>fn_admin_force_supprimer_compte</code> sera créée Sprint 8 si nécessaire » — jargon RPC + nom de fonction + planning interne affichés en pied de formulaire
- [ ] l.148 : titre de page « Outils RGPD » — orienté catégorie plutôt qu'action (ex. « Traiter les demandes RGPD »)

### Quick wins
- [ ] Section 2 entière (l.290-391) : le bouton « Forcer la suppression définitive » appelle une RPC qui n'existe pas en base (assumé aux l.4-5, 111, 120-124, 386-388). Tout le formulaire (3 champs validés + double confirmation) aboutit systématiquement à un toast d'erreur — fonctionnalité morte à masquer ou RPC à déployer
- [ ] l.168-176 : BoutonY2K « Recharger » avec children vides (balise ouvrante/fermante sans contenu) — bouton icône sans libellé visible, seul l'aria-label le décrit
- [ ] l.42 : demandes typé any[] — aucun typage des lignes journaux_audit alors que les colonnes utilisées sont connues (l.80-89)

## AdminReclamations

- **Route** : /admin/reclamations (App.tsx:371, src/routes/adminRoutes.tsx:39)
- **Rôle** : Traitement des réclamations générales des utilisateurs (hors contestations de score) : réponse optionnelle + changement de statut via une seule action « Traiter ».
- **File de travail** : deja-fait
- **Doublons / chevauchements** : Chevauchement historique avec /admin/reclamations-score (AdminReclamationsScore.tsx) et le triage des scores (AdminScoreTriage.tsx) — déjà résolu dans ce fichier : le commentaire l.13-15 documente la suppression de l'ancien onglet doublon reclamations_scoring, et le sous-titre l.94-97 renvoie explicitement vers « Réclamations score ». Pas de doublon restant ici.
- **Mobile** : Aucun problème : mise en page 100 % cartes (pas de table), textarea et select pleine largeur. Seule la ligne select + bouton (l.129-150) pourrait se tasser sur très petit écran, sans débordement constaté dans le code.

### Listes
- ✅ déjà en file **Réclamations à traiter** (Haut de page, cartes détaillées avec formulaire inline (l.105-153))
  - Actionnable : EN_ATTENTE, EN_COURS
  - Reco : Le pattern est déjà en place (séparation actionnable/historique aux l.87-88). Améliorations : trier la file du plus ancien au plus récent, et ajouter un titre-compteur « À traiter (n) » symétrique à « Traitées (n) ».
- ✅ déjà en file **Réclamations traitées** (Section « Traitées (n) » en bas de page, lignes compactes (l.155-172))
  - Reco : Déjà reléguée en historique compact sous la file — conforme.

### Copy à corriger
- [ ] l.93 : h1 « Réclamations » — titre orienté catégorie plutôt qu'action ; p.ex. « Traiter les réclamations » (seule entorse relevée : statuts traduits, aucun jargon technique, vouvoiement implicite respecté)

### Quick wins
- [ ] l.35-39 : l'erreur de la requête est ignorée (const { data } sans error) — en cas d'échec, la page affiche « Aucune réclamation générale. » (l.102) au lieu de signaler le problème
- [ ] l.38-39 : order cree_le desc + limit(100) sans filtre de statut — une réclamation EN_ATTENTE plus ancienne que les 100 dernières créées disparaît silencieusement de la file de travail
- [ ] l.96 : lien <a href="/admin/reclamations-score"> — rechargement complet de l'app au lieu d'un <Link> react-router
- [ ] l.87 + l.155-159 : la section historique a un titre-compteur « Traitées (n) » mais la file à traiter n'a ni titre, ni compteur, ni état vide dédié (si 0 à traiter mais des traitées existent, aucun message « rien à traiter » ne s'affiche)

## AdminReclamationsScore

- **Route** : /admin/reclamations-score
- **Rôle** : Trancher les réclamations sur les pénalités de score (MAINTENIR / RÉDUIRE / ANNULER) avec propagation automatique sur l'événement et recalcul du score.
- **File de travail** : deja-fait
- **Doublons / chevauchements** : Confusion de nommage avec AdminReclamations (/admin/reclamations, réclamations générales EN_COURS/RESOLUE/FERMEE) et AdminScoreTriage (/admin/scores, tableau de triage des scores). Les données sont distinctes (le doublon legacy reclamations_scoring a été supprimé d'AdminReclamations, cf. son commentaire l. 14-16), mais trois entrées de navigation « Réclamations » / « Réclamations score » / « Triage scores » restent ambiguës pour l'admin.
- **Mobile** : Cartes, pas de table. Détail : l. 93 le conteneur est flex sans flex-col sur mobile (contrairement à AdminHeuresExternes l. 124), le bouton « Traiter » comprime le texte sur écran étroit.

### Listes
- ✅ déjà en file **Réclamations de score** (Liste de cartes unique, filtres En attente / Traitées / Toutes (l. 66-72))
  - Actionnable : PENDING (bouton « Traiter » l. 136-138 ; surligné ambre, rouge si jours_attente > 7 l. 88-92)
  - Reco : Déjà une file via le filtre défaut PENDING avec escalade visuelle > 7 jours. Amélioration : en vue « Toutes », remonter les PENDING en tête, et trier les PENDING par jours_attente décroissant pour traiter les plus anciennes d'abord.

### Copy à corriger
- [ ] l. 236 : « Motif admin * (min 10 chars, visible par l'user) » — anglicismes « chars » et « l'user » à l'écran
- [ ] l. 238 : placeholder « Ex: Certif médical fourni est conforme... » — « Certif » argotique
- [ ] l. 192 : « Décision appliquée. Score recalculé + notif envoyée. » — abréviation « notif »
- [ ] l. 96 : {r.evenement_type} affiche l'enum brut SOIGNANT/ETAB à l'écran
- [ ] l. 97 : {r.event_type_evenement} affiche le type d'événement technique brut non traduit
- [ ] l. 109 : badge {r.decision_admin} affiche l'enum brut MAINTENIR/REDUIRE/ANNULER au lieu d'un libellé
- [ ] l. 114 : « Event : » — anglicisme (devrait être « Événement : »)
- [ ] l. 64 : titre « Réclamations score » — titre catégorie, pas orienté action (ex. « Trancher les réclamations de score »)

### Quick wins
- [ ] l. 121 : lien justificatif CASSÉ — URL construite en dur https://flripxtsyegjshnhzjkz.supabase.co/storage/v1/object/sign/justificatifs/... sans token : un endpoint /object/sign exige un token généré par createSignedUrl, ce lien renvoie toujours une erreur. URL projet hardcodée en plus (les autres pages utilisent supabase.storage.createSignedUrl)
- [ ] l. 106 : ternaire dégénéré « r.decision_admin === 'REDUIRE' ? 'info' : 'info' » — les deux branches identiques, le cas REDUIRE était censé se distinguer
- [ ] l. 51-55 : si la RPC répond success=false, aucune notification d'erreur (branche else manquante, contrairement à AdminHeuresExternes l. 62-64)
- [ ] l. 25 vs l. 104 : le statut CANCELLED existe dans le type mais n'a ni filtre ni badge — une réclamation annulée apparaît dans « Toutes » sans aucun indicateur de statut
- [ ] l. 171-176 : la validation REDUIRE n'exige que pc < 0 — rien n'empêche d'AGGRAVER la pénalité (saisir -100 sur un événement à -5)

## AdminSales

- **Route** : /admin/fondateur/sales (App.tsx:389, protégé ADMIN_PLATEFORME)
- **Rôle** : Cockpit growth/prospection du fondateur : annuaire de groupes sociaux de recrutement, pipeline de contacts sourcés (soignants + établissements), recherche dans les bases officielles FINESS et Annuaire Santé CNAM, envoi d'emails de prospection (mailto ou Resend), templates de messages et posts hebdomadaires générés depuis les missions ouvertes.
- **File de travail** : a-faire
- **Doublons / chevauchements** : 1) Onglet « Étab. Jolene » : chevauche AdminUtilisateurs.tsx (onglet Établissements, lignes 297/408, table etablissements en direct) et AdminVerificationEtablissements.tsx (RPC fn_admin_lister_etablissements_a_verifier, ligne 72) — trois pages listent les établissements inscrits avec leur statut de vérification. 2) Onglet « Posts de la semaine » référence AdminAcquisition (« l'impact est visible dans Acquisition », ligne 1041) : complémentaire, pas doublon. 3) AdminGroupes.tsx (« Groupes de santé ») n'est PAS un doublon malgré le nom : il gère les groupes d'établissements multi-sites et la commission, rien à voir avec les groupes sociaux de cet écran — risque de confusion de nommage dans la nav admin.
- **Mobile** : Pas de <Table> : tout est en cartes avec grid-cols-1 md:grid-cols-2, donc pas de problème de table non responsive. Deux points mineurs : la barre de 8 onglets en flex-wrap (lignes 303-312) occupe 3-4 lignes de hauteur sur mobile, et les formulaires FormPanel utilisent des grilles grid-cols-2 fixes (lignes 468, 480, 494, 506, 517, 521) qui restent en 2 colonnes même sur petit écran — champs étroits mais pas d'overflow bloquant.

### Listes
- 🔧 **Groupes de recrutement (cartes)** (onglet « Groupes »)
  - Actionnable : A_VERIFIER (« À vérifier »), groupes sans URL (badge « Lien à renseigner », ligne 386)
  - Reco : Section « À traiter » en tête avec les groupes A_VERIFIER et ceux sans URL (lien à renseigner), puis « Actifs » et enfin « Inactifs » en historique replié. Aujourd'hui un groupe à vérifier peut être noyé après les favoris.
- 🔧 **Soignants sourcés (cartes ListeContacts)** (onglet « Soignants »)
  - Actionnable : PROSPECT (à contacter), RELANCE (à relancer), CONTACTE (en attente de relance)
  - Reco : Sections « À contacter » (PROSPECT), « À relancer » (RELANCE puis CONTACTE par ancienneté de maj_le), puis « Terminés » (INSCRIT/PERDU) repliés. Les archivés restent derrière le toggle existant (ligne 573).
- 🔧 **Établissements sourcés (cartes ListeContacts)** (onglet « Étab. sourcés »)
  - Actionnable : PROSPECT, RELANCE, CONTACTE
  - Reco : Même découpage que les soignants sourcés : PROSPECT et RELANCE en tête, INSCRIT/PERDU en historique. Le composant ListeContacts (lignes 557-640) est partagé, une seule implémentation suffit.
- 🔧 **Résultats prospection établissements (base FINESS)** (onglet « Prospection étab. »)
  - Reco : Non applicable : c'est un moteur de recherche dans une base de ~270k entrées, pas une file. L'action (Pipeline, ligne 875) fait basculer vers la liste « Étab. sourcés » qui, elle, doit devenir la file de travail.
- 🔧 **Résultats prospection soignants (base Annuaire Santé CNAM)** (onglet « Prospection soignants »)
  - Reco : Non applicable : outil de recherche/sourcing, même logique que la prospection établissements.
- 🔧 **Établissements inscrits sur Jolene (cartes)** (onglet « Étab. Jolene »)
  - Actionnable : badge « En attente » quand peut_publier est faux (ligne 702) — mais l'action de vérification vit sur AdminVerificationEtablissements, « Coordonnées non renseignées » (ligne 711)
  - Reco : Liste purement consultative (appeler/écrire aux inscrits). Si on garde l'onglet, mettre les « En attente » en tête avec un lien vers la page de vérification plutôt qu'un simple badge ; sinon supprimer l'onglet (doublon, voir duplicateOverlap).
- 🔧 **Templates de messages** (onglet « Templates »)
  - Reco : Non applicable : bibliothèque de contenus à copier/éditer, pas de statut.
- 🔧 **Posts de la semaine (générés)** (onglet « Posts de la semaine »)
  - Reco : Non applicable : contenus générés à copier, pas de file.

### Copy à corriger
- [ ] Ligne 937 : « De : Gabrielle de Jolene (réponses → ta boîte perso) » — tutoiement, seul « tu » de la page (tout le reste vouvoie : lignes 346, 898, 1040, 1049).
- [ ] Lignes 530, 603, 623 : statuts pipeline affichés en code brut « PROSPECT / CONTACTE / RELANCE / INSCRIT / PERDU » (badge ligne 603 et deux <select>), sans accent ni casse française — alors que les statuts de groupe, eux, sont traduits (« À vérifier », ligne 363). Jargon de valeurs d'enum exposé à l'écran.
- [ ] Ligne 926 : toast « prospect passé en CONTACTÉ » — accentué ici mais « CONTACTE » dans le badge ligne 603 : deux labels différents pour le même statut.
- [ ] Lignes 106 et 295 : titre de page « Sales / Sourcing » — anglicisme et titre-catégorie, pas orienté action (ex. attendu : « Recruter des soignants et des établissements »).
- [ ] Ligne 435 : badges « DM soignant » / « DM établissement » — jargon anglophone « DM » exposé à l'écran.
- [ ] Lignes 310 et 425-449 : onglet « Templates » — anglicisme (« Modèles » attendu), répété dans les toasts lignes 267 (« Le message est requis ») ok mais 272 « Template enregistré ».
- [ ] Lignes 542-543 : « remplacés automatiquement à l'envoi et dans le mailto » — terme technique « mailto » exposé à l'écran.
- [ ] Ligne 1041 : « Les liens sont tracés (utm_campaign=post-hebdo) » — paramètre technique UTM exposé tel quel à l'écran.

### Quick wins
- [ ] Code mort : supprimerContact (lignes 282-286) n'est appelé nulle part — aucun bouton de suppression sur les cartes contact (seuls Éditer/Retirer existent, lignes 625-630).
- [ ] Incohérence d'écriture : ajouterAuPipeline côté établissements fait un upsert onConflict:'finess' (lignes 791-795, re-clic sans doublon) mais côté soignants un insert simple (lignes 1173-1177) — chaque clic « Pipeline » sur un même soignant crée un doublon dans sales_contacts.
- [ ] Quasi-code mort : dans ProspectionSoignants, emailEdit transporte un champ prospect (ligne 1257) jamais lu — contrairement à ProspectionEtab où sauverEmail enchaîne sur la modal d'envoi (lignes 778-787), sauverEmail soignant (lignes 1161-1170) ignore prospect ; soit retirer le champ, soit enchaîner le mailto comme côté établissements.
- [ ] Suppression destructive sans confirmation : supprimerGroupe (ligne 243) est branché sur un bouton icône poubelle sans libellé ni title ni confirm (ligne 389) — un clic = delete définitif en base.
- [ ] Incohérence email soignants : un soignant sourcé avec email reçoit un mailto vide sans template (ligne 616, branche non-ETABLISSEMENT), alors que la prospection soignants a un template dédié SUJET/CORPS_PROSPECTION_SOIGNANT (lignes 1113-1125, utilisé ligne 1183) — réutiliser ce template dans ListeContacts.
- [ ] sauverLienAvis (lignes 1015-1023) fait un .update() filtré sur cle='lien_avis_google' : si la ligne growth_config n'existe pas, 0 ligne affectée mais toast de succès quand même — préférer upsert.
- [ ] Toast trompeur possible : ligne 926 « prospect passé en CONTACTÉ » affirme un changement de statut effectué côté edge function sales-outreach ; le front ne le vérifie pas (data peut ne pas le confirmer).
- [ ] État partagé entre onglets : voirArchives (ligne 125) est commun aux onglets Soignants et Étab. sourcés, et recherche (ligne 117) ne sert qu'aux Groupes mais persiste — comportements croisés surprenants en changeant d'onglet.
- [ ] Import CSV groupes : la déduplication ne se fait que contre l'existant (ligne 132), pas à l'intérieur du collage — deux lignes identiques dans le même import créent deux groupes.

## AdminScoreTriage

- **Route** : /admin/scores (App.tsx:356, confirmé par le commentaire l.14)
- **Rôle** : Tableau centralisé des scores de fiabilité/qualité (soignants + établissements) pour repérer rapidement les comptes à risque (< 50).
- **File de travail** : deja-fait
- **Doublons / chevauchements** : Chevauche AdminReclamationsScore.tsx (/admin/reclamations-score), qui est la vraie file actionnable sur les scores (décisions MAINTENIR/REDUIRE/ANNULER via fn_admin_lister_reclamations), et AdminUtilisateurs.tsx (/admin/utilisateurs) qui affiche déjà le score en colonne avec accès au même profil. Les deux seules actions de cette page (Voir le profil → /admin/utilisateurs/:id, Message → /admin/messagerie) existent déjà ailleurs : page purement consultative, candidate à fusion avec l'une des deux.
- **Mobile** : Bien couvert : TableOuCartes avec renduCarte complet (badges, score en gros, deux boutons pleine largeur). Les filtres passent en flex-wrap sur petit écran. Rien de bloquant.

### Listes
- ✅ déjà en file **Tableau des scores soignants + établissements** (Corps de page unique (l.199-281))
  - Actionnable : score < 50 (filtre « Warnings » actif par défaut, l.61) — comptes à risque à examiner
  - Reco : Déjà conforme dans l'esprit (pires scores en premier, filtre warnings par défaut). Amélioration possible : matérialiser deux sections explicites « À traiter (<50) » / « Historique (≥50) » au lieu d'un simple filtre, et relier chaque ligne aux réclamations de score en attente.

### Copy à corriger
- [ ] l.164 : option « Warnings (<50) » — anglicisme/jargon exposé dans une UI entièrement en français (attendu : « À risque (<50) » ou « Alertes »)
- [ ] l.94 : « Erreur de chargement : ${err?.message} » — le message d'erreur technique brut (texte d'erreur Supabase/base de données) est affiché tel quel à l'écran
- [ ] l.190 : badge « Étab » — abréviation sèche, incohérente avec « Établissements » utilisé dans le filtre l.156

### Quick wins
- [ ] l.114-117 : ouvrirProfil — if/else dont les deux branches naviguent vers exactement la même URL /admin/utilisateurs/${l.user_id} : branchement mort
- [ ] l.119-121 + l.230-238 + l.268-276 : bouton « Message » par ligne avec aria-label « Messagerie ${l.nom} » mais qui navigue vers /admin/messagerie sans cibler le compte — action générique trompeuse, quasi handler mort
- [ ] l.36-41 + l.107-108 : les filtres « Warnings (<50) » et « Bronze » sélectionnent exactement le même ensemble (BRONZE = score < 50 par construction) — doublon de filtre
- [ ] l.43-51 : sémantique des couleurs inversée — BRONZE (le pire niveau) en variant 'success' (vert) et OR en 'warning' (orange)
- [ ] l.33 + l.87 : champ derniere_maj toujours null et jamais affiché — code mort
- [ ] l.54 vs l.129 : titre d'onglet « Triage scores » vs h1 « Triage des scores » — incohérence mineure
- [ ] l.139-145 et l.148-170 : <input> et <select> natifs au lieu des composants Input/Select du design system utilisés sur les autres pages admin — incohérence UI

## AdminSignalements

- **Route** : /admin/signalements
- **Rôle** : File de traitement des signalements d'utilisateurs (comportement, fraude, faux documents…) transmis par soignants et établissements : prise en charge, traitement, rejet.
- **File de travail** : a-faire
- **Doublons / chevauchements** : Chevauchement fonctionnel avec la constellation de files de plainte admin : AdminReclamations, AdminReclamationsScore, AdminScoreTriage, AdminModeration (litiges/évaluations/documents) et AdminLitiges. Les signalements sont une table distincte mais c'est une 5e file de « problèmes remontés par les utilisateurs » à triager, éclatée sur des pages séparées.

### Listes
- 🔧 **Liste des signalements** (corps de page, cartes filtrables par chips de statut (lignes 86-93))
  - Actionnable : OUVERT (boutons « Prendre en charge », « Marquer traité », « Rejeter »), EN_COURS (boutons « Marquer traité », « Rejeter »)
  - Reco : Le défaut « Tous » mélange l'actionnable et l'historique. Appliquer le pattern : section « À traiter » (OUVERT puis EN_COURS) en tête, section « Historique » (TRAITE/REJETE) repliée ou en dessous. Les chips peuvent rester comme filtre secondaire.

### Copy à corriger
- [ ] Ligne 106 : le badge affiche le statut brut `{s.statut}` — codes SQL « OUVERT », « EN_COURS », « TRAITE », « REJETE » exposés tels quels à l'écran (avec underscore pour EN_COURS), alors que des libellés existent déjà dans STATUTS lignes 33-39.
- [ ] Ligne 82 : titre « Signalements » orienté catégorie plutôt qu'action (le sous-titre ligne 83 décrit la provenance, pas le travail à faire — ex. « Traiter les signalements »).

### Quick wins
- [ ] Ligne 112 : ternaire mort — `s.cible_type === 'SOIGNANT' ? \`/admin/utilisateurs/${s.cible_id}\` : \`/admin/utilisateurs/${s.cible_id}\`` : les deux branches sont identiques, la condition ne sert à rien.
- [ ] Lignes 19-20 : les champs resolution, traite_le et mission_id sont typés et récupérés mais jamais affichés — un signalement TRAITE ne montre ni sa résolution ni sa date de traitement, et le lien vers la mission concernée n'existe pas.
- [ ] Ligne 126 : « Marquer traité » impose une résolution générique codée en dur (« Traité par l'administration ») sans permettre de saisir un motif, alors que le RPC accepte un texte libre.
- [ ] Ligne 60 : en cas d'erreur de chargement, setItems est quand même appelé avec [] — la page affiche « Aucun signalement » (état vide joyeux, mascotte happy ligne 98) au lieu d'un état d'erreur distinct.

## AdminStatus

- **Route** : /admin/status
- **Rôle** : Tableau de bord santé système agrégé (RPC fn_admin_health_check, auto-refresh 60s) : alertes actives résolvables, état des crons, webhooks Stripe 24h, stats temps réel, compteurs de logs, liens dashboards externes et test Sentry.
- **File de travail** : a-faire
- **Doublons / chevauchements** : Fort chevauchement avec /admin/healthcheck (AdminHealthcheck.tsx) : deux pages de monitoring système, chacune avec son outil Sentry et son bouton de revérification. Le compteur « Logs 24h → Audit » (l.189) recoupe /admin/audit sans lien de navigation. Fusion healthcheck+status (ou onglets) à envisager.
- **Mobile** : Table des crons déjà responsive (hidden md:block + cards mobile, l.207-252). Reste le header (l.100) non empilé sur mobile, mineur.

### Listes
- ✅ déjà en file **Alertes actives** (première card de la page, affichée seulement si non vide (l.115-138))
  - Actionnable : CRITICAL, WARNING, INFO (toutes ont un bouton « Résoudre »)
  - Reco : Déjà une file de travail (seules les alertes actives, en tête de page, action « Résoudre » par ligne). Amélioration mineure : trier CRITICAL > WARNING > INFO côté client.
- 🔧 **Crons (détail)** (card « Crons (17 actifs) », table desktop + cards mobile (l.203-254))
  - Actionnable : Échec (badge error), Retard (badge warning)
  - Reco : Trier Échec → Retard → OK (les compteurs cronsCritiques/cronsRetard/cronsOk existent déjà l.90-92, il suffit de concaténer ces trois tableaux pour le rendu), ou section « À traiter » au-dessus du tableau.
- 🔧 **Stats temps réel / Logs 24h / Dashboards externes** (cards de tuiles métriques et liens (l.165-200, 257-274))
  - Reco : Non applicable — tuiles métriques, pas des files d'items.

### Copy à corriger
- [ ] l.110 : bouton « Refresh » — anglicisme exposé à l'écran, devrait être « Actualiser ».
- [ ] l.57 et l.103 : titre « Status système » — anglicisme (« Statut » ou « État du système ») et titre catégorie, pas orienté action.
- [ ] l.204 : « Crons (17 actifs) » — le nombre 17 est codé en dur alors que la donnée réelle est `data.crons.crons.length` ; si le RPC renvoie autre chose le titre ment (règle « jamais de données inventées »).
- [ ] l.173 : « Candidatures pending » — franglais ; « Candidatures en attente ».
- [ ] l.125 : badges de sévérité affichant l'enum brut CRITICAL / WARNING / INFO en anglais — devrait être Critique / Avertissement / Info.
- [ ] l.311 : « Voir docs/sentry-setup.md » — chemin de fichier du dépôt exposé dans l'UI, inactionnable pour l'admin depuis l'écran (jargon acceptable sur page technique, mais un lien mort textuel reste inutile).

### Quick wins
- [ ] l.204 : compteur « 17 actifs » codé en dur (cf. copyIssues) — remplacer par `data.crons.crons.length`.
- [ ] l.294-304 : le bouton « Déclencher erreur test Sentry » affiche toast.success « Erreur test envoyée à Sentry » même sans DSN configurée — Sentry.captureException ne lève jamais, le try/catch l.301 est mort, donc faux succès systématique (la note l.310 admet d'ailleurs que le bouton est « inactif silencieusement »).
- [ ] l.257-277 : bug d'espacement — la card « Dashboards externes » (l.257) n'a pas de mb-4 alors qu'elle est suivie de « Outils diagnostic » (l.277) qui en a un : les deux cards sont collées et la page se termine sur une marge inutile. Ordre des sections probablement inversé (outils diagnostic semble pensé pour venir avant les liens externes).
- [ ] l.64 : `supabase.rpc('fn_admin_health_check' as any)` et l.81 idem — casts `as any` signalant des types Supabase non régénérés.
- [ ] l.100 : header `flex items-start justify-between` sans variante mobile — le bouton Refresh peut comprimer le titre sur écran étroit.

## AdminTauxCommission

- **Route** : /admin/taux-commission (confirmé dans App.tsx:377)
- **Rôle** : Configurer les taux de commission négociés par groupe et par établissement (cascade établissement > groupe > défaut 15 %), avec raison obligatoire journalisée à chaque modification.
- **File de travail** : non-applicable
- **Doublons / chevauchements** : Doublon fonctionnel direct avec AdminGroupes (/admin/groupes) qui permet déjà d'éditer le taux par groupe (AdminGroupes.tsx ligne 291) et par établissement (lignes 458 et 552), apparemment sans passer par la RPC auditée fn_admin_modifier_taux_commission ni raison obligatoire — deux chemins d'édition concurrents pour la même donnée, dont un contourne l'audit. AdminDetailUtilisateur affiche aussi le taux (lignes 402, 706) en lecture seule.
- **Mobile** : Pas de table (donc pas de scroll horizontal), mais les lignes Groupes (ligne 145) et Établissements (ligne 172) sont en flex horizontal nom + taux + bouton « Modifier » sans empilement responsive : sur écran étroit, les noms longs écrasent le taux et le bouton. Aucune variante mobile (pas de hidden md:block ni cards dédiées).

### Listes
- 🔧 **Groupes (lignes 136-163, liste divisée avec taux négocié + bouton Modifier)** (Section « Groupes » en haut de page)
  - Reco : Non applicable au sens strict : page de configuration sans statuts ni cycle de vie. Si on veut quand même une logique « à traiter », remonter en premier les entités sans taux négocié (badge « Défaut 15% ») pour signaler les contrats jamais négociés.
- 🔧 **Établissements (lignes 166-196, liste avec taux résolu + badge de source Étab/Groupe/Défaut 15% + bouton Modifier)** (Section « Établissements » sous les groupes)
  - Reco : Non applicable (configuration). Option : trier/sectionner par taux_resolu_source pour mettre en tête les établissements en « defaut_15 » (jamais négociés), et ajouter une recherche car la liste charge tous les établissements sans filtre.

### Copy à corriger
- [ ] Ligne 240 : « Audité dans <code>journaux_audit</code> (action <code>TAUX_COMMISSION_MODIFIE</code>) » — nom de table SQL et code d'action technique exposés à l'écran dans la modale.
- [ ] Lignes 58 et 98 : toast.error((data as any)?.error || error?.message || …) — le message d'erreur technique brut de Supabase/Postgres peut être affiché tel quel à l'utilisateur.
- [ ] Ligne 84 : toast « Raison obligatoire (audit) » — formulation sèche et jargonneuse ; préférer « Merci d'indiquer la raison de cette modification ».
- [ ] Ligne 33 (et ligne 149 « étab. ») : abréviation « Étab » dans le badge de source — abréviation peu soignée pour un libellé visible.
- [ ] Incohérence typographique du pourcentage : « Défaut 15% » (ligne 35) vs « défaut 15 % » (ligne 129) vs « défaut 15% » (ligne 227) — trois graphies pour la même valeur.
- [ ] Ligne 126 : titre « Taux de commission » = catégorie, pas orienté action (ex. « Négocier les taux de commission »).

### Quick wins
- [ ] Lignes 170-195 : pas d'état vide pour la liste Établissements — si etabs est vide, une carte bordée vide s'affiche, alors que la liste Groupes a son fallback « Aucun groupe » (ligne 141). Asymétrie visible.
- [ ] Lignes 110-118 : écran de chargement avec Loader2 brut au lieu du composant ChargementPage utilisé sur les autres pages admin (ex. AdminFacturation ligne 390) — incohérence UI.
- [ ] Lignes 199-251 : modale maison en div fixed au lieu du Dialog shadcn — pas de focus trap, pas de fermeture Échap, pas de rôle ARIA ; accessibilité dégradée par rapport au reste de l'app.
- [ ] Ligne 141 : « Aucun groupe » rendu en simple <p className="card-base"> au lieu du composant EmptyState utilisé ailleurs dans l'admin.
- [ ] Aucune recherche/filtre sur la liste des établissements alors que la RPC renvoie tout (lignes 62-63) — devient inutilisable au-delà de quelques dizaines d'établissements.

## AdminTemplatesContrats

- **Route** : /admin/templates-contrats (App.tsx L349)
- **Rôle** : Lister les modèles de contrats, les activer/désactiver et accéder à leur édition.
- **File de travail** : non-applicable

### Listes
- 🔧 **Templates (TableOuCartes)** (Corps de page, sous les 3 cartes de stats)
  - Reco : Non pertinent (référentiel de configuration). Au mieux, séparer visuellement actifs/inactifs puisque les compteurs L86-99 existent déjà.

### Copy à corriger
- [ ] L81 : « 14 templates Sprint 2 : CDD master (18 professions) + REMPLACEMENT_LIBERAL + 12 LIBERAL spécifiques. » — jargon interne de projet (« Sprint 2 », « CDD master ») exposé à l'écran, et le « 14 » codé en dur contredit potentiellement le compteur dynamique affiché juste dessous (L89) : risque de donnée inventée/périmée
- [ ] L124 : EmptyState « Les 14 templates Sprint 2 devraient être présents. » — même jargon « Sprint 2 » + compte en dur
- [ ] L214 : « Variables jinja-like supportées » — jargon de développeur (« jinja-like ») dans une zone visible par l'admin
- [ ] L78 : titre « Templates contrats » — anglicisme + orienté catégorie ; « Gérer les modèles de contrats » serait orienté action

### Quick wins
- [ ] L57 : confirm() natif du navigateur pour activer/désactiver, alors que AdminContrats utilise ModalConfirmation — incohérence UI
- [ ] L145 : onClick={(e) => e.stopPropagation()} sur les actions du tableau alors qu'aucun onClickLigne n'est passé à TableOuCartes (L120-124) — stopPropagation mort ; idem les e.stopPropagation() des cartes L185/L193
- [ ] L22 : champ variables typé et retourné par le RPC mais jamais affiché sur cette page — donnée chargée pour rien
- [ ] L3 : import Loader2 jamais utilisé (le spinner passe par la prop loading de BoutonY2K)

## AdminUtilisateurs

- **Route** : /admin/utilisateurs (App.tsx:343, adminRoutes.tsx:28) ; détail sur /admin/utilisateurs/:id
- **Rôle** : Annuaire admin des soignants et établissements : recherche (serveur + filtre local), suspension/réactivation, et validation/rejet des établissements en attente de vérification.
- **File de travail** : deja-fait
- **Doublons / chevauchements** : Fort chevauchement avec AdminVerificationEtablissements.tsx (/admin/verification-etablissements) : même file de validation d'établissements, mêmes RPC fn_admin_valider_etablissement / fn_admin_rejeter_etablissement, mais la page dédiée affiche un dossier plus complet (FINESS, pièce d'identité du représentant, dirigeants INSEE). Le bandeau + les boutons inline de l'onglet Établissements dupliquent cette file en version appauvrie. Chevauchement mineur avec AdminScoreTriage (/admin/scores) qui réaffiche le score_fiabilite déjà en colonne ici.
- **Mobile** : Bien couvert : TableOuCartes avec renduCarte sur les deux onglets, bandeau en flex-col sm:flex-row. Seule réserve mineure : boutons d'action h-8 (32 px) en mode tableau, sous la cible tactile de 44 px — mais le mode cartes mobile utilise bien min-h-[44px].

### Listes
- ✅ déjà en file **Bandeau « établissements en attente de vérification »** (Haut de page, au-dessus des onglets (l.215-247))
  - Actionnable : statut_verification = EN_ATTENTE et non supprimé (l.93) — boutons Valider / Rejeter / Détails
  - Reco : Déjà conforme : la section « À traiter » est matérialisée en tête de page avec compteur et actions inline.
- 🔧 **Onglet Soignants (TableOuCartes)** (Tabs > onglet « Soignants » (l.300-406))
  - Actionnable : Aucun statut n'exige une action admin par défaut — Suspendre/Réactiver sont des actions de modération à l'initiative de l'admin, pas une file
  - Reco : Pattern peu applicable : pas de statut actionnable. Au plus, remonter en tête les soignants suspendus récemment ou RPPS non vérifié avec missions terminées, sinon laisser en annuaire.
- 🔧 **Onglet Établissements (TableOuCartes)** (Tabs > onglet « Établissements » (l.408-525))
  - Actionnable : statut_verification = EN_ATTENTE (boutons Valider/Rejeter inline, l.437-446 et l.489-498)
  - Reco : Dans l'onglet, trier les EN_ATTENTE en premier puis VERIFIE/REJETE en historique — ou supprimer la duplication et s'appuyer uniquement sur le bandeau du haut (déjà une file) ou la page dédiée /admin/verification-etablissements.

### Copy à corriger
- [ ] l.254 : placeholder « Recherche serveur (≥2 car.)… » — jargon technique « serveur » exposé à l'écran + abréviation « car. » peu lisible
- [ ] l.291 : placeholder « Filtrer liste locale… » — « liste locale » expose la distinction technique client/serveur à l'utilisateur
- [ ] l.260 : aria-label « Rechercher un utilisateur (serveur) » — jargon « serveur » lu par les lecteurs d'écran
- [ ] l.212 : titre « Gestion utilisateurs » — titre catégorie plutôt qu'orienté action (ex. « Vérifier et gérer les comptes »)

### Quick wins
- [ ] l.39-57 : charger() ignore totalement les erreurs Supabase (resSoignants.error / resEtabs.error jamais testés) — en cas d'échec, listes vides silencieuses sans message
- [ ] l.44 et l.49 : colonnes sélectionnées jamais affichées (numero_rpps, siret_verifie, peut_publier_missions) — sur-sélection / code mort
- [ ] l.46 et l.51 : limit(500) sans pagination ni avertissement — au-delà de 500 comptes, les plus anciens disparaissent silencieusement
- [ ] l.348, l.395, l.462, l.514 : « Suspendre » s'exécute en un clic sans confirmation, alors que le rejet d'établissement passe par une modale — incohérence sur deux actions destructives
- [ ] l.323 vs l.373 : même état RPPS rendu « Non » dans le tableau mais « RPPS Non vérifié » sur la carte — labels différents pour la même chose
- [ ] l.537 vs l.153 : la modale annonce un motif « (optionnel) » mais un motif « Non conforme » est substitué silencieusement si vide — l'établissement reçoit un motif que l'admin n'a pas écrit
- [ ] l.250-286 + l.289-292 : deux champs de recherche empilés (serveur puis local) sur la même page — redondance UX source de confusion

## AdminVerificationEtablissements

- **Route** : /admin/verification-etablissements
- **Rôle** : File de revue manuelle des établissements non rattachés : examiner le dossier (FINESS, représentant + pièce d'identité, dirigeants INSEE, e-mail) puis valider (rattachement ADMIN) ou rejeter.
- **File de travail** : deja-fait
- **Doublons / chevauchements** : AdminUtilisateurs.tsx (l. 133-160) expose les mêmes actions valider/rejeter établissement via les mêmes RPC fn_admin_valider_etablissement / fn_admin_rejeter_etablissement — deux portes d'entrée pour la même décision, avec des validations différentes (motif par défaut « Non conforme » côté AdminUtilisateurs).
- **Mobile** : Cartes avec flex-wrap, pas de table — RAS.

### Listes
- ✅ déjà en file **Établissements à vérifier** (Liste de cartes unique, aucun filtre (l. 158-261))
  - Actionnable : Tous les dossiers listés sont en attente de décision (Valider l. 239-247 / Rejeter l. 248-256)
  - Reco : La page EST une pure file de travail (100 % actionnable). Optionnel : un onglet « Historique » (validés/rejetés récents) pour retrouver une décision, et un tri explicite par ancienneté (cree_le croissant) côté client.

### Copy à corriger
- [ ] l. 246 : « Valider (rattachement ADMIN) » — valeur d'enum interne « ADMIN » exposée en majuscules sur le bouton
- [ ] l. 100 : confirm « L'établissement pourra publier des missions (rattachement ADMIN). » — même enum interne exposée à l'écran

### Quick wins
- [ ] l. 100 et l. 116 : window.confirm() et window.prompt() natifs au lieu des modales maison utilisées partout ailleurs dans l'admin — incohérence UI
- [ ] l. 116-121 : aucun garde-fou sur le motif de rejet — un motif vide (champ effacé puis OK) est envoyé tel quel, alors que les autres pages exigent 5-10 caractères minimum
- [ ] l. 28, 38, 39, 40, 42 : champs d'interface morts jamais affichés — finess_secteur, rattachement_methode, rattachement_verifie, statut_verification, peut_publier_missions
- [ ] l. 46-53 : le composant Badge traite ok=null comme « non vérifié » sans distinguer l'état inconnu, et l. 189 affiche « ? » brut si la raison sociale FINESS est absente
## AdminAffacturage (audit manuel — hors lots D-0)

- **Route** : /admin/affacturage
- **Rôle** : Suivi des demandes d'avance via l'affactureur (Defacto) : KPIs volume/marge + tableau des avances.
- **File de travail** : a-faire (léger — page de suivi sans actions admin)

### Listes
- 🔧 **Tableau des avances** (corps de page, chips statut « Tous » par défaut)
  - Actionnable : IMPAYEE (recouvrement à suivre), DEMANDEE/EN_ANALYSE (dossiers vivants)
  - Reco : tri par priorité de statut (IMPAYEE > DEMANDEE > EN_ANALYSE > APPROUVEE > reste par date) au lieu du chronologique pur ; pas de FileDeTravail nécessaire (aucune action sur la page).

### Copy à corriger
- [ ] Sous-titre l.70 : « configurable via le secret FACTOR_MARGE_JOLENE » — jargon technique exposé à l'écran.
- [ ] Chips l.110-120 et badges l.178/207 : statuts en enum brut (« DEMANDEE », « EN ANALYSE ») — mapper en français.
