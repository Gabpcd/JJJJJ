# GO validé — chantiers de la prochaine session

> Validés par Gabrielle le 11/06/2026. Workflow habituel : PRs + CI verte + merge.

## 1. Enrichissement emails + téléphones via l'Annuaire Santé (FHIR ANS)
La clé API FHIR ANS est DÉJÀ configurée (visible healthcheck : « Annuaire Santé
(RPPS) — Clé API FHIR ANS configurée », utilisée par verify-rpps).
- Edge function `enrich-prospects-annuaire` : interroge l'API FHIR
  (Organization pour les établissements via FINESS/SIRET, Practitioner/
  PractitionerRole pour les soignants via RPPS ou nom+profession) et extrait
  les `telecom` (email — souvent MSSanté — et téléphone).
- Cible : `prospects_etablissements` (par finess) et `prospects_soignants`
  (TOUS les soignants de la base CNAM, pas seulement les libéraux — si
  l'annuaire couvre un salarié, on le prend).
- Remplir email/telephone UNIQUEMENT si vides (jamais écraser une saisie
  manuelle). Batch + rate limit API ANS, relançable par tranches comme
  import-finess. Bouton admin « Enrichir depuis l'Annuaire Santé » sur les
  deux onglets de prospection + compteur enrichis/restants.
- Une fois enrichis, l'envoi en masse existant (sales-outreach-batch) prend
  le relais automatiquement.

## 2. Page AdminBFA (backend complet, zéro UI admin)
- Table `paliers_bfa` (missions_min, missions_max, taux_bfa, est_actif),
  RPCs existantes : fn_bfa_info(), fn_calculer_bfa_safe(), fn_calculer_bfa_tous().
- Créer : RPC fn_admin_lister_paliers_bfa() + fn_admin_modifier_palier_bfa()
  (est_admin(), audit journaux_audit) + page /admin/bfa (groupe Finances,
  sous « Taux commission ») : liste des paliers éditables, simulation
  d'impact (fn_calculer_bfa_tous), état bfa_eligible/bfa_contrat_signe_le
  par groupe.

## 3. Remise groupe éditable
- AdminGroupes affiche `remise_groupe_pourcent` en lecture seule.
- Créer fn_admin_modifier_remise_groupe(p_groupe_id, p_remise) (garde admin,
  bornes 0-100, audit) + input d'édition par ligne dans AdminGroupes
  (pattern taux per-row déjà présent dans cette page).

## Fait dans la session du 11/06 (ne pas refaire)
- Conflit gel/recalcul commission corrigé (migration 20260611161826) :
  dec_calculer_commission respecte taux_commission_fige.
- Chorus healthcheck + toast réparés ; envoi en masse prospection livré ;
  réclamations regroupées ; relance mandats ; validation manuelle docs ;
  Playwright réactivé (non-bloquant, env VITE_* au build).
