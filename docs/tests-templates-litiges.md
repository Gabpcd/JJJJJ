# Tests templates litiges — FIX 13 + Bloc 4

## Objectif

Valider **manuellement** l'envoi réel des 12 templates email du flow litiges vers `gabrielle@jolene.app`, avec données mockées réalistes. Une validation automatisée structurelle complémentaire est dans `tests/litiges/templates-structure.test.ts`.

## Prérequis

```bash
export SUPABASE_URL=https://flripxtsyegjshnhzjkz.supabase.co
export SERVICE_ROLE_KEY="<service_role_key>"
export DEST_EMAIL=gabrielle@jolene.app

# destinataire_id doit être un soignant ou user existant avec email=$DEST_EMAIL
export DEST_UUID="<uuid_gabrielle>"
```

## Commandes curl — 12 templates

### 1. LITIGE_OUVERTURE

```bash
curl -X POST "$SUPABASE_URL/functions/v1/send-email" \
  -H "Authorization: Bearer $SERVICE_ROLE_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "type": "LITIGE_OUVERTURE",
    "destinataire_id": "'"$DEST_UUID"'",
    "data": {
      "type_litige": "DESACCORD_MONTANT_FACTURE",
      "mission_id": "m-001",
      "url_litige": "/soignant/litiges",
      "est_salarie": false
    }
  }'
```

### 2. LITIGE_NOUVEAU_MESSAGE

```bash
curl -X POST "$SUPABASE_URL/functions/v1/send-email" \
  -H "Authorization: Bearer $SERVICE_ROLE_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "type": "LITIGE_NOUVEAU_MESSAGE",
    "destinataire_id": "'"$DEST_UUID"'",
    "data": {
      "type_litige": "DESACCORD_MONTANT_FACTURE",
      "url_litige": "/soignant/litiges/abc"
    }
  }'
```

### 3. LITIGE_ESCALADE_ADMIN

```bash
curl -X POST "$SUPABASE_URL/functions/v1/send-email" \
  -H "Authorization: Bearer $SERVICE_ROLE_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "type": "LITIGE_ESCALADE_ADMIN",
    "destinataire_id": "'"$DEST_UUID"'",
    "data": {
      "type_litige": "CONDITIONS_MISSION_NON_RESPECTEES",
      "mission_id": "m-002",
      "est_salarie": true
    }
  }'
```

### 4. LITIGE_MEDIATION_PRIORITAIRE

```bash
curl -X POST "$SUPABASE_URL/functions/v1/send-email" \
  -H "Authorization: Bearer $SERVICE_ROLE_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "type": "LITIGE_MEDIATION_PRIORITAIRE",
    "destinataire_id": "'"$DEST_UUID"'",
    "data": {
      "type_litige": "DESACCORD_HEURES_POINTAGE",
      "mission_id": "m-003",
      "jours_depuis_escalade": 10
    }
  }'
```

### 5a. LITIGE_RESOLU_AJUSTE — variante RECALCUL

```bash
curl -X POST "$SUPABASE_URL/functions/v1/send-email" \
  -H "Authorization: Bearer $SERVICE_ROLE_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "type": "LITIGE_RESOLU_AJUSTE",
    "destinataire_id": "'"$DEST_UUID"'",
    "data": {
      "action_financiere": "RECALCUL",
      "en_faveur_de": "SOIGNANT",
      "resolution": "Heures ajustées de 35h à 33h selon preuve pointage.",
      "numero_facture": "FH-12345678-2026-00042",
      "heures_avant": 35, "heures_apres": 33,
      "montant_avant": 875, "montant_apres": 825
    }
  }'
```

### 5b. LITIGE_RESOLU_AJUSTE — variante ANNULER_REEMETTRE

```bash
curl -X POST "$SUPABASE_URL/functions/v1/send-email" \
  -H "Authorization: Bearer $SERVICE_ROLE_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "type": "LITIGE_RESOLU_AJUSTE",
    "destinataire_id": "'"$DEST_UUID"'",
    "data": {
      "action_financiere": "ANNULER_REEMETTRE",
      "en_faveur_de": "ETABLISSEMENT",
      "resolution": "Facture annulée + nouvelle émise avec montant corrigé.",
      "numero_ancienne": "FH-12345678-2026-00042",
      "numero_nouvelle": "FH-12345678-2026-00055"
    }
  }'
```

### 5c. LITIGE_RESOLU_AJUSTE — variante AVOIR

```bash
curl -X POST "$SUPABASE_URL/functions/v1/send-email" \
  -H "Authorization: Bearer $SERVICE_ROLE_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "type": "LITIGE_RESOLU_AJUSTE",
    "destinataire_id": "'"$DEST_UUID"'",
    "data": {
      "action_financiere": "AVOIR",
      "en_faveur_de": "SOIGNANT",
      "resolution": "Avoir émis — mission partiellement non honorée.",
      "numero_avoir": "AV-12345678-2026-00003"
    }
  }'
```

### 6. AVOIR_EMIS (avec PJ PDF)

Prérequis : un avoir réel avec `pdf_s3_key` présent dans `jolene-documents`.

```bash
curl -X POST "$SUPABASE_URL/functions/v1/send-email" \
  -H "Authorization: Bearer $SERVICE_ROLE_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "type": "AVOIR_EMIS",
    "destinataire_id": "'"$DEST_UUID"'",
    "data": {
      "avoir_id": "<uuid_avoir_avec_pdf>",
      "numero_avoir": "AV-12345678-2026-00003",
      "numero_facture_origine": "FH-12345678-2026-00042",
      "montant_avoir": "150.00",
      "mode_remboursement_texte": "Virement sous 7 jours ouvrés",
      "date_remboursement_prevue": "24/04/2026"
    }
  }'
```

### 7. REMBOURSEMENT_CONFIRME

```bash
curl -X POST "$SUPABASE_URL/functions/v1/send-email" \
  -H "Authorization: Bearer $SERVICE_ROLE_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "type": "REMBOURSEMENT_CONFIRME",
    "destinataire_id": "'"$DEST_UUID"'",
    "data": {
      "montant": "150.00",
      "mode_texte": "Virement bancaire",
      "reference": "VIR-2026-04-17-001",
      "numero_avoir": "AV-12345678-2026-00003",
      "delai_bancaire": "2 à 5 jours ouvrés"
    }
  }'
```

### 8. LITIGE_RAPPEL_J1

```bash
curl -X POST "$SUPABASE_URL/functions/v1/send-email" \
  -H "Authorization: Bearer $SERVICE_ROLE_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "type": "LITIGE_RAPPEL_J1",
    "destinataire_id": "'"$DEST_UUID"'",
    "data": { "url_litige": "/soignant/litiges/abc" }
  }'
```

### 9. LITIGE_RAPPEL_J3

```bash
curl -X POST "$SUPABASE_URL/functions/v1/send-email" \
  -H "Authorization: Bearer $SERVICE_ROLE_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "type": "LITIGE_RAPPEL_J3",
    "destinataire_id": "'"$DEST_UUID"'",
    "data": { "url_litige": "/soignant/litiges/abc" }
  }'
```

### 10. LITIGE_RAPPEL_J5

```bash
curl -X POST "$SUPABASE_URL/functions/v1/send-email" \
  -H "Authorization: Bearer $SERVICE_ROLE_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "type": "LITIGE_RAPPEL_J5",
    "destinataire_id": "'"$DEST_UUID"'",
    "data": { "url_litige": "/soignant/litiges/abc" }
  }'
```

### 11. REGULARISATION_SOCIALE_REQUISE

```bash
curl -X POST "$SUPABASE_URL/functions/v1/send-email" \
  -H "Authorization: Bearer $SERVICE_ROLE_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "type": "REGULARISATION_SOCIALE_REQUISE",
    "destinataire_id": "'"$DEST_UUID"'",
    "data": {
      "mission_intitule": "Nuit IDE Rémy 17/01/2026",
      "ancien_nombre_heures": "10",
      "nouveau_nombre_heures": "8",
      "ancien_montant": "250",
      "nouveau_montant": "200",
      "date_origine_facture": "20/01/2026"
    }
  }'
```

### 12a. COMMISSION_AJUSTEE — variante AVOIR

```bash
curl -X POST "$SUPABASE_URL/functions/v1/send-email" \
  -H "Authorization: Bearer $SERVICE_ROLE_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "type": "COMMISSION_AJUSTEE",
    "destinataire_id": "'"$DEST_UUID"'",
    "data": {
      "type_document": "AVOIR",
      "numero_document": "AVC-2026-04-0001",
      "montant": "24.00",
      "mission_intitule": "Nuit IDE Rémy 17/01/2026",
      "litige_id": "lit-001"
    }
  }'
```

### 12b. COMMISSION_AJUSTEE — variante FACTURE_COMPLEMENTAIRE

```bash
curl -X POST "$SUPABASE_URL/functions/v1/send-email" \
  -H "Authorization: Bearer $SERVICE_ROLE_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "type": "COMMISSION_AJUSTEE",
    "destinataire_id": "'"$DEST_UUID"'",
    "data": {
      "type_document": "FACTURE_COMPLEMENTAIRE",
      "numero_document": "FC-2026-04-0002",
      "montant": "36.00",
      "mission_intitule": "Jour AS Aïcha 18/01/2026",
      "litige_id": "lit-002"
    }
  }'
```

## Grille de validation

À remplir lors du test (par Gabrielle ou admin plateforme).

| #   | Template                       | Date envoi | Reçu | Subject correct | Body correct | Lien OK | Notes |
| --- | ------------------------------ | ---------- | ---- | --------------- | ------------ | ------- | ----- |
| 1   | LITIGE_OUVERTURE               |            |      |                 |              |         |       |
| 2   | LITIGE_NOUVEAU_MESSAGE         |            |      |                 |              |         |       |
| 3   | LITIGE_ESCALADE_ADMIN          |            |      |                 |              |         |       |
| 4   | LITIGE_MEDIATION_PRIORITAIRE   |            |      |                 |              |         |       |
| 5a  | LITIGE_RESOLU_AJUSTE — RECALCUL|            |      |                 |              |         |       |
| 5b  | LITIGE_RESOLU_AJUSTE — AR      |            |      |                 |              |         |       |
| 5c  | LITIGE_RESOLU_AJUSTE — AVOIR   |            |      |                 |              |         |       |
| 6   | AVOIR_EMIS (+ PJ PDF)          |            |      |                 |              |         |       |
| 7   | REMBOURSEMENT_CONFIRME         |            |      |                 |              |         |       |
| 8   | LITIGE_RAPPEL_J1               |            |      |                 |              |         |       |
| 9   | LITIGE_RAPPEL_J3               |            |      |                 |              |         |       |
| 10  | LITIGE_RAPPEL_J5               |            |      |                 |              |         |       |
| 11  | REGULARISATION_SOCIALE_REQUISE |            |      |                 |              |         |       |
| 12a | COMMISSION_AJUSTEE — AVOIR     |            |      |                 |              |         |       |
| 12b | COMMISSION_AJUSTEE — FC        |            |      |                 |              |         |       |

## Points de contrôle visuels

Pour chaque template :
- ✅ Subject non vide et informatif (pas "undefined" ou `${...}`)
- ✅ Pas de `{variable}` littéral dans le body (substitution OK)
- ✅ Pas de `null`, `undefined`, `[object Object]` dans le HTML
- ✅ Boutons CTA fonctionnels (lien vers le bon environnement APP_URL)
- ✅ Pour AVOIR_EMIS : pièce jointe PDF présente + téléchargeable
- ✅ Pour COMMISSION_AJUSTEE : montant affiché avec signe négatif sur avoir

## Tests automatisés

`tests/litiges/templates-structure.test.ts` vérifie :
- Chaque template litige a bien une `case 'TYPE':` dans send-email/index.ts
- Pas de placeholder `{variable}` non-interpolé dans le HTML (seuls `${...}` template literal sont autorisés)
- Chaque template utilise le wrapper `WRAPPER()` pour layout cohérent

## Historique

| Date       | Auteur     | Action                                     |
| ---------- | ---------- | ------------------------------------------ |
| 2026-04-17 | Claude (AI)| Création initiale — Bloc 4 FIX 13          |
