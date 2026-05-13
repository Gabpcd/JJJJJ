# Page admin consultation contrats (Sprint 5.7)

> Fix **P0-9** audit Sprint 5. Permet à l'admin plateforme de consulter tous les contrats avec hash SHA-256 + certificat + audit trail pour audit légal.

## Routes

- `/admin/contrats` — liste paginée avec filtres
- `/admin/contrats/:id` — détail complet d'un contrat

## RPCs

### `fn_admin_lister_contrats(p_filtre_statut?, p_recherche?, p_limit, p_offset)`

Retourne :
```json
{
  "success": true,
  "total": 123,
  "limit": 50,
  "offset": 0,
  "contrats": [
    {
      "id": "uuid",
      "numero_contrat": "...",
      "statut": "SIGNE",
      "type_contrat": "CDD",
      "mission_intitule": "...",
      "soignant_nom": "...",
      "etablissement_nom": "...",
      "hash_court": "abc12345...",
      "signe_le": "2026-05-...",
      "dpae_numero": "...",
      "cree_le": "..."
    }
  ]
}
```

Filtres `statut` : `BROUILLON`, `EN_ATTENTE_SOIGNANT`, `EN_ATTENTE_ETAB`, `SIGNE`, `ANNULE`.

Recherche full-text sur : numéro contrat, intitulé mission, nom soignant, nom étab.

### `fn_admin_detail_contrat(p_contrat_id)`

Retourne tous les champs nécessaires à l'audit légal :
- **Parties** : soignant (prenom, nom, email, RPPS), étab (nom, SIRET, email)
- **Document** : hash SHA-256 complet, type_contrat, profession, dates signature
- **Signatures détaillées** : IP, user-agent, dates pour chaque partie + table Sprint 2 `signatures_contrats` (mode OTP/PSC, hash document, statut, OTP utilisé)
- **DPAE** : numéro URSSAF + date saisie (si CDD/CDDU/SALARIE)
- **Storage** : `storage_path` du PDF + signed URL (valide 5 min)
- **Audit trail** : 100 derniers événements `journaux_audit` filtrés `type_ressource='contrat_mission'`

## Frontend

### `AdminContrats.tsx`

- **Filtres** : statut (5 options) + recherche debounced 300ms
- **Table** : numéro, soignant, étab, type, statut (badge coloré), date signature
- **Pagination** : 50/page avec navigation prev/next
- **Lien direct** vers `/admin/contrats/:id`

### `AdminDetailContrat.tsx`

6 sections :

1. **Parties** — soignant + étab avec liens vers profils admin
2. **Intégrité document** — hash SHA-256 copiable (button copy), badge statut, mode signature, dates
3. **Signatures détaillées** — IP + UA pour chaque partie + collapsible `signatures_contrats` Sprint 2 (OTP/PSC, RPPS, certificat)
4. **DPAE** — numéro URSSAF + date (si applicable)
5. **PDF embedded** — `<iframe>` avec signed URL 5 min
6. **Audit trail** — liste scrollable max-height 400px, 100 derniers événements

## Sécurité

- Toutes les RPCs vérifient `est_admin()` côté serveur (SECURITY DEFINER)
- Codes d'erreur : `NON_AUTORISE`, `CONTRAT_INTROUVABLE`
- Signed URLs PDF expirent en 5 min (audit, pas téléchargement public)
- Aucune modification possible — page consultation seule

## Cas d'usage audit légal

1. Litige client : retrouver le contrat exact signé (hash + IP + date)
2. Inspection URSSAF : exporter DPAE + contrat lié
3. Réclamation soignant : vérifier signature étab valide
4. Audit interne RGPD : trace complète des signatures + acteurs
