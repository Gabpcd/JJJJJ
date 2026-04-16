# Politique de rétention des données — Jolene

## admin_invocations (ops audit)

| Catégorie | Rétention | Critère |
|---|---|---|
| Fonctions sensibles (generate-invoice, submit-to-chorus, factor-request-advance) | **10 ans** | Aligné sur conservation factures (obligation fiscale art. L102 B LPF) |
| Invocations échouées (status 4xx/5xx) hors sensibles | **2 ans** | Analyse d'incidents |
| Invocations réussies (status 2xx) hors sensibles | **90 jours** | Audit opérationnel courant |
| Invocations jamais complétées (status NULL) | **90 jours** | Nettoyage des crashes |

Purge : `fn_admin_invocations_purge()` appelée par cron hebdomadaire.

## invoice_audit_log (traçabilité fiscale)

| Catégorie | Rétention |
|---|---|
| Toutes les lignes | **10 ans** (obligation fiscale art. L102 B LPF) |

Pas de purge automatique. Les lignes sont append-only (DELETE + UPDATE bloqués par trigger).

## journaux_audit (RGPD)

| Catégorie | Rétention |
|---|---|
| Actions utilisateur | **3 ans** (recommandation CNIL pour les logs d'activité) |
| Actions admin | **5 ans** |

## Données personnelles (RGPD art. 17)

| Donnée | Rétention | Base légale |
|---|---|---|
| Comptes utilisateurs actifs | Durée de la relation | Contrat |
| Comptes supprimés (soft delete) | **3 ans** après supprime_le | Obligation légale (santé) |
| Factures honoraires | **10 ans** | Obligation fiscale |
| Documents soignants | **5 ans** après dernière mission | Obligation légale (santé) |

## Mise en œuvre

- Les fonctions de purge sont des RPCs `SECURITY DEFINER` avec advisory lock
- Elles sont appelées par `pg_cron` (à configurer dans le dashboard Supabase)
- Le trigger de la table cible vérifie le lock avant d'autoriser le DELETE
