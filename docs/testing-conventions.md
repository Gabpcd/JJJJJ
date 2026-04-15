# Conventions de test — Jolene

## Factures de test en production

Les factures honoraires sont **immuables** une fois émises (obligation fiscale, trigger `trg_fh_immutability`). Une facture créée en prod ne peut pas être supprimée.

### Pattern pour les tests E2E en prod

1. **Utiliser un compte soignant dédié** : `test-ops@jolene.app` (à créer) avec profil marqué pour l'identifier
2. **Ajouter `admin_notes`** sur la facture après création : `"Facture de validation <PR_ID> — sans valeur fiscale"`
3. **Passer le statut à `ANNULEE`** immédiatement après validation
4. **Filtrer dans les stats** : exclure les factures avec `admin_notes LIKE 'Facture de validation%'` ou `statut = 'ANNULEE'`

### Service_role bypass

Les scripts de test utilisent le bypass service_role de `generate-invoice` avec une `service_role_reason` obligatoire :

| Reason pattern | Usage |
|---|---|
| `ops_test_<purpose>` | Scripts de test/validation (ex: `ops_test_pr2_validation`) |
| `cron_auto_generation` | Cron automatique de génération |
| `admin_replay_<uuid>` | Replay manuel par un admin (UUID = admin user) |

Chaque appel est loggé dans `invoice_audit_log` avec action `GENERATED_VIA_SERVICE_ROLE`.

### Rate limit

Max 10 appels service_role par minute sur `generate-invoice`. Au-delà → 429.

### Nettoyage post-test

```sql
-- Annuler la facture test
UPDATE factures_honoraires 
SET statut = 'ANNULEE', admin_notes = 'Facture de validation P1bis — sans valeur fiscale'
WHERE id = '<facture_id>';
```
