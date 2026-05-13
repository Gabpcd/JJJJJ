# CLAUDE.md

> Conventions et règles de travail pour Claude Code sur le projet Jolene.

## Workflow Git — règles non-négociables

Claude Code mène chaque tâche jusqu'au bout en autonomie totale, sans intervention manuelle de Gabrielle sur GitHub :

1. **Branche feature** : créer une branche descriptive si la modification est non-triviale, ou commit direct sur main pour les fixes mineurs (selon le contexte)
2. **Commit + push** : messages Conventional Commits (feat:, fix:, chore:, docs:, refactor:)
3. **Ouverture de PR** automatique via `gh pr create` **ou** `mcp__github__create_pull_request`
4. **Résolution de conflits** : si conflits avec main, résoudre automatiquement. Règle par défaut : en cas de doute, conserver les blocs des DEUX côtés et concatener (jamais supprimer du code existant).
5. **Merge automatique** via `gh pr merge --squash --delete-branch` **ou** `mcp__github__merge_pull_request` (préfère --squash pour garder un historique main propre, sauf instruction contraire)
6. **Surveillance du déploiement** : suivre le workflow `deploy-supabase` jusqu'à confirmation verte avec `gh run watch` **ou**, si gh indisponible, fournir l'URL du run à Gabrielle (`https://github.com/Gabpcd/Jolene/actions?query=branch%3Amain`) pour qu'elle confirme visuellement
7. **Rapport final** : URLs de la PR mergée, du run de workflow, et confirmation que les changements sont bien en prod

### Ce que Gabrielle ne fait JAMAIS

- Pousser du code manuellement
- Merger une PR depuis l'interface GitHub
- Résoudre des conflits manuellement
- Cliquer sur "Merge pull request"

### Pré-requis et fallback

- Avant la première opération Git de chaque session, vérifier que `gh` CLI est authentifié (`gh auth status`)
- Si `gh` n'est pas disponible (environnement Claude Code sans `gh`) : utiliser les outils MCP GitHub `mcp__github__*` à la place
- Si NI `gh` NI MCP GitHub ne sont disponibles, signaler immédiatement à Gabrielle pour résolution durable plutôt que de demander un merge manuel
- Si une opération Git échoue (CI cassée, conflit complexe, push rejeté), ne PAS retomber sur "fais-le manuellement" : analyser, corriger, recommencer

### Environnement Claude Code — détection au début de chaque session Git

Au début d'une session impliquant des opérations Git, détecter quelle voie est disponible :

| Outil | Test | Si KO, fallback |
|---|---|---|
| `gh` CLI | `gh auth status` | Tools MCP GitHub `mcp__github__*` |
| MCP GitHub | Lister les tools `mcp__github__*` disponibles dans la session | Demander à Gabrielle de configurer le serveur MCP |
| `git push/pull` | `git fetch origin` | Vérifier que le proxy git local fonctionne |

**Tableau d'équivalences gh CLI ↔ MCP GitHub** :

| Action | `gh` CLI | MCP GitHub |
|---|---|---|
| Créer une PR | `gh pr create --title ... --body ...` | `mcp__github__create_pull_request` |
| Lire une PR | `gh pr view <num>` | `mcp__github__pull_request_read --method get` |
| Lire le diff d'une PR | `gh pr diff <num>` | `mcp__github__pull_request_read --method get_diff` |
| Lire les checks d'une PR | `gh pr checks <num>` | `mcp__github__pull_request_read --method get_check_runs` |
| Merger une PR | `gh pr merge <num> --squash --delete-branch` | `mcp__github__merge_pull_request --merge_method squash` (delete branch via `git push origin --delete` ensuite) |
| Lister les PRs | `gh pr list` | `mcp__github__list_pull_requests` |
| Suivre un workflow run | `gh run watch <id>` | ❌ pas d'équivalent MCP — fournir l'URL `actions?query=branch%3Amain` à Gabrielle |
| Status combiné d'un commit | `gh api repos/.../commits/SHA/status` | ❌ MCP renvoie 403 — fallback : `mcp__github__pull_request_read get_check_runs` sur la PR du commit |

**Limites connues du MCP GitHub** (à signaler à Gabrielle plutôt que de bloquer) :

- Pas de tool pour supprimer une branche distante → utiliser `git push origin --delete <branch>` ; si le proxy bloque (HTTP 403), demander à Gabrielle de le faire via UI ou en local
- Pas de tool pour lister/suivre les workflow runs GitHub Actions
- Pas de tool pour lire les logs d'un workflow run
- `mcp__github__get_commit` ne retourne pas les statuses de checks

### Cas particulier — Vercel et Supabase

- Vercel déploie automatiquement chaque branche en Preview, et main en Production
- Supabase déploie via le workflow GitHub Actions `deploy-supabase` uniquement sur main
- Une PR mergée sur main = déclenchement automatique du déploiement Supabase prod
- Vérifier dans le rapport final que le run `deploy-supabase` est passé vert (via `gh run watch` ou en remontant l'URL du run à Gabrielle)

## Règles migrations Supabase

Apprises à la dure le 2026-05-12 (3 deploy-supabase échoués sur Sprint 1 PR 1+2).

1. **Format obligatoire** : `YYYYMMDDHHMMSS_description.sql` (14 chiffres). Pas de `YYYYMMDD_*.sql` (8 chiffres) ni autre — le Supabase CLI rejette silencieusement et la migration n'est jamais enregistrée dans `schema_migrations`.

2. **PAS de `BEGIN;`/`COMMIT;` internes** — le CLI wrap déjà en transaction. Les BEGIN/COMMIT explicites sont redondants et peuvent empêcher l'application de certains `ALTER TYPE`.

3. **Avant tout `INSERT INTO journaux_audit`**, vérifier la CHECK constraint :
   ```sql
   SELECT pg_get_constraintdef(oid) FROM pg_constraint
   WHERE conname = 'journaux_audit_action_check';
   ```
   - Si action custom non listée : utiliser `'SYSTEM'` (action générique existante) avec le contexte dans `details jsonb`, OU étendre la CHECK constraint en début de migration AVANT l'INSERT.
   - **Une CHECK constraint violation à la fin de migration rollback TOUT** (ALTER TYPE, UPDATE, etc. compris). Toujours valider la chaîne complète avant push.

4. **Si migration échoue : NE PAS LAISSER LES FICHIERS DANS LE REPO.** Les supprimer immédiatement (`git rm`) sinon ils bloquent les migrations suivantes au prochain `db push` (le CLI s'arrête à la première erreur, dans l'ordre des timestamps).

5. **Test deploy manuel si possible** avant push : `supabase db push --dry-run --password ...` localement pour catcher les erreurs avant CI.

6. **Surveillance post-merge obligatoire** : après merge, vérifier IMMÉDIATEMENT via MCP Supabase que la migration est bien dans `schema_migrations` ET que les enums/tables sont dans l'état attendu. Ne PAS attendre qu'un user signale un bug. Attendre 10 min minimum avant de conclure que le déploiement a échoué (et non juste en cours).

7. **Dollar-quoting imbriqué interdit avec `$$`** (apprises à la dure 2026-05-13 Sprint 3) : si une migration contient un `DO $$ ... $$` ET à l'intérieur un `cron.schedule(..., $$SELECT...$$)`, le parser PostgreSQL voit le 2e `$$` comme fermeture du DO block → `42601: syntax error at or near "SELECT"`. Le `supabase db push` échoue, mais l'erreur n'apparaît pas si on teste via `mcp__execute_sql` qui parse différemment.
   - **Solution** : utiliser un tag distinct pour le DO block (`DO $body$ ... $body$`) OU passer le SQL cron en simple quote (`'SELECT public.fn_xxx()'`) au lieu de `$$SELECT...$$`.
   - **Prévention** : tester chaque migration contenant pg_cron via `supabase db push --dry-run` avant push, pas seulement via MCP.

## Règles TypeScript / build (apprises 2026-05-13)

- **Utiliser `npx tsc -b` (pas `--noEmit`) pour valider en local** avant push. La config racine `tsconfig.json` a `files: []` + `references` → `tsc --noEmit` sans flag ne traverse pas les references et ne vérifie RIEN, laissant passer des comparaisons de types incompatibles (ex: `role === 'ETABLISSEMENT'` quand `UserRole = 'ADMIN_ETABLISSEMENT' | ...`). Le CI utilise `tsc -b` strict, donc reproduire localement avec la même commande.
- **Toujours utiliser les valeurs exactes des enums `UserRole`** : `SOIGNANT` | `ADMIN_ETABLISSEMENT` | `ADMIN_PLATEFORME` | `ADMIN_GROUPE`. Pas de raccourcis `ETABLISSEMENT` ou `ADMIN`.
- **Colonnes DB non encore dans les types TS générés** : si une migration ajoute des colonnes mais que le deploy-supabase ne s'est pas encore exécuté pour régénérer les types, utiliser `as any` ciblé (`select('*' as any)` + cast du résultat). Pas de hack global — juste sur la query concernée.

## Workflows produits (Sprint 1 + Sprint 2)

### Workflow signature électronique (cf. docs/SIGNATURE_ELECTRONIQUE.md)
- Flow utilisateur OTP SMS via `SignerContratOtp.tsx`
- Ordre obligatoire soignant-puis-étab (art. L1242-13)
- Anti-abus : 3 SMS / 24h × rôle, 5 tentatives OTP, expiration 10 min
- Hash SHA-256 réel du document via Web Crypto API (PR 1 Sprint 2 fix bug critique)
- Audit trail dans `signatures_contrats` (IP, UA, hash, OTP, RPPS, PSC)
- Codes d'erreur structurés `error_code` enum côté RPC → mapping FR côté UI

### Workflow contrat (cf. docs/TEMPLATES_CONTRATS.md)
- 14 templates en DB : CDD master (18 professions via `{{profession}}`) + REMPLACEMENT_LIBERAL master + 12 LIBERAL_* spécifiques
- Edge function `generate-contrat-mission-pdf` rend HTML figé → bucket `contrats-signes` → hash SHA-256
- Auto-trigger au premier affichage du contrat si `storage_path` est NULL
- RPC `fn_resolve_template_contrat(type_contrat, profession, type_etab)` pour matching spécifique ou fallback master

### Workflow DPAE (cf. docs/DPAE_OPTION_A.md)
- **Option A** (actuelle) : payload pré-rempli + copier/coller sur net-entreprises.fr + saisie n° DPAE retour URSSAF
- Schéma complet : `sexe`, `lieu_naissance_commune/departement`, `pays_naissance`, `nationalite` (PR 2 Sprint 2)
- Soignant complète son profil DPAE via `SectionDpaeIdentite.tsx`
- Étab génère + saisit le n° URSSAF via `DPAEStatus.tsx`
- Helper `fn_soignant_dpae_complet` retourne liste champs manquants

### Restrictions Mediflash (matrice profession × type_etab)
- Trigger `dec_valider_compatibilite_mission_liberal` (PR 2 Sprint 1) bloque les missions libérales sur paires incompatibles (ex: IDE LIBERAL en CLINIQUE)
- 8 `CABINET_*` distincts + `ESPIC` ajoutés aux enums type_etablissement
- Helpers `peutExercer()`, `peutExercerLiberal()` côté front (cf. `src/lib/constantes.ts`)

### Sprint 3.5 — Litiges + Annulation + Score + Réclamations

#### Litiges résolution automatique (cf. docs/LITIGES_RESOLUTION_AUTOMATIQUE.md)
- Payload structuré dans `litiges.payload_modifications` (6 types : HORAIRES, MONTANT, ANNULATION, COMPENSATION, MIXTE, SIMPLE)
- `fn_executer_modifications_litige` propage aux presences/factures + enqueue Stripe/Chorus/DPAE via `externalisation_actions`
- `FormulaireAccord.tsx` permet aux parties de proposer + accepter (auto-exec si double accord)

#### Annulation mission (cf. docs/ANNULATION_MISSION.md)
- Fenêtre rétractation 30 min après acceptation (libre pour les 2 parties)
- Grille soignant : 12-24h=-5, 1-12h=-10, ASAP<2h=-25, no-show=-30+signalement admin
- Grille étab : OUVERTE=libre, ACCEPTEE sans contrat=-3, CDD signé=-10+indem L1243-8, libéral signé=-10+clause pénale art.1231-5 (50/30/10%), après pointage=-20+montant complet
- AUCUNE suspension automatique. AUCUNE pénalité financière soignant.

#### Score révisé (cf. docs/SCORE_FIABILITE.md)
- Soignant : note moyenne (40) + comportement events 12m (40) + ancienneté (20)
- Étab : note moyenne (40) + comportement events 12m (40) + délai paiement (20)
- Events ANNULES par admin neutralisés. REDUIRE applique `points_corriges`.

#### Réclamations admin (cf. docs/RECLAMATIONS_ADMIN.md)
- Toute pénalité contestable via `fn_creer_reclamation_score`
- Admin tranche MAINTENIR/REDUIRE/ANNULER via `/admin/reclamations-score`
- Propagation auto sur event + recalcul score + notif user
- AUCUNE action automatique sur compte sans admin

### Sprint 4 — Backend & infra mobile production

#### Push natif (cf. docs/PUSH_NATIVE_FINAL.md)
- `send-push` refacto multi-plateforme : Web Push (VAPID) + FCM HTTP v1 (qui dispatche APNS)
- OAuth2 JWT service account signé via Web Crypto API (RSASSA-PKCS1-v1_5)
- Fallback gracieux si `FIREBASE_SERVICE_ACCOUNT_JSON` absent : Web Push continue, tokens natifs skip avec WARNING
- Channels Android déclarés dans `MainActivity.onCreate` (6 channels selon type_evenement)
- Navigation in-app smart par `type_evenement` (`navigationPathForEvent`)

#### Worker `externalisation_actions` (cf. docs/WORKER_EXTERNALISATION.md)
- Edge function `process-externalisation-actions` + cron pg_cron 5 min
- Dispatch Stripe / Chorus / DPAE / Email / Push / AVOIR PDF
- Backoff exponentiel 1/5/30 min + PENDING_AIFE 24h pour Chorus
- Lock distribué via `FOR UPDATE SKIP LOCKED` + récupération orphelins > 10 min
- Page admin `/admin/externalisations-actions` (retry/cancel/détail)

#### Capacitor wrappers (cf. docs/CAPACITOR_PRODUCTION.md)
- `src/lib/geoloc.ts` : routing native/web pour GPS pointage
- `src/lib/camera.ts` : photo + QR scanner (mlkit natif / html5-qrcode web)
- Plugins : push-notifications, geolocation, camera, network, barcode-scanning
- Permissions iOS `UIBackgroundModes ['remote-notification']` + Android `WAKE_LOCK`/`RECEIVE_BOOT_COMPLETED`/`ACCESS_NETWORK_STATE`

#### Variables d'env requises (Sprint final pour Firebase)
- `FIREBASE_SERVICE_ACCOUNT_JSON` (Vault) — service account JSON Firebase
- `FIREBASE_PROJECT_ID` (Vault) — ID projet
- Si absents : Web Push continue, push natifs désactivés (fallback gracieux)

#### Chantiers reportés post-Sprint 4
- **Sprint final** : création projet Firebase + comptes Apple/Google Developer + APNs p8 key + Xcode capabilities + uploads stores
- **Sprint 4.5** : anti-triche pointage (alerte_teleportation cron + signalement admin)
- **Sprint 5** : UI dette (refacto pages legacy)
- **Sprint 5.5** : CGV à jour + tests E2E Playwright complets

### Sprint 4.5 — Anti-triche pointage (cf. docs/ANTI_TRICHE_POINTAGE.md)

Architecture défensive multi-couches contre la fraude au pointage. **Aucune photo selfie, aucune suspension auto, aucune pénalité financière soignant.**

#### Hiérarchie UX `<CartePointage />`
1. **Scanner QR (recommandé)** — bouton principal large (PR 6 + PR 12)
2. **GPS + Code secours** — boutons secondaires en grille 50/50
3. **Indicateur file offline** quand `qr-offline-queue` non vide

#### Couches anti-triche
- **QR backend** (PR 4) : `fn_generer_qr_mission` + `fn_valider_scan_qr` + auto-génération au signe contrat (trigger). Token UUID + suffix 16 hex.
- **Mock GPS** (PR 2) : `src/lib/mock-detection.ts` heuristiques `accuracy=0`, coords rondes, vitesse aberrante.
- **Téléportation** (PR 2) : `fn_vitesse_entre_pointages` IMMUTABLE + cron `*/15 min` Haversine + alerte si > 200 km/h.
- **Tolérance adaptive** (PR 8) : `tolerance_gps_metres` CHECK `[30, 1000]` DEFAULT 100.
- **Code secours bcrypt** (PR 9) : `fn_generer_code_secours_mission` (clair UNE fois) + `fn_valider_code_secours` (`crypt()` comparison).
- **Ping GPS background** (PR 10) : opt-in RGPD strict, `@capacitor-community/background-geolocation`, table `pings_gps_mission`, purge 30j.
- **Cohérence temporelle** (PR 11) : `fn_evaluer_coherence_pointage` IMMUTABLE 7 codes incidents + worker cron `*/30 min` + `alertes_systeme`.

#### Crons actifs
| Cron | Schedule |
|---|---|
| `jolene_alerte_teleportation` | `*/15 min` |
| `jolene_purger_pings_gps` | `0 3 * * *` |
| `jolene_verifier_pointages_incoherents` | `*/30 min` |

#### Tests (PR 13)
- 12 tests DB-level dans `e2e/flows/anti-triche-pointage.spec.ts`
- Tests UI exclus (QR scanners + background-geolocation non testables headless)

### Sprint 5 — Audit frontend exhaustif (cf. docs/AUDIT_FRONTEND_EXHAUSTIF.md)

Audit Phase 1 diagnostic, 63 sections, 13 P0 / 15 P1 / 15 P2 identifiés. 6 sub-agents Explore en parallèle, 209 RPCs orphelines détectées.

Suivi par hotfix #133 (bug import `ModalReclamationScore` → `score/ModaleReclamationScore` Sprint 3.5).

### Sprint 5.5 — Fixes P0 critiques (8/13 P0 résolus)

Cf. docs/ANNULATION_CANDIDATURE.md, docs/ANNULATION_MISSION_ETAB.md, docs/PARAMETRES_SOIGNANT.md, docs/TOLERANCE_GPS_ETAB.md, docs/DPAE_SOIGNANT.md.

#### Workflows produits livrés
- **Annulation candidature soignant Sprint 3.5** (#134) : fenêtre rétractation 30 min + grille pénalité (5/10/25/30 pts), motif structuré, justificatif optionnel, contestable via page score.
- **Annulation mission étab Sprint 3.5** (#136) : 4 buckets (OUVERTE / ACCEPTEE sans contrat / CDD signé L1243-8 / Libéral signé clause pénale 1231-5 / Après pointage), décomposition financière AVANT confirmation, cadre légal cité.
- **Page paramètres soignant unifiée** (#138 + #139 + #140) : `/soignant/parametres` avec 6 sections (compte/identité/préférences/dispos/RGPD/avancé), `ChangementMotDePasse` (validation 5 critères force), wiring `ConsentementPingGps`.
- **Tolérance GPS étab éditable** (#141) : RPC dédiée `fn_modifier_tolerance_pointage_etab`, slider range [30, 1000] dans tab "config".
- **Page obligations financières étab** (#142) : `/etablissement/obligations` consolidée via `fn_obligations_financieres`, 3 KPI cards, filtres par type, liens vers facturation.
- **DPAE soignant + NIR** (#143) : champ NIR avec validation regex français, page `/soignant/dpae` listant DPAE générées + numéro URSSAF.

#### Nettoyage legacy
- `ModalReclamationScore.tsx` supprimé (#144)
- `AdminReclamations` tab "scoring" : bandeau pointant `/admin/reclamations-score` Sprint 3.5
- Table `reclamations_scoring` conservée pour historique audit

#### Tests playwright (#135 + #137)
- 10 tests annulation candidature soignant (grille 5 buckets + helpers)
- 12 tests annulation mission étab (4 buckets + L1243-8 + 1231-5)

#### P0 reportés Sprint 5.7
- P0-5 : Gestion équipe étab (ADMIN_GROUPE / RH multi-utilisateurs)
- P0-8 : Évaluation reverse étab → soignant
- P0-9 : Page admin consultation contrats (hash + certificat + audit)
- P0-10 : Page admin templates contrats Sprint 2 (CRUD 14 templates)
- P0-11 : Page admin alertes anti-triche Sprint 4.5

### Sprint 5.7 — Fixes 5 P0 majeurs restants (5/5 P0 résolus)

Cf. docs/EQUIPE_ETAB.md, docs/EVALUATION_REVERSE_ETAB.md, docs/ADMIN_CONTRATS.md, docs/ADMIN_TEMPLATES_CONTRATS.md, docs/ADMIN_ALERTES_POINTAGE.md.

12 PRs enchaînées en mode autonome :

#### Workflows produits livrés
- **Équipe étab multi-utilisateurs P0-5** (#147 + #148 + #149) : tables `membres_etablissement` + `invitations_etablissement`, 5 rôles (PROPRIETAIRE / ADMIN_GROUPE / RH / POINTAGE_ONLY / LECTURE_SEULE) × 10 permissions, hook `useEtabPermissions`, wrapper `<SiPermissionEtab>`, page `/etablissement/equipe`, page `/etab/invitation/:token`, email `INVITATION_EQUIPE_ETAB`.
- **Évaluation reverse étab→soignant P0-8** (#151 + #152) : réutilise `notations_missions` sens `ETAB_VERS_SOIGNANT`, 4 critères (ponctualité, technique, relationnel, conformité), page `/etablissement/evaluations-a-faire`.
- **Page admin contrats P0-9** (#153) : `/admin/contrats` + `/admin/contrats/:id` avec hash SHA-256 + signatures détaillées IP/UA + DPAE + PDF embedded + audit trail.
- **Page admin templates contrats P0-10** (#154) : 14 templates Sprint 2 éditables, layout 2-cols avec sidebar 16 variables jinja-like, versioning auto.
- **Page admin alertes anti-triche P0-11** (#155 + #156) : 5 KPIs Sprint 4.5, 4 décisions admin (LEGITIME / FRAUDE_AVERTISSEMENT / FRAUDE_SUSPENSION_PROPOSEE / IGNORER), aucune action automatique sur compte.

#### Sécurité + garde-fous
- Tous les RPCs `fn_admin_*` Sprint 5.7 vérifient `est_admin()` côté serveur
- Dernier PROPRIETAIRE étab protégé (`MIN_PROPRIETAIRE_REQUIS`)
- Aucune suspension automatique (alertes pointage : task admin manuelle uniquement)
- Aucune pénalité financière soignant
- Contrats signés : immutables (template d'origine conservé en snapshot)
- Audit trail complet `journaux_audit` sur toutes les actions admin

#### Tests playwright (#157)
- 5 tests structure équipe étab (tables, bootstrap PROPRIETAIRE, RPCs rejet sans auth)
- 8 tests sécurité admin RPCs (NON_AUTORISE sans auth + 14 templates présents)
- 3 tests évaluation reverse (enum sens ETAB_VERS_SOIGNANT + signalement)

#### Bilan
- ✅ **13/13 P0 Sprint 5 résolus** (8 Sprint 5.5 + 5 Sprint 5.7)
- Prêt pour Sprint 6 (P1/P2 audit Sprint 5)

### Sprint 6 — Fixes P1 audit Sprint 5 (12/15 P1 résolus)

Cf. docs/ONBOARDING_TUTORIEL.md, docs/EVALUATION_POST_MISSION_SOIGNANT.md, docs/SCORE_ETAB_CONTESTATION.md, docs/OTP_SMS_TELEPHONE.md, docs/MANDAT_FACTURATION_SOIGNANT.md.

13 PRs enchaînées en mode autonome :

| PR | P1 | Workflow / Composant | Description courte |
|---|---|---|---|
| PR 1 | P1-3 | Page évaluations reçues soignant | `/soignant/evaluations` dédiée + filtres établissement / période / note |
| PR 2 | P1-2 | Wizard ouverture litige + bouton noter mission | `WizardOuvertureLitige` 3 étapes + `BoutonNoterMission` intégré historique |
| PR 3 | P1-6 | Countdown 72h signature contrat | `CountdownExpirationContrat` visible étab + soignant, désactivation Yousign legacy |
| PR 4 | P1-9 | Contestation événements score étab | `SectionEvenementsScore` générique + page `/etablissement/mes-reclamations` |
| PR 5 | P1-1 | Onboarding tutoriel 7 étapes persistant DB | `OnboardingGuide` étendu + `TooltipAide` + `BoutonResetOnboarding` |
| PR 6 | P1-10 | Dashboard admin alertes anti-triche Sprint 4.5 | Bandeau KPIs téléportation / mock GPS / cohérence cliquables vers `/admin/alertes-pointage` |
| PR 7 | P1-15 | Filtres anti-triche `AdminAuditLogs` | Ajout TELEPORTATION_DETECTEE, MOCK_GPS_SUSPECT, POINTAGE_INCOHERENT, etc. |
| PR 8 | P1-8 | Détail payload accord litige timeline | `PayloadAccordVisualization` rendu jolie des 6 types Sprint 3.5 |
| PR 9 | P1-12 | OTP SMS téléphone | Migration `otps_telephone` + RPCs `fn_envoyer_otp_telephone` / `fn_verifier_otp_telephone` + composant `VerificationTelephoneOTP` |
| PR 10 | P1-13 | Banner mandat facturation embarquable | `BannerMandatFacturation` (statut SIGNÉ / NON_SIGNÉ / VERSION_OBSOLETE) |
| PR 11 | P1-7 | Alertes cohérence pointage côté étab | 7 codes incidents Sprint 4.5 visibles + code secours `visible-once` + badge mock GPS |
| PR 12 | P1-14 | KBIS upload dans inscription étab | Step KBIS dans `InscriptionEtablissement` (déplacé depuis `FinaliserInscriptionEtab`) |
| PR 13 | — | Documentation Sprint 6 | 5 docs MD + CLAUDE.md + AUDIT_FRONTEND_EXHAUSTIF.md badges |

#### Sécurité + garde-fous Sprint 6
- OTP SMS bcrypt salt 8 + rate limit 3/24h + 5 tentatives max
- Onboarding persistance DB priorisée sur localStorage (multi-device)
- Mandat facturation hash SHA-256 + audit IP/UA + résiliation conserve historique RGPD 5 ans
- Aucune action automatique sur compte/score sans admin
- Aucune pénalité financière soignant

#### P1 reportés Sprint 7
- P1-4 : Modal récap mission avant publication + radio LIBERAL disabled (§25)
- P1-5 : Score breakdown soignant inline candidatures (§27)
- P1-11 : Page admin `AdminAuditRLS.tsx` (§49)

#### Bilan
- ✅ **12/15 P1 Sprint 5 résolus** (P1-1, P1-2, P1-3, P1-6, P1-7, P1-8, P1-9, P1-10, P1-12, P1-13, P1-14, P1-15)
- 3 P1 reportés Sprint 7 (P1-4, P1-5, P1-11)
- Prêt pour Sprint 7 (3 P1 restants + P2 polish)
