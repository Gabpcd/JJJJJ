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
2. **Timestamps DOIVENT être la date courante** (ou postérieure). Avant de pusher une nouvelle migration, vérifier `list_migrations` pour s'assurer qu'aucune version remote n'est postérieure — sinon `supabase db push` refuse l'ordre out-of-order et le workflow `deploy-supabase` devient rouge (incident Sprint 10-A v3 PR #264-267 → hotfix manuel via MCP `execute_sql` + `INSERT INTO supabase_migrations.schema_migrations`)
3. PAS de `BEGIN;`/`COMMIT;` internes
4. Avant tout `INSERT INTO journaux_audit` : vérifier CHECK constraint
5. Si migration échoue : supprimer le fichier
6. Test deploy manuel `supabase db push --dry-run` si possible
7. Surveillance post-merge via MCP Supabase
8. Dollar-quoting imbriqué interdit avec `$$` — utiliser tags distincts (`$body$`)

## Règles TypeScript / build

- `npx tsc -b` (pas `--noEmit`) pour valider en local
- Valeurs exactes des enums `UserRole` : `SOIGNANT` | `ADMIN_ETABLISSEMENT` | `ADMIN_PLATEFORME` | `ADMIN_GROUPE`
- Colonnes DB non encore dans types TS : utiliser `as any` ciblé

## Règles edge functions Supabase

### verify_jwt — `config.toml` PAS lu par `--use-api`

Le workflow `deploy-supabase` utilise `supabase functions deploy --use-api`. Ce mode
**ne lit pas** la valeur `verify_jwt` du `supabase/config.toml`. Conséquence : modifier
`config.toml` n'a aucun effet sur prod tant qu'on ne redéploie pas via Management API
ou Dashboard avec `verify_jwt` explicite.

Incident Sprint 12-A : PR #271 a posé `verify_jwt = false` dans config.toml pour
`process-externalisation-actions` + `sync-chorus-status`. Le workflow s'est déployé
en succès mais l'API Gateway gardait `verify_jwt = true` → 401 toutes les 5 min
(process-externalisation-actions) et 2h (sync-chorus-status). Fix : redéploiement
via MCP `deploy_edge_function` avec `verify_jwt: false` explicite.

**Règle** : quand on change `verify_jwt` d'une fonction, redéployer via MCP
`deploy_edge_function` (paramètre `verify_jwt`) ou Dashboard. Le `config.toml`
est un mémo de traçabilité, pas une source de vérité côté API Gateway.

### Auth crons pg_cron — Bearer sb_secret_* (vault v2)

Le vault stocke `service_role_key` au format `sb_secret_*` (41 chars, asymétrique v2),
PAS le JWT legacy ~213 chars. Pg_cron envoie ce sb_secret_* comme Bearer. Or l'env var
auto-injectée `SUPABASE_SERVICE_ROLE_KEY` dans les edge functions reste le JWT legacy.

**Conséquence** : si une edge function fait `bearer === SERVICE_ROLE_KEY` strict, le
cron échoue 401. Pattern correct (cf. `process-stripe-refunds`, `_shared/admin-auth.ts`
post-Sprint 12-A) : fallback via RPC `fn_lire_secret_cron` qui lit
`vault.decrypted_secrets` server-side et matche le bearer.

```ts
let _cachedVaultSecret: string | null = null;
async function getVaultCronSecret(sb: any): Promise<string> {
  if (_cachedVaultSecret) return _cachedVaultSecret;
  const env = Deno.env.get("SUPABASE_SECRET_KEY") || "";
  if (env) { _cachedVaultSecret = env; return env; }
  try {
    const { data } = await sb.rpc("fn_lire_secret_cron");
    if (data) { _cachedVaultSecret = data; return data; }
  } catch { /* ignore */ }
  return "";
}
```

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

### Sprint 11-A — Admin mobile-first AdminFinances + AdminGroupes (3 PRs)
Cf. docs/SPRINT_11_A.md.

- **PR 1** (#277) : `AdminFinances` table "Détail par établissement" (9 cols) → `TableOuCartes`. Tri par colonne préservé (desktop : click header, mobile : select + ↑↓). KPIs/chart/export CSV inchangés.
- **PR 2** (#278) : `AdminGroupes` tableau "Détail par clinique" (9 cols + email form inline `colSpan=9` + édition taux per-row) → pattern `hidden md:block` + cards mobile parallèles (préserve l'expansion + état local par row que TableOuCartes ne supporte pas).
- **PR 3** : doc Sprint 11-A + CLAUDE.md.

### Sprint 11-B — Admin mobile-first AdminConformite + AdminModeration (3 PRs)
Cf. docs/SPRINT_11_B.md.

- **PR 1** (#280) : `AdminConformite` table détail drill-down (5-6 cols, 7 indicateurs) → refactor `Indicateur` interface vers `champs[]` unifié (titre + render + primary?). Desktop table + mobile cards label/value depuis la même config. Couplage `colonnes` + `renderRow` original éliminé.
- **PR 2** (#281) : `AdminModeration` 6 tabs composite → refactor partiel par tab (audit-first) :
  * Documents (4 cols), Identité (8 cols — la pire UX mobile) : `hidden md:block` + cards. Identité cards = 3 noms label/value + grid 3 cols pour matches ✓/✗.
  * Litiges + Évaluations : skip honnête (déjà cards mobile-friendly).
  * Avoirs + Legacy : sous-composants externes hors scope ce fichier.
  * Bonus : `TabsList` wrappée en `overflow-x-auto + w-max` (6 tabs sur 375px).
- **PR 3** : doc Sprint 11-B + CLAUDE.md.

### Sprint 11-C — Admin mobile-first AdminChorusPro + AdminDetailUtilisateur (3 PRs)
Cf. docs/SPRINT_11_C.md.

- **PR 1** (#283) : `AdminChorusPro` (3 tabs Dashboard/Submissions/Config) → 3 tables refactorées vers `hidden md:block` + cards mobile : Dashboard 5 cols (compactes), Submissions 8 cols (cards complètes avec bouton "Voir détail"), Config 6 cols (Switch Actif + bouton "Éditer config"). KPIs/filtres/dialogs externes préservés.
- **PR 2** (#284) : `AdminDetailUtilisateur` page detail composite (6 tabs) → 2 tabs refactorées : Documents (5 cols) + Missions (6-7 cols selon type soignant/etab). 4 autres tabs skip honnête (Informations/Score/Profil complet/Actions admin déjà responsive). Audit RGPD + 2 ModalConfirmation préservés.
- **PR 3** : doc Sprint 11-C + CLAUDE.md.

### Sprint 11-D — Admin mobile-first AdminFacturation (la plus complexe) (2 PRs)
Cf. docs/SPRINT_11_D.md + docs/SPRINT_11_FINAL.md.

- **PR 1** (#286) : `AdminFacturation` (page unique, pas de tabs comme supposé initialement) — table 10 cols + nested expandable 8 cols + bulk actions Stripe/Chorus/CSV + multi-status VIREMENT_DECLARE workflow. Refactor :
  * Extraction logique fetch missions → hook `useMissionsFacture` (réutilisable desktop+mobile)
  * Extraction rendu → `FactureDetailContenu` component avec `mode: 'desktop' | 'mobile'`
  * `hidden md:block` cards mobile avec bandeau "Tout sélectionner" + cards par facture (checkbox + grid 2x2 HT/TTC/Missions/Émise + actions VIREMENT_DECLARE + expand inline)
  * `BoutonsBulkFactures` (Stripe Connect, Chorus Pro, CSV) inchangé mobile+desktop
  * Toutes RPC actions + PDF jsPDF + edge function `sepa-auto-charge` préservés
- **PR 2** : doc Sprint 11-D + docs/SPRINT_11_FINAL.md (récap Sprint 11 A→D) + CLAUDE.md.

#### Bilan Sprint 11 complet (A → D)
- **11 PRs livrées en prod**
- **7 pages admin mobile-first 100%** (les 7 reportées Sprint 8.5)
- **11 tables denses refactorées** (3399 lignes touchées)
- Pattern `hidden md:block` + cards mobile parallèles privilégié sur TableOuCartes (incompatible avec expansion / state local per-row / tabs imbriquées)
- Refactor `champs[]` unifié uniquement pour AdminConformite (config déclarative pure)
- Audit-first systématique : skip honnête (Litiges/Évaluations AdminModeration ; Informations/Score/Profil/Actions admin AdminDetailUtilisateur)

### Sprint 9-D — Animations + glassmorphism + doc finale (4 PRs)
Cf. docs/SPRINT_9_FINAL.md.

- **PR 1** : `src/lib/animations.ts` (EASINGS bouncy/soft/snap cubic-bezier, DURATIONS, TRANSITIONS compositions) + classes CSS `.transition-bouncy/soft/snap` dans `index.css`. Pure CSS, pas de framer-motion.
- **PR 2** : `DialogResponsive` glassmorphism — overlay `bg-jolene-midnight/40 backdrop-blur-sm`, content `rounded-3xl border-jolene-rose-200/60 shadow-holographic` (desktop).
- **PR 3** : `LayoutAdmin` mobile header + bottom nav glassmorphism `bg-card/85 backdrop-blur-xl` + border `jolene-rose-200/40`. (BarreNavigation soignant/étab déjà glassmorphism, audit lucide.)
- **PR 4** : `docs/SPRINT_9_FINAL.md` récap complet Sprint 9 (A→D) + CLAUDE.md.

**Sprint 9 clos.** 16 PRs total. Pas de dépendance externe ajoutée (économie ~80KB bundle). Migration progressive non-breaking.

### Sprint 9-C — Refonte dashboards Y2K (5 PRs)
Cf. docs/COMPOSANTS_Y2K.md.

- **PR 1** : `CarteKPIY2K.tsx` (3 variants : default/holographic/soft, icône + valeur tabular + variation up/down/neutral + contexte optionnel, hover lift).
- **PR 2** : `ListeSwipe.tsx` (carousel horizontal swipe-snap CSS natif, dots mobile + boutons prev/next desktop, `aria-roledescription="carousel"`).
- **PR 3** : DashboardSoignant header Y2K — `<Mascotte etat="happy|thinking" />` + "Hiii [prénom]" en `text-gradient-hero`.
- **PR 4** : DashboardEtablissement header Y2K — `<Mascotte etat="happy" />` + "Bonjour [étab]" en `text-gradient-hero`.
- **PR 5** : doc CarteKPIY2K + ListeSwipe + intégrations dashboards.

**Touche progressive** : composants existants (CarteKPI, sections KPI) inchangés. Les composants Y2K sont disponibles pour adoption page par page.

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

### Sprint 12-A — Hotfix verify_jwt edge functions
Cf. section "Règles edge functions Supabase" ci-dessus.

1 PR (#288) — fix auth crons sb_secret_* vault + config.toml + doc CLAUDE.md.

### Sprint 12-B — Adoption Y2K boutons critiques (5 PRs)
Cf. docs/SPRINT_12_B.md.

| Sprint | PR | Pages | Boutons migrés |
|---|---|---|---|
| 12-B-1 | #289 | Flow soignant : HistoriqueMissions, RechercheMissions, MesFacturesHonoraires, BulletinsPaie | 14 |
| 12-B-2 | #290 | Flow étab : FacturationEtablissement, FinaliserInscriptionEtab, LitigesEtablissement, ObligationsFinancieresEtab | 20 |
| 12-B-3 | #291 | Litiges/finance : LitigesSoignant, MesReclamations, PageStripeConnect, ChorusConfig | 16 |
| 12-B-4 | #292 | Finance/légal : MandatFacturation, ContratPlateforme, ChargesSociales, MesGains | 16 |
| 12-B-5 | (this) | Doc | — |
| **Total** | **5 PRs** | **16 pages** | **66 boutons** |

**Variant mapping** :
- shadcn `default/absent` → Y2K `primary` (gradient holographique)
- `secondary` / `outline` → `secondary` (border rose)
- `ghost` → `ghost`
- `destructive` / `link` → **SKIP** (pas d'équivalent Y2K — garder shadcn)
- `size="icon"` → **SKIP** (Y2K pas d'icon-only)

**Skips** : 7 boutons préservés (4 ArrowLeft back nav `size="icon"` + 3 `variant="destructive"` actions irréversibles).

**Adoption ratio** : avant Sprint 12-B = 2 BoutonY2K (0.9%) → après = 68 BoutonY2K, reste ~154 Button shadcn (pages admin + composants partagés reportés Sprint 12-C/D/E).

### Sprint 12-C — Adoption Y2K Cards + KPIs visuels (4 PRs)
Cf. docs/SPRINT_12_C.md.

| Sprint | PR | Chantier | Livré |
|---|---|---|---|
| 12-C-1 | #294 | BoutonY2K variant destructive | Gradient #FF4D6B → #FF6BBE rouge-rose holographique, foundation pour migrer les 3 destructive skippés Sprint 12-B |
| 12-C-2 | #295 | Dashboards .btn-primary CSS → BoutonY2K | 6 quick actions dashboards soignant + étab |
| 12-C-3 | #296 | CarteKPI → CarteKPIY2K | 36 KPIs sur 9 pages (8 holographic + 26 default + 2 soft) |
| 12-C-4 | (this) | Doc | — |
| **Total** | **4 PRs** | — | **42 migrations** |

**Card → CardY2K SKIPPED Sprint 12-C** : refactor structurel (CardHeader/Title/Content → flatten Y2K) trop risqué sur Premium/Contrat/Facturation. Reporté Sprint 12-E avec audit visuel par page.

**Mapping CarteKPI legacy → Y2K** :
- `icone={Briefcase}` ref → `icone={<Briefcase className="h-4 w-4" />}` JSX
- `lien="/path"` → `onClick={() => navigate("/path")}`
- `sousLabel` → `contexte`
- `couleurIcone/couleurFond` semantic → drop (palette Y2K rose unifiée)

### Sprint 12-D — Mascotte EmptyState + animations + cards restantes (4 PRs)
Cf. docs/SPRINT_12_D.md.

| Sprint | PR | Chantier | Livré |
|---|---|---|---|
| 12-D-1 | #298 | EmptyState foundation `mascotte` prop | Nouvelle prop mascotte + auto-rendu (variant→état) + rétro-compat 100% |
| 12-D-2 | #299 | animations.ts adoption Y2K core | BoutonY2K → transition-snap, CardY2K + CarteKPIY2K → transition-bouncy |
| 12-D-3 | #300 | Mascotte sur 9 EmptyState | 4 thinking + 3 empty + 2 happy sur RechercheMissions, MesAvances, HistoriqueMissions, LitigesSoignant/Etab, etc. |
| 12-D-4 | (this) | Doc Sprint 12-D | — |
| **Total** | **4 PRs** | — | **9 Mascotte EmptyState + 3 transitions Y2K + 1 foundation** |

**Card → CardY2K 4 pages user-facing SKIPPED** (audit explicite docs/SPRINT_12_D.md) :
- PremiumSoignant + PremiumEtablissement : pricing layout avec borders sémantiques (besoin variant CardY2K dédié)
- ContratPlateforme : 3 Cards state-coded (default/warning/success) — perte signalétique légale critique
- FacturationEtablissement : 11 Cards dans `<DialogResponsive>` modales — cohérence shadcn requise

Reporté Sprint 12-E avec création de variants CardY2K (pricing, status-coded) + décision UX produit.

**Mapping variant EmptyState → Mascotte etat** : `info`→`empty`, `success`→`happy`, `warning`→`thinking`.

### Sprint 12-E — Badges Y2K + Mascotte 100% + final (5 PRs)
Cf. docs/SPRINT_12_E.md et docs/SPRINT_12_FINAL.md.

| Sprint | PR | Chantier | Livré |
|---|---|---|---|
| 12-E-1 | #302 | BadgeY2K soignant | 19 badges sur 5 pages |
| 12-E-2 | #303 | BadgeY2K étab | 28 badges sur 4 pages |
| 12-E-3 | #304 | BadgeY2K admin | 56 badges sur 16 fichiers (helpers TS retypés strict) |
| 12-E-4 | #305 | Mascotte 100% EmptyState | 37 Mascotte → 61/61 = 100% adoption |
| 12-E-5 | (this) | Doc Sprint 12-E + Sprint 12 FINAL | — |
| **Total** | **5 PRs** | — | **103 badges + 37 Mascotte** |

**Mapping Badge shadcn → BadgeY2K** :
- `default/secondary/outline` → `info` ; `destructive` → `error`
- className success/valide/PAYE/TERMINE → `success`
- className warning/yellow/EN_ATTENTE/OUVERTE → `warning`
- className gold/premium/PLATINE → `premium`

**Statuts métier mappés** : OUVERTE→warning, ASSIGNEE→success, ANNULEE→error, PAYEE→success, EN_RETARD→error, TELEPORTATION/GPS_TRUQUE→error (anti-triche), RLS désactivée→error.

**Helpers TS retypés strictement** vers union Y2K (pas de `as any`) : statutColor AdminFacturation, statutBadge AdminMissions, badgeStatut AvoirsList, badge.groupe AdminLitiges.

### Sprint 12 FINAL (A → E)
Cf. docs/SPRINT_12_FINAL.md.

- **22 PRs livrées** sur 5 sous-sprints (12-A hotfix + 12-B + 12-C + 12-D + 12-E)
- **~280 migrations Y2K** au total
- **Adoption finale** : BoutonY2K 75, BadgeY2K 103, CarteKPIY2K 40, Mascotte 61/66 EmptyState (100% si on compte les 9 illustrations Sprint 8 BIS)
- **0 PR ouverte** post Sprint 12
- **0 régression CI**
- Reportés post Sprint 12 : CardY2K adoption (variants pricing/status-coded), BadgeRPPS/Niveau/Statut/Palier custom rewrite, animations spring élargies (Dialog/FAB/notifs)
