# Stratégie UX — Refonte « addictive + instinctive »

> Audit complet du 11/06/2026 (162 routes, 3 interfaces) + plan d'exécution en sessions.
> Objectif : rétention soignants + intuitivité totale. Principe directeur : **chaque écran
> répond d'abord à « qu'est-ce que JE fais maintenant »**, le reste est secondaire.

## Diagnostic global

L'app est ~70 % bien structurée, 20 % fragmentée (routes redondantes, paramètres éclatés,
wording incohérent), 10 % de gamification existante mais invisible. Le design system Y2K
est en place (BoutonY2K/CardY2K/BadgeY2K/Mascotte/gradients) mais pas appliqué aux Tabs ni
exploité pour l'engagement quotidien.

### Problèmes transverses identifiés
1. **Wording incohérent** : « Menu » vs « Profil » vs « Mon compte » ; « Tableau de bord »
   route vs « Accueil » label ; titres de pages ≠ labels de nav. → corrigé en partie (PR Session A).
2. **Routes redondantes** : 12+ redirections masquées (`/soignant/documents`,
   `/soignant/fiabilite`, `/etablissement/analytics`…). À consolider, pas à multiplier.
3. **Dashboards trop denses** : 9-10 blocs de poids égal, scroll infini mobile, l'action
   du jour noyée (le bandeau « À faire maintenant » des pages mission est le bon pattern
   à généraliser aux dashboards).
4. **Gamification cachée** : badges/streaks/score/classement/super-likes existent mais ne
   sont pas exposés au bon endroit (dashboard, swipe, post-action).
5. **Nav mobile ≠ nav desktop** : la bottom nav 5 items ne mappe pas la sidebar groupée.

## Sessions d'exécution

### ✅ Session A — App globale + bugs (11/06/2026, cette session)
- Fix « Impossible de charger les litiges » (FK manquantes litiges→soignants/etablissements)
- Suppression doublon contestations score admin (onglet legacy vide)
- KPIs Cockpit Fondateur cliquables
- Refonte landing : hero mascotte + accroche bi-audience + micro-preuves factuelles,
  proposition de valeur remontée avant « Comment ça marche », étapes réécrites neutres,
  suppression des données inventées (rating 4.8/150, « centaines d'utilisateurs »)
- Bottom nav « Menu » → « Profil » (soignant + étab) + titres de pages alignés

### Session B — Interface SOIGNANT (rétention = priorité n°1)
1. **Dashboard hero compact** : score + streak + prochain badge + « À faire maintenant »
   en haut ; suggestions limitées à 3 cartes ; analytics (graphiques, top étabs) en
   section repliable.
2. **Gamification visible** :
   - Compteur super-likes restants en évidence sur SwipeMissions
   - Toast/confetti « badge débloqué » à la 1re/10e mission (mécanique existe côté DB)
   - Widget « plus que X h avant le badge Y » (progress bar)
   - Classement : teaser « Top 3 de votre profession cette semaine » sur le dashboard
3. **Consolidation documents** : `/soignant/mes-documents` = Justificatifs | Contrats |
   DPAE (supprimer la page DPAE séparée, rediriger)
4. **Paramètres unifiés** : un seul hub `/soignant/parametres` (compte, préférences
   missions, notifications, recherches sauvegardées, avancé) ; `/soignant/profil` = identité
   publique + documents seulement
5. **Missions par défaut** : onglet Missions mobile → page avec toggle Swipe/Liste visible
   immédiatement (le swipe est le différenciateur addictif, il doit être à 1 tap)
6. Tabs stylées Y2K partout (TabsList rose/mauve au lieu du gris shadcn)

### Session C — Interface ÉTABLISSEMENT (conversion + récurrence)
1. **Dashboard hero compact** : KPIs 2×2 + « À faire maintenant » (candidatures en
   attente, missions sans candidat → booster, factures à régler) ; missions assignées
   limitées à 3 + « Voir tout »
2. **Publication ultra-rapide** : bouton « Republier » 1 clic depuis le dashboard
   (mission précédente dupliquée pré-remplie = re-booking)
3. **Inscription** : barre de progression (étape X/3) + découpage des 10 champs de
   l'étape 2 en 2 écrans
4. **Facturation** : fusionner « Obligations financières » en onglet de Facturation
5. **Tableau RH / Shifts / Export paie** : clarifier le groupe « Gestion » (libellés
   explicites, pages peu découvertes)

### Session D — Interface ADMIN (refonte complète, demandée explicitement)
1. Re-architecture de la sidebar (8 groupes → 5 : Pilotage, Utilisateurs, Opérations,
   Finances, Système) — supprimer les doublons restants
2. Toutes les listes → pattern « file de travail » : ce qui demande une action d'abord,
   le reste en historique
3. Recherche globale admin (utilisateur, mission, facture) en ⌘K
4. Cockpit : KPIs cliquables (fait) + drill-down par graphique
5. Audit page par page des 30+ pages admin (même méthode que Sprint 11)

## Règles de copy (toutes interfaces)
- Vouvoiement, ton chaleureux mais PRO (pas d'argot) — l'effet Gen Z vient du visuel
- Jamais de jargon technique exposé (pas de « RPC », « legacy », noms de tables)
- Jamais de données inventées (chiffres, notes, logos) — uniquement des faits produit
- Titres orientés action (« Publier une mission ») plutôt que catégorie (« Gestion »)
- 1 émoji max par titre, comme marqueur visuel, pas comme décoration systématique
