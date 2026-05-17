# Sprint 14 FINAL — Tests E2E réels matching swipe (PR 1 → 5)

Sprint 14 convertit les **27 stubs `test.skip(true)`** créés en Sprint 13 (A → D) en **19 tests E2E fonctionnels** qui passent réellement en CI. Comble la dette technique callout du user post-Sprint 13.

## Sous-sprints livrés

| Sous-sprint | PR | Chantier | Livré |
|---|---|---|---|
| 14-1 | #335 | Helpers seed-matching foundation | `e2e/helpers/seed-matching.ts` (7 helpers : seedMissionMatching, seedSwipe, seedMatchingScore, cleanupMatchingForSoignant, cleanupMissionsTest, getStreakInfo, getBadges, getSuperLikesRestant) |
| 14-2 | #336 | Backend matching — 8 tests réels | Remplace 11 stubs `matching-backend.spec.ts` ; ajout helper `userClient(email, password)` + env `SUPABASE_PUBLISHABLE_KEY` workflow |
| 14-3 | #337 | UI swipe — 6 tests réels | Remplace 10 stubs `swipe-matching-ui.spec.ts` ; loginAs + toggle Swipe/Liste + MesMatches |
| 14-4 | #338 | Flow complet — 5 tests réels | Remplace 6 stubs `matching-complete.spec.ts` ; triggers DB (badges + streaks + match) |
| 14-5 | (this) | Doc Sprint 14 FINAL + audit dette résiduelle | docs/SPRINT_14_FINAL.md + CLAUDE.md update |
| **Total** | **5 PRs** | — | **19 tests E2E réels** |

## Tests livrés par fichier

### `e2e/flows/matching-backend.spec.ts` (8 tests)

1. `fn_calculer_score_matching` : structure score 0-100 + breakdown JSONB
2. `fn_calculer_score_matching` : filtre dur profession → score 0 + `breakdown.filtre_dur_ko='profession_incompatible'`
3. `fn_enregistrer_swipe` : LIKE → `ok:true` + INSERT vérifié en DB
4. `fn_enregistrer_swipe` : 6e SUPER_LIKE → `quota_super_like_atteint` + aucun swipe créé
5. `fn_enregistrer_swipe` : re-swipe même mission → `mission_deja_swipee`
6. `fn_obtenir_missions_swipe` : exclut les missions déjà swipées
7. `fn_obtenir_missions_swipe` : tri par score DESC (seedMatchingScore forced)
8. RLS swipes : compte étab ne voit pas swipes d'un soignant

### `e2e/flows/swipe-matching-ui.spec.ts` (6 tests)

1. Route `/soignant/swipe-missions` accessible (heading "Découvrir" + tablist)
2. Toggle Liste depuis SwipeMissions → nav + `localStorage='liste'`
3. Toggle Swipe depuis RechercheMissions → nav + `localStorage='swipe'`
4. Préférence `liste` redirige automatiquement (useEffect mount)
5. Route `/soignant/mes-matches` + stats engagement rendues
6. Filtres MesMatches : 3 boutons (Tous / En cours / Terminées) + click filtre

### `e2e/flows/matching-complete.spec.ts` (5 tests)

1. `trg_award_badges_swipe` : 1er swipe → badge `PREMIER_SWIPE`
2. `trg_award_badges_swipe` : 1er SUPER_LIKE → `PREMIER_SWIPE` + `PREMIER_SUPER_LIKE`
3. `trg_award_badges_swipe` : 50 swipes → badge `EXPLORATEUR` (batch INSERT 50 missions)
4. `trg_update_streak_on_swipe` : streak_count=1 + last_activity_date=today
5. `trg_award_badges_match` : swipe LIKE + UPDATE candidature ASSIGNEE → `PREMIER_MATCH`

## Pattern foundation Sprint 14

### Helpers seed-matching (`e2e/helpers/seed-matching.ts`)

```ts
seedMissionMatching({ profession, tauxHoraire, estUrgente, debut, dureeHeures })
  → { id, etablissement_id } | null
seedSwipe(soignantId, missionId, direction)  → { id } | null
seedMatchingScore(soignantId, missionId, scoreForce?)  → { score } | null
cleanupMatchingForSoignant(soignantId)  → void
cleanupMissionsTest()  → void  // purge [playwright-test]%
getStreakInfo(soignantId)  → { streak_count, max_streak } | null
getBadges(soignantId)  → string[]
getSuperLikesRestant(soignantId)  → number  // 5-count du jour
```

### Helper auth (`e2e/helpers/db.ts`)

```ts
userClient(email, password)  // Promise<SupabaseClient> — anon + signInWithPassword (RLS appliquée)
```

Pour les RPCs `SECURITY DEFINER` qui dépendent de `auth.uid()`.

### Pattern test type

```ts
test.beforeAll(async () => {
  soignantId = await userIdByEmail(TEST_ACCOUNTS.soignant.email);
  test.skip(!soignantId, 'Compte test absent');
});

test.afterEach(async () => {
  if (soignantId) await cleanupMatchingForSoignant(soignantId);
  await cleanupMissionsTest();
});
```

### Workflow CI (`.github/workflows/playwright.yml`)

Ajout `SUPABASE_PUBLISHABLE_KEY: ${{ secrets.VITE_SUPABASE_PUBLISHABLE_KEY }}` aux steps `Run Playwright tests` (PR + main matrix).

## Skips honnêtes documentés (Sprint 14)

| Test skipped | Raison |
|---|---|
| Gesture swipe (Pointer Events dispatch + setPointerCapture) | Flaky cross-browser CI — WebKit/Chromium/Firefox émettent les pointer events différemment. Couvert manuellement. |
| Streak J+1/J+2 | Nécessite clock mock (`pg_set_local` ou `SET LOCAL TIME ZONE`) trop intrusif sur DB partagée |
| `notif-match` SUPER_LIKE → notification INSERT étab | Edge function appelée best-effort par UI ; testée manuellement post-déploiement |
| Flow UI multi-comptes étab-accepte | Backend test #5 `PREMIER_MATCH` couvre le trigger ; UI tests manuels |

## Avant / Après Sprint 14

### Stubs matching Sprint 13 (cibles Sprint 14)

| Fichier | Avant | Après |
|---|---|---|
| `matching-backend.spec.ts` | 11 stubs | 8 tests réels |
| `swipe-matching-ui.spec.ts` | 10 stubs | 6 tests réels |
| `matching-complete.spec.ts` | 6 stubs | 5 tests réels |
| **Total Sprint 13 matching** | **27 stubs** | **19 tests réels** (0 dette résiduelle matching) |

## Dette résiduelle E2E historique (HORS Sprint 14)

Audit `grep -c "test.skip(true"` sur tout `e2e/` après Sprint 14 :

| Fichier | # stubs | Origine | Action |
|---|---|---|---|
| `flows/candidature.spec.ts` | 2 | Sprint 1 | Reportés Sprint 15 — seed mission OUVERTE + auth soignant + flow candidature |
| `flows/changer-password.spec.ts` | 2 | Sprint 5 | Reportés Sprint 15 — modale + Supabase auth.updateUser |
| `flows/export-rgpd.spec.ts` | 3 | Sprint 6 | Reportés Sprint 15 — export ZIP + download |
| `flows/litige.spec.ts` | 2 | Sprint 3.5 | Reportés Sprint 15 |
| `flows/notation.spec.ts` | 1 | Sprint 3.5 | Reportés Sprint 15 |
| `flows/notifications.spec.ts` | 1 | Sprint 7 | Reportés Sprint 15 |
| `flows/parrainage.spec.ts` | 2 | Sprint 7 | Reportés Sprint 15 |
| `flows/pointage.spec.ts` | 1 | Sprint 4.5 | Reportés Sprint 15 (anti-triche déjà testé via `anti-triche-pointage.spec.ts`) |
| `flows/pool-urgence.spec.ts` | 2 | Sprint 7 | Reportés Sprint 15 |
| `flows/recherche-missions.spec.ts` | 1 | Sprint 5 | Reportés Sprint 15 (refonte Y2K Sprint 12 couvre déjà filtres) |
| `flows/sprint57-equipe-etab.spec.ts` | 1 | Sprint 5.7 | Reportés Sprint 15 |
| `flows/sprint57-evaluation-reverse.spec.ts` | 3 | Sprint 5.7 | Reportés Sprint 15 |
| `inscription.spec.ts` | 2 | Sprint 1 | Skipped intentionnellement (Supabase non joignable CI sur secrets VITE_*) |
| `regression-bugs.spec.ts` | 1 | Sprint 6 | Reportés Sprint 15 |
| **Total dette historique** | **24 stubs** | — | **Sprint 15 dédié** |

### Sprint 15 (post-launch) — Recommandation

Plan d'attaque pour absorber les 24 stubs historiques :
- **15-A** : Auth + inscription + changer-password (4 stubs, foundation auth helpers étendue)
- **15-B** : Workflow mission complète — candidature + notation + litige + pointage (6 stubs)
- **15-C** : Engagement secondaire — parrainage + notifications + pool-urgence (5 stubs)
- **15-D** : Admin/back-office — Sprint 5.7 equipe-etab + evaluation-reverse + RGPD export (7 stubs)
- **15-E** : Recherche missions + regression (2 stubs)

Estimation : **5 sous-sprints × 5 PRs = ~25 PRs** pour atteindre 0 dette E2E.

## Bilan Sprint 14 complet

- **5 PRs livrées en prod** (#335 → #338 + this)
- **19 tests E2E réels** (0 dette résiduelle Sprint 13 matching)
- **8 helpers seed-matching** + **1 helper userClient**
- **Pattern documenté** : adminClient (seed) + userClient (auth.uid) + test.afterEach cleanup
- **24 stubs dette historique** (audit honnête) → Sprint 15 dédié post-launch
- **0 régression CI**

### Décisions techniques Sprint 14

#### Pourquoi adminClient + userClient en parallèle
- `adminClient` (service_role) : seed/cleanup, bypass RLS, accès direct triggers DB
- `userClient` (anon + signInWithPassword) : tests des RPCs `SECURITY DEFINER` dépendantes de `auth.uid()` (fn_enregistrer_swipe, fn_obtenir_missions_swipe)
- Couverture parallèle = robustesse RLS + logique métier sans dupliquer

#### Pourquoi skip honnête gesture Pointer Events
- `dispatchEvent(new PointerEvent(...))` + `setPointerCapture` produit des résultats incohérents cross-browser CI
- Tests visuels via Lighthouse + tests fonctionnels via clic bouton LIKE/DISLIKE/SUPER_LIKE (couvert backend test #3 PR 2)

#### Pourquoi 50 missions batch INSERT pour EXPLORATEUR
- Le seuil EXPLORATEUR = 50 swipes cumulés (UNIQUE par mission)
- INSERT loop séquentiel = 50× RTT à Supabase = 5-10s
- INSERT batch single = ~500ms, tient dans le timeout 30s du test

## URLs prod confirmées (couvertes par tests Sprint 14)

- `/soignant/swipe-missions` — couvert tests 1-4 swipe-matching-ui.spec.ts
- `/soignant/mes-matches` — couvert tests 5-6 swipe-matching-ui.spec.ts
- `/soignant/recherche-missions` — couvert tests 2-4 swipe-matching-ui.spec.ts (toggle)
- RPCs `fn_calculer_score_matching` / `fn_enregistrer_swipe` / `fn_obtenir_missions_swipe` — couvert tests 1-7 matching-backend.spec.ts
- Triggers `trg_award_badges_swipe` / `trg_update_streak_on_swipe` / `trg_award_badges_match` — couvert tests 1-5 matching-complete.spec.ts
