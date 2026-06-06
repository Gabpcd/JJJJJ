-- AUDIT performance (Supabase advisors) — index FK manquants + suppression des doublons.
-- Source : get_advisors(performance). Aucun impact fonctionnel, gains à l'échelle
-- (joins, ON DELETE/UPDATE cascade, lookups). CREATE INDEX non-concurrent : OK en
-- migration transactionnelle, tables de taille modérée.

-- ── 1) Index couvrant les clés étrangères non indexées (30) ──────────────────────
CREATE INDEX IF NOT EXISTS idx_contrats_travail_missions_etablissement_id ON contrats_travail_missions (etablissement_id);
CREATE INDEX IF NOT EXISTS idx_contrats_travail_missions_soignant_id ON contrats_travail_missions (soignant_id);
CREATE INDEX IF NOT EXISTS idx_credits_etablissement_facture_id ON credits_etablissement (facture_id);
CREATE INDEX IF NOT EXISTS idx_equipe_membres_equipe_id ON equipe_membres (equipe_id);
CREATE INDEX IF NOT EXISTS idx_etablissements_parraine_par_id ON etablissements (parraine_par_id);
CREATE INDEX IF NOT EXISTS idx_evenements_score_etab_litige_id ON evenements_score_etab (litige_id);
CREATE INDEX IF NOT EXISTS idx_evenements_score_etab_mission_id ON evenements_score_etab (mission_id);
CREATE INDEX IF NOT EXISTS idx_evenements_score_soignant_candidature_id ON evenements_score_soignant (candidature_id);
CREATE INDEX IF NOT EXISTS idx_evenements_score_soignant_litige_id ON evenements_score_soignant (litige_id);
CREATE INDEX IF NOT EXISTS idx_evenements_score_soignant_mission_id ON evenements_score_soignant (mission_id);
CREATE INDEX IF NOT EXISTS idx_factor_advances_etablissement_id ON factor_advances (etablissement_id);
CREATE INDEX IF NOT EXISTS idx_factor_advances_mission_id ON factor_advances (mission_id);
CREATE INDEX IF NOT EXISTS idx_heures_externes_soignants_valide_par ON heures_externes_soignants (valide_par);
CREATE INDEX IF NOT EXISTS idx_invitations_etablissement_acceptee_par_user_id ON invitations_etablissement (acceptee_par_user_id);
CREATE INDEX IF NOT EXISTS idx_invitations_etablissement_invite_par ON invitations_etablissement (invite_par);
CREATE INDEX IF NOT EXISTS idx_litiges_paiement_soignant_id ON litiges (paiement_soignant_id);
CREATE INDEX IF NOT EXISTS idx_membres_etablissement_invite_par ON membres_etablissement (invite_par);
CREATE INDEX IF NOT EXISTS idx_messages_litige_litige_id ON messages_litige (litige_id);
CREATE INDEX IF NOT EXISTS idx_missions_specialite_medicale_requise ON missions (specialite_medicale_requise);
CREATE INDEX IF NOT EXISTS idx_reclamations_mission_id ON reclamations (mission_id);
CREATE INDEX IF NOT EXISTS idx_reclamations_traite_par ON reclamations (traite_par);
CREATE INDEX IF NOT EXISTS idx_scans_pointage_creneau_effectif_id ON scans_pointage (creneau_effectif_id);
CREATE INDEX IF NOT EXISTS idx_scans_pointage_soignant_id ON scans_pointage (soignant_id);
CREATE INDEX IF NOT EXISTS idx_scans_pointage_valide_par ON scans_pointage (valide_par);
CREATE INDEX IF NOT EXISTS idx_shift_affectations_mission_id ON shift_affectations (mission_id);
CREATE INDEX IF NOT EXISTS idx_soignants_score_breakdown_id ON soignants (score_breakdown_id);
CREATE INDEX IF NOT EXISTS idx_soignants_specialite_medicale ON soignants (specialite_medicale);
CREATE INDEX IF NOT EXISTS idx_stripe_refunds_queue_avoir_id ON stripe_refunds_queue (avoir_id);
CREATE INDEX IF NOT EXISTS idx_stripe_refunds_queue_facture_origine_id ON stripe_refunds_queue (facture_origine_id);
CREATE INDEX IF NOT EXISTS idx_typing_status_user_id ON typing_status (user_id);

-- ── 2) Suppression des index dupliqués (6) ──────────────────────────────────────
-- On conserve l'index adossé à une contrainte (ou le mieux nommé) et on supprime le doublon.
DROP INDEX IF EXISTS public.uniq_contrat_travail_mission;       -- doublon de contrats_travail_missions_mission_id_key (contrainte)
DROP INDEX IF EXISTS public.favoris_etab_soignant_unique;        -- doublon de favoris_etablissement_id_soignant_id_key (contrainte)
DROP INDEX IF EXISTS public.idx_docs_soignant;                   -- doublon de idx_documents_soignant_type
DROP INDEX IF EXISTS public.idx_factures_etablissement;          -- doublon de idx_factures_etablissement_statut
DROP INDEX IF EXISTS public.idx_missions_etablissement;          -- doublon de idx_missions_etablissement_statut
DROP INDEX IF EXISTS public.idx_paie_mission;                    -- doublon de idx_paiements_soignant_mission
