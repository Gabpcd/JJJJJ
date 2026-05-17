# Sprint 13 FINAL — Swipe matching Hinge-style (A → D)

Sprint 13 livre la fonctionnalité différenciante face à Mediflash/Hublo : **matching soignant ↔ missions en mode swipe Hinge**, avec algorithme premium, UI ultra-fluide, mécaniques engagement, et tests E2E.

## Sous-sprints livrés

| Sous-sprint | Focus | PRs | Livré |
|---|---|---|---|
| **13-A** | Algorithme matching premium | 5 (#316-#320) | 3 tables (matching_scores, swipes, super_swipes_quota) + 3 RPCs + cron horaire + edge function notif-match + tests stubs |
| **13-B** | UI swipe ultra-fluide Hinge-style | 5 (#321-#325) | CardMissionSwipe Y2K + StackCards gestures + BoutonsActionSwipe + ConfettiSwipe + SwipeMissions page + ModalDetailMissionSwipe |
| **13-C** | Mécaniques engagement | 5 (#326-#330) | 8 badges (PREMIER_SWIPE/EXPLORATEUR/TOP_SWIPER/PREMIER_SUPER_LIKE/PREMIER_MATCH/MATCH_KING_QUEEN/30_DAYS_STREAK/100_DAYS_STREAK) + streaks quotidien + CelebrationMatch modal + edge function notif-candidature-acceptee + page MesMatches |
| **13-D** | Liste classique + tests E2E + doc | 4 (#331-#334) | Toggle Swipe/Liste persistant + E2E swipe UI + E2E flow complet + doc finale |
| **Total** | | **19 PRs** | |

## Stack technique livré

### Backend Supabase (Sprint 13-A + 13-C)

**Tables** (4) :
- `matching_scores` — cache score 0-100 soignant×mission + breakdown JSONB
- `swipes` — historique LIKE/DISLIKE/SUPER_LIKE immuable (UNIQUE par soignant×mission)
- `super_swipes_quota` — compteur quotidien super-likes (CHECK count ≤ 5)
- `badges_soignant` — badges engagement (UNIQUE par soignant×badge_type)
- `streaks_soignant` — streak quotidien + max_streak historique

**RPCs** (6) :
- `fn_calculer_score_matching(soignant_id, mission_id)` — algorithme scoring multi-critères
- `fn_obtenir_missions_swipe(p_limit)` — missions OUVERTE non-swipées triées par score DESC
- `fn_enregistrer_swipe(p_mission_id, p_direction)` — INSERT swipe + quota super-likes
- `fn_recalculer_scores_soignants_actifs()` — cron horaire pré-calcul
- `fn_mes_badges()` — liste badges du soignant
- `fn_ma_streak()` — streak + max + actif_aujourdhui + risque_perte
- `fn_mes_matches()` — candidatures ASSIGNEE issues d'un swipe + stats engagement

**Triggers** (3) :
- `trg_award_badges_swipe` AFTER INSERT swipes (PREMIER_SWIPE/EXPLORATEUR/TOP_SWIPER/PREMIER_SUPER_LIKE)
- `trg_award_badges_match` AFTER UPDATE candidatures (PREMIER_MATCH/MATCH_KING_QUEEN)
- `trg_update_streak_on_swipe` AFTER INSERT swipes (incrément + reset + badges 30/100 days)

**Cron pg_cron** : `matching_scores_recalcul_hourly` @ `0 * * * *` (toutes les heures, batch 200 soignants × 50 missions).

**Edge functions** (2) :
- `notif-match` — SUPER_LIKE → notification INSERT étab type MATCHING_SUPER_LIKE
- `notif-candidature-acceptee` — étab accepte → notification INSERT soignant type MATCHING_CANDIDATURE_ACCEPTEE (titre "🎉 C'est un match !" si via swipe)

### Algorithme scoring (Sprint 13-A PR 2)

**Filtres durs (KO immédiat → score 0)** :
- `mission.profession_requise <> soignant.profession`
- distance Haversine > 50 km

**Filtres softs (somme pondérée 100)** :
| Critère | Poids | Logique |
|---|---|---|
| Tarif horaire | 25 | >= 30€/h = 25, dégressif sous 30 |
| Distance | 25 | < 5km = 25, dégressif jusqu'à 0 à 50km |
| Score étab qualité | 20 | etab.score_qualite / 100 * 20 |
| Urgence | 15 | +15 si mission urgente |
| Fiabilité soignant | 15 | score_fiabilite / 100 * 15 |

Pondérations affinables Sprint 13-E selon analytics réels post-launch.

### Frontend Y2K (Sprint 13-B + 13-C + 13-D)

**Composants swipe** (`src/components/swipe/`) :
- `CardMissionSwipe` — card plein écran Y2K (gradient hero rose-mauve, badge Match X/100 premium si ≥80, grid 3 cols infos)
- `StackCards` — stack 3 cards parallax + gestures Pointer Events + spring physics
- `BoutonsActionSwipe` — DISLIKE/SUPER_LIKE/LIKE + haptic feedback navigator.vibrate
- `ConfettiSwipe` — animation CSS 30/60 particules rose/mauve/cyan/butter
- `ModalDetailMissionSwipe` — détail mission expansion + breakdown score
- `CelebrationMatch` — modal plein écran Mascotte celebrating + 60 confettis

**Pages soignant** :
- `/soignant/swipe-missions` (Sprint 13-B PR 4) — page swipe principale
- `/soignant/mes-matches` (Sprint 13-C PR 5) — liste matches + stats engagement

**Toggle Swipe/Liste** (Sprint 13-D PR 1) :
- localStorage `jolene_missions_view_pref` ('swipe' | 'liste')
- Pill toggle 2 boutons visible sur SwipeMissions + RechercheMissions
- Default Swipe, persistant ensuite

## Mécaniques engagement Hinge-grade

### Badges (8 types)

| Badge | Déclencheur |
|---|---|
| `PREMIER_SWIPE` | 1er swipe |
| `EXPLORATEUR` | 50 swipes cumulés |
| `TOP_SWIPER` | 200 swipes cumulés |
| `PREMIER_SUPER_LIKE` | 1er SUPER_LIKE |
| `PREMIER_MATCH` | 1ère candidature ASSIGNEE issue swipe LIKE/SUPER_LIKE |
| `MATCH_KING_QUEEN` | 10 candidatures ASSIGNEE via swipe |
| `30_DAYS_STREAK` | streak quotidien atteint 30 |
| `100_DAYS_STREAK` | streak quotidien atteint 100 |

### Streaks quotidien
- 1 swipe/jour = +1 streak
- Lendemain sans swipe = reset à 1
- `max_streak` historique persisté
- `risque_perte=true` si swipé hier mais pas aujourd'hui (UI peut afficher rappel)

### Quota anti-spam
- Super-likes limités à **5/jour** (CHECK constraint DB + validation RPC)
- Badge compteur visible bouton SUPER_LIKE (5 → 4 → 3 → 2 → 1 → 0 disabled)
- Reset automatique date suivante

### Confettis Y2K
- 30 particules sur SUPER_LIKE déclenché
- 60 particules sur CelebrationMatch (match accepté)
- Couleurs Y2K rose/mauve/cyan/butter
- `prefers-reduced-motion` respecté

### Haptic feedback (mobile)
- DISLIKE : `navigator.vibrate(15)` (court)
- LIKE : `[10, 30, 10]` (tap-tap)
- SUPER_LIKE : `[20, 40, 20, 40, 60]` (crescendo)

## Tests E2E (Sprint 13-A PR 5 + 13-D PR 2 + PR 3)

- **matching-backend.spec.ts** : 11 spec stubs RPCs + RLS + edge functions
- **swipe-matching-ui.spec.ts** : 10 spec stubs UI swipe + toggle + modal + EmptyState
- **matching-complete.spec.ts** : 6 spec stubs flow end-to-end multi-comptes (soignant + étab via browser.newContext)

Pattern `test.skip(true)` cohérent avec specs existantes (candidature.spec.ts, dpae-confirmation.spec.ts). Implémentation détaillée post-lancement quand helpers seed multi-comptes prêts.

## Décisions techniques

### Pourquoi Pointer Events vs framer-motion
- StackCards utilise `setPointerCapture` + transform inline + transition-bouncy CSS
- **Économie ~80KB bundle** vs framer-motion
- `prefers-reduced-motion: reduce` géré nativement via `@media reduce` index.css

### Pourquoi pré-calcul cron horaire
- fn_calculer_score_matching coûteuse (Haversine + JOINs) si appelée live à chaque fetch
- Pré-calcul horaire pour 200 soignants × 50 missions max par run = ~10000 scores cached
- fn_obtenir_missions_swipe utilise LEFT JOIN matching_scores → fast read

### Pourquoi notifications via edge function vs trigger DB
- Trigger DB ne peut pas appeler `pg_net.http_post` de façon fiable en cas de timeout
- Edge function notif-match invoqué depuis le client après mutation swipe (best-effort)
- Edge function notif-candidature-acceptee appelable par trigger DB OU UI étab côté front
- Audit trail via `fn_ecrire_audit_safe` dans les 2 cas

### RechercheMissions "refonte" — Sprint 12 fait, Sprint 13-D PR 2 skipped
La refonte filtres avancés Y2K était listée Sprint 13-D PR 2 dans le brief initial. **Audit révèle que RechercheMissions a déjà été refonté en Y2K Sprint 12** : filtres profession/rayon/tarif/typeContrat/urgentesOnly/horaire/villeRecherche + Map Leaflet + BoutonY2K toggles. **Skip honnête** : refonte déjà acquise, on a juste ajouté le toggle Swipe/Liste (Sprint 13-D PR 1).

## Bilan Sprint 13 complet

- **19 PRs livrées en prod** (5 + 5 + 5 + 4)
- **5 tables** + **6 RPCs** + **3 triggers** + **1 cron pg_cron** + **2 edge functions**
- **6 composants swipe Y2K** + **2 pages soignant**
- **8 types badges** + **streaks quotidien** + **quota super-likes 5/jour**
- **3 spec files E2E** (27 tests stubs)
- **0 PR ouverte** post Sprint 13
- **0 régression CI**

### Hotfixes appliqués pendant Sprint 13
- Workflow deploy-supabase initialement rouge sur migrations Sprint 13-A (pas registered dans schema_migrations après MCP apply_migration). Fix : INSERT manuel via MCP execute_sql. Désormais chaque migration MCP est suivie d'un INSERT explicit dans `supabase_migrations.schema_migrations` pour éviter le drift.

### URLs prod
- `/soignant/swipe-missions` — page swipe Hinge-style
- `/soignant/mes-matches` — liste matches + stats engagement
- `/soignant/recherche-missions` — vue liste classique (toggle persistant)

## Reportés Sprint 13-E (post-launch)

- Notifications push web (Service Worker + web-push) pour notif match (UI fallback in-app via subscribe realtime)
- Page profil soignant : section "Mes badges" avec collection + dates earned
- Widget streak sur DashboardSoignant (banner Mascotte happy + count)
- Affinage pondérations algorithme matching selon analytics 14 jours post-launch
- A/B test confetti on/off (préférences soignant)
- Son optionnel sur SUPER_LIKE / match (toggle dans préférences notifications)
- Page admin /admin/matching-stats : analytics globales (taux match, top missions, profession matrix)
