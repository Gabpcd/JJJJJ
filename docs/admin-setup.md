# Setup compte admin Jolene

Date : 2026-05-03

## Comptes admin existants

| Email | UUID | Rôle | Créé le |
|---|---|---|---|
| `admin@jolene.app` | 09e82688-e524-42bb-9268-1384c757f33d | ADMIN_PLATEFORME | 2026-03-16 |
| `ops-test@jolene.app` | 07dae751-4be3-468d-b8ec-c4b8176a596f | ADMIN_PLATEFORME | 2026-04-16 |

Le compte admin est identifié par `raw_app_meta_data->>'role' = 'ADMIN_PLATEFORME'` dans `auth.users` (vérifié par `est_admin()` côté Postgres).

## Pourquoi les pages /admin/* refusent l'accès

Toutes les RPCs et pages admin vérifient `est_admin()` (qui lit `raw_app_meta_data->>'role'` depuis `auth.users` pour `auth.uid()`). Si l'utilisateur connecté n'a pas ce rôle :
- Les RPCs retournent `{"error": "Accès refusé"}`
- Les pages affichent un message d'erreur explicite (ou redirection vers `/`)

## Comment créer un compte admin

### Option A — Promouvoir un compte existant en admin

```sql
-- Identifier l'utilisateur
SELECT id, email FROM auth.users WHERE email = 'NOUVEL_ADMIN@example.com';

-- Promouvoir
UPDATE auth.users
SET raw_app_meta_data = jsonb_set(
  COALESCE(raw_app_meta_data, '{}'::jsonb),
  '{role}',
  '"ADMIN_PLATEFORME"'
)
WHERE id = 'UUID_DU_USER';

-- Vérifier
SELECT id, email, raw_app_meta_data->>'role' AS role FROM auth.users WHERE id = 'UUID_DU_USER';
```

L'utilisateur doit se reconnecter pour que le nouveau rôle soit pris en compte (le JWT actuel cache l'ancien `app_metadata`).

### Option B — Créer un nouveau compte admin via Supabase Dashboard

1. https://supabase.com/dashboard/project/flripxtsyegjshnhzjkz/auth/users
2. "Invite user" → renseigner l'email
3. L'utilisateur reçoit un mail d'invitation, définit un mot de passe
4. Une fois connecté, exécuter la requête SQL ci-dessus pour le promouvoir

### Option C — Compte test ops-test@jolene.app

Ce compte existe déjà (`ops-test@jolene.app`). Mot de passe à définir via Supabase Dashboard → Authentication → "Send password recovery" (ou via SQL `UPDATE auth.users SET encrypted_password = crypt('nouveau-pwd', gen_salt('bf'))`).

## Vérifier qu'un compte est admin

```sql
SELECT id, email, raw_app_meta_data->>'role' AS role
FROM auth.users
WHERE email = 'votre@email.com';
```

Doit retourner `role = 'ADMIN_PLATEFORME'`.

## Tester depuis l'UI

Une fois connecté avec un compte admin :
1. https://jolene.app/admin → dashboard admin
2. Toutes les pages `/admin/*` doivent charger sans "Accès refusé"

## Pages admin disponibles (post-fix Session)

Toutes les pages sont protégées par `RouteProtegee rolesAutorises={['ADMIN_PLATEFORME']}` côté frontend + check `est_admin()` côté RPC.

| Sidebar | Route | Page |
|---|---|---|
| Dashboard | `/admin` | AdminDashboard |
| Tous les utilisateurs | `/admin/utilisateurs` | AdminUtilisateurs |
| Modération | `/admin/moderation` | AdminModeration |
| Réclamations | `/admin/reclamations` | AdminReclamations |
| Groupes santé | `/admin/groupes` | AdminGroupes |
| Toutes les missions | `/admin/missions` | AdminMissions |
| Pool urgence | `/admin/pool-urgence` | PoolUrgenceEtablissement (mode admin) |
| Calendrier | `/admin/calendrier` | AdminCalendrier |
| Litiges | `/admin/litiges` | AdminLitiges |
| Vue d'ensemble finance | `/admin/finances` | AdminFinances |
| Facturation | `/admin/facturation` | AdminFacturation |
| Impayées | `/admin/impayees` | AdminImpayees |
| Mandats facturation | `/admin/mandats-facturation` | AdminMandatsFacturation |
| Affacturage | `/admin/affacturage` | AdminAffacturage |
| Chorus Pro | `/admin/chorus-pro` | AdminChorusPro |
| Cohort & Economics | `/admin/cohort` | AdminCohortEconomics |
| Taux commission | `/admin/taux-commission` | AdminTauxCommission |
| Messagerie | `/admin/messagerie` | PageMessagerie (mode admin) |
| Conformité | `/admin/conformite` | AdminConformite |
| Audit Logs | `/admin/audit` | AdminAuditLogs |
| DPIA | `/admin/dpia` | AdminDPIA |
| Healthcheck | `/admin/healthcheck` | AdminHealthcheck |
| Status système | `/admin/status` | AdminStatus |
| Emails | `/admin/emails` | AdminEmails |
| API | `/admin/api` | AdminAPI |
| Demo | `/admin/demo` | AdminDemo |

## Tech-debt résolue (Session admin)

- **4 pages 404 fixées** : `/admin/audit`, `/admin/dpia`, `/admin/healthcheck`, `/admin/cohort` — pages existaient mais routes manquantes dans App.tsx
- **AdminCohortEconomics LayoutApp → LayoutAdmin** : cohérence visuelle avec autres pages admin
- **AdminChorusPro message d'erreur explicite** : "Accès refusé ou erreur chargement stats" → message détaillé indiquant la cause (RPC error vs role check) + lien vers `admin-setup.md`
