# Module Facturation & Affacturage — Architecture

## Vue d'ensemble

Jolene agit comme **mandataire de facturation** (art. 289 I-2 CGI) : elle émet les factures d'honoraires au nom et pour le compte du professionnel de santé libéral. Le soignant reste le vendeur légal de la prestation.

## Schéma de flux

```
Période facturable LIBÉRAL
      │
      ▼
┌─────────────────┐
│ generate-invoice │  ← Vérifie mandat + mission + pas de doublon
│                  │  ← Réserve numéro + pièce + bail dans une transaction
│                  │  ← Génère PDF + XML CII (EN16931)
│                  │  ← Upload Supabase Storage
│                  │  ← Finalise registre + émission dans une transaction
└─────────────────┘
      │
      ├── Secteur PUBLIC ──▶ submit-to-chorus ──▶ Chorus Pro (PISTE API)
      │                           │
      │                     sync-chorus-status (cron horaire)
      │
      └── Secteur PRIVÉ ──▶ send-email (template FACTURE_EMISE)
                                 │
                           Relances J+15, J+30, J+45
```

## Tables

| Table | Rôle |
|---|---|
| `factures_honoraires` | Factures d'honoraires du soignant (30 cols) |
| `chorus_submissions` | Historique des soumissions PISTE |
| `invoice_audit_log` | Traçabilité fiscale (append-only, DELETE/UPDATE bloqués) |
| `factoring_partners` | Partenaires d'affacturage (Defacto, etc.) |
| `mandats_facturation_signatures` | Signatures de mandats (horodatées, SHA-256) |

## Numérotation

Nouvelles pièces : `JOL-{UUID_EMETTEUR_32}-{YYYY}-{SEQUENCE}` ; les avoirs
utilisent le préfixe `AV`. Les numéros déjà attribués restent inchangés.

- Séquence par soignant, sur toutes les pièces conservées, y compris en erreur
- UUID complet sans tirets pour distinguer deux SIRET ou UUID de même préfixe
- Au moins cinq chiffres, sans troncature lorsque la séquence grandit
- Pas de reset annuel (le préfixe année est informatif)
- `next_invoice_number`/`next_avoir_number` calculent le suivant dans la
  transaction de leur producteur SQL. Un appel isolé ne réserve aucun numéro.
- Le générateur Edge réserve numéro et pièce avec
  `fn_reserver_facture_honoraires`, puis rend les snapshots persistés.
- Un bail privé limite le rendu simultané ; la reprise après panne conserve la
  même pièce et son numéro. Le registre des octets et la première émission sont
  enregistrés ensemble, sous vérification du token serveur courant.

La preuve de concurrence est dans `scripts/ci/numerotation-concurrence-pg17.py`
(PostgreSQL 17 éphémère). L'ancien test réseau qui sélectionnait deux soignants
arbitraires et supposait qu'un simple appel de calcul consommait un numéro est
retiré ; aucun fallback production ni secret n'est requis par son remplaçant.

## Triggers (factures_honoraires)

1. **Immutabilité** : une fois EMISE, les montants/numéro/identités sont verrouillés (bypass service_role + admin)
2. **Auto-audit** : chaque INSERT/UPDATE crée automatiquement une ligne dans `invoice_audit_log`
3. **updated_at** : MAJ automatique
4. **Détection secteur public** : `is_public_sector` copié depuis `etablissements.est_secteur_public` à l'INSERT

## RLS

- Soignant : voit ses propres factures
- Établissement : voit les factures qui lui sont adressées
- Admin : voit tout
- `invoice_audit_log` : même visibilité que la facture associée
- `chorus_submissions` : idem
- `factoring_partners` : authenticated voit les actifs, admin voit tout

---

## Activation Chorus Pro

### Prérequis

1. **Compte PISTE** : inscription sur [developer.aife.economie.gouv.fr](https://developer.aife.economie.gouv.fr)
2. **Application créée** sur le portail → récupérer Client ID + Client Secret
3. **Souscription API** "Chorus Pro - Factures" (sandbox d'abord, puis prod)

### Secrets Supabase à configurer

| Variable | Valeur | Source |
|---|---|---|
| `PISTE_CLIENT_ID` | `632ac022-...` | Portail PISTE > Mes applications |
| `PISTE_CLIENT_SECRET` | `***` | Idem (cliquer "Consulter le client secret") |
| `CHORUS_TECH_USER_LOGIN` | Login du compte technique | Dashboard Chorus Pro > Gestion des habilitations |
| `CHORUS_TECH_USER_PASSWORD` | Password du compte technique | Idem |
| `PISTE_ENV` | `sandbox` ou `production` | Commencer par `sandbox` |

### Configurer dans Supabase

Dashboard Supabase → Project Settings → Edge Functions → Secrets → ajouter les 5 variables ci-dessus.

### Endpoints concernés

| Edge Function | Rôle |
|---|---|
| `submit-to-chorus` | Dépôt de facture PDF via DeposerPDFacture PISTE |
| `sync-chorus-status` | Cron horaire de mise à jour des statuts |
| `chorus-pro-deposit` | Legacy (factures commissions, pas honoraires) |

### Scénario de test (sandbox)

1. Configurer les secrets PISTE en mode sandbox
2. Lancer le script d'activation :
   ```bash
   npx tsx scripts/activate-chorus.ts
   ```
3. Le script fait :
   - 1 appel OAuth2 → vérifie le token
   - 1 dépôt test → vérifie le retour 200 + identifiant flux
   - 1 consultation statut → vérifie le parsing
4. Si tout passe : les edge functions `submit-to-chorus` et `sync-chorus-status` sont prêtes
5. Pour passer en prod : changer `PISTE_ENV` de `sandbox` à `production` et mettre à jour les Client ID/Secret si différents

### FAQ rejets Chorus Pro

| Code erreur | Cause | Action |
|---|---|---|
| `SIRET_INVALID` | SIRET fournisseur ou destinataire invalide | Vérifier les données établissement |
| `SERVICE_NOT_FOUND` | Code service inexistant | Vérifier chorus_pro_config.code_service |
| `DUPLICATE_INVOICE` | Numéro de facture déjà déposé | Normal si retry — la facture est déjà traitée |
| `FORMAT_ERROR` | XML CII invalide | Vérifier les données de la facture (montants, dates) |

### Procédure de changement de factor

1. Admin → Factoring Partners → Désactiver l'ancien partner
2. Créer le nouveau partner (legal_name, SIRET, IBAN, BIC, subrogation_template)
3. Les nouvelles factures avec `factor_assigned=true` utiliseront automatiquement le partner actif
4. Les factures existantes gardent leur référence factor_id (pas de modification rétroactive)
