# Équipe étab multi-utilisateurs (Sprint 5.7)

> Fix **P0-5** audit Sprint 5. Permet à plusieurs utilisateurs (RH, comptable, infirmier coordinateur, etc.) de partager l'accès à un compte établissement avec des permissions granulaires, sans exposer le mot de passe du compte principal.

## Architecture

### Tables

| Table | Description |
|---|---|
| `membres_etablissement` | Lien `user_id` ↔ `etablissement_id` avec rôle + statut |
| `invitations_etablissement` | Invitations en attente (token + email + rôle) |

### Rôles disponibles

| Rôle | Description | Permissions par défaut |
|---|---|---|
| **PROPRIETAIRE** | Créateur initial (un par étab minimum) | Toutes (10/10) |
| **ADMIN_GROUPE** | Admin pour groupes multi-sites | Toutes sauf gestion équipe |
| **RH** | Gestion contrats + paiements | 8/10 (pas équipe, pas suppression) |
| **POINTAGE_ONLY** | Validation pointages uniquement | 2/10 (pointage + lecture missions) |
| **LECTURE_SEULE** | Consultation uniquement | 4/10 (toutes les lectures) |

### Matrice permissions (10 permissions × 5 rôles)

| Permission | PROPRIETAIRE | ADMIN_GROUPE | RH | POINTAGE_ONLY | LECTURE_SEULE |
|---|:---:|:---:|:---:|:---:|:---:|
| `gestion_equipe` | ✅ | ❌ | ❌ | ❌ | ❌ |
| `gestion_etablissement` | ✅ | ✅ | ❌ | ❌ | ❌ |
| `creation_mission` | ✅ | ✅ | ✅ | ❌ | ❌ |
| `lecture_missions` | ✅ | ✅ | ✅ | ✅ | ✅ |
| `gestion_contrats` | ✅ | ✅ | ✅ | ❌ | ❌ |
| `validation_pointage` | ✅ | ✅ | ✅ | ✅ | ❌ |
| `paiement` | ✅ | ✅ | ✅ | ❌ | ❌ |
| `lecture_finances` | ✅ | ✅ | ✅ | ❌ | ✅ |
| `notation_soignant` | ✅ | ✅ | ✅ | ✅ | ❌ |
| `suppression_membre` | ✅ | ❌ | ❌ | ❌ | ❌ |

## RPCs

| RPC | Auth | Description |
|---|---|---|
| `fn_mes_permissions_etab()` | tout user connecté | Retourne `{role, permissions}` pour l'étab courant |
| `fn_inviter_membre_etab(email, role)` | PROPRIETAIRE | Crée invitation + envoie email |
| `fn_accepter_invitation_membre(token)` | invité | Active l'adhésion à l'étab |
| `fn_modifier_role_membre(membre_id, nouveau_role)` | PROPRIETAIRE | Change le rôle |
| `fn_revoquer_membre(membre_id)` | PROPRIETAIRE | Désactive l'adhésion |
| `fn_lister_membres_etab()` | étab connecté | Liste membres + invitations |
| `fn_annuler_invitation_membre(invitation_id)` | PROPRIETAIRE | Annule invitation pending |
| `fn_init_proprietaire_etab(etab_id)` | bootstrap système | Crée le premier PROPRIETAIRE |

## Garde-fous

1. **Dernier PROPRIETAIRE protégé** : impossible de révoquer ou rétrograder le dernier PROPRIETAIRE d'un établissement (`MIN_PROPRIETAIRE_REQUIS` error_code).
2. **Token invitation sécurisé** : `encode(gen_random_bytes(24), 'hex')` = 48 chars hex.
3. **Expiration invitation** : 7 jours, statut `EXPIRE` automatique.
4. **Pas de self-invitation** : `INVITATION_SOI_MEME` interdite.
5. **Pas de double-membre** : `MEMBRE_EXISTANT` si déjà membre.
6. **Audit complet** : chaque action `INSERT INTO journaux_audit` (action=`ADMIN_ACTION`).

## Frontend

- `/etablissement/equipe` — page de gestion (membres actifs + invitations pending + 3 modales)
- `/etab/invitation/:token` — page d'acceptation (auth requise ou redirection inscription)
- Hook `useEtabPermissions()` — retourne `{role, permissions, loading}` pour l'étab courant
- Composant `<SiPermissionEtab permission="paiement">{children}</SiPermissionEtab>` — wrapper conditionnel

## Email

Type `INVITATION_EQUIPE_ETAB` dans `send-email` :
- Subject : "Invitation à rejoindre [nom_etab] sur Jolene"
- CTA : `https://jolene.app/etab/invitation/{token}`
- Expire dans 7 jours

## Bootstrap migration

La migration `20260514160000_pr1s57_membres_etablissement.sql` crée automatiquement un PROPRIETAIRE pour chaque établissement existant via la colonne `email_contact` (matching avec `auth.users`).
