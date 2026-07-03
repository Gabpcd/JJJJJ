-- ============================================================
-- Baseline prod Jolene — RLS policies (schema public)
-- Extrait le 2026-07-03 depuis pg_policies (projet flripxtsyegjshnhzjkz)
-- 313 policies au total
-- ============================================================

-- admin_invocations.admin_inv_select
CREATE POLICY admin_inv_select ON public.admin_invocations AS PERMISSIVE FOR SELECT TO authenticated
  USING (est_admin_valide());

-- admins_groupe_sante.pol_agrp_delete
CREATE POLICY pol_agrp_delete ON public.admins_groupe_sante AS PERMISSIVE FOR DELETE TO authenticated
  USING (est_admin());

-- admins_groupe_sante.pol_agrp_select
CREATE POLICY pol_agrp_select ON public.admins_groupe_sante AS PERMISSIVE FOR SELECT TO authenticated
  USING ((( SELECT est_admin() AS est_admin) OR (utilisateur_id = ( SELECT auth.uid() AS uid))));

-- admins_groupe_sante.pol_agrp_update
CREATE POLICY pol_agrp_update ON public.admins_groupe_sante AS PERMISSIVE FOR UPDATE TO authenticated
  USING (est_admin());

-- admins_groupe_sante.pol_agrp_write
CREATE POLICY pol_agrp_write ON public.admins_groupe_sante AS PERMISSIVE FOR INSERT TO authenticated
  WITH CHECK (est_admin());

-- alertes_systeme.pol_alertes_admin
CREATE POLICY pol_alertes_admin ON public.alertes_systeme AS PERMISSIVE FOR ALL TO public
  USING (est_admin())
  WITH CHECK (est_admin());

-- api_keys.pol_apikeys_delete
CREATE POLICY pol_apikeys_delete ON public.api_keys AS PERMISSIVE FOR DELETE TO authenticated
  USING ((est_admin() OR (etablissement_id = mon_etablissement_id())));

-- api_keys.pol_apikeys_insert
CREATE POLICY pol_apikeys_insert ON public.api_keys AS PERMISSIVE FOR INSERT TO authenticated
  WITH CHECK ((est_admin() OR (etablissement_id = mon_etablissement_id())));

-- api_keys.pol_apikeys_select
CREATE POLICY pol_apikeys_select ON public.api_keys AS PERMISSIVE FOR SELECT TO authenticated
  USING (((etablissement_id = mon_etablissement_id()) OR est_admin()));

-- api_keys.pol_apikeys_update
CREATE POLICY pol_apikeys_update ON public.api_keys AS PERMISSIVE FOR UPDATE TO authenticated
  USING ((est_admin() OR (etablissement_id = mon_etablissement_id())));

-- articles_aide.aa_admin_all
CREATE POLICY aa_admin_all ON public.articles_aide AS PERMISSIVE FOR ALL TO authenticated
  USING (est_admin())
  WITH CHECK (est_admin());

-- articles_aide.aa_select_publie
CREATE POLICY aa_select_publie ON public.articles_aide AS PERMISSIVE FOR SELECT TO anon, authenticated
  USING ((publie = true));

-- assurance_config.etab_own_config
CREATE POLICY etab_own_config ON public.assurance_config AS PERMISSIVE FOR ALL TO authenticated
  USING (((etablissement_id = mon_etablissement_id()) OR est_admin()))
  WITH CHECK (((etablissement_id = mon_etablissement_id()) OR est_admin()));

-- assurances_mission.etab_own_assurances
CREATE POLICY etab_own_assurances ON public.assurances_mission AS PERMISSIVE FOR ALL TO authenticated
  USING (((etablissement_id = mon_etablissement_id()) OR (soignant_id = ( SELECT auth.uid() AS uid)) OR est_admin()))
  WITH CHECK (((etablissement_id = mon_etablissement_id()) OR est_admin()));

-- attestations_heures_externes.pol_att_ext_insert
CREATE POLICY pol_att_ext_insert ON public.attestations_heures_externes AS PERMISSIVE FOR INSERT TO authenticated
  WITH CHECK ((soignant_id = ( SELECT auth.uid() AS uid)));

-- attestations_heures_externes.pol_att_ext_select
CREATE POLICY pol_att_ext_select ON public.attestations_heures_externes AS PERMISSIVE FOR SELECT TO authenticated
  USING (((soignant_id = ( SELECT auth.uid() AS uid)) OR ( SELECT est_admin() AS est_admin)));

-- attestations_heures_externes.pol_att_ext_update
CREATE POLICY pol_att_ext_update ON public.attestations_heures_externes AS PERMISSIVE FOR UPDATE TO authenticated
  USING ((est_admin() OR ((soignant_id = ( SELECT auth.uid() AS uid)) AND (cree_le > (now() - '24:00:00'::interval)))))
  WITH CHECK ((est_admin() OR ((soignant_id = ( SELECT auth.uid() AS uid)) AND (cree_le > (now() - '24:00:00'::interval)))));

-- avoirs.pol_avoirs_deny_write
CREATE POLICY pol_avoirs_deny_write ON public.avoirs AS PERMISSIVE FOR INSERT TO authenticated
  WITH CHECK (false);

-- avoirs.pol_avoirs_select
CREATE POLICY pol_avoirs_select ON public.avoirs AS PERMISSIVE FOR SELECT TO authenticated
  USING ((est_admin() OR (emis_par = ( SELECT auth.uid() AS uid)) OR (EXISTS ( SELECT 1
   FROM missions m
  WHERE ((m.id = avoirs.source_mission_id) AND ((m.soignant_assigne_id = ( SELECT auth.uid() AS uid)) OR (m.etablissement_id = mon_etablissement_id())))))));

-- badges_soignant.badges_soignant_select_own
CREATE POLICY badges_soignant_select_own ON public.badges_soignant AS PERMISSIVE FOR SELECT TO public
  USING ((soignant_id = ( SELECT auth.uid() AS uid)));

-- badges_soignant.badges_soignant_service_role
CREATE POLICY badges_soignant_service_role ON public.badges_soignant AS PERMISSIVE FOR ALL TO service_role
  USING (true)
  WITH CHECK (true);

-- bfa_suivi.pol_bfa_select
CREATE POLICY pol_bfa_select ON public.bfa_suivi AS PERMISSIVE FOR SELECT TO authenticated
  USING ((( SELECT est_admin() AS est_admin) OR (( SELECT est_admin_etablissement() AS est_admin_etablissement) AND (etablissement_id = ( SELECT mon_etablissement_id() AS mon_etablissement_id))) OR (groupe_id IN ( SELECT admins_groupe_sante.groupe_id
   FROM admins_groupe_sante
  WHERE (admins_groupe_sante.utilisateur_id = ( SELECT auth.uid() AS uid))))));

-- bulletins_paie.bp_select_own
CREATE POLICY bp_select_own ON public.bulletins_paie AS PERMISSIVE FOR SELECT TO authenticated
  USING (((soignant_id = ( SELECT auth.uid() AS uid)) OR (etablissement_id = mon_etablissement_id()) OR est_admin()));

-- calendar_connections.own_calendar_connections
CREATE POLICY own_calendar_connections ON public.calendar_connections AS PERMISSIVE FOR ALL TO public
  USING ((utilisateur_id = ( SELECT auth.uid() AS uid)));

-- calendar_events_sync.own_calendar_events
CREATE POLICY own_calendar_events ON public.calendar_events_sync AS PERMISSIVE FOR ALL TO public
  USING ((connection_id IN ( SELECT calendar_connections.id
   FROM calendar_connections
  WHERE (calendar_connections.utilisateur_id = ( SELECT auth.uid() AS uid)))));

-- candidatures.pol_cand_delete
CREATE POLICY pol_cand_delete ON public.candidatures AS PERMISSIVE FOR DELETE TO authenticated
  USING ((( SELECT est_admin() AS est_admin) OR ((soignant_id = ( SELECT auth.uid() AS uid)) AND (statut = 'EN_ATTENTE'::text))));

-- candidatures.pol_cand_insert
CREATE POLICY pol_cand_insert ON public.candidatures AS PERMISSIVE FOR INSERT TO authenticated
  WITH CHECK (((soignant_id = ( SELECT auth.uid() AS uid)) OR ( SELECT est_admin() AS est_admin) OR (mission_id IN ( SELECT missions.id
   FROM missions
  WHERE (missions.etablissement_id = ( SELECT mon_etablissement_id() AS mon_etablissement_id))))));

-- candidatures.pol_cand_select
CREATE POLICY pol_cand_select ON public.candidatures AS PERMISSIVE FOR SELECT TO authenticated
  USING (((soignant_id = ( SELECT auth.uid() AS uid)) OR (mission_id IN ( SELECT missions.id
   FROM missions
  WHERE (missions.etablissement_id = ( SELECT mon_etablissement_id() AS mon_etablissement_id)))) OR ( SELECT est_admin() AS est_admin)));

-- candidatures.pol_cand_update
CREATE POLICY pol_cand_update ON public.candidatures AS PERMISSIVE FOR UPDATE TO authenticated
  USING (((soignant_id = ( SELECT auth.uid() AS uid)) OR ( SELECT est_admin() AS est_admin) OR (mission_id IN ( SELECT missions.id
   FROM missions
  WHERE (missions.etablissement_id = ( SELECT mon_etablissement_id() AS mon_etablissement_id))))))
  WITH CHECK ((( SELECT est_admin() AS est_admin) OR (soignant_id = ( SELECT auth.uid() AS uid)) OR (mission_id IN ( SELECT missions.id
   FROM missions
  WHERE (missions.etablissement_id = ( SELECT mon_etablissement_id() AS mon_etablissement_id))))));

-- cessions_creance.pol_cessions_select
CREATE POLICY pol_cessions_select ON public.cessions_creance AS PERMISSIVE FOR SELECT TO authenticated
  USING ((est_admin() OR (soignant_id = ( SELECT auth.uid() AS uid))));

-- chorus_pro_config.pol_cpro_delete
CREATE POLICY pol_cpro_delete ON public.chorus_pro_config AS PERMISSIVE FOR DELETE TO authenticated
  USING (est_admin());

-- chorus_pro_config.pol_cpro_insert
CREATE POLICY pol_cpro_insert ON public.chorus_pro_config AS PERMISSIVE FOR INSERT TO authenticated
  WITH CHECK ((etablissement_id = mon_etablissement_id()));

-- chorus_pro_config.pol_cpro_select
CREATE POLICY pol_cpro_select ON public.chorus_pro_config AS PERMISSIVE FOR SELECT TO authenticated
  USING (((etablissement_id = mon_etablissement_id()) OR est_admin()));

-- chorus_pro_config.pol_cpro_update
CREATE POLICY pol_cpro_update ON public.chorus_pro_config AS PERMISSIVE FOR UPDATE TO authenticated
  USING (((etablissement_id = mon_etablissement_id()) OR est_admin()))
  WITH CHECK (((etablissement_id = mon_etablissement_id()) OR est_admin()));

-- chorus_submissions.chorus_sub_insert_service
CREATE POLICY chorus_sub_insert_service ON public.chorus_submissions AS PERMISSIVE FOR INSERT TO authenticated
  WITH CHECK (est_admin());

-- chorus_submissions.chorus_sub_select
CREATE POLICY chorus_sub_select ON public.chorus_submissions AS PERMISSIVE FOR SELECT TO authenticated
  USING ((EXISTS ( SELECT 1
   FROM factures_honoraires fh
  WHERE ((fh.id = chorus_submissions.invoice_id) AND ((fh.soignant_id = ( SELECT auth.uid() AS uid)) OR est_admin())))));

-- chorus_submissions.chorus_sub_update_service
CREATE POLICY chorus_sub_update_service ON public.chorus_submissions AS PERMISSIVE FOR UPDATE TO authenticated
  USING (est_admin());

-- codes_secours_mission.pol_codes_secours_select
CREATE POLICY pol_codes_secours_select ON public.codes_secours_mission AS PERMISSIVE FOR SELECT TO authenticated
  USING ((est_admin() OR (EXISTS ( SELECT 1
   FROM missions m
  WHERE ((m.id = codes_secours_mission.mission_id) AND (m.etablissement_id = mon_etablissement_id()))))));

-- conformite_travail.pol_conf_delete_deny
CREATE POLICY pol_conf_delete_deny ON public.conformite_travail AS PERMISSIVE FOR DELETE TO authenticated
  USING (false);

-- conformite_travail.pol_conf_delete_deny_anon
CREATE POLICY pol_conf_delete_deny_anon ON public.conformite_travail AS PERMISSIVE FOR DELETE TO anon
  USING (false);

-- conformite_travail.pol_conf_insert_deny
CREATE POLICY pol_conf_insert_deny ON public.conformite_travail AS PERMISSIVE FOR INSERT TO authenticated
  WITH CHECK (false);

-- conformite_travail.pol_conf_insert_deny_anon
CREATE POLICY pol_conf_insert_deny_anon ON public.conformite_travail AS PERMISSIVE FOR INSERT TO anon
  WITH CHECK (false);

-- conformite_travail.pol_conf_select
CREATE POLICY pol_conf_select ON public.conformite_travail AS PERMISSIVE FOR SELECT TO authenticated
  USING (((soignant_id = ( SELECT auth.uid() AS uid)) OR ( SELECT est_admin() AS est_admin) OR (mission_id IN ( SELECT missions.id
   FROM missions
  WHERE (missions.etablissement_id = ( SELECT mon_etablissement_id() AS mon_etablissement_id))))));

-- conformite_travail.pol_conf_update_deny
CREATE POLICY pol_conf_update_deny ON public.conformite_travail AS PERMISSIVE FOR UPDATE TO authenticated
  USING (false)
  WITH CHECK (false);

-- conformite_travail.pol_conf_update_deny_anon
CREATE POLICY pol_conf_update_deny_anon ON public.conformite_travail AS PERMISSIVE FOR UPDATE TO anon
  USING (false)
  WITH CHECK (false);

-- consentements_ping_gps.pol_consent_ping_select
CREATE POLICY pol_consent_ping_select ON public.consentements_ping_gps AS PERMISSIVE FOR SELECT TO authenticated
  USING (((soignant_id = ( SELECT auth.uid() AS uid)) OR est_admin()));

-- contrats_mission.pol_contrat_insert
CREATE POLICY pol_contrat_insert ON public.contrats_mission AS PERMISSIVE FOR INSERT TO authenticated
  WITH CHECK (est_admin());

-- contrats_mission.pol_contrat_select
CREATE POLICY pol_contrat_select ON public.contrats_mission AS PERMISSIVE FOR SELECT TO authenticated
  USING ((( SELECT est_admin() AS est_admin) OR (soignant_id = ( SELECT auth.uid() AS uid)) OR (etablissement_id = ( SELECT mon_etablissement_id() AS mon_etablissement_id))));

-- contrats_mission.pol_contrat_update
CREATE POLICY pol_contrat_update ON public.contrats_mission AS PERMISSIVE FOR UPDATE TO authenticated
  USING (est_admin());

-- contrats_service_signatures.css_insert
CREATE POLICY css_insert ON public.contrats_service_signatures AS PERMISSIVE FOR INSERT TO authenticated
  WITH CHECK ((etablissement_id = mon_etablissement_id()));

-- contrats_service_signatures.css_select
CREATE POLICY css_select ON public.contrats_service_signatures AS PERMISSIVE FOR SELECT TO authenticated
  USING (((etablissement_id = mon_etablissement_id()) OR est_admin()));

-- contrats_travail_missions.ctm_insert
CREATE POLICY ctm_insert ON public.contrats_travail_missions AS PERMISSIVE FOR INSERT TO authenticated
  WITH CHECK ((etablissement_id = mon_etablissement_id()));

-- contrats_travail_missions.ctm_select
CREATE POLICY ctm_select ON public.contrats_travail_missions AS PERMISSIVE FOR SELECT TO authenticated
  USING (((etablissement_id = mon_etablissement_id()) OR (soignant_id = ( SELECT auth.uid() AS uid)) OR est_admin()));

-- conversations.pol_conv_delete
CREATE POLICY pol_conv_delete ON public.conversations AS PERMISSIVE FOR DELETE TO authenticated
  USING (( SELECT est_admin() AS est_admin));

-- conversations.pol_conv_insert
CREATE POLICY pol_conv_insert ON public.conversations AS PERMISSIVE FOR INSERT TO authenticated
  WITH CHECK (((participant_1_id = ( SELECT auth.uid() AS uid)) OR (participant_2_id = ( SELECT auth.uid() AS uid)) OR ( SELECT est_admin() AS est_admin)));

-- conversations.pol_conv_select
CREATE POLICY pol_conv_select ON public.conversations AS PERMISSIVE FOR SELECT TO authenticated
  USING (((participant_1_id = ( SELECT auth.uid() AS uid)) OR (participant_2_id = ( SELECT auth.uid() AS uid)) OR ( SELECT est_admin() AS est_admin)));

-- conversations.pol_conv_update
CREATE POLICY pol_conv_update ON public.conversations AS PERMISSIVE FOR UPDATE TO authenticated
  USING (((participant_1_id = ( SELECT auth.uid() AS uid)) OR (participant_2_id = ( SELECT auth.uid() AS uid)) OR ( SELECT est_admin() AS est_admin)));

-- conversions_liberal.pol_conv_delete
CREATE POLICY pol_conv_delete ON public.conversions_liberal AS PERMISSIVE FOR DELETE TO authenticated
  USING (est_admin());

-- conversions_liberal.pol_conv_insert
CREATE POLICY pol_conv_insert ON public.conversions_liberal AS PERMISSIVE FOR INSERT TO authenticated
  WITH CHECK ((( SELECT est_admin() AS est_admin) OR ((soignant_id = ( SELECT auth.uid() AS uid)) AND (free_transition_eligible = false) AND (taux_prise_en_charge = 0) AND (montant_pris_en_charge = (0)::numeric) AND (statut = 'INITIE'::text) AND (indy_active = false) AND (qonto_active = false) AND (macsf_active = false) AND (guide_pdf_genere = false) AND (complete_le IS NULL) AND (indy_lien_affiliation IS NULL) AND (qonto_lien_affiliation IS NULL) AND (macsf_lien_affiliation IS NULL))));

-- conversions_liberal.pol_conv_select
CREATE POLICY pol_conv_select ON public.conversions_liberal AS PERMISSIVE FOR SELECT TO authenticated
  USING (((soignant_id = ( SELECT auth.uid() AS uid)) OR ( SELECT est_admin() AS est_admin)));

-- conversions_liberal.pol_conv_update
CREATE POLICY pol_conv_update ON public.conversions_liberal AS PERMISSIVE FOR UPDATE TO authenticated
  USING (est_admin());

-- cotisations_sociales.pol_cotis_insert
CREATE POLICY pol_cotis_insert ON public.cotisations_sociales AS PERMISSIVE FOR INSERT TO authenticated
  WITH CHECK (est_admin());

-- cotisations_sociales.pol_cotis_select
CREATE POLICY pol_cotis_select ON public.cotisations_sociales AS PERMISSIVE FOR SELECT TO authenticated
  USING (((soignant_id = ( SELECT auth.uid() AS uid)) OR ( SELECT est_admin() AS est_admin) OR (mission_id IN ( SELECT missions.id
   FROM missions
  WHERE (missions.etablissement_id = ( SELECT mon_etablissement_id() AS mon_etablissement_id))))));

-- credits_etablissement.pol_credits_etab_select
CREATE POLICY pol_credits_etab_select ON public.credits_etablissement AS PERMISSIVE FOR SELECT TO public
  USING (((etablissement_id = mon_etablissement_id()) OR ( SELECT est_admin() AS est_admin)));

-- demandes_rgpd.pol_rgpd_delete
CREATE POLICY pol_rgpd_delete ON public.demandes_rgpd AS PERMISSIVE FOR DELETE TO authenticated
  USING (est_admin());

-- demandes_rgpd.pol_rgpd_insert
CREATE POLICY pol_rgpd_insert ON public.demandes_rgpd AS PERMISSIVE FOR INSERT TO authenticated
  WITH CHECK (((demandeur_id = ( SELECT auth.uid() AS uid)) AND (statut = 'EN_ATTENTE'::text)));

-- demandes_rgpd.pol_rgpd_select
CREATE POLICY pol_rgpd_select ON public.demandes_rgpd AS PERMISSIVE FOR SELECT TO authenticated
  USING (((demandeur_id = ( SELECT auth.uid() AS uid)) OR ( SELECT est_admin() AS est_admin)));

-- demandes_rgpd.pol_rgpd_update
CREATE POLICY pol_rgpd_update ON public.demandes_rgpd AS PERMISSIVE FOR UPDATE TO authenticated
  USING (est_admin())
  WITH CHECK (est_admin());

-- documents_requis_par_profession.pol_documents_requis_par_profession_lecture
CREATE POLICY pol_documents_requis_par_profession_lecture ON public.documents_requis_par_profession AS PERMISSIVE FOR SELECT TO authenticated
  USING (true);

-- documents_soignants.pol_doc_delete
CREATE POLICY pol_doc_delete ON public.documents_soignants AS PERMISSIVE FOR DELETE TO authenticated
  USING ((( SELECT est_admin() AS est_admin) OR ((soignant_id = ( SELECT auth.uid() AS uid)) AND (statut_verification = ANY (ARRAY['EN_ATTENTE'::statut_verification, 'REJETE'::statut_verification])))));

-- documents_soignants.pol_doc_insert
CREATE POLICY pol_doc_insert ON public.documents_soignants AS PERMISSIVE FOR INSERT TO authenticated
  WITH CHECK ((( SELECT est_admin() AS est_admin) OR ((soignant_id = ( SELECT auth.uid() AS uid)) AND (statut_verification = 'EN_ATTENTE'::statut_verification) AND (verifie_par IS NULL) AND (verifie_le IS NULL) AND (motif_rejet IS NULL))));

-- documents_soignants.pol_doc_select
CREATE POLICY pol_doc_select ON public.documents_soignants AS PERMISSIVE FOR SELECT TO authenticated
  USING (((soignant_id = ( SELECT auth.uid() AS uid)) OR ( SELECT est_admin() AS est_admin)));

-- documents_soignants.pol_doc_update
CREATE POLICY pol_doc_update ON public.documents_soignants AS PERMISSIVE FOR UPDATE TO authenticated
  USING ((( SELECT est_admin() AS est_admin) OR (soignant_id = ( SELECT auth.uid() AS uid))))
  WITH CHECK ((( SELECT est_admin() AS est_admin) OR ((soignant_id = ( SELECT auth.uid() AS uid)) AND (NOT (statut_verification IS DISTINCT FROM 'EN_ATTENTE'::statut_verification)))));

-- email_queue."Admin lit emails"
CREATE POLICY "Admin lit emails" ON public.email_queue AS PERMISSIVE FOR ALL TO public
  USING (est_admin())
  WITH CHECK (est_admin());

-- emails_envoyes.pol_email_select
CREATE POLICY pol_email_select ON public.emails_envoyes AS PERMISSIVE FOR SELECT TO authenticated
  USING (est_admin());

-- emails_post_mission.admin_all_emails_post_mission
CREATE POLICY admin_all_emails_post_mission ON public.emails_post_mission AS PERMISSIVE FOR ALL TO public
  USING (est_admin())
  WITH CHECK (est_admin());

-- equipe_admin.admin_all_equipe_admin
CREATE POLICY admin_all_equipe_admin ON public.equipe_admin AS PERMISSIVE FOR ALL TO public
  USING (est_admin())
  WITH CHECK (est_admin());

-- equipe_membres.etab_own_membres
CREATE POLICY etab_own_membres ON public.equipe_membres AS PERMISSIVE FOR ALL TO authenticated
  USING (((equipe_id IN ( SELECT equipes.id
   FROM equipes
  WHERE (equipes.etablissement_id = mon_etablissement_id()))) OR est_admin()))
  WITH CHECK (((equipe_id IN ( SELECT equipes.id
   FROM equipes
  WHERE (equipes.etablissement_id = mon_etablissement_id()))) OR est_admin()));

-- equipes.etab_own_equipes
CREATE POLICY etab_own_equipes ON public.equipes AS PERMISSIVE FOR ALL TO authenticated
  USING (((etablissement_id = mon_etablissement_id()) OR est_admin()))
  WITH CHECK (((etablissement_id = mon_etablissement_id()) OR est_admin()));

-- equivalences_scolarite.equiv_scolarite_admin_all
CREATE POLICY equiv_scolarite_admin_all ON public.equivalences_scolarite AS PERMISSIVE FOR ALL TO public
  USING (est_admin())
  WITH CHECK (est_admin());

-- etablissements.pol_etab_delete
CREATE POLICY pol_etab_delete ON public.etablissements AS PERMISSIVE FOR DELETE TO authenticated
  USING (est_admin());

-- etablissements.pol_etab_insert
CREATE POLICY pol_etab_insert ON public.etablissements AS PERMISSIVE FOR INSERT TO authenticated
  WITH CHECK (est_admin());

-- etablissements.pol_etab_select
CREATE POLICY pol_etab_select ON public.etablissements AS PERMISSIVE FOR SELECT TO authenticated
  USING (((id = mon_etablissement_id()) OR est_admin() OR (id IN ( SELECT m.etablissement_id
   FROM missions m
  WHERE (m.soignant_assigne_id = ( SELECT auth.uid() AS uid))))));

-- etablissements.pol_etab_update
CREATE POLICY pol_etab_update ON public.etablissements AS PERMISSIVE FOR UPDATE TO authenticated
  USING ((est_admin() OR (id = mon_etablissement_id())));

-- evaluations.pol_eval_insert
CREATE POLICY pol_eval_insert ON public.evaluations AS PERMISSIVE FOR INSERT TO authenticated
  WITH CHECK (((evaluateur_id = ( SELECT auth.uid() AS uid)) AND ((mission_id IN ( SELECT missions.id
   FROM missions
  WHERE (missions.soignant_assigne_id = ( SELECT auth.uid() AS uid)))) OR (mission_id IN ( SELECT missions.id
   FROM missions
  WHERE (missions.etablissement_id = ( SELECT mon_etablissement_id() AS mon_etablissement_id)))) OR ( SELECT est_admin() AS est_admin))));

-- evaluations.pol_eval_select
CREATE POLICY pol_eval_select ON public.evaluations AS PERMISSIVE FOR SELECT TO public
  USING ((( SELECT est_admin() AS est_admin) OR (evaluateur_id = ( SELECT auth.uid() AS uid)) OR (evaluateur_id = ( SELECT mon_etablissement_id() AS mon_etablissement_id)) OR ((evalue_id = ( SELECT auth.uid() AS uid)) AND (visible = true))));

-- evenements_score_etab.pol_evt_score_etab_deny_write
CREATE POLICY pol_evt_score_etab_deny_write ON public.evenements_score_etab AS PERMISSIVE FOR INSERT TO authenticated
  WITH CHECK (false);

-- evenements_score_etab.pol_evt_score_etab_select
CREATE POLICY pol_evt_score_etab_select ON public.evenements_score_etab AS PERMISSIVE FOR SELECT TO authenticated
  USING ((est_admin() OR (etablissement_id = mon_etablissement_id())));

-- evenements_score_soignant.pol_evt_score_sg_deny_write
CREATE POLICY pol_evt_score_sg_deny_write ON public.evenements_score_soignant AS PERMISSIVE FOR INSERT TO authenticated
  WITH CHECK (false);

-- evenements_score_soignant.pol_evt_score_sg_select
CREATE POLICY pol_evt_score_sg_select ON public.evenements_score_soignant AS PERMISSIVE FOR SELECT TO authenticated
  USING ((est_admin() OR (soignant_id = ( SELECT auth.uid() AS uid))));

-- exclusions.pol_exclusion_delete
CREATE POLICY pol_exclusion_delete ON public.exclusions AS PERMISSIVE FOR DELETE TO authenticated
  USING (((exclu_par = ( SELECT auth.uid() AS uid)) OR ( SELECT est_admin() AS est_admin)));

-- exclusions.pol_exclusion_insert
CREATE POLICY pol_exclusion_insert ON public.exclusions AS PERMISSIVE FOR INSERT TO authenticated
  WITH CHECK ((exclu_par = ( SELECT auth.uid() AS uid)));

-- exclusions.pol_exclusion_select
CREATE POLICY pol_exclusion_select ON public.exclusions AS PERMISSIVE FOR SELECT TO authenticated
  USING (((exclu_id = ( SELECT auth.uid() AS uid)) OR (exclu_par = ( SELECT auth.uid() AS uid)) OR ( SELECT est_admin() AS est_admin)));

-- externalisation_actions.pol_ext_actions_admin
CREATE POLICY pol_ext_actions_admin ON public.externalisation_actions AS PERMISSIVE FOR SELECT TO authenticated
  USING (est_admin());

-- factor_advances.pol_factor_advances_admin_write
CREATE POLICY pol_factor_advances_admin_write ON public.factor_advances AS PERMISSIVE FOR ALL TO authenticated
  USING (est_admin())
  WITH CHECK (est_admin());

-- factor_advances.pol_factor_advances_select
CREATE POLICY pol_factor_advances_select ON public.factor_advances AS PERMISSIVE FOR SELECT TO authenticated
  USING ((est_admin() OR (soignant_id = ( SELECT auth.uid() AS uid))));

-- factoring_partners.fp_admin
CREATE POLICY fp_admin ON public.factoring_partners AS PERMISSIVE FOR ALL TO authenticated
  USING (est_admin());

-- factoring_partners.fp_select
CREATE POLICY fp_select ON public.factoring_partners AS PERMISSIVE FOR SELECT TO authenticated
  USING (((active = true) OR est_admin()));

-- factures.pol_fact_delete
CREATE POLICY pol_fact_delete ON public.factures AS PERMISSIVE FOR DELETE TO authenticated
  USING (est_admin());

-- factures.pol_fact_insert
CREATE POLICY pol_fact_insert ON public.factures AS PERMISSIVE FOR INSERT TO authenticated
  WITH CHECK (est_admin());

-- factures.pol_fact_select
CREATE POLICY pol_fact_select ON public.factures AS PERMISSIVE FOR SELECT TO authenticated
  USING ((est_admin() OR (est_admin_etablissement() AND (etablissement_id = mon_etablissement_id()))));

-- factures.pol_fact_update
CREATE POLICY pol_fact_update ON public.factures AS PERMISSIVE FOR UPDATE TO authenticated
  USING (est_admin());

-- factures_honoraires."Admin gère factures honoraires"
CREATE POLICY "Admin gère factures honoraires" ON public.factures_honoraires AS PERMISSIVE FOR ALL TO authenticated
  USING (est_admin())
  WITH CHECK (est_admin());

-- factures_honoraires.fh_select_own
CREATE POLICY fh_select_own ON public.factures_honoraires AS PERMISSIVE FOR SELECT TO authenticated
  USING (((soignant_id = ( SELECT auth.uid() AS uid)) OR (etablissement_id = mon_etablissement_id()) OR est_admin()));

-- favoris_etab_soignant.pol_fav_es_delete
CREATE POLICY pol_fav_es_delete ON public.favoris_etab_soignant AS PERMISSIVE FOR DELETE TO authenticated
  USING ((etablissement_id = mon_etablissement_id()));

-- favoris_etab_soignant.pol_fav_es_insert
CREATE POLICY pol_fav_es_insert ON public.favoris_etab_soignant AS PERMISSIVE FOR INSERT TO authenticated
  WITH CHECK ((etablissement_id = mon_etablissement_id()));

-- favoris_etab_soignant.pol_fav_es_select
CREATE POLICY pol_fav_es_select ON public.favoris_etab_soignant AS PERMISSIVE FOR SELECT TO authenticated
  USING (((etablissement_id = ( SELECT mon_etablissement_id() AS mon_etablissement_id)) OR ( SELECT est_admin() AS est_admin)));

-- favoris_soignant_etab.pol_fav_se_delete
CREATE POLICY pol_fav_se_delete ON public.favoris_soignant_etab AS PERMISSIVE FOR DELETE TO public
  USING ((soignant_id = ( SELECT auth.uid() AS uid)));

-- favoris_soignant_etab.pol_fav_se_insert
CREATE POLICY pol_fav_se_insert ON public.favoris_soignant_etab AS PERMISSIVE FOR INSERT TO public
  WITH CHECK ((soignant_id = ( SELECT auth.uid() AS uid)));

-- favoris_soignant_etab.pol_fav_se_select
CREATE POLICY pol_fav_se_select ON public.favoris_soignant_etab AS PERMISSIVE FOR SELECT TO public
  USING (((soignant_id = ( SELECT auth.uid() AS uid)) OR ( SELECT est_admin() AS est_admin)));

-- file_revue_manuelle.pol_file_revue_insert
CREATE POLICY pol_file_revue_insert ON public.file_revue_manuelle AS PERMISSIVE FOR INSERT TO authenticated
  WITH CHECK (est_admin());

-- file_revue_manuelle.pol_file_revue_select
CREATE POLICY pol_file_revue_select ON public.file_revue_manuelle AS PERMISSIVE FOR SELECT TO authenticated
  USING (est_admin());

-- filtres_sauvegardes.fs_delete_own
CREATE POLICY fs_delete_own ON public.filtres_sauvegardes AS PERMISSIVE FOR DELETE TO authenticated
  USING ((utilisateur_id = ( SELECT auth.uid() AS uid)));

-- filtres_sauvegardes.fs_insert_own
CREATE POLICY fs_insert_own ON public.filtres_sauvegardes AS PERMISSIVE FOR INSERT TO authenticated
  WITH CHECK ((utilisateur_id = ( SELECT auth.uid() AS uid)));

-- filtres_sauvegardes.fs_select_own
CREATE POLICY fs_select_own ON public.filtres_sauvegardes AS PERMISSIVE FOR SELECT TO authenticated
  USING (((utilisateur_id = ( SELECT auth.uid() AS uid)) OR est_admin()));

-- filtres_sauvegardes.fs_update_own
CREATE POLICY fs_update_own ON public.filtres_sauvegardes AS PERMISSIVE FOR UPDATE TO authenticated
  USING ((utilisateur_id = ( SELECT auth.uid() AS uid)))
  WITH CHECK ((utilisateur_id = ( SELECT auth.uid() AS uid)));

-- fondateur_documents.admin_all_fondateur_documents
CREATE POLICY admin_all_fondateur_documents ON public.fondateur_documents AS PERMISSIVE FOR ALL TO public
  USING (est_admin())
  WITH CHECK (est_admin());

-- groupes_sante.pol_grp_select
CREATE POLICY pol_grp_select ON public.groupes_sante AS PERMISSIVE FOR SELECT TO authenticated
  USING ((( SELECT est_admin() AS est_admin) OR (id IN ( SELECT etablissements.groupe_sante_id
   FROM etablissements
  WHERE (etablissements.id = ( SELECT mon_etablissement_id() AS mon_etablissement_id)))) OR (id IN ( SELECT admins_groupe_sante.groupe_id
   FROM admins_groupe_sante
  WHERE (admins_groupe_sante.utilisateur_id = ( SELECT auth.uid() AS uid))))));

-- growth_config.admin_all_growth_config
CREATE POLICY admin_all_growth_config ON public.growth_config AS PERMISSIVE FOR ALL TO public
  USING (est_admin())
  WITH CHECK (est_admin());

-- health_check.pol_health_insert
CREATE POLICY pol_health_insert ON public.health_check AS PERMISSIVE FOR INSERT TO authenticated
  WITH CHECK (est_admin());

-- health_check.pol_health_select
CREATE POLICY pol_health_select ON public.health_check AS PERMISSIVE FOR SELECT TO authenticated
  USING (est_admin());

-- heures_externes.pol_hext_delete
CREATE POLICY pol_hext_delete ON public.heures_externes AS PERMISSIVE FOR DELETE TO authenticated
  USING (est_admin());

-- heures_externes.pol_hext_insert
CREATE POLICY pol_hext_insert ON public.heures_externes AS PERMISSIVE FOR INSERT TO authenticated
  WITH CHECK ((( SELECT est_admin() AS est_admin) OR ((soignant_id = ( SELECT auth.uid() AS uid)) AND (statut = 'EN_ATTENTE'::text) AND (validee_par IS NULL) AND (validee_le IS NULL) AND (motif_rejet IS NULL))));

-- heures_externes.pol_hext_select
CREATE POLICY pol_hext_select ON public.heures_externes AS PERMISSIVE FOR SELECT TO authenticated
  USING (((soignant_id = ( SELECT auth.uid() AS uid)) OR ( SELECT est_admin() AS est_admin)));

-- heures_externes.pol_hext_update
CREATE POLICY pol_hext_update ON public.heures_externes AS PERMISSIVE FOR UPDATE TO authenticated
  USING (est_admin());

-- heures_externes_soignants.soignant_gere_ses_heures_externes
CREATE POLICY soignant_gere_ses_heures_externes ON public.heures_externes_soignants AS PERMISSIVE FOR INSERT TO authenticated
  WITH CHECK ((soignant_id = ( SELECT auth.uid() AS uid)));

-- heures_externes_soignants.soignant_modifie_ses_heures_externes
CREATE POLICY soignant_modifie_ses_heures_externes ON public.heures_externes_soignants AS PERMISSIVE FOR UPDATE TO authenticated
  USING ((((soignant_id = ( SELECT auth.uid() AS uid)) AND (statut_validation = 'EN_ATTENTE'::text)) OR est_admin()))
  WITH CHECK (((soignant_id = ( SELECT auth.uid() AS uid)) OR est_admin()));

-- heures_externes_soignants.soignant_supprime_ses_heures_en_attente
CREATE POLICY soignant_supprime_ses_heures_en_attente ON public.heures_externes_soignants AS PERMISSIVE FOR DELETE TO authenticated
  USING (((soignant_id = ( SELECT auth.uid() AS uid)) AND (statut_validation = 'EN_ATTENTE'::text)));

-- heures_externes_soignants.soignant_voit_ses_heures_externes
CREATE POLICY soignant_voit_ses_heures_externes ON public.heures_externes_soignants AS PERMISSIVE FOR SELECT TO authenticated
  USING (((soignant_id = ( SELECT auth.uid() AS uid)) OR est_admin()));

-- historique_blocages_etablissements.historique_blocages_select
CREATE POLICY historique_blocages_select ON public.historique_blocages_etablissements AS PERMISSIVE FOR SELECT TO authenticated
  USING ((est_admin() OR (etablissement_id = mon_etablissement_id())));

-- investisseurs_pipeline.admin_all_investisseurs
CREATE POLICY admin_all_investisseurs ON public.investisseurs_pipeline AS PERMISSIVE FOR ALL TO public
  USING (est_admin())
  WITH CHECK (est_admin());

-- invitations_etablissement.pol_invitations_etab_select
CREATE POLICY pol_invitations_etab_select ON public.invitations_etablissement AS PERMISSIVE FOR SELECT TO authenticated
  USING (((EXISTS ( SELECT 1
   FROM membres_etablissement m
  WHERE ((m.etablissement_id = invitations_etablissement.etablissement_id) AND (m.user_id = ( SELECT auth.uid() AS uid)) AND (m.actif = true) AND (m.role = ANY (ARRAY['PROPRIETAIRE'::text, 'ADMIN_GROUPE'::text]))))) OR (invite_par = ( SELECT auth.uid() AS uid)) OR est_admin()));

-- invoice_audit_log.ial_select
CREATE POLICY ial_select ON public.invoice_audit_log AS PERMISSIVE FOR SELECT TO authenticated
  USING ((EXISTS ( SELECT 1
   FROM factures_honoraires fh
  WHERE ((fh.id = invoice_audit_log.invoice_id) AND ((fh.soignant_id = ( SELECT auth.uid() AS uid)) OR est_admin())))));

-- journaux_audit.pol_audit_insert
CREATE POLICY pol_audit_insert ON public.journaux_audit AS PERMISSIVE FOR INSERT TO authenticated
  WITH CHECK (((acteur_id = ( SELECT auth.uid() AS uid)) OR (acteur_id IS NULL)));

-- journaux_audit.pol_audit_select
CREATE POLICY pol_audit_select ON public.journaux_audit AS PERMISSIVE FOR SELECT TO authenticated
  USING (est_admin());

-- jours_feries_fr.pol_jours_feries_fr_lecture
CREATE POLICY pol_jours_feries_fr_lecture ON public.jours_feries_fr AS PERMISSIVE FOR SELECT TO authenticated
  USING (true);

-- liste_attente_premium.pol_liste_insert
CREATE POLICY pol_liste_insert ON public.liste_attente_premium AS PERMISSIVE FOR INSERT TO authenticated
  WITH CHECK (((utilisateur_id = ( SELECT auth.uid() AS uid)) AND (email = (( SELECT users.email
   FROM auth.users
  WHERE (users.id = ( SELECT auth.uid() AS uid))))::text)));

-- liste_attente_premium.pol_liste_select
CREATE POLICY pol_liste_select ON public.liste_attente_premium AS PERMISSIVE FOR SELECT TO authenticated
  USING (est_admin());

-- litiges.pol_litige_insert
CREATE POLICY pol_litige_insert ON public.litiges AS PERMISSIVE FOR INSERT TO authenticated
  WITH CHECK ((( SELECT est_admin() AS est_admin) OR ((soignant_id = ( SELECT auth.uid() AS uid)) AND (mission_id IN ( SELECT missions.id
   FROM missions
  WHERE (missions.soignant_assigne_id = ( SELECT auth.uid() AS uid))))) OR ((etablissement_id = ( SELECT mon_etablissement_id() AS mon_etablissement_id)) AND (mission_id IN ( SELECT missions.id
   FROM missions
  WHERE (missions.etablissement_id = ( SELECT mon_etablissement_id() AS mon_etablissement_id)))))));

-- litiges.pol_litige_select
CREATE POLICY pol_litige_select ON public.litiges AS PERMISSIVE FOR SELECT TO authenticated
  USING ((( SELECT est_admin() AS est_admin) OR (soignant_id = ( SELECT auth.uid() AS uid)) OR (etablissement_id = ( SELECT mon_etablissement_id() AS mon_etablissement_id))));

-- litiges.pol_litige_update
CREATE POLICY pol_litige_update ON public.litiges AS PERMISSIVE FOR UPDATE TO authenticated
  USING ((( SELECT est_admin() AS est_admin) OR ((initie_par = 'ETABLISSEMENT'::text) AND (soignant_id = ( SELECT auth.uid() AS uid)) AND (statut = ANY (ARRAY['OUVERT'::text, 'EN_DISCUSSION'::text]))) OR ((initie_par = 'SOIGNANT'::text) AND (etablissement_id = ( SELECT mon_etablissement_id() AS mon_etablissement_id)) AND (statut = ANY (ARRAY['OUVERT'::text, 'EN_DISCUSSION'::text])))));

-- mandats_facturation_signatures.pol_mandats_select
CREATE POLICY pol_mandats_select ON public.mandats_facturation_signatures AS PERMISSIVE FOR SELECT TO authenticated
  USING ((est_admin() OR (soignant_id = ( SELECT auth.uid() AS uid))));

-- marche_taux_medians.pol_marche_medians_select
CREATE POLICY pol_marche_medians_select ON public.marche_taux_medians AS PERMISSIVE FOR SELECT TO authenticated
  USING (true);

-- matching_preferences_soignant.pol_matching_prefs_select
CREATE POLICY pol_matching_prefs_select ON public.matching_preferences_soignant AS PERMISSIVE FOR SELECT TO authenticated
  USING ((soignant_id = ( SELECT auth.uid() AS uid)));

-- matching_scores.matching_scores_select_own
CREATE POLICY matching_scores_select_own ON public.matching_scores AS PERMISSIVE FOR SELECT TO public
  USING ((soignant_id = ( SELECT auth.uid() AS uid)));

-- matching_scores.matching_scores_service_role
CREATE POLICY matching_scores_service_role ON public.matching_scores AS PERMISSIVE FOR ALL TO service_role
  USING (true)
  WITH CHECK (true);

-- membres_etablissement.pol_membres_etab_select
CREATE POLICY pol_membres_etab_select ON public.membres_etablissement AS PERMISSIVE FOR SELECT TO authenticated
  USING (((user_id = ( SELECT auth.uid() AS uid)) OR (EXISTS ( SELECT 1
   FROM membres_etablissement m
  WHERE ((m.etablissement_id = membres_etablissement.etablissement_id) AND (m.user_id = ( SELECT auth.uid() AS uid)) AND (m.actif = true)))) OR est_admin()));

-- messages_chat.pol_mchat_delete
CREATE POLICY pol_mchat_delete ON public.messages_chat AS PERMISSIVE FOR DELETE TO authenticated
  USING (( SELECT est_admin() AS est_admin));

-- messages_chat.pol_mchat_update
CREATE POLICY pol_mchat_update ON public.messages_chat AS PERMISSIVE FOR UPDATE TO authenticated
  USING ((( SELECT est_admin() AS est_admin) OR (conversation_id IN ( SELECT conversations.id
   FROM conversations
  WHERE ((conversations.participant_1_id = ( SELECT auth.uid() AS uid)) OR (conversations.participant_2_id = ( SELECT auth.uid() AS uid)))))));

-- messages_chat.pol_msg_chat_insert
CREATE POLICY pol_msg_chat_insert ON public.messages_chat AS PERMISSIVE FOR INSERT TO authenticated
  WITH CHECK (((auteur_id = ( SELECT auth.uid() AS uid)) AND (NOT (EXISTS ( SELECT 1
   FROM conversations c
  WHERE ((c.id = messages_chat.conversation_id) AND (c.archived_at IS NOT NULL)))))));

-- messages_chat.pol_msg_select
CREATE POLICY pol_msg_select ON public.messages_chat AS PERMISSIVE FOR SELECT TO authenticated
  USING ((( SELECT est_admin() AS est_admin) OR (auteur_id = ( SELECT auth.uid() AS uid)) OR (conversation_id IN ( SELECT conversations.id
   FROM conversations
  WHERE ((conversations.participant_1_id = ( SELECT auth.uid() AS uid)) OR (conversations.participant_2_id = ( SELECT auth.uid() AS uid)))))));

-- messages_contact.messages_contact_admin_all
CREATE POLICY messages_contact_admin_all ON public.messages_contact AS PERMISSIVE FOR ALL TO authenticated
  USING (est_admin())
  WITH CHECK (est_admin());

-- messages_contact.messages_contact_insert_self
CREATE POLICY messages_contact_insert_self ON public.messages_contact AS PERMISSIVE FOR INSERT TO authenticated
  WITH CHECK ((expediteur_id = ( SELECT auth.uid() AS uid)));

-- messages_contact.messages_contact_select_self
CREATE POLICY messages_contact_select_self ON public.messages_contact AS PERMISSIVE FOR SELECT TO authenticated
  USING ((expediteur_id = ( SELECT auth.uid() AS uid)));

-- messages_litige.pol_messages_litige_insert
CREATE POLICY pol_messages_litige_insert ON public.messages_litige AS PERMISSIVE FOR INSERT TO public
  WITH CHECK ((auteur_id = ( SELECT auth.uid() AS uid)));

-- messages_litige.pol_messages_litige_select
CREATE POLICY pol_messages_litige_select ON public.messages_litige AS PERMISSIVE FOR SELECT TO public
  USING (((auteur_id = ( SELECT auth.uid() AS uid)) OR (EXISTS ( SELECT 1
   FROM litiges l
  WHERE ((l.id = messages_litige.litige_id) AND ((l.soignant_id = ( SELECT auth.uid() AS uid)) OR (l.etablissement_id = mon_etablissement_id()))))) OR est_admin()));

-- messages_mission.pol_msg_insert
CREATE POLICY pol_msg_insert ON public.messages_mission AS PERMISSIVE FOR INSERT TO authenticated
  WITH CHECK ((( SELECT est_admin() AS est_admin) OR (mission_id IN ( SELECT missions.id
   FROM missions
  WHERE (missions.soignant_assigne_id = ( SELECT auth.uid() AS uid)))) OR (mission_id IN ( SELECT missions.id
   FROM missions
  WHERE (missions.etablissement_id = ( SELECT mon_etablissement_id() AS mon_etablissement_id))))));

-- messages_mission.pol_msg_miss_delete
CREATE POLICY pol_msg_miss_delete ON public.messages_mission AS PERMISSIVE FOR DELETE TO authenticated
  USING (( SELECT est_admin() AS est_admin));

-- messages_mission.pol_msg_miss_update
CREATE POLICY pol_msg_miss_update ON public.messages_mission AS PERMISSIVE FOR UPDATE TO authenticated
  USING ((( SELECT est_admin() AS est_admin) OR (mission_id IN ( SELECT missions.id
   FROM missions
  WHERE (missions.soignant_assigne_id = ( SELECT auth.uid() AS uid)))) OR (mission_id IN ( SELECT missions.id
   FROM missions
  WHERE (missions.etablissement_id = ( SELECT mon_etablissement_id() AS mon_etablissement_id))))))
  WITH CHECK ((( SELECT est_admin() AS est_admin) OR (mission_id IN ( SELECT missions.id
   FROM missions
  WHERE (missions.soignant_assigne_id = ( SELECT auth.uid() AS uid)))) OR (mission_id IN ( SELECT missions.id
   FROM missions
  WHERE (missions.etablissement_id = ( SELECT mon_etablissement_id() AS mon_etablissement_id))))));

-- messages_mission.pol_msg_select
CREATE POLICY pol_msg_select ON public.messages_mission AS PERMISSIVE FOR SELECT TO authenticated
  USING ((( SELECT est_admin() AS est_admin) OR (auteur_id = ( SELECT auth.uid() AS uid)) OR (mission_id IN ( SELECT missions.id
   FROM missions
  WHERE (missions.soignant_assigne_id = ( SELECT auth.uid() AS uid)))) OR (mission_id IN ( SELECT missions.id
   FROM missions
  WHERE (missions.etablissement_id = ( SELECT mon_etablissement_id() AS mon_etablissement_id))))));

-- mission_creneaux.mc_delete
CREATE POLICY mc_delete ON public.mission_creneaux AS PERMISSIVE FOR DELETE TO public
  USING (est_admin());

-- mission_creneaux.mc_insert
CREATE POLICY mc_insert ON public.mission_creneaux AS PERMISSIVE FOR INSERT TO public
  WITH CHECK ((EXISTS ( SELECT 1
   FROM missions m
  WHERE ((m.id = mission_creneaux.mission_id) AND (est_admin() OR (m.etablissement_id = mon_etablissement_id()))))));

-- mission_creneaux.mc_select
CREATE POLICY mc_select ON public.mission_creneaux AS PERMISSIVE FOR SELECT TO public
  USING ((EXISTS ( SELECT 1
   FROM missions m
  WHERE ((m.id = mission_creneaux.mission_id) AND (est_admin() OR (m.etablissement_id = mon_etablissement_id()) OR (m.soignant_assigne_id = ( SELECT auth.uid() AS uid)) OR (est_soignant() AND (m.statut = 'OUVERTE'::statut_mission)))))));

-- mission_creneaux.mc_update
CREATE POLICY mc_update ON public.mission_creneaux AS PERMISSIVE FOR UPDATE TO public
  USING ((EXISTS ( SELECT 1
   FROM missions m
  WHERE ((m.id = mission_creneaux.mission_id) AND (est_admin() OR (m.etablissement_id = mon_etablissement_id()))))));

-- mission_series.ms_delete
CREATE POLICY ms_delete ON public.mission_series AS PERMISSIVE FOR DELETE TO public
  USING (est_admin());

-- mission_series.ms_insert
CREATE POLICY ms_insert ON public.mission_series AS PERMISSIVE FOR INSERT TO public
  WITH CHECK ((est_admin() OR (etablissement_id = mon_etablissement_id())));

-- mission_series.ms_select
CREATE POLICY ms_select ON public.mission_series AS PERMISSIVE FOR SELECT TO public
  USING ((est_admin() OR (etablissement_id = mon_etablissement_id())));

-- mission_series.ms_update
CREATE POLICY ms_update ON public.mission_series AS PERMISSIVE FOR UPDATE TO public
  USING (est_admin());

-- missions.missions_masquer_etabs_test (RESTRICTIVE)
CREATE POLICY missions_masquer_etabs_test ON public.missions AS RESTRICTIVE FOR SELECT TO authenticated
  USING (((NOT fn_est_etab_test(etablissement_id)) OR (NOT fn_suis_soignant_reel())));

-- missions.pol_mission_delete
CREATE POLICY pol_mission_delete ON public.missions AS PERMISSIVE FOR DELETE TO authenticated
  USING (est_admin());

-- missions.pol_mission_insert
CREATE POLICY pol_mission_insert ON public.missions AS PERMISSIVE FOR INSERT TO authenticated
  WITH CHECK ((est_admin() OR (est_admin_etablissement() AND (etablissement_id = mon_etablissement_id()))));

-- missions.pol_mission_select
CREATE POLICY pol_mission_select ON public.missions AS PERMISSIVE FOR SELECT TO authenticated
  USING ((( SELECT est_admin() AS est_admin) OR (etablissement_id = ( SELECT mon_etablissement_id() AS mon_etablissement_id)) OR (soignant_assigne_id = ( SELECT auth.uid() AS uid)) OR (( SELECT est_soignant() AS est_soignant) AND (statut = 'OUVERTE'::statut_mission) AND (NOT fn_est_exclu(( SELECT auth.uid() AS uid), etablissement_id)))));

-- missions.pol_mission_update
CREATE POLICY pol_mission_update ON public.missions AS PERMISSIVE FOR UPDATE TO authenticated
  USING ((est_admin() OR (etablissement_id = mon_etablissement_id())));

-- missions_sauvegardees.missions_sauvegardees_delete
CREATE POLICY missions_sauvegardees_delete ON public.missions_sauvegardees AS PERMISSIVE FOR DELETE TO authenticated
  USING ((soignant_id = auth.uid()));

-- missions_sauvegardees.missions_sauvegardees_insert
CREATE POLICY missions_sauvegardees_insert ON public.missions_sauvegardees AS PERMISSIVE FOR INSERT TO authenticated
  WITH CHECK ((soignant_id = auth.uid()));

-- missions_sauvegardees.missions_sauvegardees_select
CREATE POLICY missions_sauvegardees_select ON public.missions_sauvegardees AS PERMISSIVE FOR SELECT TO authenticated
  USING ((soignant_id = auth.uid()));

-- notations_missions.pol_notations_insert
CREATE POLICY pol_notations_insert ON public.notations_missions AS PERMISSIVE FOR INSERT TO public
  WITH CHECK (((notateur_id = ANY (ARRAY[( SELECT auth.uid() AS uid), COALESCE(mon_etablissement_id(), '00000000-0000-0000-0000-000000000000'::uuid)])) OR ( SELECT est_admin() AS est_admin)));

-- notations_missions.pol_notations_select
CREATE POLICY pol_notations_select ON public.notations_missions AS PERMISSIVE FOR SELECT TO public
  USING ((((note_id = ( SELECT auth.uid() AS uid)) AND (masque = false)) OR ((note_id = mon_etablissement_id()) AND (masque = false)) OR (notateur_id = ( SELECT auth.uid() AS uid)) OR (notateur_id = mon_etablissement_id()) OR ( SELECT est_admin() AS est_admin)));

-- notations_missions.pol_notations_update
CREATE POLICY pol_notations_update ON public.notations_missions AS PERMISSIVE FOR UPDATE TO public
  USING (((notateur_id = ANY (ARRAY[( SELECT auth.uid() AS uid), COALESCE(mon_etablissement_id(), '00000000-0000-0000-0000-000000000000'::uuid)])) OR ( SELECT est_admin() AS est_admin)));

-- notifications.pol_notif_delete
CREATE POLICY pol_notif_delete ON public.notifications AS PERMISSIVE FOR DELETE TO authenticated
  USING (est_admin());

-- notifications.pol_notif_insert
CREATE POLICY pol_notif_insert ON public.notifications AS PERMISSIVE FOR INSERT TO authenticated
  WITH CHECK (((destinataire_id = ( SELECT auth.uid() AS uid)) OR ( SELECT est_admin() AS est_admin)));

-- notifications.pol_notif_select
CREATE POLICY pol_notif_select ON public.notifications AS PERMISSIVE FOR SELECT TO authenticated
  USING (((destinataire_id = ( SELECT auth.uid() AS uid)) OR ( SELECT est_admin() AS est_admin)));

-- notifications.pol_notif_update
CREATE POLICY pol_notif_update ON public.notifications AS PERMISSIVE FOR UPDATE TO authenticated
  USING ((destinataire_id = ( SELECT auth.uid() AS uid)));

-- notifications_notation_j1.pol_notif_notation_j1_select
CREATE POLICY pol_notif_notation_j1_select ON public.notifications_notation_j1 AS PERMISSIVE FOR SELECT TO public
  USING (((destinataire_id = ( SELECT auth.uid() AS uid)) OR (destinataire_id = mon_etablissement_id()) OR ( SELECT est_admin() AS est_admin)));

-- otps_telephone.otps_tel_self_select
CREATE POLICY otps_tel_self_select ON public.otps_telephone AS PERMISSIVE FOR SELECT TO authenticated
  USING ((user_id = ( SELECT auth.uid() AS uid)));

-- paiements_mission.pol_paie_mission_delete
CREATE POLICY pol_paie_mission_delete ON public.paiements_mission AS PERMISSIVE FOR DELETE TO authenticated
  USING (est_admin());

-- paiements_mission.pol_paim_insert
CREATE POLICY pol_paim_insert ON public.paiements_mission AS PERMISSIVE FOR INSERT TO authenticated
  WITH CHECK (est_admin());

-- paiements_mission.pol_paim_select
CREATE POLICY pol_paim_select ON public.paiements_mission AS PERMISSIVE FOR SELECT TO authenticated
  USING (((etablissement_id = mon_etablissement_id()) OR est_admin()));

-- paiements_mission.pol_paim_update
CREATE POLICY pol_paim_update ON public.paiements_mission AS PERMISSIVE FOR UPDATE TO authenticated
  USING (est_admin());

-- paiements_soignant.pol_paie_soig_delete
CREATE POLICY pol_paie_soig_delete ON public.paiements_soignant AS PERMISSIVE FOR DELETE TO authenticated
  USING (est_admin());

-- paiements_soignant.pol_paie_soig_insert
CREATE POLICY pol_paie_soig_insert ON public.paiements_soignant AS PERMISSIVE FOR INSERT TO authenticated
  WITH CHECK (((etablissement_id = mon_etablissement_id()) OR est_admin()));

-- paiements_soignant.pol_paie_soig_select
CREATE POLICY pol_paie_soig_select ON public.paiements_soignant AS PERMISSIVE FOR SELECT TO authenticated
  USING (((soignant_id = ( SELECT auth.uid() AS uid)) OR (etablissement_id = ( SELECT mon_etablissement_id() AS mon_etablissement_id)) OR ( SELECT est_admin() AS est_admin)));

-- paiements_soignant.pol_paie_soig_update
CREATE POLICY pol_paie_soig_update ON public.paiements_soignant AS PERMISSIVE FOR UPDATE TO authenticated
  USING (((soignant_id = ( SELECT auth.uid() AS uid)) OR (etablissement_id = ( SELECT mon_etablissement_id() AS mon_etablissement_id)) OR ( SELECT est_admin() AS est_admin)));

-- paliers_bfa.pol_paliers_bfa_lecture
CREATE POLICY pol_paliers_bfa_lecture ON public.paliers_bfa AS PERMISSIVE FOR SELECT TO authenticated
  USING (true);

-- paliers_commission.pol_paliers_commission_lecture
CREATE POLICY pol_paliers_commission_lecture ON public.paliers_commission AS PERMISSIVE FOR SELECT TO authenticated
  USING (true);

-- parametres_litiges.pol_param_litiges_delete_admin
CREATE POLICY pol_param_litiges_delete_admin ON public.parametres_litiges AS PERMISSIVE FOR DELETE TO authenticated
  USING (est_admin());

-- parametres_litiges.pol_param_litiges_insert_admin
CREATE POLICY pol_param_litiges_insert_admin ON public.parametres_litiges AS PERMISSIVE FOR INSERT TO authenticated
  WITH CHECK (est_admin());

-- parametres_litiges.pol_param_litiges_select
CREATE POLICY pol_param_litiges_select ON public.parametres_litiges AS PERMISSIVE FOR SELECT TO authenticated
  USING (true);

-- parametres_litiges.pol_param_litiges_update_admin
CREATE POLICY pol_param_litiges_update_admin ON public.parametres_litiges AS PERMISSIVE FOR UPDATE TO authenticated
  USING (est_admin())
  WITH CHECK (est_admin());

-- parametres_systeme.pol_parametres_systeme_admin
CREATE POLICY pol_parametres_systeme_admin ON public.parametres_systeme AS PERMISSIVE FOR ALL TO authenticated
  USING (est_admin())
  WITH CHECK (est_admin());

-- parcours_liberal_soignants.soignant_cree_son_parcours
CREATE POLICY soignant_cree_son_parcours ON public.parcours_liberal_soignants AS PERMISSIVE FOR INSERT TO authenticated
  WITH CHECK ((soignant_id = ( SELECT auth.uid() AS uid)));

-- parcours_liberal_soignants.soignant_modifie_son_parcours
CREATE POLICY soignant_modifie_son_parcours ON public.parcours_liberal_soignants AS PERMISSIVE FOR UPDATE TO authenticated
  USING ((soignant_id = ( SELECT auth.uid() AS uid)))
  WITH CHECK ((soignant_id = ( SELECT auth.uid() AS uid)));

-- parcours_liberal_soignants.soignant_voit_son_parcours
CREATE POLICY soignant_voit_son_parcours ON public.parcours_liberal_soignants AS PERMISSIVE FOR SELECT TO authenticated
  USING (((soignant_id = ( SELECT auth.uid() AS uid)) OR est_admin()));

-- parrainage_fraude_signals.pol_fraude_signals_admin
CREATE POLICY pol_fraude_signals_admin ON public.parrainage_fraude_signals AS PERMISSIVE FOR ALL TO public
  USING (est_admin());

-- parrainages.pol_parr_insert
CREATE POLICY pol_parr_insert ON public.parrainages AS PERMISSIVE FOR INSERT TO authenticated
  WITH CHECK (((parrain_id = ( SELECT auth.uid() AS uid)) OR ( SELECT est_admin() AS est_admin)));

-- parrainages.pol_parr_select
CREATE POLICY pol_parr_select ON public.parrainages AS PERMISSIVE FOR SELECT TO authenticated
  USING (((parrain_id = ( SELECT auth.uid() AS uid)) OR (filleul_id = ( SELECT auth.uid() AS uid)) OR ( SELECT est_admin() AS est_admin)));

-- parrainages_etablissements.pol_parr_etab_insert
CREATE POLICY pol_parr_etab_insert ON public.parrainages_etablissements AS PERMISSIVE FOR INSERT TO public
  WITH CHECK (((filleul_etab_id = mon_etablissement_id()) OR ( SELECT est_admin() AS est_admin)));

-- parrainages_etablissements.pol_parr_etab_select
CREATE POLICY pol_parr_etab_select ON public.parrainages_etablissements AS PERMISSIVE FOR SELECT TO public
  USING (((parrain_etab_id = mon_etablissement_id()) OR (filleul_etab_id = mon_etablissement_id()) OR ( SELECT est_admin() AS est_admin)));

-- partages_rib.pol_rib_delete
CREATE POLICY pol_rib_delete ON public.partages_rib AS PERMISSIVE FOR DELETE TO authenticated
  USING (est_admin());

-- partages_rib.pol_rib_insert
CREATE POLICY pol_rib_insert ON public.partages_rib AS PERMISSIVE FOR INSERT TO authenticated
  WITH CHECK (( SELECT est_admin() AS est_admin));

-- partages_rib.pol_rib_select
CREATE POLICY pol_rib_select ON public.partages_rib AS PERMISSIVE FOR SELECT TO authenticated
  USING (((actif = true) AND ((expire_le IS NULL) OR (expire_le > now())) AND ((soignant_id = ( SELECT auth.uid() AS uid)) OR (etablissement_id = ( SELECT mon_etablissement_id() AS mon_etablissement_id)) OR ( SELECT est_admin() AS est_admin))));

-- pauses_presence.pol_pause_insert
CREATE POLICY pol_pause_insert ON public.pauses_presence AS PERMISSIVE FOR INSERT TO authenticated
  WITH CHECK ((soignant_id = ( SELECT auth.uid() AS uid)));

-- pauses_presence.pol_pause_select
CREATE POLICY pol_pause_select ON public.pauses_presence AS PERMISSIVE FOR SELECT TO authenticated
  USING (((soignant_id = ( SELECT auth.uid() AS uid)) OR ( SELECT est_admin() AS est_admin) OR (EXISTS ( SELECT 1
   FROM (presences p
     JOIN missions m ON ((m.id = p.mission_id)))
  WHERE ((p.id = pauses_presence.presence_id) AND (m.etablissement_id = ( SELECT mon_etablissement_id() AS mon_etablissement_id)))))));

-- pings_gps_mission.pol_pings_gps_select
CREATE POLICY pol_pings_gps_select ON public.pings_gps_mission AS PERMISSIVE FOR SELECT TO authenticated
  USING (((soignant_id = ( SELECT auth.uid() AS uid)) OR (EXISTS ( SELECT 1
   FROM missions m
  WHERE ((m.id = pings_gps_mission.mission_id) AND (m.etablissement_id = mon_etablissement_id())))) OR est_admin()));

-- plans_prevoyance.pol_plans_prevoyance_lecture
CREATE POLICY pol_plans_prevoyance_lecture ON public.plans_prevoyance AS PERMISSIVE FOR SELECT TO authenticated
  USING (true);

-- preferences_notifications.pn_insert_own
CREATE POLICY pn_insert_own ON public.preferences_notifications AS PERMISSIVE FOR INSERT TO authenticated
  WITH CHECK ((utilisateur_id = ( SELECT auth.uid() AS uid)));

-- preferences_notifications.pn_select_own
CREATE POLICY pn_select_own ON public.preferences_notifications AS PERMISSIVE FOR SELECT TO authenticated
  USING (((utilisateur_id = ( SELECT auth.uid() AS uid)) OR est_admin()));

-- preferences_notifications.pn_update_own
CREATE POLICY pn_update_own ON public.preferences_notifications AS PERMISSIVE FOR UPDATE TO authenticated
  USING ((utilisateur_id = ( SELECT auth.uid() AS uid)))
  WITH CHECK ((utilisateur_id = ( SELECT auth.uid() AS uid)));

-- preferences_notifications_par_evenement.pnpe_delete_own
CREATE POLICY pnpe_delete_own ON public.preferences_notifications_par_evenement AS PERMISSIVE FOR DELETE TO authenticated
  USING ((utilisateur_id = ( SELECT auth.uid() AS uid)));

-- preferences_notifications_par_evenement.pnpe_insert_own
CREATE POLICY pnpe_insert_own ON public.preferences_notifications_par_evenement AS PERMISSIVE FOR INSERT TO authenticated
  WITH CHECK ((utilisateur_id = ( SELECT auth.uid() AS uid)));

-- preferences_notifications_par_evenement.pnpe_select_own
CREATE POLICY pnpe_select_own ON public.preferences_notifications_par_evenement AS PERMISSIVE FOR SELECT TO authenticated
  USING (((utilisateur_id = ( SELECT auth.uid() AS uid)) OR est_admin()));

-- preferences_notifications_par_evenement.pnpe_update_own
CREATE POLICY pnpe_update_own ON public.preferences_notifications_par_evenement AS PERMISSIVE FOR UPDATE TO authenticated
  USING ((utilisateur_id = ( SELECT auth.uid() AS uid)))
  WITH CHECK ((utilisateur_id = ( SELECT auth.uid() AS uid)));

-- presence_status.pol_presence_status_insert
CREATE POLICY pol_presence_status_insert ON public.presence_status AS PERMISSIVE FOR INSERT TO authenticated
  WITH CHECK ((user_id = ( SELECT auth.uid() AS uid)));

-- presence_status.pol_presence_status_select
CREATE POLICY pol_presence_status_select ON public.presence_status AS PERMISSIVE FOR SELECT TO authenticated
  USING (true);

-- presence_status.pol_presence_status_update
CREATE POLICY pol_presence_status_update ON public.presence_status AS PERMISSIVE FOR UPDATE TO authenticated
  USING ((user_id = ( SELECT auth.uid() AS uid)))
  WITH CHECK ((user_id = ( SELECT auth.uid() AS uid)));

-- presences.pol_pres_delete
CREATE POLICY pol_pres_delete ON public.presences AS PERMISSIVE FOR DELETE TO authenticated
  USING (est_admin());

-- presences.pol_pres_insert
CREATE POLICY pol_pres_insert ON public.presences AS PERMISSIVE FOR INSERT TO authenticated
  WITH CHECK (((soignant_id = ( SELECT auth.uid() AS uid)) OR ( SELECT est_admin() AS est_admin) OR (mission_id IN ( SELECT missions.id
   FROM missions
  WHERE (missions.etablissement_id = ( SELECT mon_etablissement_id() AS mon_etablissement_id))))));

-- presences.pol_pres_select
CREATE POLICY pol_pres_select ON public.presences AS PERMISSIVE FOR SELECT TO authenticated
  USING ((( SELECT est_admin() AS est_admin) OR (soignant_id = ( SELECT auth.uid() AS uid)) OR (( SELECT est_admin_etablissement() AS est_admin_etablissement) AND (mission_id IN ( SELECT missions.id
   FROM missions
  WHERE (missions.etablissement_id = ( SELECT mon_etablissement_id() AS mon_etablissement_id)))))));

-- presences.pol_pres_update
CREATE POLICY pol_pres_update ON public.presences AS PERMISSIVE FOR UPDATE TO authenticated
  USING ((( SELECT est_admin() AS est_admin) OR (( SELECT est_admin_etablissement() AS est_admin_etablissement) AND (mission_id IN ( SELECT missions.id
   FROM missions
  WHERE (missions.etablissement_id = ( SELECT mon_etablissement_id() AS mon_etablissement_id)))))));

-- prevoyance_liste_attente.pol_prev_la_insert
CREATE POLICY pol_prev_la_insert ON public.prevoyance_liste_attente AS PERMISSIVE FOR INSERT TO public
  WITH CHECK (((soignant_id IS NULL) OR (soignant_id = ( SELECT auth.uid() AS uid))));

-- prevoyance_liste_attente.pol_prev_la_select
CREATE POLICY pol_prev_la_select ON public.prevoyance_liste_attente AS PERMISSIVE FOR SELECT TO public
  USING (((soignant_id = ( SELECT auth.uid() AS uid)) OR ( SELECT est_admin() AS est_admin)));

-- prevoyance_liste_attente.pol_prev_la_update
CREATE POLICY pol_prev_la_update ON public.prevoyance_liste_attente AS PERMISSIVE FOR UPDATE TO public
  USING (((soignant_id = ( SELECT auth.uid() AS uid)) OR ( SELECT est_admin() AS est_admin)));

-- professions_liberal_eligible.pol_professions_liberal_eligible_lecture
CREATE POLICY pol_professions_liberal_eligible_lecture ON public.professions_liberal_eligible AS PERMISSIVE FOR SELECT TO authenticated
  USING (true);

-- prospects_etablissements.admin_all_prospects_etab
CREATE POLICY admin_all_prospects_etab ON public.prospects_etablissements AS PERMISSIVE FOR ALL TO public
  USING (est_admin())
  WITH CHECK (est_admin());

-- prospects_soignants.admin_all_prospects_soignants
CREATE POLICY admin_all_prospects_soignants ON public.prospects_soignants AS PERMISSIVE FOR ALL TO public
  USING (est_admin())
  WITH CHECK (est_admin());

-- psc_auth_sessions.pol_psc_auth_sessions_deny_all
CREATE POLICY pol_psc_auth_sessions_deny_all ON public.psc_auth_sessions AS PERMISSIVE FOR ALL TO anon, authenticated
  USING (false)
  WITH CHECK (false);

-- qr_codes_mission.pol_qr_codes_select
CREATE POLICY pol_qr_codes_select ON public.qr_codes_mission AS PERMISSIVE FOR SELECT TO authenticated
  USING ((est_admin() OR (EXISTS ( SELECT 1
   FROM missions m
  WHERE ((m.id = qr_codes_mission.mission_id) AND ((m.soignant_assigne_id = ( SELECT auth.uid() AS uid)) OR (m.etablissement_id = mon_etablissement_id())))))));

-- rappels_contrat_travail.rct_admin_select
CREATE POLICY rct_admin_select ON public.rappels_contrat_travail AS PERMISSIVE FOR SELECT TO authenticated
  USING (est_admin());

-- rate_limits.pol_rate_limits_delete
CREATE POLICY pol_rate_limits_delete ON public.rate_limits AS PERMISSIVE FOR DELETE TO authenticated
  USING (false);

-- rate_limits.pol_rate_limits_insert
CREATE POLICY pol_rate_limits_insert ON public.rate_limits AS PERMISSIVE FOR INSERT TO authenticated
  WITH CHECK (false);

-- rate_limits.pol_rate_limits_select
CREATE POLICY pol_rate_limits_select ON public.rate_limits AS PERMISSIVE FOR SELECT TO authenticated
  USING (est_admin());

-- rate_limits.pol_rate_limits_update
CREATE POLICY pol_rate_limits_update ON public.rate_limits AS PERMISSIVE FOR UPDATE TO authenticated
  USING (false);

-- reclamations.reclamations_insert_own
CREATE POLICY reclamations_insert_own ON public.reclamations AS PERMISSIVE FOR INSERT TO authenticated
  WITH CHECK ((utilisateur_id = ( SELECT auth.uid() AS uid)));

-- reclamations.reclamations_select_own
CREATE POLICY reclamations_select_own ON public.reclamations AS PERMISSIVE FOR SELECT TO authenticated
  USING (((utilisateur_id = ( SELECT auth.uid() AS uid)) OR est_admin()));

-- reclamations.reclamations_update_admin
CREATE POLICY reclamations_update_admin ON public.reclamations AS PERMISSIVE FOR UPDATE TO authenticated
  USING (est_admin());

-- reclamations_score.pol_rec_score_select
CREATE POLICY pol_rec_score_select ON public.reclamations_score AS PERMISSIVE FOR SELECT TO authenticated
  USING ((est_admin() OR (contesteur_id = ( SELECT auth.uid() AS uid))));

-- reclamations_scoring.pol_recl_insert
CREATE POLICY pol_recl_insert ON public.reclamations_scoring AS PERMISSIVE FOR INSERT TO authenticated
  WITH CHECK ((soignant_id = ( SELECT auth.uid() AS uid)));

-- reclamations_scoring.pol_recl_select
CREATE POLICY pol_recl_select ON public.reclamations_scoring AS PERMISSIVE FOR SELECT TO authenticated
  USING (((soignant_id = ( SELECT auth.uid() AS uid)) OR ( SELECT est_admin() AS est_admin)));

-- reclamations_scoring.pol_recl_update
CREATE POLICY pol_recl_update ON public.reclamations_scoring AS PERMISSIVE FOR UPDATE TO authenticated
  USING (est_admin());

-- regles_exercice_profession.pol_regles_exercice_admin
CREATE POLICY pol_regles_exercice_admin ON public.regles_exercice_profession AS PERMISSIVE FOR ALL TO authenticated
  USING (est_admin())
  WITH CHECK (est_admin());

-- regles_exercice_profession.pol_regles_exercice_select
CREATE POLICY pol_regles_exercice_select ON public.regles_exercice_profession AS PERMISSIVE FOR SELECT TO public
  USING (true);

-- relances_soignants.admin_all_relances
CREATE POLICY admin_all_relances ON public.relances_soignants AS PERMISSIVE FOR ALL TO public
  USING (est_admin())
  WITH CHECK (est_admin());

-- rist_plafonds.pol_rist_plafonds_lecture
CREATE POLICY pol_rist_plafonds_lecture ON public.rist_plafonds AS PERMISSIVE FOR SELECT TO authenticated
  USING (true);

-- rpps_test.pol_rpps_select
CREATE POLICY pol_rpps_select ON public.rpps_test AS PERMISSIVE FOR SELECT TO authenticated
  USING (est_admin());

-- sales_annuaires.pol_sales_annuaires_admin
CREATE POLICY pol_sales_annuaires_admin ON public.sales_annuaires AS PERMISSIVE FOR ALL TO authenticated
  USING (est_admin())
  WITH CHECK (est_admin());

-- sales_contacts.admin_all_sales_contacts
CREATE POLICY admin_all_sales_contacts ON public.sales_contacts AS PERMISSIVE FOR ALL TO public
  USING (est_admin())
  WITH CHECK (est_admin());

-- sales_groupes.admin_all_sales_groupes
CREATE POLICY admin_all_sales_groupes ON public.sales_groupes AS PERMISSIVE FOR ALL TO public
  USING (est_admin())
  WITH CHECK (est_admin());

-- sales_templates.admin_all_sales_templates
CREATE POLICY admin_all_sales_templates ON public.sales_templates AS PERMISSIVE FOR ALL TO public
  USING (est_admin())
  WITH CHECK (est_admin());

-- scans_pointage.sp_insert
CREATE POLICY sp_insert ON public.scans_pointage AS PERMISSIVE FOR INSERT TO public
  WITH CHECK ((( SELECT auth.uid() AS uid) = soignant_id));

-- scans_pointage.sp_select
CREATE POLICY sp_select ON public.scans_pointage AS PERMISSIVE FOR SELECT TO public
  USING (((( SELECT auth.uid() AS uid) = soignant_id) OR est_admin() OR est_admin_etablissement()));

-- scans_pointage.sp_update
CREATE POLICY sp_update ON public.scans_pointage AS PERMISSIVE FOR UPDATE TO public
  USING ((est_admin() OR est_admin_etablissement()));

-- scoring_breakdown.pol_scoring_bd_select
CREATE POLICY pol_scoring_bd_select ON public.scoring_breakdown AS PERMISSIVE FOR SELECT TO public
  USING (((soignant_id = ( SELECT auth.uid() AS uid)) OR ( SELECT est_admin() AS est_admin)));

-- serie_email_envois.see_select_own
CREATE POLICY see_select_own ON public.serie_email_envois AS PERMISSIVE FOR SELECT TO authenticated
  USING (((utilisateur_id = ( SELECT auth.uid() AS uid)) OR est_admin()));

-- shift_affectations.etab_own_affectations
CREATE POLICY etab_own_affectations ON public.shift_affectations AS PERMISSIVE FOR ALL TO authenticated
  USING (((shift_id IN ( SELECT shifts.id
   FROM shifts
  WHERE (shifts.etablissement_id = mon_etablissement_id()))) OR est_admin()))
  WITH CHECK (((shift_id IN ( SELECT shifts.id
   FROM shifts
  WHERE (shifts.etablissement_id = mon_etablissement_id()))) OR est_admin()));

-- shifts.etab_own_shifts
CREATE POLICY etab_own_shifts ON public.shifts AS PERMISSIVE FOR ALL TO authenticated
  USING (((etablissement_id = mon_etablissement_id()) OR est_admin()))
  WITH CHECK (((etablissement_id = mon_etablissement_id()) OR est_admin()));

-- signalements.pol_signalements_select
CREATE POLICY pol_signalements_select ON public.signalements AS PERMISSIVE FOR SELECT TO public
  USING (((signaleur_id = ( SELECT auth.uid() AS uid)) OR est_admin()));

-- signalements.pol_signalements_update
CREATE POLICY pol_signalements_update ON public.signalements AS PERMISSIVE FOR UPDATE TO public
  USING (est_admin())
  WITH CHECK (est_admin());

-- signature_rate_limit_ip.pol_sig_rl_deny_all
CREATE POLICY pol_sig_rl_deny_all ON public.signature_rate_limit_ip AS PERMISSIVE FOR ALL TO authenticated
  USING (false)
  WITH CHECK (false);

-- signatures_contrats.pol_sig_contrats_delete_deny
CREATE POLICY pol_sig_contrats_delete_deny ON public.signatures_contrats AS PERMISSIVE FOR DELETE TO authenticated
  USING (false);

-- signatures_contrats.pol_sig_contrats_insert_deny
CREATE POLICY pol_sig_contrats_insert_deny ON public.signatures_contrats AS PERMISSIVE FOR INSERT TO authenticated
  WITH CHECK (false);

-- signatures_contrats.pol_sig_contrats_select
CREATE POLICY pol_sig_contrats_select ON public.signatures_contrats AS PERMISSIVE FOR SELECT TO authenticated
  USING ((est_admin() OR (signataire_user_id = ( SELECT auth.uid() AS uid)) OR (EXISTS ( SELECT 1
   FROM contrats_mission cm
  WHERE ((cm.id = signatures_contrats.contrat_id) AND ((cm.soignant_id = ( SELECT auth.uid() AS uid)) OR (cm.etablissement_id = mon_etablissement_id())))))));

-- signatures_contrats.pol_sig_contrats_update_deny
CREATE POLICY pol_sig_contrats_update_deny ON public.signatures_contrats AS PERMISSIVE FOR UPDATE TO authenticated
  USING (false)
  WITH CHECK (false);

-- sms_envoyes."Admin lit sms"
CREATE POLICY "Admin lit sms" ON public.sms_envoyes AS PERMISSIVE FOR ALL TO public
  USING (est_admin())
  WITH CHECK (est_admin());

-- soignants.pol_soig_delete
CREATE POLICY pol_soig_delete ON public.soignants AS PERMISSIVE FOR DELETE TO authenticated
  USING (est_admin());

-- soignants.pol_soig_insert
CREATE POLICY pol_soig_insert ON public.soignants AS PERMISSIVE FOR INSERT TO authenticated
  WITH CHECK (((id = ( SELECT auth.uid() AS uid)) AND (rpps_verifie IS NOT TRUE) AND (diplome_verifie IS NOT TRUE) AND (identite_verifiee IS NOT TRUE) AND (tous_documents_valides IS NOT TRUE) AND ((score_fiabilite IS NULL) OR (score_fiabilite = 50.00)) AND ((total_missions_terminees IS NULL) OR (total_missions_terminees = 0)) AND ((heures_cumulees IS NULL) OR (heures_cumulees = (0)::numeric)) AND ((heures_plateforme IS NULL) OR (heures_plateforme = (0)::numeric)) AND (eligible_conversion_3200h IS NOT TRUE) AND ((statut_verification_aria IS NULL) OR (statut_verification_aria = 'EN_ATTENTE'::statut_verification)) AND (parraine_par IS NULL)));

-- soignants.pol_soig_select
CREATE POLICY pol_soig_select ON public.soignants AS PERMISSIVE FOR SELECT TO authenticated
  USING (((id = ( SELECT auth.uid() AS uid)) OR est_admin() OR (id IN ( SELECT m.soignant_assigne_id
   FROM missions m
  WHERE ((m.etablissement_id = mon_etablissement_id()) AND (m.soignant_assigne_id IS NOT NULL)))) OR (id IN ( SELECT c.soignant_id
   FROM candidatures c
  WHERE (c.mission_id IN ( SELECT m2.id
           FROM missions m2
          WHERE (m2.etablissement_id = mon_etablissement_id())))))));

-- soignants.pol_soig_update
CREATE POLICY pol_soig_update ON public.soignants AS PERMISSIVE FOR UPDATE TO authenticated
  USING ((( SELECT est_admin() AS est_admin) OR (id = ( SELECT auth.uid() AS uid))))
  WITH CHECK ((( SELECT est_admin() AS est_admin) OR ((id = ( SELECT auth.uid() AS uid)) AND (NOT (rpps_verifie IS DISTINCT FROM ( SELECT soignants_1.rpps_verifie
   FROM soignants soignants_1
  WHERE (soignants_1.id = ( SELECT auth.uid() AS uid))))) AND (NOT (diplome_verifie IS DISTINCT FROM ( SELECT soignants_1.diplome_verifie
   FROM soignants soignants_1
  WHERE (soignants_1.id = ( SELECT auth.uid() AS uid))))) AND (NOT (identite_verifiee IS DISTINCT FROM ( SELECT soignants_1.identite_verifiee
   FROM soignants soignants_1
  WHERE (soignants_1.id = ( SELECT auth.uid() AS uid))))) AND (NOT (tous_documents_valides IS DISTINCT FROM ( SELECT soignants_1.tous_documents_valides
   FROM soignants soignants_1
  WHERE (soignants_1.id = ( SELECT auth.uid() AS uid))))) AND (NOT (score_fiabilite IS DISTINCT FROM ( SELECT soignants_1.score_fiabilite
   FROM soignants soignants_1
  WHERE (soignants_1.id = ( SELECT auth.uid() AS uid))))) AND (NOT (total_missions_terminees IS DISTINCT FROM ( SELECT soignants_1.total_missions_terminees
   FROM soignants soignants_1
  WHERE (soignants_1.id = ( SELECT auth.uid() AS uid))))) AND (NOT (heures_cumulees IS DISTINCT FROM ( SELECT soignants_1.heures_cumulees
   FROM soignants soignants_1
  WHERE (soignants_1.id = ( SELECT auth.uid() AS uid))))) AND (NOT (heures_plateforme IS DISTINCT FROM ( SELECT soignants_1.heures_plateforme
   FROM soignants soignants_1
  WHERE (soignants_1.id = ( SELECT auth.uid() AS uid))))) AND (NOT (eligible_conversion_3200h IS DISTINCT FROM ( SELECT soignants_1.eligible_conversion_3200h
   FROM soignants soignants_1
  WHERE (soignants_1.id = ( SELECT auth.uid() AS uid))))) AND (NOT (validation_3200h_statut IS DISTINCT FROM ( SELECT soignants_1.validation_3200h_statut
   FROM soignants soignants_1
  WHERE (soignants_1.id = ( SELECT auth.uid() AS uid))))) AND (NOT (statut_liberal IS DISTINCT FROM ( SELECT soignants_1.statut_liberal
   FROM soignants soignants_1
  WHERE (soignants_1.id = ( SELECT auth.uid() AS uid))))) AND (NOT (parraine_par IS DISTINCT FROM ( SELECT soignants_1.parraine_par
   FROM soignants soignants_1
  WHERE (soignants_1.id = ( SELECT auth.uid() AS uid))))))));

-- souscriptions_prevoyance.pol_prevoy_delete
CREATE POLICY pol_prevoy_delete ON public.souscriptions_prevoyance AS PERMISSIVE FOR DELETE TO authenticated
  USING (est_admin());

-- souscriptions_prevoyance.pol_prevoy_insert
CREATE POLICY pol_prevoy_insert ON public.souscriptions_prevoyance AS PERMISSIVE FOR INSERT TO authenticated
  WITH CHECK (est_admin());

-- souscriptions_prevoyance.pol_prevoy_select
CREATE POLICY pol_prevoy_select ON public.souscriptions_prevoyance AS PERMISSIVE FOR SELECT TO authenticated
  USING (((soignant_id = ( SELECT auth.uid() AS uid)) OR ( SELECT est_admin() AS est_admin)));

-- souscriptions_prevoyance.pol_prevoy_update
CREATE POLICY pol_prevoy_update ON public.souscriptions_prevoyance AS PERMISSIVE FOR UPDATE TO authenticated
  USING (est_admin());

-- specialites_medicales."Lecture publique specialites_medicales"
CREATE POLICY "Lecture publique specialites_medicales" ON public.specialites_medicales AS PERMISSIVE FOR SELECT TO authenticated
  USING (true);

-- statut_services_api.pol_statut_api_select
CREATE POLICY pol_statut_api_select ON public.statut_services_api AS PERMISSIVE FOR SELECT TO authenticated
  USING (est_admin());

-- streaks_soignant.streaks_soignant_select_own
CREATE POLICY streaks_soignant_select_own ON public.streaks_soignant AS PERMISSIVE FOR SELECT TO public
  USING ((soignant_id = ( SELECT auth.uid() AS uid)));

-- streaks_soignant.streaks_soignant_service_role
CREATE POLICY streaks_soignant_service_role ON public.streaks_soignant AS PERMISSIVE FOR ALL TO service_role
  USING (true)
  WITH CHECK (true);

-- stripe_connect_onboarding.pol_connect_insert
CREATE POLICY pol_connect_insert ON public.stripe_connect_onboarding AS PERMISSIVE FOR INSERT TO authenticated
  WITH CHECK ((soignant_id = ( SELECT auth.uid() AS uid)));

-- stripe_connect_onboarding.pol_connect_select
CREATE POLICY pol_connect_select ON public.stripe_connect_onboarding AS PERMISSIVE FOR SELECT TO authenticated
  USING (((soignant_id = ( SELECT auth.uid() AS uid)) OR ( SELECT est_admin() AS est_admin)));

-- stripe_connect_onboarding.pol_connect_update
CREATE POLICY pol_connect_update ON public.stripe_connect_onboarding AS PERMISSIVE FOR UPDATE TO authenticated
  USING (((soignant_id = ( SELECT auth.uid() AS uid)) OR est_admin()));

-- stripe_refunds_queue.pol_stripe_refunds_admin_all
CREATE POLICY pol_stripe_refunds_admin_all ON public.stripe_refunds_queue AS PERMISSIVE FOR ALL TO authenticated
  USING (est_admin())
  WITH CHECK (est_admin());

-- stripe_transfers.pol_transfer_delete
CREATE POLICY pol_transfer_delete ON public.stripe_transfers AS PERMISSIVE FOR DELETE TO authenticated
  USING (est_admin());

-- stripe_transfers.pol_transfer_insert
CREATE POLICY pol_transfer_insert ON public.stripe_transfers AS PERMISSIVE FOR INSERT TO authenticated
  WITH CHECK (( SELECT est_admin() AS est_admin));

-- stripe_transfers.pol_transfer_select
CREATE POLICY pol_transfer_select ON public.stripe_transfers AS PERMISSIVE FOR SELECT TO authenticated
  USING (((soignant_id = ( SELECT auth.uid() AS uid)) OR (etablissement_id = ( SELECT mon_etablissement_id() AS mon_etablissement_id)) OR ( SELECT est_admin() AS est_admin)));

-- stripe_webhook_events.pol_stripe_webhook_events_admin
CREATE POLICY pol_stripe_webhook_events_admin ON public.stripe_webhook_events AS PERMISSIVE FOR ALL TO public
  USING (est_admin())
  WITH CHECK (est_admin());

-- suivi_conversion_3200h.pol_3200h_delete
CREATE POLICY pol_3200h_delete ON public.suivi_conversion_3200h AS PERMISSIVE FOR DELETE TO authenticated
  USING (est_admin());

-- suivi_conversion_3200h.pol_3200h_insert
CREATE POLICY pol_3200h_insert ON public.suivi_conversion_3200h AS PERMISSIVE FOR INSERT TO authenticated
  WITH CHECK (est_admin());

-- suivi_conversion_3200h.pol_3200h_select
CREATE POLICY pol_3200h_select ON public.suivi_conversion_3200h AS PERMISSIVE FOR SELECT TO authenticated
  USING (((soignant_id = ( SELECT auth.uid() AS uid)) OR ( SELECT est_admin() AS est_admin)));

-- suivi_conversion_3200h.pol_3200h_update
CREATE POLICY pol_3200h_update ON public.suivi_conversion_3200h AS PERMISSIVE FOR UPDATE TO authenticated
  USING (est_admin());

-- super_swipes_quota.super_swipes_quota_select_own
CREATE POLICY super_swipes_quota_select_own ON public.super_swipes_quota AS PERMISSIVE FOR SELECT TO public
  USING ((soignant_id = ( SELECT auth.uid() AS uid)));

-- super_swipes_quota.super_swipes_quota_service_role
CREATE POLICY super_swipes_quota_service_role ON public.super_swipes_quota AS PERMISSIVE FOR ALL TO service_role
  USING (true)
  WITH CHECK (true);

-- swipes.swipes_insert_own
CREATE POLICY swipes_insert_own ON public.swipes AS PERMISSIVE FOR INSERT TO public
  WITH CHECK ((soignant_id = ( SELECT auth.uid() AS uid)));

-- swipes.swipes_select_own
CREATE POLICY swipes_select_own ON public.swipes AS PERMISSIVE FOR SELECT TO public
  USING ((soignant_id = ( SELECT auth.uid() AS uid)));

-- swipes.swipes_service_role
CREATE POLICY swipes_service_role ON public.swipes AS PERMISSIVE FOR ALL TO service_role
  USING (true)
  WITH CHECK (true);

-- templates_contrat.pol_templates_contrat_lecture
CREATE POLICY pol_templates_contrat_lecture ON public.templates_contrat AS PERMISSIVE FOR SELECT TO authenticated
  USING (est_admin());

-- tokens_calendrier.pol_cal_token_delete
CREATE POLICY pol_cal_token_delete ON public.tokens_calendrier AS PERMISSIVE FOR DELETE TO authenticated
  USING ((soignant_id = ( SELECT auth.uid() AS uid)));

-- tokens_calendrier.pol_tcal_insert
CREATE POLICY pol_tcal_insert ON public.tokens_calendrier AS PERMISSIVE FOR INSERT TO authenticated
  WITH CHECK ((soignant_id = ( SELECT auth.uid() AS uid)));

-- tokens_calendrier.pol_tcal_select
CREATE POLICY pol_tcal_select ON public.tokens_calendrier AS PERMISSIVE FOR SELECT TO authenticated
  USING ((soignant_id = ( SELECT auth.uid() AS uid)));

-- tokens_push.pol_token_delete
CREATE POLICY pol_token_delete ON public.tokens_push AS PERMISSIVE FOR DELETE TO authenticated
  USING ((utilisateur_id = ( SELECT auth.uid() AS uid)));

-- tokens_push.pol_token_insert
CREATE POLICY pol_token_insert ON public.tokens_push AS PERMISSIVE FOR INSERT TO authenticated
  WITH CHECK ((utilisateur_id = ( SELECT auth.uid() AS uid)));

-- tokens_push.pol_token_select
CREATE POLICY pol_token_select ON public.tokens_push AS PERMISSIVE FOR SELECT TO authenticated
  USING ((utilisateur_id = ( SELECT auth.uid() AS uid)));

-- tokens_push.pol_token_update
CREATE POLICY pol_token_update ON public.tokens_push AS PERMISSIVE FOR UPDATE TO authenticated
  USING ((utilisateur_id = ( SELECT auth.uid() AS uid)));

-- typing_status.pol_typing_status_delete
CREATE POLICY pol_typing_status_delete ON public.typing_status AS PERMISSIVE FOR DELETE TO authenticated
  USING ((user_id = ( SELECT auth.uid() AS uid)));

-- typing_status.pol_typing_status_select
CREATE POLICY pol_typing_status_select ON public.typing_status AS PERMISSIVE FOR SELECT TO authenticated
  USING ((EXISTS ( SELECT 1
   FROM conversations c
  WHERE ((c.id = typing_status.conversation_id) AND ((c.participant_1_id = ( SELECT auth.uid() AS uid)) OR (c.participant_2_id = ( SELECT auth.uid() AS uid)))))));

-- typing_status.pol_typing_status_upsert
CREATE POLICY pol_typing_status_upsert ON public.typing_status AS PERMISSIVE FOR INSERT TO authenticated
  WITH CHECK (((user_id = ( SELECT auth.uid() AS uid)) AND (EXISTS ( SELECT 1
   FROM conversations c
  WHERE ((c.id = typing_status.conversation_id) AND ((c.participant_1_id = ( SELECT auth.uid() AS uid)) OR (c.participant_2_id = ( SELECT auth.uid() AS uid))))))));

-- Fin — 313 policies.
