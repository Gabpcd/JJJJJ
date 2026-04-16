# Comptes de test — Jolene

## Comptes existants

| Rôle | Email | Usage | raw_app_meta_data |
|---|---|---|---|
| Soignant (test principal) | test@jolene.app | Tests fonctionnels soignant, factures, mandat | `{role: "SOIGNANT"}` |
| Établissement (test) | etab@jolene.app | Tests missions, facturation | `{role: "ADMIN_ETABLISSEMENT"}` |
| Admin plateforme | admin@jolene.app | Administration prod | `{role: "ADMIN_PLATEFORME"}` |

## Compte à créer

| Rôle | Email | Usage | raw_app_meta_data |
|---|---|---|---|
| Admin ops-test | ops-test@jolene.app | Invocations admin-invoke, tests E2E | `{role: "ADMIN_PLATEFORME", is_test_admin: true}` |

### Restrictions ops-test@jolene.app

- `is_test_admin: true` dans les metadata
- Toutes les invocations via admin-invoke sont marquées `is_test=true`
- Le dashboard admin frontend masque les fonctionnalités opérationnelles si `is_test_admin=true`
- Ce compte ne doit PAS être utilisé pour des actions prod réelles
- Password stocké dans Supabase Secrets : `OPS_TEST_ADMIN_PASSWORD`

## Règles

1. **Aucun credential de test ne doit être committé dans le repo** — uniquement dans Supabase Secrets
2. Les factures créées par des comptes de test doivent être marquées `admin_notes = 'Facture de test — sans valeur fiscale'` et passées en statut ANNULEE après validation
3. Les invocations de test sont identifiables via `is_test=true` dans admin_invocations

## Gestion des mots de passe

- Les mots de passe des comptes de test sont stockés **UNIQUEMENT** dans Supabase Secrets (nommés `OPS_TEST_ADMIN_PASSWORD`, etc.)
- **Rotation tous les 90 jours** (tâche manuelle, à planifier dans le calendrier ops)
- Les comptes de test ne doivent **JAMAIS** être utilisés pour une démo client, un investisseur, ou un test de UX. Leur rôle est **strictement technique** (tests E2E, invocations admin, debug).
- **En cas de compromission suspectée** :
  1. Régénération immédiate du password dans Supabase Secrets
  2. Révocation de toutes les sessions actives (`auth.admin.deleteUser` + recréation si nécessaire)
  3. Audit des `admin_invocations` sur les 72 dernières heures pour ce user_id
  4. Notification à l'équipe via email [OPS]
