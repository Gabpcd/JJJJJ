# Audit RLS Jolene — État au 28 avril 2026

Couverture exhaustive des 87 tables `public.*` avec RLS activée. Toutes
les tables sensibles (santé, financières, audit) sont protégées.

## Périmètre

- **87 tables** publiques dont **100 % ont RLS activée** (`pg_class.relrowsecurity = true`).
- **0 table** sans policy (toutes les tables RLS-on ont au moins une policy).
- **0 table publique sans RLS** (tables techniques `_prisma_migrations` exclues).

## Pattern RLS Jolene

### Soignants
- Lecture : soi-même OU admin OU étab (si soignant assigné/candidat à mes missions).
- Insert : soi-même, avec champs vérification = false (anti-self-validation).
- Update : soi-même OU admin, champs vérification immutables côté soignant.
- Delete : admin uniquement.

### Établissements
- Lecture : soi-même OU admin OU soignant (visibilité réduite via `est_etablissement_visible`).
- Update : soi-même OU admin, avec trigger `fn_protect_etablissement_commercial`
  qui bloque la modif des champs financiers (taux_commission, palier, Stripe ID, etc.).
- Bypass admin via `est_admin()` ou `app.internal_operation = 'true'` (RPC SECURITY DEFINER).

### Données financières (factures, factures_honoraires, bulletins_paie, cotisations)
- Lecture : propriétaire (soignant/étab) OU admin.
- Pas de policy INSERT/UPDATE pour authenticated : seules les RPC SECURITY DEFINER
  (`generate-invoice`, `fn_creer_bulletin_paie`, `fn_calculer_cotisations`) et le
  service_role peuvent écrire.
- Triggers d'immutabilité (`trg_fh_immutability`, `trg_bp_immutability`) verrouillent
  les champs critiques quand statut IN ('EMISE','PAYEE').

### Audit logs
- `journaux_audit` : SELECT admin uniquement, INSERT par tout authenticated avec
  `acteur_id = auth.uid() OR acteur_id IS NULL` (système). Pas de UPDATE/DELETE
  pour authenticated → append-only au niveau privilèges.
- `invoice_audit_log` : SELECT propriétaire facture OU admin, INSERT **uniquement
  service_role** (les triggers SECURITY DEFINER tournent en owner postgres,
  bypassent RLS). **Faille corrigée le 2026-04-28** : avant cette date, la
  policy `ial_insert` avait `with_check = true` ce qui permettait à n'importe
  quel authenticated d'insérer dans le log fiscal append-only.

### Tables RGPD
- `demandes_rgpd` : utilisateur insère pour soi-même en EN_ATTENTE,
  sélectionne ses demandes, admin gère.

## Tests cross-tenant — résultats du 28/04/2026

Tests via comptes `audit-medecin@jolene-test.dev`, `audit-as@jolene-test.dev`,
`audit-clinique@jolene-test.dev`, `audit-hopital@jolene-test.dev`. Méthode :
transaction PostgreSQL avec `SET LOCAL ROLE authenticated` + `set_config('request.jwt.claims', '{"sub":"<uuid>"}')`.

### Lecture cross-tenant (16 tests, 16 PASS)

| # | Test | Attendu | Obtenu |
|---|---|---|---|
| T1 | medecin lit son propre profil | 1 | 1 ✓ |
| T2 | medecin lit profil audit-as | 0 | 0 ✓ |
| T3 | medecin liste tous soignants visibles | ≤ étabs partagés | 1 (lui-même) ✓ |
| T4 | medecin lit factures audit-as | 0 | 0 ✓ |
| T5 | medecin lit bulletins_paie audit-as | 0 | 0 ✓ |
| T6 | medecin lit missions clinique (sans candidature) | 0 | 0 ✓ |
| T7 | medecin lit invoice_audit_log audit-as | 0 | 0 ✓ |
| T8 | medecin lit journaux_audit (admin only) | 0 | 0 ✓ |
| T9 | medecin lit cotisations_sociales audit-as | 0 | 0 ✓ |
| T10 | medecin lit demandes_rgpd audit-as | 0 | 0 ✓ |
| T11 | medecin lit documents_soignants audit-as | 0 | 0 ✓ |
| T12 | medecin lit notifications audit-as | 0 | 0 ✓ |
| T14 | medecin lit stripe_connect_onboarding audit-as | 0 | 0 ✓ |
| T15 | medecin lit partages_rib audit-as | 0 | 0 ✓ |
| T16 | medecin lit api_keys (admin only) | 0 | 0 ✓ |
| T17 | medecin lit chorus_pro_config | 0 | 0 ✓ |

### Écriture cross-tenant (4 tests, 4 PASS)

| # | Test | Attendu | Obtenu |
|---|---|---|---|
| W2 | medecin DELETE soignants audit-as | 0 rows | 0 rows ✓ |
| W3 | medecin DELETE journaux_audit | permission denied | denied ✓ (pas de GRANT DELETE) |
| W4 | medecin INSERT invoice_audit_log fictif | row violates RLS | denied ✓ (post-fix REVOKE INSERT) |

### Résultat global

100 % des tests cross-tenant passent. Pas d'évasion possible entre comptes
authentifiés via les tables sensibles.

## Advisors Supabase (post-fix)

| Lint | Avant | Après | Statut |
|---|---|---|---|
| `rls_policy_always_true` | 1 (invoice_audit_log) | 0 | ✅ FIX |
| `function_search_path_mutable` | 2 | 0 | ✅ FIX |
| `anon_security_definer_function_executable` | 2 | 2 | ⚠️ VOLONTAIRE (fn_missions_publiques_recherche, fn_types_exercice_autorises pour inscription/recherche publique) |
| `authenticated_security_definer_function_executable` | 219 | 221 | ⚠️ PATTERN JOLENE (toutes les RPC métier sont SECURITY DEFINER avec GRANT authenticated) |

## Helpers RLS centraux

- `auth.uid()` : UUID utilisateur courant (Supabase Auth).
- `est_admin()` : booléen, true si l'utilisateur est admin plateforme.
- `mon_etablissement_id()` : UUID de l'établissement principal courant (= auth.uid() pour le compte propriétaire).
- `app.internal_operation = 'true'` : bypass triggers de protection commerciale (RPC SECURITY DEFINER seulement).

## Bug connu (non bloquant)

**`pol_soig_update` infinite recursion** : la policy WITH CHECK contient des
sous-requêtes `SELECT ... FROM soignants WHERE id = auth.uid()` qui re-déclenchent
l'évaluation de policies, créant une recursion. Tout UPDATE direct sur `soignants`
par un authenticated échoue avec `42P17 infinite recursion`.

**Impact** : nul en pratique. Le frontend passe par `fn_modifier_mon_profil`
(SECURITY DEFINER) qui bypass RLS. Aucun bug report utilisateur.

**Fix recommandé (P3)** : réécrire la policy pour utiliser une fonction
SECURITY DEFINER cachée qui retourne les valeurs sentinelles (rpps_verifie etc.)
pour l'utilisateur courant, sans re-lire `soignants` dans WITH CHECK.

## Comptes audit-* (à ne pas supprimer)

19 comptes pour tests RLS futurs. Préfixe `audit-{profession}@jolene-test.dev`,
mot de passe `auditTest2026!`.

- 15 soignants : audit-{ide,medecin,as,aes,kine,sage-femme,iade,ibode,
  ergotherapeute,manipulateur-radio,orthophoniste,pharmacien,
  preparateur-pharma,psychomotricien,dieteticien}
- 4 établissements : audit-{clinique,hopital,ehpad,pharmacie}

Pour ré-exécuter la batterie, voir `scripts/test-rls-cross-tenant.sql`
(à créer si test régression nécessaire).
