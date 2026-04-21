# Tests CP-C-5 — Chorus Pro activation (E15)

Scope : helper shared PISTE + submit-to-chorus + chorus-pro-deposit + subrogation + tests.

## Pré-requis

### Migrations / tables

- `chorus_submissions` (12+2 colonnes : type_document, avoir_reference_invoice)
- `chorus_pro_config` (par étab, actif=true requis)
- `factures_honoraires.chorus_submission_id`, `chorus_submission_status`, `pdf_s3_key`, `facturx_xml_url`
- `factures.chorus_pro_*` (table commission Jolene)

### Edge functions (vérifié en session)

| Fonction | Version | Commit source |
|---|---|---|
| `chorus-pro-deposit` | v191 | `6006bafa` (C5-B.1) |
| `submit-to-chorus` | v50+ | `d28b4c52` (C5-B.2) |
| `generate-invoice` | v52 | `5970b92a` (C5-B.3 subrogation) |
| `sync-chorus-status` | v50 (stub) | antérieur |
| `test-piste-credentials` | v16 | `f77d61c8` (Phase 1) |

### Secrets requis (Supabase Dashboard → Edge Functions → Secrets)

**Credentials PISTE (activation Chorus Pro)** :
- `PISTE_CLIENT_ID` (fallback `CHORUS_PRO_CLIENT_ID`)
- `PISTE_CLIENT_SECRET` (fallback `CHORUS_PRO_CLIENT_SECRET`)
- `PISTE_API_KEY` (optionnel)
- `PISTE_ENV` = `sandbox` (défaut) ou `prod`
- `CHORUS_TECH_USER_LOGIN` (header `cpro-account`)
- `CHORUS_TECH_USER_PASSWORD`

**Identité Jolene (émetteur factures commission + mention subrogation)** :
- `JOLENE_SIRET` (14 chiffres)
- `JOLENE_ADDRESS`
- `JOLENE_CITY`
- `JOLENE_POSTAL_CODE`
- `JOLENE_EMAIL` (défaut `facturation@jolene.app`)

## Tests SQL automatisables

```bash
psql "$DB_URL" -f tests/chorus/cp-c-5-b.test.sql
```

Couvre 7 scénarios :
- [1] Structure `chorus_submissions` : 14 colonnes attendues présentes
- [2] RLS `chorus_submissions` : 3 policies (INSERT service / SELECT own / UPDATE admin)
- [3] RLS `chorus_pro_config` : 4 policies (SELECT/INSERT/UPDATE/DELETE)
- [4] Idempotence : insertion fixture `status='submitted'` (terminal, skip par edge fn)
- [5] Mode AVOIR : `avoir_reference_invoice` propagé
- [6] Mode FACTURE standard : `status='pending'` accepté
- [7] Enum `type_document_facture` contient FACTURE + AVOIR

### Résultats exécution MCP (session)

- [1] 14 colonnes ✅
- [2] 3 policies ✅
- [3] 4 policies ✅
- [4] submitted accepted ✅
- [5] avoir_reference_invoice propagé ✅
- [6] pending accepted ✅
- [7] enum 2 valeurs ✅

**Bug découvert + corrigé** : submit-to-chorus v50 utilisait `'DEPOT_PDF_FACTURX'` et `'submitting'` non autorisés par `chorus_submissions_submission_type_check` (allowed: DEPOT_PDF_API/SAISIE_API) et `chorus_submissions_status_check` (allowed: pending_credentials/pending/submitted/accepted/rejected/error). Corrigé en C5-B.4 (même commit).

## Checklist E2E manuelle

### M1 — Mode simulation (sans credentials PISTE)

**Pré-requis** : supprimer temporairement `PISTE_CLIENT_ID` du Dashboard Secrets.

**Étapes** :
1. Créer facture honoraire test pour soignant LIBERAL sur etab secteur public
2. Invoquer submit-to-chorus :
   ```bash
   curl -X POST "https://flripxtsyegjshnhzjkz.supabase.co/functions/v1/submit-to-chorus" \
     -H "Authorization: Bearer $SRK" \
     -H "Content-Type: application/json" \
     -d '{"facture_honoraire_id":"<uuid>"}'
   ```

**Vérifications** :
- [ ] Retour 202 + `{ simulation: true, status: 'pending_credentials' }`
- [ ] INSERT `chorus_submissions` avec `status='pending_credentials'`
- [ ] UPDATE `factures_honoraires.chorus_submission_status='pending_credentials'`
- [ ] Message clair "PISTE credentials en attente"

### M2 — Génération XML avec mention subrogation

**Étapes** :
1. Créer facture honoraire via `generate-invoice` pour soignant LIBERAL (siret_liberal renseigné)
2. Télécharger XML depuis bucket `jolene-documents/invoices/<sg.id>/<numero>.xml`

**Vérifications** :
- [ ] XML contient `<ram:IncludedNote><ram:Content>Facture emise par JOLENE SAS (SIRET ...) en qualite de mandataire de facturation ...</ram:Content><ram:SubjectCode>AAB</ram:SubjectCode></ram:IncludedNote>`
- [ ] Texte inclut SIRET Jolene (`JOLENE_SIRET`) + prénom/nom soignant + siret_liberal
- [ ] Mentions légales : `article 289 I-2 du CGI` + `article 242 nonies A du CGI`
- [ ] PDF contient section "MENTION SUBROGATIVE" visible à l'œil

### M3 — Dépôt live Chorus Pro (après déblocage 403)

**Pré-requis** :
- Credentials PISTE configurés et validés via `test-piste-credentials`
- Etab test avec `est_secteur_public=true` + `chorus_pro_config` actif
- Facture honoraire générée avec `pdf_s3_key` + `facturx_xml_url`

**Étapes** :
```bash
curl -X POST "https://flripxtsyegjshnhzjkz.supabase.co/functions/v1/submit-to-chorus" \
  -H "Authorization: Bearer $SRK" \
  -d '{"facture_honoraire_id":"<uuid>"}'
```

**Vérifications** :
- [ ] Retour 200 `{ success: true, submission_id, piste_request_id, sandbox: true }`
- [ ] `chorus_submissions.status='submitted'`, `piste_request_id` renseigné, `response_raw` JSON PISTE
- [ ] `factures_honoraires.chorus_submission_status='submitted'`, `chorus_last_sync_at`

### M4 — Dépôt AVOIR

**Étapes** : idem M3 avec facture `type_document='AVOIR'` et `chorus_avoir_reference_invoice` rempli.

**Vérifications** :
- [ ] `chorus_submissions.type_document='AVOIR'`
- [ ] `chorus_submissions.avoir_reference_invoice` = numéro de la facture référencée
- [ ] XML Factur-X contient `TypeCode=381` et `<ram:InvoiceReferencedDocument>`

### M5 — Erreur API PISTE

**Simulation** : corrompre temporairement le PDF avant invocation (ex. truncate du fichier storage), puis invoquer submit-to-chorus.

**Vérifications** :
- [ ] Retour 502 `{ success: false, error: "Chorus Pro API erreur ..." }`
- [ ] `chorus_submissions.status='error'`, `error_code`, `error_message` remplis
- [ ] `factures_honoraires.chorus_submission_status='error'`

### M6 — Idempotence

**Étapes** : invoquer submit-to-chorus 2× sur la même facture déjà `status='submitted'`.

**Vérifications** :
- [ ] 2ème appel retour 200 `{ skipped: true, reason: "Facture déjà soumise (statut=submitted)" }`
- [ ] Pas de 2ème ligne dans `chorus_submissions`

### M7 — chorus-pro-deposit (factures commission)

**Étapes** :
1. UI étab : page facturation, cliquer "Déposer sur Chorus Pro" sur une facture commission
2. Invoke `chorus-pro-deposit` action='deposer'

**Vérifications** :
- [ ] Retour `{ success: true, numero_flux, identifiant_cpp }`
- [ ] `factures.chorus_pro_statut='DEPOSEE'`, `chorus_pro_date_depot`, `chorus_pro_numero_flux`
- [ ] XML généré à la volée **ne contient PAS** `IncludedNote AAB` (factures commission propres Jolene, pas de subrogation)

## Vérifications post-prod

```sql
-- Soumissions récentes
SELECT type_document, status, COUNT(*)
FROM public.chorus_submissions
WHERE created_at > NOW() - INTERVAL '7 days'
GROUP BY type_document, status;

-- Factures honoraires en statut chorus
SELECT chorus_submission_status, COUNT(*)
FROM public.factures_honoraires
WHERE chorus_submission_status IS NOT NULL
GROUP BY chorus_submission_status;

-- Factures commission Chorus Pro
SELECT chorus_pro_statut, COUNT(*)
FROM public.factures
WHERE chorus_pro_statut IS NOT NULL
GROUP BY chorus_pro_statut;
```

## Tickets clôturés (C5-B partiel)

- **E15 partie 1** (activation Chorus Pro) : déploiement mode simulation OK, déploiement mode réel **bloqué** par support PISTE (403).
- Helper shared `_shared/piste-client.ts` + `_shared/facturx-builder.ts` : livrés
- `chorus-pro-deposit` refactoré sur `deposer/flux` + Factur-X généré à la volée : livré
- `submit-to-chorus` finalisé (DEPOT_PDF_API + idempotence + AVOIR + mode simulation) : livré
- Mention subrogation Factur-X (art. 289 I-2 CGI + 242 nonies A) : livré
- Tests SQL 7 scénarios : validés via MCP

## Reste à faire (E15 partie 2)

1. **Déblocage PISTE** : attendre réponse support (ticket en cours Gabrielle)
2. **sync-chorus-status** : finaliser pour synchro périodique via `consulterFacture` (stub actuel v50)
3. **UI admin Chorus Pro** : tableau de bord monitoring soumissions + détails erreurs
4. **Tests live** M3/M4/M5 sandbox post-déblocage
5. **Cron schedule** : ajouter sync-chorus-status au `cron.job` (ex. `*/30 * * * *`)

## Décisions architecturales

1. **2 flux Chorus distincts** : chorus-pro-deposit (commission Jolene → étab) vs submit-to-chorus (factures_honoraires soignant → étab). Helpers shared pour OAuth + Factur-X.
2. **Mode dépôt unifié** : `deposer/flux` avec fichier Factur-X base64 (XML standalone pour commission, PDF/A-3 embarqué pour honoraires).
3. **Subrogation art. 289 I-2 CGI** : ajoutée sur factures honoraires uniquement (Jolene mandataire). Pas sur commission (Jolene facture pour son compte).
4. **Status + submission_type enum strict** : pending_credentials/pending/submitted/accepted/rejected/error + DEPOT_PDF_API/SAISIE_API.
5. **Mode simulation automatique** : si credentials PISTE absents, insert placeholder + retour 202 (compat avec environnements dev).
