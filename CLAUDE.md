# CLAUDE.md

> Conventions et règles de travail pour Claude Code sur le projet Jolene.

## Workflow Git — règles non-négociables

1. **Branche feature** : créer une branche descriptive si la modification est non-triviale, ou commit direct sur main pour les fixes mineurs
2. **Commit + push** : messages Conventional Commits (feat:, fix:, chore:, docs:, refactor:)
3. **Ouverture de PR** automatique via `gh pr create` ou `mcp__github__create_pull_request`
4. **Résolution de conflits** : automatique. Règle par défaut : en cas de doute, conserver les blocs des DEUX côtés
5. **Merge automatique** via `gh pr merge --squash` ou `mcp__github__merge_pull_request`
6. **Surveillance du déploiement** : suivre `deploy-supabase` jusqu'à confirmation verte
7. **Rapport final** : URLs de la PR mergée, du run de workflow, confirmation prod

### Vérification CI systématique — règle non-négociable

1. **Avant merge** : `get_check_runs` → tous les checks `success` requis (Typecheck+build, Drift, Lighthouse, Vercel)
2. **Après merge** : refaire `get_check_runs` sur merge commit (push event re-trigger CI)
3. **Si CI rouge sur main** : commit hotfix IMMÉDIATEMENT
4. **`npx tsc -b` local AVANT push** : reproduit le check CI
5. **Subagents Write/Edit** : après chaque subagent qui touche TS/TSX, faire un `npx tsc -b`

## Règles migrations Supabase

1. Format obligatoire `YYYYMMDDHHMMSS_*.sql` (14 chiffres)
2. PAS de `BEGIN;`/`COMMIT;` internes
3. Avant tout `INSERT INTO journaux_audit` : vérifier CHECK constraint
4. Si migration échoue : supprimer le fichier
5. Test deploy manuel `supabase db push --dry-run` si possible
6. Surveillance post-merge via MCP Supabase
7. Dollar-quoting imbriqué interdit avec `$$` — utiliser tags distincts (`$body$`)

## Règles TypeScript / build

- `npx tsc -b` (pas `--noEmit`) pour valider en local
- Valeurs exactes des enums `UserRole` : `SOIGNANT` | `ADMIN_ETABLISSEMENT` | `ADMIN_PLATEFORME` | `ADMIN_GROUPE`
- Colonnes DB non encore dans types TS : utiliser `as any` ciblé

## Workflows produits

### Sprint 1 + 2 — Signature électronique, contrats, DPAE, restrictions Mediflash
### Sprint 3.5 — Litiges + Annulation + Score + Réclamations
### Sprint 4 — Push natif + worker externalisation + Capacitor
### Sprint 4.5 — Anti-triche pointage (cf. docs/ANTI_TRICHE_POINTAGE.md)
### Sprint 5 — Audit frontend exhaustif (cf. docs/AUDIT_FRONTEND_EXHAUSTIF.md)
### Sprint 5.5 — Fixes P0 critiques (8/13 P0 résolus)
### Sprint 5.7 — Fixes 5 P0 majeurs restants (5/5 P0 résolus)
### Sprint 6 — Fixes P1 audit Sprint 5 (12/15 P1 résolus)
### Sprint 7 — P1 restants + P2 cosmétiques (10 PRs)

### Sprint 8 — Polish UX global + briques mobile-first (9 PRs)
Cf. docs/UX_POLISH_STANDARDS.md.

8/9 PRs livrées : Skeletons, EmptyState, Toasts unifiés, useApiCall+errorMessages,
useViewport+inputMobile, BannerAdminMobile, ImageOptimisee, BoutonsBulkFactures wiré, Doc.

### Sprint 8 BIS — Wiring polish UX (4 PRs)
Cf. docs/RESPONSIVE_MOBILE.md.

| PR | # | Chantier | Livré |
|---|---|---|---|
| 1 | #191 | TableOuCartes + DialogResponsive | Briques foundation : `<TableOuCartes>` (table↔cartes selon viewport) + `<DialogResponsive>` (modal fullscreen mobile / centered desktop) |
| 2 | #192 | Wiring EmptyState SOIGNANT | 3 pages migrées : MesAvances, BulletinsPaie, MesFacturesHonoraires (variant info/warning selon mandat) |
| 3 | #193 | Majorations CCN tooltip (P2 §6) | `lib/majorationsCCN.ts` détection nuit/dimanche/férié + badge `+X% CCN` sur CarteMissionSoignant avec tooltip détail (CCN 51 art. 82/83) |
| 4 | this | Documentation Sprint 8 BIS | docs/RESPONSIVE_MOBILE.md + CLAUDE.md |

#### Bilan Sprint 8 BIS
- 1 P2 résolu (§6 majorations breakdown)
- 2 briques foundation prêtes (TableOuCartes + DialogResponsive)
- 3 pages SOIGNANT wirées EmptyState

### Sprint 8 BIS ter — Wiring complet mobile-first (A → J, 45+ PRs)
Cf. docs/SPRINT_8_BIS_FINAL.md.

**Sprints livrés en cascade :**

| Sprint | Livré | PRs |
|---|---|---|
| 8 ter-A BIS | 21 pages EtatVide → EmptyState (#203) | 1 PR consolidée |
| 8 ter-B | 5 PRs tableaux SOIGNANT → TableOuCartes (#204-208) | 5/5 |
| 8 ter-C | 4 PRs tableaux ÉTAB part 1 → TableOuCartes (#209-212) | 4/4 |
| 8 ter-D | Tableaux ÉTAB part 2 + ADMIN (#213-216) | 4/5 (skip ListeMissions = series+singles, déjà responsive) |
| 8 ter-E | Modales SOIGNANT → DialogResponsive (#217-220) | 4/5 (skip SignerContratOtp = inline, argument juridique art. 1366) |
| 8 ter-F | Modales ÉTAB → DialogResponsive (#221-224) | 4/5 (skip SignerContratOtp étab = même justification) |
| 8 ter-G | Lazy-load modales + React.memo TableOuCartes (#225-229) | 5/5 (~49KB économisés bundle) |
| 8 ter-H | A11y RGAA AA — audit lucide : ~92% déjà conforme, 2 fixes ciblés (#230-231) | 2/5 (3 chantiers déjà OK) |
| 8 ter-I | E2E tests — audit lucide : 31 specs / 3019L déjà en place, 2 gaps comblés (#232-233) | 2/5 (réclamation score + DPAE) |
| 8 ter-J | A11y residuals + doc finale | 4 PRs (3 a11y + doc) |

#### Bilan global Sprint 8 BIS complet
- **Pattern foundation** : `<TableOuCartes />` + `<DialogResponsive />` + `<EmptyState />` + `useDebounce` + `useViewport` + `ImageOptimisee` (tous Sprint 8 BIS PR #191)
- **Couverture mobile-first** : 100% tableaux SOIGNANT/ÉTAB/ADMIN + 100% modales workflow critiques migrées
- **Performance** : ~49KB économisés du bundle initial via lazy-load 5 modales + React.memo TableOuCartes
- **A11y** : ~96% RGAA AA conforme (axe-core CI sur 9 pages publiques, skip links, focus-visible, prefers-reduced-motion, ARIA live, htmlFor/id sur inputs)
- **E2E** : 33 spec files / ~3211 lines (réclamation score Sprint 3.5 + DPAE legal ajoutés)
- **Skips honnêtes documentés** : 6 PRs skippées avec justification (régression UX, RPCs backend manquants, inline composants juridiquement critiques, N/A absence de vidéo)

#### Reportés Sprint 8.5 dédié
- P2 §12 context menu actions admin missions (besoin RPCs backend `fn_admin_modifier/arreter/rembourser_mission`)
- Admin mobile-first complet (pages admin restantes)
- Lighthouse mobile soignant >90 mesure absolue (Vercel preview)

### Sprint 8.5 — Admin mobile-first (A → D, 8 PRs)
Cf. docs/SPRINT_8_5_FINAL.md.

| Sprint | Livré | PRs |
|---|---|---|
| 8.5-A | Navigation admin : useScrollDirection + suppression BannerAdminMobile | 2 (#238 #240) |
| 8.5-B | Tableaux admin part 1 : AdminMissions / AdminContrats / AdminTemplatesContrats | 3 (#241-243) |
| 8.5-C | Tableaux admin part 2 : AdminScoreTriage / AdminAuditLogs | 2 (#244-245) |
| 8.5-D | AdminEmails + doc finale | 2 |

#### Bilan Sprint 8.5
- **8 PRs livrées** sur 18 pages admin auditées
- **Pages migrées (8) avec TableOuCartes** : AdminUtilisateurs, AdminMissions, AdminContrats, AdminTemplatesContrats, AdminScoreTriage, AdminAuditLogs, AdminEmails + LayoutAdmin scroll-aware
- **Pages N/A (4)** : AdminDashboard (KPI grid), AdminReclamationsScore, AdminAlertesPointage, AdminExternalisationsActions (déjà cards)
- **Pages reportées post-launch (7)** : AdminFacturation, AdminChorusPro, AdminConformite, AdminModeration, AdminFinances, AdminGroupes, AdminDetailUtilisateur (haute complexité, refactors dédiés nécessaires)

#### Reportés post-launch (Sprint 10+)
- Refactor AdminFacturation (expandable + bulk + multi-status actions)
- Refactor AdminChorusPro (3 tables workflow)
- Refactor AdminConformite (audit multi-sections)
- Refactor AdminModeration (6 tabs)
- Mesure Lighthouse absolue mobile soignant
- P2 §12 RPCs backend admin missions

### Sprint 9-B — Mascotte + composants Y2K (5 PRs)
Cf. docs/COMPOSANTS_Y2K.md.

- **PR 1** : `Mascotte.tsx` (cœur arrondi Y2K, 5 états : idle/happy/thinking/celebrating/empty). SVG vectoriel avec dégradé rose→mauve + animations CSS (pas de framer-motion, bundle plus léger). Tailles sm/md/lg/xl.
- **PR 2** : `BoutonY2K.tsx` (primary/secondary/ghost variants, gradient hero + shadow holographique sur primary).
- **PR 3** : `CardY2K.tsx` (default/holographic/glass variants, glassmorphism `backdrop-blur-xl`).
- **PR 4** : `BadgeY2K.tsx` (success/warning/error/info/premium, le dernier en gradient celebrate).
- **PR 5** : `docs/COMPOSANTS_Y2K.md` + rappel ton de voix sobre PRO.

**Ton de voix préservé** : vouvoiement, pas d'argot ("slay/iconic/girlie" interdits). L'effet Gen Z vient à 100% de l'UI visuelle.

### Sprint 9-A — Fondations CSS Y2K Gen Z (4 PRs)
Cf. docs/IDENTITE_VISUELLE_JOLENE.md.

- **PR 1** : Variables CSS palette Y2K dans `src/index.css` — `--jolene-rose/mauve/cyan/butter` (avec variantes 50→900) + neutres `--jolene-lavender/cloud/midnight/bubblegum`. Light + dark mode.
- **PR 2** : Tailwind config étendu — alias `jolene-rose`, `jolene-mauve`, etc. utilisables comme `bg-jolene-rose-500`.
- **PR 3** : Dégradés utility classes — `.bg-gradient-hero` (linear rose→mauve→cyan), `.bg-gradient-soft` (lavender→rose pâle), `.bg-gradient-celebrate` (conic 4 couleurs), `.bg-holographic` (animé 8s, `prefers-reduced-motion` respecté), `.text-gradient-hero`, `.shadow-holographic`.
- **PR 4** : Documentation `docs/IDENTITE_VISUELLE_JOLENE.md` (HEX/HSL/usage Tailwind/accessibilité).

**Non-breaking** : palette ajoutée EN PARALLÈLE du design system existant (`--primary`, `--rose`, etc.). Migration progressive.
