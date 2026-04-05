# Fonctions cron (service_role only)

Ces fonctions sont appelées par des jobs cron via `pg_cron` ou des triggers Supabase.
Elles n'ont PAS de GRANT vers `authenticated` — c'est intentionnel.

## Facturation
- `fn_auto_facturation_mensuelle` — Génère les factures mensuelles de commission
- `fn_recalculer_palier_commission` — Recalcule le palier dégressif par établissement
- `fn_recalculer_tous_paliers` — Recalcule tous les paliers (batch)

## Notifications
- `fn_alerter_paiements_retard` — Alerte les établissements avec paiements en retard
- `fn_email_documents_expirants` — Email pour documents qui expirent bientôt
- `fn_email_eligible_liberal` — Email quand un soignant atteint 3200h
- `fn_email_factures_impayees` — Rappel factures impayées
- `fn_email_rappels_j1` — Rappel J-1 avant une mission
- `fn_email_recap_hebdo` — Récap hebdomadaire

## Maintenance
- `fn_anonymiser_gps_anciennes` — RGPD : anonymise les GPS > 90 jours
- `fn_purger_audit_ancien` — Purge les logs d'audit > 1 an
- `fn_purger_gps_ancien` — Purge les données GPS anciennes
- `fn_nettoyer_missions_fantomes` — Supprime les missions orphelines
- `fn_nettoyer_partages_rib_expires` — Expire les partages RIB
- `fn_nettoyer_tokens_push` — Supprime les tokens push invalides
- `fn_rgpd_purge_automatique_inactifs` — RGPD : anonymise les comptes inactifs > 2 ans

## Calculs
- `fn_calculer_bfa` / `fn_calculer_bfa_safe` / `fn_calculer_bfa_tous` — Calcul BFA
- `fn_calculer_cotisations` — Calcul des cotisations sociales
- `fn_calculer_financier_mission` — Calcul financier d'une mission
- `fn_calculer_heures_totales` — Recalcul heures cumulées
- `fn_relancer_signatures_contrats` — Relance signatures en attente

## Triggers internes
- `fn_generer_code_parrainage` — Auto-génère code JO-XXXXXX
- `fn_generer_numero_contrat` — Auto-génère numéro de contrat
- `fn_generer_numero_facture` — Auto-génère numéro de facture
- `fn_proteger_document_verification` — Empêche la modification des champs de vérification
- `fn_valider_transition_statut_mission` — Valide les transitions de statut
- `fn_verifier_coherence_publication` — Vérifie la cohérence avant publication mission
