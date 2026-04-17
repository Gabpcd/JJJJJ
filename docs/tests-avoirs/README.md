# Smoke-test visuel — PDF AVOIR (CP-LITIGES-7a FIX 17)

Ce dossier centralise les captures d'écran du rendu PDF des **avoirs** émis
suite à la résolution d'un litige en cas `AVOIR` (action_financiere = AVOIR
dans `fn_admin_resoudre_litige`). Le but : détecter visuellement toute
régression sur les éléments obligatoires et les tampons FIX 7.

## Points de contrôle visuels (checklist)

Pour **chaque PDF avoir** généré, vérifier :

- [ ] **Titre "AVOIR"** affiché en rouge en en-tête (pas "FACTURE").
- [ ] **Mention légale L441-10 C.com.** : texte rappelant la facture
      d'origine sous la forme *"Avoir sur facture FH-YYYY-MM-NNNN du
      DD/MM/YYYY"* (depuis `precedingInvoiceNumber` + `precedingInvoiceIssueDate`).
- [ ] **Montants en négatif** préfixés `-` :
  - Montant HT : `-XXX,XX €`
  - Montant TVA : `-XX,XX €` (ou 0,00 si exonéré)
  - Montant TTC : `-XXX,XX €`
- [ ] **Motif de l'avoir** (depuis `litiges.resolution`, tronqué à 100 chars)
      visible sous la description.
- [ ] **Tampon FIX 7** si applicable :
  - `ANNULÉE` rouge transparent, rotation -30° (statut = `ANNULEE`).
  - `REMPLACÉE par FH-YYYY-MM-NNNN` orange (statut = `REMPLACEE`, lookup
    via `facture_precedente_id`).
- [ ] **XML Factur-X** embarqué (BT-3 = `381` pour avoir, BT-25/BT-26 avec
      `precedingInvoiceNumber`, `precedingInvoiceIssueDate`).
- [ ] **Identité soignant** (SIRET, RPPS/ADELI) + **identité étab**
      (SIRET) correctement remplies.
- [ ] **Mention TVA** cohérente (exoneration → "TVA non applicable — art.
      261, 4-1° du CGI", sinon taux affiché).

## Prérequis

- Accès à un environnement Supabase (dev ou staging) avec :
  - Un **litige résolu en cas AVOIR** (`litiges.resolution_action =
    'AVOIR'`) et une facture `AVOIR` liée (`factures_honoraires.litige_id`
    rempli + `type_document = 'AVOIR'`).
  - La facture d'origine toujours présente en S3 (bucket `jolene-documents`
    sous `invoices/<soignant_id>/FH-...pdf`).
- `SUPABASE_URL` + `SUPABASE_SERVICE_ROLE_KEY` exportés.

## Procédure de génération (mode regen)

### Étape 1 — Identifier l'avoir à tester

```sql
-- Avoir récent lié à un litige résolu
SELECT f.id, f.numero_facture, f.litige_id, f.facture_precedente_id,
       f.montant_ttc, f.statut, l.resolution
  FROM public.factures_honoraires f
  JOIN public.litiges l ON l.id = f.litige_id
 WHERE f.type_document = 'AVOIR'
   AND l.resolution_action = 'AVOIR'
 ORDER BY f.cree_le DESC
 LIMIT 5;
```

### Étape 2 — Forcer la regen du PDF

```sql
-- Flag pdf_a_regenerer pour forcer une nouvelle génération
UPDATE public.factures_honoraires
   SET pdf_a_regenerer = TRUE
 WHERE id = '<avoir_id>';
```

```bash
# Appeler generate-invoice en mode regen (facture_id sans mission_id)
curl -X POST "$SUPABASE_URL/functions/v1/generate-invoice" \
  -H "Authorization: Bearer $SUPABASE_SERVICE_ROLE_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "facture_id": "<avoir_id>",
    "service_role_reason": "ops_test_fix17_avoir_visuel"
  }'
```

Réponse attendue (HTTP 200) :

```json
{
  "success": true,
  "mode": "regen",
  "facture_id": "<avoir_id>",
  "type_document": "AVOIR",
  "numero_facture": "AV-YYYY-MM-NNNN",
  "pdf_path": "avoirs/<soignant_id>/AV-YYYY-MM-NNNN.pdf",
  "xml_path": "avoirs/<soignant_id>/AV-YYYY-MM-NNNN.xml"
}
```

### Étape 3 — Télécharger PDF + XML

```sql
SELECT pdf_s3_key, facturx_xml_url
  FROM public.factures_honoraires
 WHERE id = '<avoir_id>';
```

Depuis Supabase Dashboard (Storage > `jolene-documents` bucket) ou via
l'API :

```bash
# PDF
curl -o avoir-<numero>.pdf \
  "$SUPABASE_URL/storage/v1/object/jolene-documents/avoirs/<soignant_id>/<numero>.pdf" \
  -H "Authorization: Bearer $SUPABASE_SERVICE_ROLE_KEY"

# XML Factur-X (optionnel, pour validation BT-3 / BT-25)
curl -o avoir-<numero>.xml \
  "$SUPABASE_URL/storage/v1/object/jolene-documents/avoirs/<soignant_id>/<numero>.xml" \
  -H "Authorization: Bearer $SUPABASE_SERVICE_ROLE_KEY"
```

### Étape 4 — Capture visuelle

Convertir la première page en PNG et déposer ici :

```bash
# macOS/Linux avec pdftoppm (poppler-utils)
pdftoppm -r 120 -png -f 1 -l 1 avoir-<numero>.pdf avoir-<numero>
# → avoir-<numero>-1.png

# Renommer selon le scénario
mv avoir-<numero>-1.png docs/tests-avoirs/avoir-<scenario>-<numero>.png
```

**Scénarios à capturer** (minimum 3 cas) :

| Scénario               | Fichier attendu                              |
| ---------------------- | -------------------------------------------- |
| AVOIR standard         | `docs/tests-avoirs/avoir-standard-<num>.png` |
| AVOIR + statut ANNULEE | `docs/tests-avoirs/avoir-annulee-<num>.png`  |
| AVOIR + statut REMPLACEE | `docs/tests-avoirs/avoir-remplacee-<num>.png` |

### Étape 5 — Valider le XML Factur-X

```bash
# Extraire et vérifier les balises clés
grep -E "TypeCode|IssuerAssignedID|FormattedIssueDateTime" avoir-<numero>.xml
```

Assertions attendues :

```xml
<ram:TypeCode>381</ram:TypeCode>
<ram:IssuerAssignedID>FH-YYYY-MM-NNNN</ram:IssuerAssignedID>  <!-- facture origine -->
<udt:DateTimeString format="102">YYYYMMDD</udt:DateTimeString>  <!-- date origine -->
```

(`381` = code avoir commercial EN16931 ; `IssuerAssignedID` doit référencer
la facture d'origine, pas l'avoir lui-même.)

## Grille de validation

| Avoir testé       | Date  | Titre rouge | L441-10 | Montants `-` | Motif | Tampon FIX 7 | BT-3=381 | BT-25 OK | Notes |
| ----------------- | ----- | ----------- | ------- | ------------ | ----- | ------------ | -------- | -------- | ----- |
| AV-...            |       |             |         |              |       |              |          |          |       |

## Plan de test prod-like (si indisponible en staging)

Si aucun litige résolu en AVOIR n'existe sur l'environnement courant, la
procédure reproductible en prod-like est :

1. **Créer un litige** via `fn_ouvrir_litige` (ou directement INSERT
   `litiges` + `UPDATE factures_honoraires.statut_litige = 'EN_ATTENTE_LITIGE'`).
2. **Résoudre en cas AVOIR** via `fn_admin_resoudre_litige` avec :
   ```sql
   SELECT public.fn_admin_resoudre_litige(
     p_litige_id        := '<litige_id>',
     p_resolution       := 'Heures incomplètes constatées — avoir de régularisation',
     p_action_financiere:= 'AVOIR',
     p_en_faveur_de     := 'ETABLISSEMENT',
     p_nouveaux_montants:= jsonb_build_object('montant_avoir', 150.00)
   );
   ```
3. Le helper `fn_admin_resoudre_litige` pose automatiquement
   `pdf_a_regenerer = TRUE` sur l'avoir inséré (CP-LITIGES-7a FIX 7/19).
4. Invoker `generate-invoice` en mode regen (étape 2 ci-dessus).
5. Télécharger le PDF et capturer (étapes 3-4).

## Regression tests associés

- `tests/litiges/cp7a-fix7.test.sql` : tampons statut
- `tests/litiges/cp7a-fix19.test.sql` : push LITIGE_RESOLU_AJUSTE + AVOIR_EMIS
- Ce README : validation **visuelle** uniquement (le rendu PDF ne se
  teste pas en SQL ; seules les captures détectent régressions graphiques).

## Owners

- Exécution initiale : Gabrielle (prod-like staging).
- Re-run : à chaque modification de `generate-invoice/index.ts` touchant
  au rendu avoir ou au XML CII.
- Captures stockées en git pour diff visuel (ou S3 si > 1 MB).
