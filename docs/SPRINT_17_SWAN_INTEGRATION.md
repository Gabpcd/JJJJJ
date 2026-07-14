# Sprint 17 — Intégration SWAN + Parrainage + ADELI

## Vue d'ensemble

Sprint 17 livre 3 chantiers majeurs :

1. **Parrainage soignant double moteur** (prime cash 50€+50€)
2. **Socle SWAN API** (lecture canonique et webhooks sécurisés ; émission automatique désactivée au lancement)
3. **Vérification ADELI + allègement documents**

## Architecture versement primes

```
Commission facture PAYEE (trigger DB)
  → parrainages.commission_cumulee_filleul += montant_ht
  → Seuil ≥ 100€ atteint ?
    → Anti-fraude check (même IP ?)
    → Action RECOMPENSE_PARRAINAGE_SOIGNANT créée
      → Worker process-externalisation-actions (cron 5min)
        → Stripe Connect uniquement si compte complet et identité exacte
        → sinon prime conservée comme due + traitement manuel explicite
      → PRIME_VERSEE seulement après deux transferts Stripe persistés et contrôlés
```

> **État pré-lancement :** les virements automatiques Swan sont volontairement
> désactivés. Une création de `Payment` peut rester `ConsentPending` et ne prouve
> jamais un virement. Le webhook authentifie et relit la transaction canonique,
> mais ne modifie aucun avoir ni parrainage sans liaison durable préalable.

## SWAN API — Configuration

### Secrets Supabase (Edge Functions)

| Secret | Description |
|---|---|
| `SWAN_OAUTH_URL` | `https://oauth.swan.io` |
| `SWAN_CLIENT_ID` | OAuth2 client credentials (Dashboard SWAN > Developers > API) |
| `SWAN_CLIENT_SECRET` | OAuth2 client secret |
| `SWAN_GRAPHQL_URL` | `https://api.swan.io/sandbox-partner/graphql` (sandbox) ou `https://api.swan.io/live-partner/graphql` (live) |
| `SWAN_ENVIRONMENT` | `sandbox` ou `live` |
| `SWAN_ACCOUNT_ID` | ID du compte Jolene SASU chez SWAN |
| `SWAN_S2S_PRIVATE_KEY_PEM` | Clé privée ECDSA P-256 PKCS#8 servant à signer le JWT `{challenge}` du consentement S2S |
| `SWAN_WEBHOOK_SECRET` | Secret partagé comparé au header officiel `x-swan-secret` (ce n'est pas une signature HMAC) |
| `SWAN_PROJECT_ID` | Optionnel : verrou supplémentaire sur le `projectId` de l'enveloppe webhook |

### Bascule sandbox → live

1. Créer un nouveau couple Client ID / Client Secret **live** dans SWAN Dashboard
2. Mettre à jour les 3 secrets : `SWAN_CLIENT_ID`, `SWAN_CLIENT_SECRET`, `SWAN_GRAPHQL_URL` (→ `live-partner`)
3. Mettre à jour `SWAN_ENVIRONMENT` → `live`
4. Mettre à jour `SWAN_ACCOUNT_ID` → ID du compte live
5. Installer la clé publique S2S dans SWAN Dashboard **live** (confirmation SMS représentant légal)
6. Créer le webhook **live** avec la bonne URL et un secret partagé dédié
7. Avant toute activation de l'émission automatique : configurer l'impersonation
   autorisée du représentant légal, implémenter le cycle
   `challenge → JWT ES256 → grantConsentWithServerSignature`, puis valider une
   recette sandbox et live. Tant que ce point n'est pas validé, conserver le
   traitement manuel.

### Rotation clés ECDSA (tous les 2 ans)

1. Générer une nouvelle paire ECDSA P-256
2. Coller la nouvelle clé publique (JWK) dans SWAN Dashboard > Server Consent
3. Mettre à jour `SWAN_S2S_PRIVATE_KEY_PEM` dans Supabase Secrets
4. Supprimer l'ancienne clé dans SWAN Dashboard
5. Tester un virement sandbox avant de passer en live

## Fichiers clés

| Fichier | Rôle |
|---|---|
| `supabase/functions/_shared/swan-client.ts` | OAuth2 token cache + GraphQL client |
| `supabase/functions/_shared/swan-sign-s2s.ts` | JWT ES256 du challenge de consentement S2S |
| `supabase/functions/_shared/swan-client.test.ts` | Tests unitaires Deno |
| `supabase/functions/swan-webhook/index.ts` | Réception webhooks SWAN |
| `supabase/functions/process-externalisation-actions/index.ts` | Worker Stripe Connect ou traitement manuel ; émission Swan neutralisée |
| `src/components/profil-soignant/SectionPaiements.tsx` | Coordonnées bancaires liées à un RIB vérifié |

## Vérification ADELI

`verify-rpps` étendu pour accepter ADELI (9 chiffres) via le même endpoint FHIR :
- RPPS : préfixe IDNPS `8` + 11 chiffres
- ADELI : préfixe IDNPS `0` + 9 chiffres
- Même cross-check nom/prénom, même robustesse

### Allègement documents

Si `rpps_verifie=true` ou `adeli_verifie=true` :
- DIPLOME et RPPS_ADELI (attestation) exclus des documents requis
- Le trigger `fn_recalculer_tous_documents_valides` les ignore

Professions sans RPPS/ADELI (AS, AES, préparateur pharma) : diplôme reste obligatoire.

## PRs livrées

| PR | Titre | CI |
|---|---|---|
| #362 | Sprint 17-A — prime cash 50€+50€ soignant | 4/4 ✅ |
| #363 | Phase A — foundation OAuth2 + S2S ECDSA | 4/4 ✅ |
| #364 | Phase B — saisie IBAN soignant sécurisée | 4/4 ✅ |
| #365 | Phase C — UI saisie IBAN | 4/4 ✅ |
| #366 | fix: "Zone dangereuse" → "Suppression de compte" | 4/4 ✅ |
| #367 | fix: IBAN form dans profil > Paiements | 4/4 ✅ |
| #368 | fix: cleanup dead code Phase C | 4/4 ✅ |
| #369 | fix: audit frontend Sprint 17 | 4/4 ✅ |
| #370 | fix: supprimer +50h illégal + sidebar Mon profil | 4/4 ✅ |
| #371 | fix: article aide parrainage — prime 50€ | 4/4 ✅ |
| #372 | Chantier 1 — vérification ADELI via FHIR | 4/4 ✅ |
| #373 | Chantier 2 — allègement documents | 4/4 ✅ |
| #374 | Chantier 3 — tests E2E ADELI + documents | 4/4 ✅ |
| #375 | Phase D — worker SWAN SCT | 4/4 ✅ |
| #376 | Phase E — webhook réception statut | 4/4 ✅ |
