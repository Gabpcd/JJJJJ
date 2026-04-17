# Génération des avoirs — Jolene

## Vue d'ensemble

Depuis CP-LITIGES-6, l'edge function `generate-invoice` supporte **deux modes** :

| Mode       | Paramètre d'entrée | Cas d'usage                                        |
| ---------- | ------------------ | -------------------------------------------------- |
| Création   | `mission_id`       | Émission d'une nouvelle facture depuis une mission TERMINEE. |
| Regen      | `facture_id`       | (Re)génération du PDF/XML d'une facture existante. Inclut les avoirs. |

Le mode regen est utilisé lorsque `fn_admin_resoudre_litige` (CP3) crée une facture avec `pdf_a_regenerer=TRUE` (cas `ANNULER_REEMETTRE` ou `AVOIR`).

## Flow d'un avoir

1. **Déclencheur** : `fn_admin_resoudre_litige` (CP3) détermine `action='AVOIR'` (facture d'origine PAYEE).
2. **INSERT ligne** : nouvelle ligne dans `factures_honoraires` avec :
   - `type_document = 'AVOIR'`
   - `numero_facture` généré par `next_avoir_number()` (format `AV-{SIRET}-{YYYY}-{NNNNN}`)
   - `facture_precedente_id` → UUID facture d'origine
   - `litige_id` → UUID litige ayant déclenché l'avoir
   - `statut = 'EMISE'`
   - `mode_remboursement` : `AUTO_STRIPE` si paiement Stripe <120j, sinon `VIREMENT_MANUEL`
   - `pdf_a_regenerer = TRUE`
3. **Regen async** : le cron quotidien `litige-escalation-cron` scanne `fn_lister_factures_a_regenerer()` et invoke `generate-invoice { facture_id }` pour chaque ligne.
4. **Génération** : PDF + XML Factur-X produits, uploadés sur S3 sous `avoirs/{soignant_id}/{numero}.pdf|xml`.
5. **Chorus** : si `is_public_sector=TRUE`, soumission à `submit-to-chorus` avec `type_document='AVOIR'` et `chorus_avoir_reference_invoice` renseigné.
6. **Email** : `AVOIR_EMIS` envoyé au soignant + étab via `fn_litige_push_notification` (CP5). Le PDF est accessible via lien S3 (attachment email à implémenter en Sub-PR 3).
7. **Remboursement** :
   - `AUTO_STRIPE` → ligne dans `stripe_refunds_queue` traitée par `process-stripe-refunds` (squelette CP4 — T13 pour activation).
   - `VIREMENT_MANUEL` → admin exécute virement bancaire + appelle `fn_confirmer_remboursement_avoir(avoir_id, ref)` → statut `REMBOURSE` + email `REMBOURSEMENT_CONFIRME`.

## Obligations légales

### PDF

- **Titre** : "AVOIR" en rouge (distinction visuelle de "FACTURE").
- **Mention obligatoire** (art. L441-10 C. com.) :
  `Avoir émis sur facture n° {numero_facture_precedente} du {date_emission_precedente}`
- **Motif** : extrait de `litiges.resolution` (90 car. max).
- **Montants** : préfixés par signe négatif (`-XXX.XX EUR`).
- **TVA** : régime identique à la facture d'origine (exonération art. 261 CGI conservée).
- **Mandat de facturation** : mention Jolene SASU mandataire (art. 289 I-2 CGI) conservée, version identique à l'origine.

### Factur-X XML (profil BASIC WL)

| Champ   | Valeur avoir                                        |
| ------- | --------------------------------------------------- |
| `BT-3`  | `381` (CreditNote) — au lieu de `380` (Invoice)     |
| `BT-25` | `PrecedingInvoiceReference` = numero_facture origine |
| `BT-26` | `FormattedIssueDateTime` = date_emission origine    |
| `BT-109` | `TaxBasisTotalAmount` négatif                      |
| `BT-112` | `InvoiceTotalAmount` négatif                       |
| `BT-115` | `AmountDuePayable` négatif                         |

Implémentation dans `supabase/functions/generate-invoice/index.ts` :
- Fonction `generateCiiXml()` prend les paramètres optionnels `isAvoir`, `precedingInvoiceNumber`, `precedingInvoiceIssueDate`.
- Bloc `<ram:InvoiceReferencedDocument>` ajouté au `ApplicableHeaderTradeAgreement` si `isAvoir=true`.
- Montants passés via helper `signed(amount)` = `amount * (-1 si avoir, sinon 1)`.

### Chorus Pro

- Métadonnée `chorus_avoir_reference_invoice` : numero_facture d'origine, requise.
- Invocation : `submit-to-chorus { facture_honoraire_id, type_document: 'AVOIR' }`.
- L'edge function `submit-to-chorus` accepte `type_document='AVOIR'` et stocke la référence dans `chorus_submissions.avoir_reference_invoice` (CP-LITIGES-7a FIX 15).
- Le payload Factur-X (BT-3=381) est transmis tel quel à l'API PISTE DeposerPDFacture (même endpoint que FACTURE, le BT-3 distingue le type).

## Trigger et cadence de regen

Le cron `litige-escalation-cron` (quotidien 08h UTC) scanne `fn_lister_factures_a_regenerer(50)` et invoke `generate-invoice` en mode regen.

**Avant FIX 18** : délai jusqu'à 24h entre résolution admin et disponibilité du PDF.
**Depuis FIX 18** : regen déclenchée immédiatement via `pg_net.http_post` depuis `fn_admin_resoudre_litige`. Le cron reste filet de sécurité (filtre `modifie_le < NOW() - INTERVAL '1 hour'`). Ticket **T14** fermé.

## Edge function — API mode regen

### Requête

```
POST /generate-invoice
Authorization: Bearer <service_role_key>
Content-Type: application/json

{
  "facture_id": "uuid-de-la-facture-ou-avoir",
  "service_role_reason": "cron_auto_generation"
}
```

### Réponse succès

```json
{
  "success": true,
  "mode": "regen",
  "facture_id": "...",
  "type_document": "AVOIR",
  "numero_facture": "AV-12345678-2026-00001",
  "pdf_path": "avoirs/soignant-uuid/AV-12345678-2026-00001.pdf",
  "xml_path": "avoirs/soignant-uuid/AV-12345678-2026-00001.xml"
}
```

### Comportement

- Mode regen **skippe** les vérifications mission (TERMINEE, mandat, idempotence) — la facture EXISTE déjà, ses montants sont figés par le trigger d'immutabilité.
- Met à jour `pdf_s3_key`, `facturx_xml_url`, `pdf_a_regenerer=FALSE`, `chorus_avoir_reference_invoice` (pour avoirs).
- Return early avant le flow `mission_id` classique.
- Rejette si AVOIR sans `facture_precedente_id` (incohérence critique).

## Stockage S3

| Type document | Path                                           |
| ------------- | ---------------------------------------------- |
| FACTURE       | `invoices/{soignant_id}/{numero_facture}.pdf`  |
| AVOIR         | `avoirs/{soignant_id}/{numero_avoir}.pdf`      |

Même bucket `jolene-documents`. Upload avec `upsert: true` pour autoriser regenerations répétées (retries).

## Tests

- **SQL metadata** : `tests/litiges/cp6-avoir-support.test.sql` (3 blocs).
- **Rendu PDF + parsing XML Factur-X** : prévu en CP-LITIGES-8 (vitest avec appel réel à l'edge function + validation schéma EN16931 + assert sur contenu PDF).
- **End-to-end** : scénario admin résout → avoir généré → email envoyé → remboursement confirmé → statut REMBOURSE. En CP-LITIGES-8.
