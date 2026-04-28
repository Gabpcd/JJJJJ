# Module facturation Jolene — mandataire art. 289 I-2 CGI

Date : 2026-04-28

## Cadre légal

Jolene SAS est **mandataire de facturation** pour les soignants
LIBERAL/MIXTE au sens de l'article 289 I-2 du Code Général des Impôts.
Concrètement :

- Le **soignant reste le vendeur légal** de la prestation.
- **Jolene émet techniquement** les factures au nom du soignant
  (identité, RPPS/ADELI, SIRET, RIB du soignant en émetteur).
- Mention obligatoire sur chaque facture émise :
  `"Facture émise par JOLENE SAS en qualité de mandataire de facturation
  au sens de l'article 289 I-2 du CGI"`
- Mention TVA pour les soins exonérés :
  `"TVA non applicable - art. 261-4 CGI"`
- Numérotation **séquentielle et immutable** par soignant.

Le mandat est **résiliable à tout moment** par chacune des parties (la
révocation est immédiate techniquement ; le préavis de 30 jours
mentionné dans le mandat lie les parties contractuellement mais n'est
pas opposable techniquement, conformément au principe de libre
résiliation des mandats).

## Architecture

### Tables clés

| Table | Rôle |
|---|---|
| `mandats_facturation_signatures` | Historique horodaté des signatures (version, IP, user_agent, hash SHA-256, revoked_at). |
| `soignants.mandat_facturation_signe` | Flag de présence d'un mandat actif (lu par `generate-invoice`). |
| `factures_honoraires` | Factures émises par Jolene au nom du soignant. Numérotation séquentielle, immutable post-EMISE. |
| `cessions_creance` | Signatures de cession d'une créance vers le factor (Defacto). |
| `factor_advances` | Demandes d'avance affacturage par facture. |
| `chorus_submissions` | Soumissions Chorus Pro pour le secteur public. |
| `invoice_audit_log` | Trace fiscale append-only de tous les changements sur factures. |
| `journaux_audit` | Audit applicatif global (signature/révocation mandat, etc.). |

### RPC SQL

| Fonction | Rôle |
|---|---|
| `fn_signer_mandat_facturation(p_version, p_ip, p_user_agent, p_contenu_hash)` | Signature soignant. INSERT row + flag soignant. |
| `fn_revoquer_mandat_facturation(p_motif)` | Révocation soignant (UPDATE revoked_at + reset flag + audit). |
| `fn_signer_cession_creance(p_facture_honoraire_id, p_version, p_ip, p_user_agent, p_contenu_hash)` | Signature cession à Defacto. |
| `fn_mes_factures_honoraires()` | Liste factures du soignant connecté (avec établissement + mission). |
| `fn_mes_avances_factor()` | Liste demandes d'avance Defacto. |

### Edge functions

| Fonction | Trigger | Rôle |
|---|---|---|
| `generate-invoice` | Manuel (soignant) ou cron service_role (`cron_auto_generation`) | Génère PDF + XML Factur-X (EN16931 BASIC WL), upload Storage `jolene-documents`, INSERT `factures_honoraires`, déclenche Chorus si secteur public. Vérifie `mandat_facturation_signe` avant. Numéro `JOL-{SIRET8}-{ANNEE}-{SEQ5}`. |
| `factor-request-advance` | Manuel (soignant) | POST Defacto `/v1/invoices`, INSERT `factor_advances`. |
| `factor-webhook` | Webhook Defacto | Maj statut avance + notif soignant. HMAC vérifié (`DEFACTO_WEBHOOK_SECRET`). |
| `submit-to-chorus` | Async depuis `generate-invoice` si `is_public_sector=true` | POST PISTE Chorus Pro. |
| `sync-chorus-status` | Cron 2h | Polling statuts soumissions Chorus. |

## Workflow soignant

### 1. Passage en libéral
Le soignant active son statut LIBERAL/MIXTE via `/soignant/passer-en-liberal`.

### 2. Signature du mandat
`/soignant/mandat-facturation` :
1. Lecture intégrale (scroll forcé jusqu'en bas).
2. Acceptation explicite (checkbox).
3. RPC `fn_signer_mandat_facturation` avec hash SHA-256 du texte +
   user-agent + IP capturée serveur.
4. UI affiche bandeau « Mandat signé et actif » + boutons :
   - **Télécharger mon mandat (PDF)** (jspdf, généré client-side)
   - **Révoquer mon mandat** (modal de confirmation)

### 3. Mission terminée → facture
Quand une mission `TERMINEE` arrive pour un soignant LIBERAL/MIXTE
ayant un mandat signé : `generate-invoice(mission_id)` est appelée
(manuellement ou par cron).

- Numéro séquentiel via advisory lock (concurrence safe).
- PDF Factur-X avec mention art. 289 I-2 + art. 261-4 CGI si
  exoneration_tva.
- Storage `jolene-documents/invoices/{soignant_id}/{numero}.pdf`.

### 4. Cession Defacto (paiement rapide)
Sur facture EMISE/EN_RETARD : `/soignant/mes-factures-honoraires` →
bouton « Recevoir maintenant » → `ModalCessionCreance` →
`fn_signer_cession_creance` → `factor-request-advance` (Defacto).

Webhook Defacto met à jour le statut quand l'argent arrive
(FINANCEE → RECOUVREE).

### 5. Révocation du mandat
Bouton sur `/soignant/mandat-facturation` → modal de confirmation →
RPC `fn_revoquer_mandat_facturation`.

Effets :
- `revoked_at = now()` sur la signature active.
- `soignants.mandat_facturation_signe = false`.
- Audit `MANDAT_FACTURATION_REVOQUE` dans `journaux_audit`.
- `generate-invoice` refusera désormais (flag = false).
- Les factures **déjà émises** restent immutables et exigibles
  (cohérent avec art. 289 I-2 : pas d'effet rétroactif).

Le soignant peut signer un nouveau mandat à tout moment ; cela crée
une nouvelle row dans `mandats_facturation_signatures` (l'historique
révoqué est conservé pour audit).

## Sécurité & immutabilité

### Triggers DB
- `trg_fh_immutability` : factures EMISE → montants, numéro, identités,
  date_emission **non-modifiables** (sauf admin/service_role).
- `trg_fh_auto_audit_*` : INSERT/UPDATE → row dans `invoice_audit_log`.
- `trg_ial_no_delete` / `trg_ial_no_update` : `invoice_audit_log` est
  append-only (RAISE EXCEPTION sur DELETE/UPDATE).

### RLS
- `factures_honoraires` : soignant = ses factures, étab = factures de
  ses missions, admin = tout.
- `mandats_facturation_signatures` : soignant = ses signatures, admin =
  tout. **GRANT SELECT TO authenticated** ajouté le 2026-04-28
  (manquait, bloquait la lecture par le soignant lui-même → impossible
  de générer le PDF).
- `cessions_creance`, `factor_advances` : RLS strictes par soignant.

### Audit applicatif
`fn_ecrire_audit_safe` (wrapper avec `EXCEPTION WHEN OTHERS THEN NULL`)
est utilisé pour ne jamais bloquer une opération métier. Actions
émises pour la facturation :
- `MANDAT_FACTURATION_SIGNE` (via trigger ou explicite)
- `MANDAT_FACTURATION_REVOQUE` (via `fn_revoquer_mandat_facturation`)
- `FACTURE_GENEREE`, `FACTURE_REGENEREE` (via generate-invoice)

## Tests SQL bout-en-bout (28/04/2026)

Tests exécutés via MCP avec compte `audit-medecin@jolene-test.dev`.

| # | Cas | Résultat |
|---|---|---|
| 1 | Signature mandat (`fn_signer_mandat_facturation`) | PASS — row créée avec version/ip/ua/hash, flag soignant=true |
| 2 | Révocation (`fn_revoquer_mandat_facturation`) | PASS — revoked_at set, flag soignant=false, audit row |
| 3 | Révocation sans mandat actif | PASS — `{success:false, error:"Aucun mandat actif à révoquer"}` |
| 4 | Re-signature après révocation | PASS — ancienne signature reste révoquée, nouvelle active |

Tests trigger immutabilité : couverts par les tests existants des
migrations `20260413140000_invoicing_module_schema.sql`.

## Fichiers source

### Frontend
- `src/pages/MandatFacturation.tsx` — UI signature + révocation + download PDF.
- `src/pages/MesFacturesHonoraires.tsx` — Liste factures avec filtres
  période/statut.
- `src/pages/MesAvances.tsx` — Affacturage Defacto.
- `src/components/ModalCessionCreance.tsx` — Modal cession.
- `src/components/FactureHonorairesCard.tsx` — Carte facture (mission).
- `src/lib/mandat-facturation-pdf.ts` — Génération PDF mandat (jsPDF).
- `src/lib/facture-honoraires-pdf.ts` — Génération PDF facture (jsPDF).
- `src/lib/pdf-design-system.ts` — Helpers communs PDF.
- `src/constantes/mandatFacturation.ts` — Texte du mandat (v1.1).

### Backend
- `supabase/functions/generate-invoice/` — Edge function principale.
- `supabase/functions/factor-request-advance/`, `factor-webhook/` — Defacto.
- `supabase/functions/submit-to-chorus/`, `sync-chorus-status/` — Chorus.
- `supabase/migrations/20260413140000_invoicing_module_schema.sql` — Schéma.
- `supabase/migrations/20260417100000_export_mandat_facturation_schema.sql` — Mandat.
- `supabase/migrations/20260417110000_export_affactureur_schema.sql` — Defacto.
- `supabase/migrations/20260428200000_fn_revoquer_mandat_facturation.sql` — **Cette session**.
- `supabase/migrations/20260428200500_grant_select_mandats_facturation_signatures.sql` — **Cette session** (fix bug pré-existant GRANT manquant).

## Déploiement

- **DB** : migrations appliquées via MCP `apply_migration`.
- **Frontend** : push main → auto-deploy Vercel.
- **Edge functions** : redéploiement manuel non requis pour cette session
  (aucune edge function modifiée). Pour les sessions futures qui
  toucheraient à `generate-invoice` ou consorts, utiliser MCP
  `deploy_edge_function` ou supabase CLI `supabase functions deploy`.

## Limitations connues / à approfondir

- Le bouton « Révocation » est **immédiat techniquement**. Le mandat
  v1.1 mentionne 30 jours de préavis : c'est un engagement
  contractuel, pas une contrainte technique. Si l'on souhaite imposer
  un préavis, ajouter une colonne `revocation_planifiee_le` et un
  cron qui matérialise la révocation après échéance.
- Le PDF du mandat est généré **côté client** (jsPDF). Pour archivage
  cryptographiquement signé, prévoir une edge function future qui
  génère le PDF côté serveur et upload sur `mandats_facturation_signatures.pdf_url`.
- La page `/soignant/parametres` ne contient pas encore de raccourci
  vers `/soignant/mandat-facturation` (accès via dashboard ou URL
  directe).
