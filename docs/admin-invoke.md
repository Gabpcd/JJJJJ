# admin-invoke — Outil d'ops permanent

## Quand utiliser

- **Tests E2E** : invoquer `generate-invoice` sur une mission de test pour valider le PDF/XML
- **Replay Chorus** : relancer `submit-to-chorus` sur une facture dont la soumission a échoué
- **Régénération facture** : relancer `generate-invoice` si un bug a été corrigé dans le template
- **Debug prod** : invoquer `factor-request-advance` pour diagnostiquer un rejet Defacto
- **Dry run** : tester le payload sans invoquer la fonction cible

## Quand NE PAS utiliser

- Tout ce qui est un flow utilisateur normal (inscription, publication mission, paiement) — utiliser le frontend
- Suppression de données — utiliser les RPCs admin dédiées
- Modification de configuration — utiliser le dashboard Supabase

## Allowlist

| Fonction | Usage ops |
|---|---|
| `generate-invoice` | Test E2E, régénération facture |
| `submit-to-chorus` | Replay soumission échouée |
| `sync-chorus-status` | Forcer une sync de statut |
| `factor-request-advance` | Debug rejet affacturage |
| `send-email` | Renvoyer un email admin |

### Comment ajouter une fonction à l'allowlist

1. Ouvrir `supabase/functions/admin-invoke/index.ts`
2. Ajouter le nom dans `ALLOWED_FUNCTIONS_PROD`
3. Si sensible (flux argent, facture, données perso), ajouter aussi dans `SENSITIVE_FUNCTIONS`
4. Créer une PR avec justification (pourquoi cette fonction doit être invocable par un admin)
5. Valider que la fonction cible supporte le bypass service_role

### Mode dev (A4)

En mode `SUPABASE_ENV=dev`, des fonctions supplémentaires sont autorisées (ex: `seed-test-data`). Ces fonctions sont dans `ALLOWED_FUNCTIONS_DEV_EXTRA`. Ne jamais ajouter de fonctions sensibles dans cette liste — elles doivent être dans `ALLOWED_FUNCTIONS_PROD`.

### Correlation (A3)

Chaque invocation génère un `request_id` (UUID v4) propagé dans :
- La colonne `request_id` de `admin_invocations`
- Le header `X-Request-Id` passé à la fonction cible
- L'email de notification Resend
- Les logs console `[admin-invoke][request_id]`

### internal_status (V7)

| État | Signification |
|---|---|
| PENDING | Audit écrit, invocation pas encore lancée |
| INVOKED | Fetch vers la cible en cours |
| COMPLETED | Résultat reçu et écrit dans audit |
| CRASHED | Monitoring : lignes PENDING/INVOKED > 5 min |

## Auth (3 couches)

1. **JWT valide** (verify_jwt=true dans config.toml)
2. **Admin Jolene** (raw_app_meta_data.role = 'ADMIN_PLATEFORME', pas banni, email confirmé)
3. **X-Admin-Confirm header** : `SHA256(user_id + ":" + minute_window + ":" + ADMIN_INVOKE_SALT)`
   - Valide la minute courante ET la minute précédente (tolérance horloge)
   - Salt en env var `ADMIN_INVOKE_SALT`

## Rate limit

- **20 invocations par admin par heure**
- **100 invocations globales par heure**
- Comptage via query DB (persiste entre cold starts)

## Runbooks

### Test E2E generate-invoice

```bash
npx tsx scripts/test-generate-invoice.ts <mission_id>
```

Le script :
1. Se connecte en admin (email/password)
2. Calcule X-Admin-Confirm
3. Appelle admin-invoke avec target_function="generate-invoice"
4. Télécharge PDF + XML depuis Storage
5. Vérifie les mentions légales

### Replay soumission Chorus

```
POST /functions/v1/admin-invoke
{
  "target_function": "submit-to-chorus",
  "target_payload": { "facture_honoraire_id": "<uuid>" },
  "reason": "admin_replay — soumission échouée le DD/MM/YYYY"
}
```

### Régénération facture

```
POST /functions/v1/admin-invoke
{
  "target_function": "generate-invoice",
  "target_payload": { "mission_id": "<uuid>" },
  "reason": "admin_replay — correction template v2"
}
```

Note : la facture existante doit être en statut ANNULEE d'abord (idempotence).
