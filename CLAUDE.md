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
8. **Séquence stricte (rappel Gabrielle 10/07/2026)** : PR ouverte → CI VERT
   (`validate-pr` + Vercel) → merge sur main. JAMAIS de merge git-level direct
   sur main, SAUF panne avérée de l'API GitHub (rate-limit, MCP déconnecté)
   **ET** contenu déjà recetté (branche Supabase + `tsc -b` + guards) — et dans
   ce cas le signaler explicitement dans le message de merge et le rapport.

### Règle « livré ≠ mergé » — recette obligatoire (post-incident merges invisibles)

**« Mergé » ne veut pas dire « recetté ».** Une PR UI n'est déclarée *livrée* que
lorsque le comportement a été **vérifié sur le device de destination** (capture
d'écran du nouvel état dans la PR). Un « Lot terminé » annoncé sans cette
vérification est prématuré.

Corollaires (incident du 03/07 : deux surfaces GPS empilées → l'edit portait sur
un composant réel mais **pas celui rendu au pointage**) :
1. **Avant d'éditer une chaîne UI** : `git grep` le texte visible pour repérer
   les **doublons** (plusieurs composants/toasts affichent la même idée). Éditer
   TOUTES les surfaces réellement rendues par l'écran cible, pas la première
   trouvée.
2. **Tracer le composant réellement monté** par la route (App.tsx → page →
   sous-composants) avant de conclure « c'est fait ».
3. **Cache** : `index.html` en `no-store` (vercel.json), assets hashés
   `immutable`. Un merge doit être visible au prochain chargement, sans vider le
   cache à la main.
4. **Build stamp** (`<BuildStamp />` en bas de « Mon compte ») : le SHA affiché
   doit correspondre au dernier commit de `main`. C'est le test « mon merge
   est-il sur mon téléphone » en 2 secondes.

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
9. **Tout migration repair / INSERT dans `schema_migrations` DOIT peupler la
   colonne `statements`** (le SQL découpé de la migration). Le branching
   Supabase (branche preview, rebuild from scratch) rejoue les migrations
   depuis `statements` — PAS depuis les fichiers git. Une ligne sans
   statements = migration muette au rejeu → base neuve incomplète (incident
   04-05/07/2026 : baseline squash enregistrée `(version, name)` seulement →
   branches à 0 table). Outil : `scripts/populate-baseline-statements.ts` +
   workflow `populate-baseline-registry` (source unique = fichier versionné,
   vérif md5 bloquante). Invariant surveillé par drift-check (rouge si une
   ligne du registre a `statements` NULL/vide).

### Garde-fous 9.0 — réconciliation repo ↔ prod (NON NÉGOCIABLES, post-incidents 02/07/2026)

1. **Un seul chemin d'application : le CI `deploy-supabase`.** Plus JAMAIS de
   `apply_migration`/`execute_sql` MCP pour du DDL en temps normal — la
   migration part en PR, le merge l'applique. Exception unique : hotfix
   incident prod → SQL direct autorisé MAIS re-capturé en fichier de migration
   **le jour même** + enregistré dans `schema_migrations`.
2. **Toute redéfinition part de la définition LIVE** (`scripts/dump-live-def.sh
   <fonction|trigger|policy> <nom>` ou `pg_get_functiondef` via SQL), JAMAIS
   d'un fichier de migration du repo. Les fichiers repo peuvent être obsolètes :
   l'incident enum du 02/07 (21 min de transitions de statut mission cassées
   en prod) vient d'un trigger réécrit depuis `20260528131400` alors que la
   version live avait été corrigée depuis.
3. **Step « Heal » du deploy = fenêtre de grâce 24 h.** Il ne purge plus les
   versions remote orphelines récentes (une migration MCP dont la PR n'est pas
   mergée est orpheline par construction — la purger casse le deploy SUIVANT :
   incident registre `20260702180753` du 02/07). Orphelin récent → warning +
   consigne « merger la PR puis re-run », pas d'effacement.
4. **Drift-check quotidien** (`.github/workflows/drift-check.yml`, 5h UTC) :
   dump du schéma prod diffé contre la baseline versionnée
   `supabase/schema/public.sql` (produite par `schema-snapshot.yml`). Rouge =
   dérive → soit re-snapshot (dérive légitime après merge), soit re-capture en
   migration (dérive sauvage).
5. **Baseline de vérité** : `db/baseline_prod_2026-07-04/` (703 fonctions,
   structure, policies, cron, edge) + `docs/DRIFT_AUDIT.md` (écarts repo↔prod
   au 04/07). Toute archéologie de fonction commence là, pas dans les
   migrations historiques.

## Principe — un gap connu reste verrouillé

Toute limitation/gap documenté doit être **rendu impossible à déclencher
silencieusement** : rejet explicite (exception + message clair) + **référence au
TODO/doc** dans le message. Un « TODO » seul ne suffit pas — le chemin qui
mènerait au comportement cassé doit lever une erreur nette, pas produire un état
incohérent en silence. Exemples : verrou remboursement partiel pré-release escrow
(`fn_escrow_rembourser`, gap SPEC §9.4), verrou stockage documents de santé
(`fn_trg_bloquer_documents_sante`, `docs/CONFORMITE.md`). Corollaire : avant de
poser un tel verrou, `git grep` les chemins appelants — s'il existe une feature
vivante qui l'emprunte, la traiter d'abord (ou exclure explicitement + documenter).

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

## Pièges Safari iOS mobile

- **`100vh` saute** au focus clavier ou changement barre Safari. Utiliser `min-h-[100dvh]` (dynamic viewport height) sur tout container plein écran. `dvh ≡ vh` sur desktop → 0 risque régression.
- **Cascade Tailwind** : `@layer utilities` (text-sm, min-h-screen) ÉCRASE `@layer base` d'index.css. Les protections globales (`html, body { min-height: 100dvh }` + `input, textarea, select { font-size: 16px }` à `index.css:285-295`) ne suffisent PAS si une classe utilité Tailwind est appliquée sur l'élément. Forcer la valeur correcte sur chaque composant/page.
- **Zoom auto sur input < 16px** : Safari iOS zoom sur focus si font-size effective < 16px. Pattern : `text-base md:text-sm` (16px mobile, 14px desktop ≥768px) sur Input + Textarea shadcn. `.input-base` CSS classe a déjà l'override mobile.
- **Pas de `scrollIntoView({behavior:'smooth'})` au focus input** : Safari iOS scroll nativement vers le champ focusé. Le JS smooth + setTimeout crée un saut. Valable uniquement pour scroll vers section/message (FilDiscussionLitige, DashboardRH, etc.), PAS au focus champ.
- **Note Capacitor (Sprint 18)** : `@capacitor/keyboard` déjà préparé dans `lib/platform.ts:170-175` (resize mode + listener `keyboardWillShow`). Ajouter `user-scalable=no` dans viewport meta WKWebView pour bloquer le zoom au cas où. Cf. docs/HOTFIX_UX_SAFARI_MOBILE.md.

## Règle de rémunération / facturation — heures facturées

> **GLOSSAIRE ESCROW — RÈGLE #11 (plancher inviolable).** À connaître d'office
> pour toute session escrow/paiement rapide ⚡ : `honoraires_cents` de
> `paiements_escrow` est **figé à la confirmation** (`net_a_payer` prévisionnel)
> et **jamais recalculé** par la validation des présences. Heures validées <
> publiées → le soignant touche **le plancher = tout l'escrow** (jamais de
> réduction auto). Contester des heures = **litige** (`DISPUTE`), seule voie de
> réduction (`fn_escrow_rembourser`, admin). Surplus (validées > publiées) : non
> couvert aujourd'hui, débit complémentaire à venir (Lot 13/14). Détail :
> `docs/SPEC_ESCROW_REVENUS_SOIGNANT.md` §9.

> **CIRCUIT MONÉTAIRE ESCROW (v15) — à connaître d'office.** Le débit
> (`escrow-debit-echeance`) est une **destination charge** Stripe :
> `transfer_data.destination` = compte connecté soignant + `application_fee_amount`
> = commission. **`on_behalf_of` est RETIRÉ depuis v15** : le mandat SEPA nomme
> **Jolene créancier** → Jolene = **merchant of record** (toute redéfinition part de
> `escrow-debit-echeance` LIVE, jamais d'un doc obsolète). Wording exact : les
> honoraires ne **STATIONNENT jamais** sur un compte Jolene (ils *transitent* le
> settlement, mécanique destination charge) — **ne pas** écrire « ne transitent
> jamais ». Séquestre = payout **manuel** sur le compte connecté, libéré à la
> validation des présences. Réf. unique : `docs/flux-monetaire-escrow.md`.

**Patterns backend (10/07/2026, incident PR #835)** :
1. **Toute NOUVELLE fonction SQL user-facing DOIT être suivie d'un `GRANT
   EXECUTE ... TO authenticated`** dans la même migration. `CREATE OR REPLACE`
   d'une fonction existante conserve ses ACLs, mais une fonction créée de zéro
   n'hérite de RIEN dans cette base → 42501 « permission denied » pour tous les
   utilisateurs connectés (incident : 4 RPCs Lot 17/empêchement muettes en prod).
2. **`fn_test_update_mission` pose le flag `app.test_bypass_protections`**
   (migration `20260710130000` v2) que `dec_proteger_mission_soignant` respecte
   (early return) : ce trigger re-force debut_le/soignant_assigne_id depuis OLD
   pour tout caller non-admin, service_role compris — sans le flag, le helper
   était un no-op SILENCIEUX (l'UPDATE « réussit », rien ne change). NB :
   `SET session_replication_role` est refusé via PostgREST (supautils vérifie
   le rôle de SESSION, pas le owner SECURITY DEFINER). Avant d'écrire un test
   qui modifie `missions` hors RPC métier, passer par ce helper, jamais par un
   UPDATE direct.
3. **`journaux_audit` est IMMUABLE** (triggers dec_audit_immuable +
   dec_proteger_audit_delete) : aucune purge possible dans les tests. Toute
   assertion E2E sur un compteur basé sur l'audit (ex. empêchements/12 mois du
   compte partagé) doit être RELATIVE (n_avant + 1), jamais absolue, avec
   snapshot/restore de l'état du soignant (score, compteurs) autour du test.

**Patterns backend (audit 10/07/2026, filet 72h + RPC mortes)** :
1. **Le cron d'auto-validation 72h était neutralisé par un trigger de protection.**
   `dec_proteger_presence_soignant` (BEFORE UPDATE presences) revertait
   `valide_par_etablissement` dès `NOT est_admin() AND NOT est_admin_etablissement()`
   — vrai en contexte cron (`auth.uid()` NULL → `est_admin()`=false). Le cron
   posait `valide_auto_72h_le` (non reverté) → présence exclue des passages
   suivants mais jamais réellement validée. Fix `20260710140000` : exempter
   `auth.uid() IS NULL` (système), comme le jumeau `fn_protect_presence_integrity`.
   **Règle** : tout trigger anti-tamper sur une table écrite par un cron/backend
   DOIT exempter le contexte système (`auth.uid() IS NULL`), sinon il annule
   silencieusement les writes légitimes du cron.
2. **Audit croisé RPC↔grants** : `grep` toutes les `supabase.rpc('fn_...')` de
   `src/`, puis vérifier en prod `has_function_privilege('authenticated', oid,
   'EXECUTE')`. Une fonction NEUVE n'hérite d'aucun grant → 42501 silencieux.
   Audit du 10/07 : 4 RPC frontend mortes (fn_scanner_code_pointage,
   fn_admin_lister/maj_parametre, fn_calculer_bfa_safe) — 3 grantées
   (`20260710150000`), la 4e laissée morte (aucun contrôle interne + composant
   non monté).

**Patterns backend (Lot 13)** :
1. **Avant tout `fn_creer_notification` avec un nouveau type** : vérifier `notifications_type_check` (le type `CONTESTATION_PRESENCE` était utilisé par le front mais absent du CHECK → notifs de contestation muettes en prod, jamais d'erreur visible côté client).
2. **Tout `cron.schedule` posé via MCP doit être recapturé en migration** (garde `pg_extension pg_cron` pour les branches preview) — le cron d'auto-validation 72h tournait en prod sans exister dans le repo : un rebuild l'aurait perdu, et l'« auto-72h » CGU §4.6 avec lui.

**Pattern régime/contrat (Lot 14, gardé par `test:guards` 7)** : sur toute ligne financière/facturation, le régime affiché vient de `missions.type_contrat_applique` (figé à l'assignation) — **jamais** de `soignants.type_exercice` (profil) : un libéral peut faire une mission CDD, afficher le profil crée des chips contradictoires.

**Patterns escrow (3 bugs recette, gardés par `test:guards` 4-6)** :
1. **Jamais `on_behalf_of`** sur un PaymentIntent escrow : le mandat SEPA nomme Jolene créancier — avec `on_behalf_of`, Stripe exige un mandat au nom du compte connecté et le débit échoue (recette run #10).
2. **Audit escrow = insert DIRECT en table** (helper `auditEscrow`), jamais `rpc('fn_ecrire_audit_safe')` côté edge : binding uuid cassé PostgREST 14.5 (« invalid input syntax for type uuid: null ») → audits muets. Ne PAS « corriger » en passant la fonction uuid→text : 66 appelants DB positionnels casseraient.
3. **Le passage `→ DEBITE` doit enfiler la release** (`fn_trg_escrow_enqueue_on_debite`, migration `20260709130000`) : sans ce trigger, settlement OK mais aucun versement ne part jamais.

**Règle officielle (explicite)** : les heures facturées (et payées au soignant) =

```
heures_facturees = GREATEST(prévisionnel hors pause, effectif hors pause)
```

- **Plancher prévisionnel garanti** : si le soignant travaille MOINS que prévu, il
  touche quand même le planifié. S'il travaille PLUS (pointage effectif > prévu), il
  touche le réel.
- **Pauses toujours exclues** (`est_pause = true` ne compte jamais).
- Appliqué de façon cohérente sur `duree_heures` (→ bulletin de paie), `net_a_payer` /
  `total_brut` (→ commission + facture honoraires finale), et l'hebdo
  (`fn_calculer_montant_periode` utilise déjà `GREATEST`).
- Fonctions : `fn_sync_mission_creneaux` (`duree_heures`), `dec_calculer_finance_mission`
  (`net_a_payer`/majorations, choisit le jeu de créneaux EFFECTIF vs PREVISIONNEL le plus
  élevé). Migrations `20260624160000` (exclusion pauses) + `20260624170000` (plancher).
- **À surfacer côté produit** (CGU / carte mission / contrat) : « vous êtes rémunéré au
  minimum sur les heures planifiées ». Non encore affiché dans l'UI — à décider.

## Pièges vérification documents (verify-document)

- **HEIC iPhone** → conversion JPEG côté browser (OffscreenCanvas) avant upload, l'API Anthropic Vision n'accepte pas HEIC.
- **PDF** → envoyer en `type: "document"` (PAS `type: "image"`) à l'API Anthropic.
- **REJETE ≠ EXPIRE** : ce sont 2 statuts distincts. Ne JAMAIS écrire `valide_jusqua`/`valide_depuis` quand verdict=REJETE (la date extraite par l'IA appartient au mauvais fichier). Côté UI, tester `estRejete` AVANT `estExpire`.
- **Crédits Anthropic** : si `documents_soignants.resultat_ia.erreur_anthropic` apparaît → vérifier crédits + bonne organization de `ANTHROPIC_API_KEY`. Cf. docs/VERIFICATION_DOCUMENTS.md.
- **Documents requis par profession + exercice** : filtrer par `profession` ET `type_exercice` (table `documents_requis_par_profession.type_exercice_requis` = SALARIE_ONLY/LIBERAL_ONLY/TOUS). Cf. docs/SPRINT_HOTFIX_UX_DOCUMENTS.md. AS/AES = CNI+DIPLOME seulement (ni RPPS, ni RCP). Pas de KBIS (sociétés, libéraux en BNC). Pas de casier judiciaire (rôle employeur).

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

### Sprint 12-F — Migration Card shadcn → CardY2K complète (5 PRs)
Cf. docs/SPRINT_12_F.md.

| Sprint | PR | Chantier | Livré |
|---|---|---|---|
| 12-F-1 | #307 | Foundation CardY2K subcomponents | Drop-in shadcn (Header/Title/Description/Content/Footer) + prop noPadding |
| 12-F-2 | #308 | Migration Card user-facing | 17 Cards sur 4 pages (Premium x2 + Contrat + Facturation) — levée blocage Sprint 12-D |
| 12-F-3 | #309 | Migration Card admin part 1 | 49 Cards sur 5 pages (AdminDetailUtilisateur 19, AdminStatus 9, AdminDashboard 8, AdminFinances 7, AdminAffacturage 6) |
| 12-F-4 | #310 | Migration Card admin part 2 + components | 19 Cards sur 9 fichiers (E2E data-testid préservés) |
| 12-F-5 | (this) | Doc Sprint 12-F + Sprint 12 FINAL update | — |
| **Total** | **5 PRs** | — | **85 Cards + 1 foundation** |

**Adoption CardY2K** : 0% (1 foundation) → **100%** (85 ouvertures). Aucun Card shadcn restant sur cas migrables.

**Pattern drop-in** :
```tsx
<CardY2K noPadding>
  <CardY2KHeader><CardY2KTitle>X</CardY2KTitle></CardY2KHeader>
  <CardY2KContent>Y</CardY2KContent>
</CardY2K>
```

### Sprint 12-G — Cleanup final adoption Y2K (4 PRs)
Cf. docs/SPRINT_12_G.md.

| Sprint | PR | Chantier | Livré |
|---|---|---|---|
| 12-G-1 | #312 | Badge custom Y2K interne | BadgeRPPS/Statut/Palier/Niveau réécrits avec BadgeY2K interne (call sites inchangés) |
| 12-G-2 | #313 | Buttons user-facing restants | 38 boutons sur 19 pages (PageRecherchesSauvegardees, BlogArticle, Parcours3200h, Premium x2, MesDPAE, DetailMission) |
| 12-G-3 | #314 | Buttons admin + composants | 161 boutons (AdminUtilisateurs 21, AdminGroupes 13, AdminFacturation 10, +24 composants partagés) |
| 12-G-4 | (this) | Doc Sprint 12-G + Sprint 12 update | — |
| **Total** | **4 PRs** | — | **199 boutons + 4 badges custom** |

**Skips justifiés (21 total)** : 12 asChild Radix Slot (Dialog/Popover/Dropdown/Anchor) + 2 size="icon" (Sprint 12-G PR 3) + 5 size="icon" back nav (Sprint 12-G PR 2) + 2 asChild LinkedIn/WhatsApp share.

### Sprint 12 FINAL complet (A → G)
- **31 PRs livrées** sur 7 sous-sprints
- **~560+ migrations Y2K** au total
- **Adoption finale** : BoutonY2K ~272 ouvertures, BadgeY2K 103+, CardY2K ~88, CarteKPIY2K 40, Mascotte 61/66 EmptyState, animations.ts 3 composants core
- Reste uniquement cas légitimes shadcn (~40 buttons : asChild Radix Slot / icon back nav / variant link / Calendar/DataTable primitives)
- **0 dette Y2K résiduelle**

### Sprint 13 — Swipe matching Hinge-style (A → D, 19 PRs)
Cf. docs/SPRINT_13_FINAL.md.

| Sous-sprint | PRs | Livré |
|---|---|---|
| 13-A | 5 (#316-#320) | Backend matching : 3 tables + 3 RPCs scoring/swipe + cron horaire + edge function notif-match |
| 13-B | 5 (#321-#325) | UI swipe Y2K : CardMissionSwipe + StackCards Pointer Events + BoutonsActionSwipe + ConfettiSwipe + page SwipeMissions + ModalDetailMissionSwipe |
| 13-C | 5 (#326-#330) | Engagement : 8 badges (PREMIER_SWIPE/EXPLORATEUR/TOP_SWIPER/PREMIER_SUPER_LIKE/PREMIER_MATCH/MATCH_KING_QUEEN/30/100_DAYS_STREAK) + streaks + CelebrationMatch + notif-candidature-acceptee + page MesMatches |
| 13-D | 4 (#331-#334) | Toggle Swipe/Liste localStorage + E2E swipe UI 10 specs + E2E flow complet 6 specs + doc finale |
| **Total** | **19 PRs** | **5 tables + 6 RPCs + 3 triggers + 1 cron + 2 edge functions + 6 composants swipe + 2 pages + 27 spec stubs E2E** |

**Algorithme scoring matching** : filtres durs (profession, distance Haversine <50km) + softs (tarif 25, distance 25, étab 20, urgence 15, fiabilité soignant 15) → score 0-100 + breakdown JSONB.

**Mécaniques engagement Hinge-grade** : badges automatiques (8 types) + streaks quotidien (reset si jour manqué) + quota anti-spam super-likes 5/jour + confettis CSS Y2K (rose/mauve/cyan/butter) + haptic feedback mobile (navigator.vibrate).

**URLs prod** :
- `/soignant/swipe-missions` — page swipe Hinge-style
- `/soignant/mes-matches` — liste matches + stats engagement
- `/soignant/recherche-missions` — vue liste classique (toggle persistant)

**Skip honnête PR 2 13-D** : refonte RechercheMissions déjà acquise Sprint 12 (filtres profession/rayon/tarif/typeContrat/urgentesOnly/horaire/villeRecherche + BoutonY2K toggles). Sprint 13-D PR 1 ajoute juste le toggle Swipe/Liste persistant.

**Règle migrations apply_migration** : chaque MCP `apply_migration` DOIT être suivi d'un INSERT explicit dans `supabase_migrations.schema_migrations` pour éviter le drift workflow `supabase db push` (incident Sprint 13-A + Sprint 13-C). Hotfixes appliqués.

### Sprint 14 — Tests E2E réels matching swipe (5 PRs)
Cf. docs/SPRINT_14_FINAL.md.

| Sous-sprint | PR | Chantier | Livré |
|---|---|---|---|
| 14-1 | #335 | Helpers seed-matching foundation | `e2e/helpers/seed-matching.ts` (8 helpers : seedMissionMatching, seedSwipe, seedMatchingScore, cleanup×2, getStreakInfo, getBadges, getSuperLikesRestant) |
| 14-2 | #336 | Backend matching — 8 tests réels | Remplace 11 stubs `matching-backend.spec.ts` + helper `userClient(email,password)` + env workflow `SUPABASE_PUBLISHABLE_KEY` |
| 14-3 | #337 | UI swipe — 6 tests réels | Remplace 10 stubs `swipe-matching-ui.spec.ts` (routes, toggle, MesMatches) |
| 14-4 | #338 | Flow complet — 5 tests réels | Remplace 6 stubs `matching-complete.spec.ts` (triggers badges/streaks/match) |
| 14-5 | (this) | Doc Sprint 14 FINAL + audit dette résiduelle | docs/SPRINT_14_FINAL.md |
| **Total** | **5 PRs** | — | **19 tests E2E réels** (27 stubs Sprint 13 → 0 dette matching) |

**Pattern Sprint 14** :
- `adminClient()` (service_role) : seed/cleanup, bypass RLS, triggers DB direct
- `userClient(email, password)` : anon + signInWithPassword pour RPCs `SECURITY DEFINER` dépendantes de `auth.uid()`
- `test.afterEach` : `cleanupMatchingForSoignant(soignantId)` + `cleanupMissionsTest()`

**Skips honnêtes Sprint 14** :
- Gesture swipe Pointer Events (cross-browser flaky)
- Streak J+1/J+2 (clock mock pg_set_local trop intrusif)
- notif-match edge function (testé manuellement post-déploiement)
- Flow UI multi-comptes étab-accepte (couvert backend test #5 PREMIER_MATCH)

**Dette E2E historique restante** : 24 stubs pré-Sprint 13 (`candidature/changer-password/export-rgpd/litige/notation/notifications/parrainage/pointage/pool-urgence/recherche-missions/sprint57-*/inscription/regression-bugs`) → Sprint 15 dédié post-launch.

### Sprint 15 — DPAE conforme + nettoyage pré-lancement (5 PRs)
Cf. docs/SPRINT_15.md.

| Sous-sprint | PR | Chantier | Livré |
|---|---|---|---|
| 15-1 | #340 | IBAN/BIC réel Jolene SASU | Coordonnées SWAN SAS réelles (FR76 1732 8844 0018 3164 8362 916 / SWNBFR22) — bloqueur lancement résolu |
| 15-2 | #341 | Suppression Flow B DPAE | Retrait bouton "J'ai effectué la DPAE" sans preuve + DROP RPC fn_confirmer_dpae + suppression edge confirm-dpae du repo |
| 15-3 | #342 | Validation regex n° DPAE + email | fn_enregistrer_numero_dpae regex `^[A-Za-z0-9]{8,30}$` + au moins 1 chiffre + template Resend DPAE_DECLAREE_SOIGNANT |
| 15-4 | #343 | Mention CGU DPAE + warning pointage | PageCGU article 4.5 (étab seul responsable, Jolene ni employeur ni tiers-déclarant) + fn_pointer_arrivee warnings non-bloquant |
| 15-5 | (this) | Cleanup + doc finale | Suppression mock-data.ts orphelin + SET search_path TO 'public' sur 4 fonctions + docs/SPRINT_15.md |
| **Total** | **5 PRs** | — | **3 bloquants lancement résolus + 4 fonctions hardenisées** |

**Flow DPAE conforme post-Sprint 15** (Scénario 1 "concierge manuel") :
- Étab génère payload pré-rempli via fn_generer_donnees_dpae
- Étab copie sur net-entreprises.fr, soumet, reçoit n° URSSAF
- Étab saisit n° dans Jolene → fn_enregistrer_numero_dpae (validation + email soignant)
- Soignant reçoit confirmation email + n° URSSAF en preuve
- Si pointage sans n° saisi → warning DPAE_NON_REGULARISEE + push étab (non-bloquant)

**Limitations connues (documentées docs/SPRINT_15.md)** :
- Edge functions deployed-hors-repo (temp-sync-vault-key, invoke-generate-invoice-internal, confirm-dpae) restent ACTIVE en Supabase, à supprimer manuellement Dashboard (aucun outil MCP delete_edge_function). 0 impact fonctionnel.
- Tiers-déclarant URSSAF EDI reporté post-Série A (3-6 mois agrément).

### Sprint 16 — Tests E2E historiques réels (5 PRs)
Cf. docs/SPRINT_16.md.

| Sous-sprint | PR | Chantier | Stubs convertis |
|---|---|---|---|
| 16-1 | #345 | candidature + notation + recherche-missions | 4 tests réels |
| 16-2 | #346 | notifications + pool urgence | 3 tests réels |
| 16-3 | #347 | parrainage + changer-password | 3 tests réels + 1 skip honnête |
| 16-4 | #348 | pointage + litige + export RGPD | 5 tests réels |
| 16-5 | (this) | Doc Sprint 16 + bilan E2E global | — |
| **Total** | **5 PRs** | — | **15 tests E2E réels + 0 stub non justifié** |

**Bilan dette E2E global post Sprint 16** :
- 0 stub vide non justifié dans le codebase (`grep test.skip(true` → 8 occurrences, toutes documentées)
- 254 tests actifs sur 33 spec files
- 8 hard-coded `test.skip(true)` restants : 1 PR 3 (changer-password password restore = race condition CI), 4 conditional (sprint57 + sprint57-reverse), 2 inscription (Promise.race fallback), 1 regression-bugs (cross-référencé admin-invoke)
- ~26 conditional `test.skip(!ENV)` (runtime guards légitimes)

**Skips honnêtes documentés (infrastructure manquante précise)** : 8 cas — voir docs/SPRINT_16.md section "Skips honnêtes". Chacun avec infra manquante + couverture alternative explicite.

### Sprint 17 — Vérifs e2e approfondies prélancement + professions (PR #417 + doc)

Vérifications e2e de bout en bout (impersonation RPC + transactions annulées, zéro
persistance) des flux **facturation, litige, paie**, étendues aux 15 professions et
aux 2 types d'exercice. **18 bugs latents** corrigés, tous masqués en prod car les
chemins concernés (libéral honoraires → litige → avoir → remboursement, missions de
professions salariées-only) n'avaient jamais été exécutés de bout en bout.

**Cause racine commune** : contraintes `CHECK` désynchronisées du code applicatif +
antipattern Postgres `RECORD IS NOT NULL` (toujours faux sur un record à colonnes
nullables) + trigger trop strict.

Correctifs DB (migrations `20260530284000` → `296000`, appliquées prod + enregistrées) :
- `fn_generer_facture_honoraires_mission` + `fn_admin_resoudre_litige` : ajout
  `periode_debut/periode_fin` (NOT NULL) aux INSERT.
- `journaux_audit_action_check` (+16 actions) / `_type_acteur_check` (+ADMIN/ETABLISSEMENT/
  SYSTEM/DEPRECATED_CALLER) / `notifications_type_check` (+10 types) / `_type_destinataire`
  (fix ADMIN) / `factures_honoraires_statut_check` (+REMBOURSE) : alignées sur le code.
- `fn_admin_resoudre_litige` : antipattern record-NULL → `.id IS NOT NULL` (les branches
  RECALCUL/ANNULER_REEMETTRE/AVOIR + notifications étaient toutes silencieusement ignorées).
- `dec_valider_type_contrat_mission` : auto-restriction `TOUS→SALARIE` pour professions
  salariées-only (AS/AES/PREPARATEUR_PHARMA) — **bug bloquant** : création de mission
  impossible pour l'aide-soignant.
- `fn_confirmer_remboursement_avoir` : notifie le soignant (REMBOURSEMENT_CONFIRME) sur
  confirmation manuelle.

**Intégration professions (conforme législation)** :
- **CHIRURGIEN-DENTISTE** (`DENTISTE`, art. L4141-1 CSP) : enum + libéral (CABINET_DENTAIRE,
  CNOC R.4127-274) + docs (CNI/diplôme/RPPS ; RCP/RIB/URSSAF libéral) + CARCDSF.
- **AUXILIAIRE_PUERICULTURE** (DEAP) : enum + salarié uniquement + docs (CNI/diplôme) + sans RPPS.
- Le frontend (`constantes.ts`) listait déjà ces 2 professions → l'enum DB ne les avait
  pas → inscription cassée. Synchronisé. **Seules ces 2 manquaient** (frontend 17 vs DB 15).

**RAPPEL CRITIQUE migrations** (incident évité Sprint 17) : tout `apply_migration` via MCP
DOIT être suivi d'un `INSERT INTO supabase_migrations.schema_migrations`. 4 migrations
(`260000-272000`) appliquées mais non enregistrées auraient fait virer `deploy-supabase` au
rouge (out-of-order `db push`). Toujours vérifier `schema_migrations` vs fichiers repo avant merge.

### Sessions UX D & E — refonte admin + activation soignant (11-12/06/2026)

- **Session D** (7 PRs #531→#542) : sidebar admin 5 groupes (RBAC découplé par
  clé `acces`, périmètres equipe_admin inchangés), recherche globale ⌘K
  (`fn_admin_recherche_globale`), pattern « file de travail » sur toutes les
  listes admin (composant `FileDeTravail`), drill-down cockpit, audit 43 pages
  + 116 corrections copy. Cf. docs/SESSION_D.md + docs/AUDIT_ADMIN_SESSION_D.md.
- **Stratégie produit/acquisition** : docs/STRATEGIE_PRODUIT_ACQUISITION.md
  (verdict UX 12 lots, roadmap Sessions E/F/G, plan d'acquisition phasé,
  4 métriques North Star).
- **Session E** (3 PRs code #559/#560/#561 + doc) : activation soignant —
  déblocage RPPS, valeur avant l'effort (`fn_apercu_marche_profession`, GRANT
  anon), `ChecklistActivation` dashboard (remplace OnboardingGuide 7 slides),
  états vides recruteurs (alerte 1-tap via filtres sauvegardés IMMEDIATE),
  documents caméra-first verdict IA inline, checkout net estimé + sticky mobile.
  Cf. docs/SESSION_E.md.
- **Sessions F (activation étab + matching) et G (consolidation nav)** : à
  lancer — périmètres détaillés dans la stratégie.

### Lot 17 — Matching alert-first paramétrable + calendrier dispos (09/07/2026)

- **Toutes les mécaniques A2/A3/A4 sont paramétrées** via `parametres_systeme`
  (`vague_taille_1/2/3`, `vague_delai_2/3_min`, `vague_cap_push_24h`,
  `vague_fenetre_urgente_h`, `vague_non_urgente_*`, `alerte_filtre_cap_h`,
  `confirmation_j1_min/max_h`, `relance_presence_max_h`,
  `alerte_etab_presence_h`, `noshow_detection_min`, `matching_bonus_service`).
  Défauts = anciennes valeurs en dur ; ne plus JAMAIS remettre un seuil en dur
  dans ces fonctions (migration `20260709250000`).
- **Vagues non urgentes** : vague UNIQUE par mission (dédup = existence d'une
  notification `MISSION_A_POURVOIR` pointant vers la mission). Vagues urgentes :
  élargissement cumulatif par ancienneté (comportement historique 7d-5).
- **A1** : le `service` (libellés normalisés Lot 12) est désormais un critère
  soft du scoring (`matching_bonus_service`, comparaison lower/btrim).
- **F5** : table `disponibilites_soignant` (RLS lecture soignant, écriture via
  `fn_definir_disponibilite`), matching inversé quotidien
  (`fn_matching_inverse_dispos`, cron `jolene_matching_inverse_dispos` 06:30 UTC),
  vivier étab `fn_vivier_disponibilites` (compte + prénoms/scores, RGPD), page
  `/soignant/disponibilites` + hint vivier dans FormulaireMission.
- **F2** : `mission_source='REPUBLICATION'` posé par `fn_marquer_source_mission`
  juste après `fn_creer_mission[_multi_jours]` quand `?dupliquer=` est présent.
