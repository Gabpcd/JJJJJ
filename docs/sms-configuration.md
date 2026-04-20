# SMS configuration — Jolene

## Vue d'ensemble

L'edge function `send-sms` (Twilio) envoie des SMS courts (≤ 160 car.) aux soignants et établissements pour alertes critiques (litiges, présences, remboursements). Chaque SMS est préfixé par un marqueur d'origine (`Jolene: ` par défaut).

Depuis **CP-LITIGES-7a FIX 20**, ce préfixe est configurable globalement via variable d'environnement + override par type de message.

## Variables d'environnement

| Secret                  | Obligatoire | Défaut      | Description                                    |
| ----------------------- | ----------- | ----------- | ---------------------------------------------- |
| `SMS_PREFIX_DEFAULT`    | non         | `Jolene: `  | Préfixe utilisé pour tous les SMS sans override. |
| `SMS_PREFIX_OVERRIDES`  | non         | `{}`        | JSON `{type: prefix}` — overrides par `prefix_type`. |

### Exemple de configuration

```bash
# Supabase CLI
supabase secrets set SMS_PREFIX_DEFAULT="Jolene: "
supabase secrets set SMS_PREFIX_OVERRIDES='{"LITIGE_SECURITE":"Jolene-URGENT: ","LITIGE_RAPPEL_J5":"Jolene-ALERTE: "}'
```

Si `SMS_PREFIX_OVERRIDES` contient du JSON invalide, le fallback est `{}` et un warning est loggé (sans interruption).

## Utilisation côté appelant

Le body de l'appel `send-sms` accepte un champ optionnel `prefix_type` :

```json
{
  "telephone": "+33612345678",
  "contenu": "Intervention requise — zone sécurisée",
  "type": "LITIGE_SECURITE",
  "prefix_type": "LITIGE_SECURITE",
  "destinataire_id": "<uuid>"
}
```

Résolution du préfixe (fonction `resolveSmsPrefix`) :

1. Si `prefix_type` est fourni **et** une clé correspondante existe dans `SMS_PREFIX_OVERRIDES` → utiliser cette valeur.
2. Sinon → utiliser `SMS_PREFIX_DEFAULT` (soit `Jolene: ` par défaut).

### Valeur de `prefix_type` vs `type`

- `type` : catégorie stockée dans `sms_envoyes.type` (audit, analytics).
- `prefix_type` : clé de lookup pour le préfixe. Généralement identique à `type` mais peut différer si plusieurs `type` partagent un préfixe.

## Troncature dynamique

La longueur maximale SMS Twilio = **160 caractères**. Le corps est tronqué dynamiquement en fonction de la longueur du préfixe :

```
maxBodyLen = max(20, 160 - prefix.length)
```

Si `contenu.length > maxBodyLen`, le corps est tronqué à `maxBodyLen - 3` + `"..."`.

| Préfixe              | Longueur | Body max | Body tronqué à |
| -------------------- | -------- | -------- | -------------- |
| `Jolene: `           | 8        | 152      | 149 + `...`    |
| `Jolene-URGENT: `    | 15       | 145      | 142 + `...`    |
| `Jolene-ALERTE: `    | 15       | 145      | 142 + `...`    |
| `Jolene-PAIEMENT: `  | 17       | 143      | 140 + `...`    |

## Ajouter un nouveau préfixe

1. Décider du `prefix_type` côté appelant (ex : `REMBOURSEMENT_URGENT`).
2. Ajouter l'entrée dans `SMS_PREFIX_OVERRIDES` (Supabase Dashboard > Edge Functions > Secrets) :
   ```json
   {
     "LITIGE_SECURITE":      "Jolene-URGENT: ",
     "REMBOURSEMENT_URGENT": "Jolene-URGENT: "
   }
   ```
3. Côté appelant (SQL, edge function, front), passer `prefix_type: 'REMBOURSEMENT_URGENT'` dans le body.
4. Aucun redéploiement d'edge function nécessaire — la variable est lue à chaque cold-start.

## Tests

- **Unitaires** : `tests/sms/prefix.test.ts` (vitest) — couvre resolveSmsPrefix (8 cas) + buildFullBody truncation (4 cas).
- **End-to-end** : configurer `SMS_PREFIX_OVERRIDES` sur un projet staging, déclencher un SMS via `email-cron` (type `LITIGE_RAPPEL_J5` avec override → vérifier réception mobile avec le préfixe custom).

## Origine historique

Avant FIX 20, le préfixe `Jolene: ` était **hardcoded** à la ligne 75 de `send-sms/index.ts`. Toute modification nécessitait un redéploiement d'edge function. FIX 20 externalise la configuration pour permettre des tests A/B de wording et des overrides par type de message sans toucher au code.
