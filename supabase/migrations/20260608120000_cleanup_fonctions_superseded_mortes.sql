-- CLEANUP série A — suppression de 24 fonctions backend confirmées MORTES ou
-- SUPERSEDED par l'audit exhaustif backend→frontend.
--
-- Critères de sûreté vérifiés AVANT suppression (chacune des 24) :
--   1. Aucun appel dans le code applicatif frontend (src/, hors types.ts généré)
--   2. Aucun appel dans les edge functions (supabase/functions/, full-text)
--   3. Aucun appel par un cron pg_cron
--   4. Aucune référence dans le corps d'une autre fonction (pg_proc.prosrc)
--   5. Aucune référence dans une policy RLS / vue / contrainte CHECK / default de colonne
--
-- Remplaçant câblé côté app (le cas échéant) indiqué en commentaire.
-- NB: est_admin_valide a été EXCLU de ce nettoyage (utilisé par une policy RLS).
--     fn_resolve_template_contrat exclu (statut incertain, conservé par prudence).

-- Finances admin : la page AdminFinances reconstruit tout côté client depuis
-- les tables `factures` + `missions`. Ces 2 fonctions ne sont appelées nulle part.
-- (fn_admin_finances était la cible de 20260607130000 — fix devenu sans objet.)
DROP FUNCTION IF EXISTS public.fn_admin_finances();
DROP FUNCTION IF EXISTS public.fn_admin_finances_par_etablissement();

-- Validation établissement → remplacée par fn_admin_valider_etablissement /
-- fn_admin_rejeter_etablissement (AdminVerificationEtablissements.tsx).
DROP FUNCTION IF EXISTS public.fn_valider_etablissement(p_etablissement_id uuid, p_statut text, p_motif text);

-- Litiges : ouverture/clôture/médiation → flux câblé via
-- fn_ouvrir_litige_rate_limited, fn_proposer_cloture_litige,
-- fn_cloturer_litige_avec_payload, fn_repondre_litige, fn_admin_trancher_litige.
DROP FUNCTION IF EXISTS public.fn_creer_litige(p_mission_id uuid, p_presence_id uuid, p_motif text);
DROP FUNCTION IF EXISTS public.fn_cloturer_litige_mutuel(p_litige_id uuid);
DROP FUNCTION IF EXISTS public.fn_demander_mediation_litige(p_litige_id uuid);
DROP FUNCTION IF EXISTS public.fn_demander_mediation_admin(p_litige_id uuid, p_message text);

-- Paiement : confirmation/contestation → fn_confirmer_paiement_soignant +
-- fn_contester_paiement_soignant (BandeauPaiementDeclare.tsx) ; réponse à
-- contestation via le flux litige (PanneauContestation.tsx).
DROP FUNCTION IF EXISTS public.fn_confirmer_reception_paiement(p_paiement_id uuid);
DROP FUNCTION IF EXISTS public.fn_repondre_contestation_paiement(p_paiement_id uuid, p_action text, p_nouvelle_reference text, p_reponse text);

-- Pointage par code : variantes superseded par le pointage GPS
-- (fn_pointer_arrivee/depart) + scan QR (fn_valider_scan_qr) +
-- code de secours (fn_valider_code_secours).
DROP FUNCTION IF EXISTS public.fn_pointer_arrivee_code(p_mission_id uuid, p_code text);
DROP FUNCTION IF EXISTS public.fn_pointer_depart_code(p_presence_id uuid, p_code text);

-- Gamification : superseded par fn_badge_stats (ProfilSoignant.tsx).
DROP FUNCTION IF EXISTS public.fn_mes_badges();
DROP FUNCTION IF EXISTS public.fn_ma_streak();

-- Export RGPD soignant : superseded par fn_rgpd_exporter_rate_limited
-- (SectionConfidentialite.tsx). (L'implémentation interne fn_rgpd_exporter_donnees_soignant
-- est CONSERVÉE car appelée par le wrapper rate-limited.)
DROP FUNCTION IF EXISTS public.fn_exporter_mes_donnees();

-- Lectures soignant orphelines (scaffolding remplacé par requêtes directes / autres RPC).
DROP FUNCTION IF EXISTS public.fn_mes_missions_soignant();
DROP FUNCTION IF EXISTS public.fn_mes_etablissements_soignant();

-- Édition profil : superseded par fn_modifier_mon_etablissement /
-- fn_modifier_mon_profil (+ fn_toggle_pool_urgence/_sms).
DROP FUNCTION IF EXISTS public.fn_modifier_profil_etablissement(p_nom text, p_telephone_contact text, p_email_contact text, p_description text, p_adresse_rue text, p_adresse_code_postal text, p_adresse_ville text, p_adresse_departement text, p_adresse_lat numeric, p_adresse_lng numeric, p_finess text, p_couleur_theme text, p_mode_paiement_commission text, p_horaires_ouverture jsonb);
DROP FUNCTION IF EXISTS public.fn_modifier_mon_profil_extra(p_type_exercice text, p_disponible_urgence boolean, p_urgence_rayon_km integer, p_rayon_deplacement_km integer, p_adresse_lat numeric, p_adresse_lng numeric);

-- Planning : superseded par les lectures directes de `missions` (PlanningHebdomadaire.tsx).
DROP FUNCTION IF EXISTS public.fn_planning_soignant(p_debut date, p_fin date);
DROP FUNCTION IF EXISTS public.fn_planning_etablissement(p_debut date, p_fin date);
DROP FUNCTION IF EXISTS public.fn_admin_planning_global(p_debut date, p_fin date);

-- Matching legacy : superseded par le moteur Sprint 13 (fn_calculer_score_matching).
DROP FUNCTION IF EXISTS public.fn_matcher_soignants_mission(p_mission_id uuid);
DROP FUNCTION IF EXISTS public.fn_matching_soignants(p_mission_id uuid);

-- Rate-limit générique : superseded par fn_verifier_rate_limit (utilisé en interne).
DROP FUNCTION IF EXISTS public.fn_check_rate_limit(p_action text, p_max_per_minute integer);
