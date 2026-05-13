# Reversement soignant — état actuel et roadmap

> Sprint 3 PR 6 — clarification du flow de reversement libéral en attendant
> la signature du contrat d'affacturage.

## Contexte

Pour les missions **libérales** (REMPLACEMENT_LIBERAL), Jolene agit comme
**mandataire de facturation** (art. 289 I-2 CGI). Le flow attendu :

1. Soignant libéral réalise la mission, pointe via GPS
2. Étab valide les heures (manuel ou auto J+72h)
3. Jolene génère la facture d'honoraires (`generate-invoice`) au nom du
   soignant via son SIRET
4. Étab paie la facture (Stripe Connect pour étab privé, Chorus Pro pour
   étab public)
5. **Reversement au soignant**

Pour les missions **CDD/SALARIE**, Jolene n'intervient pas — l'étab paie le
soignant via sa paie habituelle (Cegid / Silae / etc.) avec bulletin généré
par `bulletin-paie-pdf.ts`.

## Reversement soignant libéral : 2 voies

### Voie A — Affacturage (cible)
Le soignant reçoit son paiement **dès la validation des heures à J+72h**,
sans attendre l'encaissement étab (qui peut prendre 30-60 jours en public).

Code prêt :
- `factor-request-advance` (edge function) : demande d'avance au factor
- `factor-webhook` (edge function) : réception statut factor (paid, rejected)
- Table `obligations_financieres_chorus` + colonne `factor_status`

État : **En attente signature contrat factor** (commercial Gabrielle 2026-Q2).

### Voie B — Virement direct via Stripe Connect (intérimaire MVP)
En attendant le factor, le reversement passe par :
- Étab privé : `stripe-connect-pay-mission` (1 paiement étab → split
  commission Jolene + reversement soignant en simultané)
- Étab public Chorus : le paiement arrive sur le compte Jolene, l'admin
  reverse manuellement au soignant via Stripe Connect transfer
  (`process-stripe-refunds` pattern adapté)

### Voie C — Virement manuel SEPA (cas dégradé)
Si Stripe Connect KO pour le soignant (ex: pas encore validé KYC) :
- Admin déclenche un virement manuel SEPA depuis le compte bancaire Jolene
- Tracker dans `paiements_soignants` avec mode='VIREMENT_MANUEL_SEPA'

## Workflow décisionnel (où on en est)

```
Validation heures J+72h
        │
        ▼
   facture émise ?
   │           │
   non         oui
   │           │
   wait        Étab payeur ?
              │       │
            privé   public
              │       │
         Stripe   Chorus Pro
        Connect    │
          │        │
       Voie B   Encaissement
                Jolene
                   │
                Voie B (manuel admin)
                ou Voie A si factor OK
```

## Triggers + crons impliqués

| Trigger / cron | Source | Action |
|---|---|---|
| `dec_facture_payee_stripe` | webhook Stripe | INSERT paiement_soignant + transfer Connect |
| `dec_chorus_facture_payee` | sync-chorus-status | Idem |
| `fn_valider_presences_72h_auto` | cron 6h (PR 3 S3) | Validation auto présence → débloque facturation |
| `weekly-invoicing-cron` | cron lundi 04:00 | Génère factures hebdo libéraux |

## Roadmap

### Sprint 4 (court terme)
- [ ] Signature contrat factor
- [ ] Switch flag `FEATURE_FACTOR_ENABLED` côté config → bascule Voie A
- [ ] Test bout-en-bout : mission → validation → facture → factor → reversement

### Sprint 5+ (moyen terme)
- [ ] Reversement automatique Chorus Pro après encaissement (sans intervention admin)
- [ ] Dashboard admin "Reversements en attente" avec actions bulk
- [ ] Audit trail complet `reversements_soignants` (statut, montant, mode, date)

## Notes opérationnelles

- **Délai SLA reversement** : J+3 ouvrés après encaissement (engagement contractuel)
- **Frais commission** : 10% sur le brut hors taxes (cf. `EncartCommissionDegressif`)
- **Compte Jolene** : un compte BNP Paribas Pro, IBAN dans `vault.decrypted_secrets`
- **Stripe Connect** : compte custom par soignant, KYC réalisé via Stripe Express
- **Chorus Pro** : un compte structure Jolene SASU, scopes en attente AIFE (cf. `CHORUS-PRO-BASCULE-PROD.md`)

## Sécurité

- RLS strict sur `factures_honoraires` : SELECT owner + admin uniquement
- Audit `journaux_audit` action='FACTURE_HONORAIRES_PAYEE' à chaque encaissement
- Détection anomalie écart montant : `PAIEMENT_MONTANT_ECART` si reversé ≠ facture émise
