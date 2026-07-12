# Jolene — Lots 19-21 : interface admin (feuille de route détaillée)

Extension de la feuille de route Lots 11-18. Source : audit des 17 écrans admin du 11/07 + audit de clôture A1-A4 en cours (findings crons/alertes). **Ce document remplace les specs compactes transmises précédemment** — à déposer dans `docs/` à côté du doc principal.

**Positionnement** : l'admin n'apparaît ni dans les screenshots stores ni dans la review Apple — ces lots ne bloquent pas la *soumission*. Mais l'admin est le cockpit d'exploitation du lancement : le Lot 19 doit être livré **avant le premier euro réel** (c'est dans son canal que tombent les tripwires), les Lots 20-21 avant la *publication*.

---

## État des lieux (17 écrans)

**À préserver** : le cockpit fondateur est une vraie bonne idée (seuil de rentabilité, charges réelles, simulateur de rémunération) ; la file de vérification des établissements avec Valider/Rejeter ; la richesse fonctionnelle (40 destinations couvrent réellement l'exploitation, la conformité et la croissance) ; Journaux d'audit et outils RGPD déjà présents.

**Trois familles de problèmes** :
1. **Fiabilité** — le cockpit se contredit (« Encaissé total 45 € » sur une carte, « Encaissé : 0 € » deux écrans plus bas ; 54 € tantôt HT tantôt TTC ; deux « GMV » homonymes dont un vient des seeds et l'autre de Stripe ; KPI « 10 établissements à valider » pour une file qui en contient 6) ; la page Audit RLS est morte ; Statut système affiche 23 alertes actives dont l'écrasante majorité sont des scories historiques jamais résolues — le canal est noyé, et c'est là que tomberont les tripwires premier-euro.
2. **Architecture** — ~40 destinations dans deux méga-grilles plates, cockpit fondateur mélangé aux ops, au légal et aux outils dev ; franglais (« Sales / Sourcing », « Cohortes & economics ») ; doublons (Statut système / Healthcheck, Vérif. établissements en double).
3. **Mécanique** — emojis-icônes, mission `[pw-test:match]` et entrées fantômes (« H », « G », NAF 62.01Z pour une clinique) visibles dans les files réelles, toast qui recouvre un KPI, « Suspendre » en action la plus proéminente de chaque carte utilisateur, double barre de recherche « serveur / locale », `CLINIQUE_PRIVEE` brut, « 31.00 € », « IS estimé : -0 € ».

---

## Lot 19 — Fiabilité admin & canal d'alerte ⚠️ avant le premier euro réel

**Objectif** : un admin dont les chiffres disent vrai et dont les alertes redeviennent un signal — le silence quand tout va bien, du bruit uniquement quand il faut.

**Périmètre** :
1. **Cycle de vie des alertes** : dédoublonnage par (cron, type) — une alerte porte un compteur d'occurrences et première/dernière date, jamais N cartes identiques ; **auto-résolution** quand le cron repasse vert ; états Active / Résolue / Acquittée, vue par défaut = actives seulement, historique séparé ; sévérité héritée du tiering (tout ce qui touche l'argent = critique).
2. **Triage des 23 alertes actuelles** (s'appuie sur l'A4-bis de l'audit) : `relance-candidatures-en-attente` (échecs répétés 28-29/06 — remplacé par les vagues du Lot 17 ? → décommissionner et résoudre) ; `sepa-auto-charge-daily` (retards 30/06-01/07 — planning changé ou seuil de retard mal calibré ?) ; `matching_scores_recalcul_hourly` (échec du 09/07 — doublon de `jolene_recalcul_scores_etab` ? → décommissionner l'ancien). Chaque série : cause écrite, action prise, alerte résolue.
3. **Cockpit à source unique** : une RPC par métrique d'argent, consommée partout — fin du « Encaissé 45 € vs 0 € » ; libellés HT/TTC explicites sur chaque montant ; « GMV missions » (données de test) visuellement distinct de « GMV Stripe réel » avec badge « Données de test » tant que la purge pré-publication n'est pas faite ; KPI « établissements à valider » branché sur la file réelle.
4. **Audit RLS** : diagnostic (route absente, flag, crash) → réparée, ou retirée proprement du menu avec ticket.
5. **Tripwires premier-euro rebranchés** sur le nouveau canal : sévérité critique + email en plus de l'alerte in-app, testés de bout en bout (événement simulé → alerte visible + email reçu).

**Hors périmètre** : réorganisation des menus (Lot 20), finitions visuelles (Lot 21).

**Critère /goal** :

```
/goal Le canal d'alerte et le cockpit admin sont fiables, prouvé par assertions : les alertes sont dédoublonnées par (cron, type) avec compteur et états Active/Résolue/Acquittée, une alerte de test s'auto-résout quand son cron repasse vert (testé), les 23 alertes historiques sont triées avec cause documentée dans la PR et le tableau de bord n'affiche plus que les actives réelles ; chaque métrique d'argent du cockpit est servie par une RPC unique et testée contre elle (Encaissé, Facturable, Commission, GMV), les montants portent HT ou TTC explicitement, les données de seed sont badgées « Données de test », le KPI établissements à valider égale le compte réel de la file (e2e) ; la page Audit RLS répond avec son contenu ou a disparu du menu avec ticket documenté ; un événement tripwire simulé produit une alerte critique visible ET un email (mode test). npm run test:regression et test:escrow verts. Stop après 12 turns.
```

**Risques & invariants** : on touche au canal qui surveillera l'argent réel — test:escrow obligatoire avant merge (B7 le force désormais) ; l'auto-résolution ne doit jamais masquer un échec en cours (une alerte ne se résout que sur run *vert*, pas sur absence de run).

---

## Lot 20 — Architecture de l'information admin (desktop-first)

**Objectif** : passer de deux méga-grilles de ~40 items à une navigation par domaines, pilotable au quotidien — l'admin se vit sur Mac, la navigation devient une sidebar.

**Périmètre** :
1. **Cinq domaines** en navigation latérale desktop (regroupement équivalent en mobile) :
   - **Opérations** : tableau de bord ops, vérification établissements, missions & pool urgence, litiges, alertes pointage, planning & calendrier, modération & signalements, réclamations & scores, heures externes (3200h), groupes santé.
   - **Argent** : facturation, taux de commission & paliers BFA, Chorus Pro, externalisations/affacturage, exports comptables.
   - **Croissance** : cockpit fondateur, acquisition, prospection, cohortes & économie, équipe, levée & documents.
   - **Conformité & légal** : conformité, DPIA, outils RGPD, journaux d'audit, audit RLS, CGU, confidentialité, mentions légales, suppression de compte, contrats & templates.
   - **Système** : statut système (fusionné avec Healthcheck — doublon), configuration, emails, API, démo.
2. **L'accueil admin devient le tableau de bord opérationnel du jour** : les files actionnables (à valider, impayées, litiges, alertes actives) en premier — le cockpit fondateur devient la page d'entrée du domaine Croissance, il ne se mélange plus aux ops.
3. **Dédoublonnage** : une seule entrée « Vérification établissements » (elle existe aujourd'hui dans le menu ET dans Gestion utilisateurs) ; « Vue d'ensemble » fusionnée avec le tableau de bord ; Statut système + Healthcheck = une page.
4. **Français partout** : « Sales / Sourcing » → « Prospection », « Cohortes & economics » → « Cohortes & économie », « Healthcheck » disparaît par fusion.
5. **Recherche globale unique** : fusion des deux barres (serveur / locale) — la distinction devient un détail d'implémentation invisible ; résultats mêlés soignants / établissements / missions.
6. **Breadcrumb + deep links** testés au clic (pattern n°4 du CLAUDE.md).

**Hors périmètre** : refonte visuelle des pages elles-mêmes (Lot 21), toute nouvelle feature.

**Critère /goal** :

```
/goal L'admin est réorganisé en 5 domaines, prouvé par assertions : sidebar des 5 domaines rendue en 1440×900 et navigation par regroupement en 390×844, chaque destination de l'ancien menu a exactement une nouvelle maison (table de mapping ancienne→nouvelle route dans la PR, redirections posées et testées), zéro doublon de destination (Vérif. établissements unique, Statut/Healthcheck fusionnés), zéro libellé anglais dans la navigation (git grep sur les libellés de nav), la recherche unique retrouve un soignant, un établissement et une mission (e2e), l'accueil admin affiche les files actionnables et le cockpit fondateur vit dans Croissance. npm run test:regression vert. Stop après 10 turns.
```

**Risques** : c'est un déménagement — les redirections des anciennes routes sont obligatoires (tes propres habitudes + tout lien encore vivant), et le mapping écrit dans la PR est la preuve qu'aucune destination n'a été perdue en route.

---

## Lot 21 — Mécanique & finitions admin

**Objectif** : appliquer à l'admin le standard déjà imposé aux interfaces soignant et établissement.

**Périmètre** :
1. **Icônes** : emojis → lucide partout (🏥👤📅 des cartes missions, 💰 du cockpit…).
2. **Données de test — décision Gabrielle du 12/07/2026** : les seeds `[pw-test:*]` restent **visibles** afin de préparer les screenshots stores ; aucune liste ne les masque. L'admin les identifie avec un badge « Donnée de test ». La purge reste une action humaine pré-publication ; enums mappés (`CLINIQUE_PRIVEE`, `LABO`…), labels INSEE propres.
3. **Actions utilisateurs rééquilibrées** : Détails devient l'action primaire ; Suspendre rétrogradé en secondaire, derrière une confirmation avec **motif obligatoire journalisé** dans `journaux_audit` ; cibles ≥ 44 px.
4. **Formats français** : « 31,00 € », dates insécables (« 26 juin » sans retour à la ligne), « -0 € » → « 0 € », HT/TTC explicites hors cockpit (le cockpit est traité au Lot 19).
5. **Toasts** : position qui ne recouvre jamais un KPI ou un CTA (le pattern FAB, version notification), auto-dismiss.
6. **Vérification établissements enrichie** : warnings automatiques pour éclairer Valider/Rejeter — code NAF hors famille santé (« 62.01Z : inhabituel pour un établissement de santé »), SIRET invalide (Luhn), lien vers l'annuaire officiel. C'est ton vrai workflow de vetting au lancement : chaque minute gagnée compte.
7. **Dark mode admin** : les écrans principaux passent le contraste AA en sombre, ou le toggle disparaît — règle « pas de feature à moitié ».
8. **Cockpit, finitions** : « Coût société (×1.82) » expliqué d'un mot, disclaimer raccourci.

**Critère /goal** :

```
/goal La mécanique admin est au standard des deux autres interfaces, prouvé par assertions : git grep zéro emoji-icône dans les pages admin, données `[pw-test:*]` conservées visibles et clairement badgées (décision Gabrielle du 12/07/2026), Suspendre exige un motif et l'écrit dans journaux_audit (INSERT réel vérifié), formats français testés (31,00 € ; aucune date coupée ; 0 € jamais négatif), aucun toast rendu sur une zone interactive (assertion de position), les warnings NAF/SIRET s'affichent sur les cas de test de la file de vérification, dark mode : les 6 écrans principaux passent AA ou le toggle a disparu. npm run test:regression vert. Stop après 10 turns.
```

---

## Ordre, articulation & séquencement vers la publication

**Ordre interne** : 19 → 20 → 21 — la fiabilité avant le déménagement, le déménagement avant la peinture. Chaque lot passe par le protocole complet désormais automatisé : checks CI requis (test:regression, guards, test:escrow si paiements), revue fraîche en PR, tiering des merges (le Lot 19 touche au canal de l'argent → feu vert humain).

**Séquencement global recommandé** (soumettre ≠ publier — publication manuelle sur les deux stores) :
1. Audit de clôture A vert (en cours).
2. Salve store-readiness.
3. Screens + passe TestFlight (Gabrielle) → **soumission en publication manuelle**.
4. Pendant la review (1-7 j) : Lots 19-21 + **mission témoin réelle** (premier euro contrôlé, tripwires du Lot 19 en place).
5. Tout est prêt + approbation reçue → purge des données de test (sauf compte démo Apple) → **publication**.

Variante « tout avant de soumettre » : mêmes étapes, 19-21 et mission témoin intercalés avant la soumission — coût : la durée de review s'ajoute au calendrier au lieu d'être absorbée.
