# Flux de vérification automatique des documents

## Pipeline bout-en-bout

```
Soignant upload document (PDF/JPEG/PNG/WebP/GIF)
  │
  ├─ [HEIC] → conversion JPEG côté browser (createImageBitmap + OffscreenCanvas)
  │
  ├─ Supabase Storage → bucket jolene-documents → {user_id}/documents/{type}/{ts}-{nom}
  │
  ├─ INSERT documents_soignants (statut_verification='EN_ATTENTE')
  │
  ├─ supabase.functions.invoke('verify-document', { document_id })
  │     │
  │     ├─ Auth : JWT utilisateur ou vault sb_secret_* (cron re-trigger)
  │     ├─ Télécharge fichier depuis Storage via service_role
  │     ├─ Base64 encode
  │     │
  │     ├─ Allowlist MIME → REJETE immédiat si non supporté
  │     │
  │     ├─ PDF → type:"document" (Anthropic API document block)
  │     ├─ Image → type:"image" (Anthropic Vision)
  │     │
  │     ├─ Appel POST https://api.anthropic.com/v1/messages
  │     │   model: claude-sonnet-4-20250514
  │     │   anthropic-version: 2023-06-01
  │     │   max_tokens: 1000
  │     │   system: prompt vérificateur (structure JSON stricte)
  │     │
  │     ├─ Parse JSON réponse → analysis { verdict, confiance, motif_rejet, ... }
  │     │
  │     ├─ fn_update_document_verification(statut, motif, dates)
  │     ├─ UPDATE documents_soignants (resultat_ia, nom_extrait_ia, coherence_nom, ...)
  │     └─ fn_ecrire_audit_safe (traçabilité)
  │
  └─ UI toast : ✅ Vérifié / 🔄 En cours / ❌ Rejeté
```

## Fichiers clés

| Fichier | Rôle |
|---|---|
| `src/pages/DocumentsSoignant.tsx` | UI upload + déclenchement verify-document |
| `supabase/functions/verify-document/index.ts` | Edge function : download + Anthropic API + écriture DB |
| `supabase/functions/_shared/rate-limit.ts` | Rate limiting mémoire 10/min par IP |
| `e2e/flows/verify-document.spec.ts` | Tests E2E pipeline bout-en-bout |

## Types MIME supportés

```
image/jpeg, image/png, image/webp, image/gif → type:"image"
application/pdf → type:"document"
image/heic, image/heif → convertis en JPEG côté browser avant upload
Tout autre → REJETE immédiat (allowlist L125)
```

## Types de documents vérifiables

| Type DB | Label IA | Vérification |
|---|---|---|
| CARTE_IDENTITE | Carte d'identité ou Passeport | Type + date expiration + nom/prénom |
| PASSEPORT | Passeport | Type + date expiration + nom/prénom |
| DIPLOME | Diplôme d'État | Type + détection cross-type (passeport ≠ diplôme) |
| RCP_ASSURANCE | Assurance RCP | Type + date fin validité |
| RIB | Relevé d'Identité Bancaire | Type seulement (pas de date) |
| KBIS | Extrait KBIS | Type |
| ATTESTATION_URSSAF | Attestation URSSAF | Type |
| RPPS_ADELI | Attestation RPPS/ADELI | Type |
| AUTORISATION_EXERCICE | Autorisation d'exercice | Type |
| FORMATION_OBLIGATOIRE | Certificat formation | Type |

## Cohérence nom (anti-fraude)

La fonction compare automatiquement :
- `nom_extrait_ia` (lu sur le document) vs `soignant.nom` (profil)
- `prenom_extrait_ia` vs `soignant.prenom` (3 premiers caractères)
- Résultat : `coherence_nom: true/false/null`
- Normalisation NFD + lowercase + trim avant comparaison

## Pièges déjà rencontrés

### 1. Photos HEIC iPhone (Sprint 10 PR #271)

**Problème** : iPhone produit des photos en HEIC/HEIF. L'API Anthropic Vision n'accepte pas ce format.

**Fix** : conversion browser-side via `createImageBitmap` + `OffscreenCanvas.convertToBlob('image/jpeg', 0.92)` dans `DocumentsSoignant.tsx:249-261`. Le fichier est converti en JPEG avant upload Storage.

**Non-testable en CI** : `OffscreenCanvas` n'existe pas dans Playwright Node.js. Test manuel uniquement.

### 2. PDF envoyé comme type:"image" (PR #350)

**Problème** : le code envoyait tous les fichiers (images ET PDF) avec `type: "image"` à l'API Anthropic. L'API Vision rejette `application/pdf` en image block → le document reste `EN_ATTENTE` éternellement.

**Fix** : distinction `isPdf` → `type: "document"` vs `isImage` → `type: "image"` (L191-201).

**Piège supplémentaire** : `anthropic-version: "2023-06-01"` est l'ancienne version. Le support `type: "document"` PDF nécessitait la version `"2025-01-01"` (GA) ou le header beta `"anthropic-beta": "pdfs-2024-09-25"`. Mis à jour dans le même fix.

### 3. Clé API Anthropic org sans crédits (PR #351)

**Problème** : `ANTHROPIC_API_KEY` dans les secrets Supabase pointait vers une organization Anthropic **sans crédits** → `400 "Your credit balance is too low"`. L'erreur était silencieuse (`console.error` seulement, pas persistée en DB).

**Fix** :
- Persistance des erreurs Anthropic dans `documents_soignants.resultat_ia.erreur_anthropic` (status + body_excerpt + timestamp) → visible sans deploy debug
- Auth vault `sb_secret_*` fallback (pattern Sprint 12-A) pour re-trigger via pg_net

**Diagnostic** : si `resultat_ia.erreur_anthropic` apparaît → vérifier crédits Anthropic sur https://console.anthropic.com/settings/billing. Le préfixe de la clé (`sk-ant-api03-XXXXX`) et l'org ID (header `anthropic-organization-id`) sont loggés pour identifier le workspace.

### 4. Test cross-type anti-fraude (validation manuelle)

Un passeport uploadé comme "Diplôme d'État" est correctement rejeté avec motif spécifique au type attendu. Testé manuellement + E2E test #2 (`verify-document.spec.ts`).

## Tests à exécuter avant chaque modification du flux

```bash
# 1. TypeScript compile
npx tsc -b

# 2. Tests E2E pipeline complet (nécessite ANTHROPIC_API_KEY avec crédits)
npx playwright test e2e/flows/verify-document.spec.ts

# 3. Vérification manuelle : upload PDF passeport depuis l'UI
#    → statut passe de EN_ATTENTE à VERIFIE/REJETE en < 30s
#    → resultat_ia non-null, score_confiance_ia > 0

# 4. Vérification anti-fraude : upload passeport déclaré comme DIPLOME
#    → verdict REJETE, motif contient "pas un diplôme"

# 5. Upload JPEG → toujours OK (non-régression images)
```

## Monitoring

Si des documents restent `EN_ATTENTE` > 1h :

```sql
SELECT id, type_document, type_mime, nom_fichier,
  resultat_ia->'erreur_anthropic' AS erreur,
  televerse_le
FROM documents_soignants
WHERE statut_verification = 'EN_ATTENTE'
  AND televerse_le < NOW() - INTERVAL '1 hour'
ORDER BY televerse_le;
```

- Si `erreur_anthropic.status = 400` + "credit balance" → recharger crédits Anthropic
- Si `erreur_anthropic.status = 404` + "model" → modèle `claude-sonnet-4-20250514` indisponible, changer de modèle
- Si `erreur_anthropic IS NULL` + `resultat_ia IS NULL` → verify-document n'a jamais été appelée (problème frontend ou auth)
