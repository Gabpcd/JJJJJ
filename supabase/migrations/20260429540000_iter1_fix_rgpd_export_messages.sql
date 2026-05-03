-- Itération 1 — Fix RGPD CRITIQUE détecté par audit attaquant (Finding 3)
-- fn_exporter_mes_donnees v9 : ajouter messages_litige + messages_mission
-- Article 15 RGPD : "toutes les données me concernant" doivent être exportables.
-- v8 incluait messages_chat mais pas messages_litige ni messages_mission.

CREATE OR REPLACE FUNCTION public.fn_exporter_mes_donnees()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_result jsonb;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('error', 'Non authentifié');
  END IF;

  SELECT jsonb_build_object(
    'export_date', NOW(),
    'utilisateur_id', v_uid,
    'profil', (SELECT to_jsonb(s.*) - 'numero_secu' - 'numero_securite_sociale' FROM soignants s WHERE id = v_uid),
    'missions', (SELECT COALESCE(jsonb_agg(to_jsonb(m.*) - 'taux_commission' - 'montant_commission_ht' - 'montant_commission_tva' - 'montant_commission_ttc' ORDER BY m.cree_le DESC), '[]'::jsonb) FROM missions m WHERE m.soignant_assigne_id = v_uid),
    'candidatures', (SELECT COALESCE(jsonb_agg(to_jsonb(c.*) ORDER BY c.cree_le DESC), '[]'::jsonb) FROM candidatures c WHERE c.soignant_id = v_uid),
    'presences', (SELECT COALESCE(jsonb_agg(to_jsonb(p.*) ORDER BY p.cree_le DESC), '[]'::jsonb) FROM presences p WHERE p.soignant_id = v_uid),
    'factures_honoraires', (SELECT COALESCE(jsonb_agg(jsonb_build_object('id',f.id,'numero_facture',f.numero_facture,'mission_id',f.mission_id,'etablissement_id',f.etablissement_id,'montant_ht',f.montant_ht,'montant_ttc',f.montant_ttc,'taux_tva',f.taux_tva,'exoneration_tva',f.exoneration_tva,'date_emission',f.date_emission,'date_echeance',f.date_echeance,'date_paiement',f.date_paiement,'statut',f.statut,'type_document',f.type_document,'pdf_s3_key',f.pdf_s3_key) ORDER BY f.date_emission DESC), '[]'::jsonb) FROM factures_honoraires f WHERE f.soignant_id = v_uid),
    'bulletins_paie', (SELECT COALESCE(jsonb_agg(to_jsonb(b.*) ORDER BY b.periode_debut DESC), '[]'::jsonb) FROM bulletins_paie b WHERE b.soignant_id = v_uid),
    'cotisations_sociales', (SELECT COALESCE(jsonb_agg(to_jsonb(c.*) ORDER BY c.calcule_le DESC), '[]'::jsonb) FROM cotisations_sociales c WHERE c.soignant_id = v_uid),
    'mandats_facturation', (SELECT COALESCE(jsonb_agg(jsonb_build_object('version',version,'signed_at',signed_at,'revoked_at',revoked_at,'ip_address',ip_address,'contenu_hash',contenu_hash) ORDER BY signed_at DESC), '[]'::jsonb) FROM mandats_facturation_signatures WHERE soignant_id = v_uid),
    'cessions_creance', (SELECT COALESCE(jsonb_agg(to_jsonb(c.*) ORDER BY c.signed_at DESC), '[]'::jsonb) FROM cessions_creance c WHERE c.soignant_id = v_uid),
    'factor_advances', (SELECT COALESCE(jsonb_agg(to_jsonb(fa.*) ORDER BY fa.cree_le DESC), '[]'::jsonb) FROM factor_advances fa WHERE fa.soignant_id = v_uid),
    'paiements_soignant', (SELECT COALESCE(jsonb_agg(to_jsonb(p.*) ORDER BY p.cree_le DESC), '[]'::jsonb) FROM paiements_soignant p WHERE p.soignant_id = v_uid),
    'contrats_mission', (SELECT COALESCE(jsonb_agg(jsonb_build_object('id',id,'mission_id',mission_id,'type_contrat',type_contrat,'numero_contrat',numero_contrat,'statut',statut,'signature_soignant_le',signature_soignant_le,'signature_etablissement_le',signature_etablissement_le,'cree_le',cree_le) ORDER BY cree_le DESC), '[]'::jsonb) FROM contrats_mission WHERE soignant_id = v_uid),
    'documents', (SELECT COALESCE(jsonb_agg(jsonb_build_object('type',type_document,'libelle',libelle,'statut_verification',statut_verification,'valide_jusqua',valide_jusqua,'televerse_le',televerse_le) ORDER BY televerse_le DESC), '[]'::jsonb) FROM documents_soignants WHERE soignant_id = v_uid AND supprime_le IS NULL),
    'evaluations_recues', (SELECT COALESCE(jsonb_agg(jsonb_build_object('mission_id',mission_id,'note',note,'commentaire',commentaire,'cree_le',cree_le) ORDER BY cree_le DESC), '[]'::jsonb) FROM evaluations WHERE evalue_id = v_uid),
    'evaluations_donnees', (SELECT COALESCE(jsonb_agg(jsonb_build_object('mission_id',mission_id,'note',note,'commentaire',commentaire,'cree_le',cree_le) ORDER BY cree_le DESC), '[]'::jsonb) FROM evaluations WHERE evaluateur_id = v_uid),
    'messages_chat', (SELECT COALESCE(jsonb_agg(jsonb_build_object('conversation_id',conversation_id,'contenu',contenu,'cree_le',cree_le,'lu',lu) ORDER BY cree_le DESC), '[]'::jsonb) FROM messages_chat WHERE auteur_id = v_uid),
    -- Iter1 RGPD fix : ajout messages_litige + messages_mission
    'messages_litige', (SELECT COALESCE(jsonb_agg(jsonb_build_object('litige_id',litige_id,'type_auteur',type_auteur,'contenu',contenu,'cree_le',cree_le) ORDER BY cree_le DESC), '[]'::jsonb) FROM messages_litige WHERE auteur_id = v_uid),
    'messages_mission', (SELECT COALESCE(jsonb_agg(jsonb_build_object('mission_id',mission_id,'type_auteur',type_auteur,'contenu',contenu,'lu',lu,'cree_le',cree_le) ORDER BY cree_le DESC), '[]'::jsonb) FROM messages_mission WHERE auteur_id = v_uid),
    'notifications', (SELECT COALESCE(jsonb_agg(jsonb_build_object('type',type,'titre',titre,'corps',corps,'lue',lue,'cree_le',cree_le) ORDER BY cree_le DESC), '[]'::jsonb) FROM notifications WHERE destinataire_id = v_uid),
    'partages_rib', (SELECT COALESCE(jsonb_agg(jsonb_build_object('etablissement_id',etablissement_id,'mission_id',mission_id,'partage_le',partage_le,'consulte_le',consulte_le,'expire_le',expire_le,'actif',actif)), '[]'::jsonb) FROM partages_rib WHERE soignant_id = v_uid),
    'parrainages', (SELECT COALESCE(jsonb_agg(jsonb_build_object('role', CASE WHEN parrain_id = v_uid THEN 'parrain' ELSE 'filleul' END,'code_parrainage',code_parrainage,'statut',statut,'valide_le',valide_le,'cree_le',cree_le)), '[]'::jsonb) FROM parrainages WHERE parrain_id = v_uid OR filleul_id = v_uid),
    'preferences_notifications', (SELECT to_jsonb(p) - 'utilisateur_id' FROM preferences_notifications p WHERE utilisateur_id = v_uid),
    'preferences_notifications_par_evenement', (SELECT COALESCE(jsonb_agg(jsonb_build_object('type_evenement',type_evenement,'canal',canal,'actif',actif)), '[]'::jsonb) FROM preferences_notifications_par_evenement WHERE utilisateur_id = v_uid),
    'serie_email_envois', (SELECT COALESCE(jsonb_agg(jsonb_build_object('serie',serie,'etape',etape,'planifie_le',planifie_le,'envoye_le',envoye_le,'statut',statut,'skip_raison',skip_raison) ORDER BY planifie_le DESC), '[]'::jsonb) FROM serie_email_envois WHERE utilisateur_id = v_uid),
    'filtres_sauvegardes', (SELECT COALESCE(jsonb_agg(jsonb_build_object('nom',nom,'audience',audience,'filtres',filtres,'alerte_active',alerte_active,'frequence_alerte',frequence_alerte,'dernier_check_le',dernier_check_le,'nb_resultats_dernier_check',nb_resultats_dernier_check,'cree_le',cree_le) ORDER BY cree_le DESC), '[]'::jsonb) FROM filtres_sauvegardes WHERE utilisateur_id = v_uid),
    'favoris_etablissements', (SELECT COALESCE(jsonb_agg(jsonb_build_object('etablissement_id', etablissement_id, 'cree_le', cree_le) ORDER BY cree_le DESC), '[]'::jsonb) FROM favoris_soignant_etab WHERE soignant_id = v_uid),
    'prevoyance_liste_attente', (SELECT COALESCE(jsonb_agg(jsonb_build_object('email', email, 'niveau_souhaite', niveau_souhaite, 'cree_le', cree_le, 'mis_a_jour_le', mis_a_jour_le)), '[]'::jsonb) FROM prevoyance_liste_attente WHERE soignant_id = v_uid),
    'notations_donnees', (SELECT COALESCE(jsonb_agg(jsonb_build_object('mission_id',mission_id,'sens',sens,'critere_1',critere_1,'critere_2',critere_2,'critere_3',critere_3,'critere_4',critere_4,'commentaire',commentaire,'cree_le',cree_le) ORDER BY cree_le DESC), '[]'::jsonb) FROM notations_missions WHERE notateur_id = v_uid),
    'notations_recues', (SELECT COALESCE(jsonb_agg(jsonb_build_object('mission_id',mission_id,'sens',sens,'critere_1',critere_1,'critere_2',critere_2,'critere_3',critere_3,'critere_4',critere_4,'commentaire',commentaire,'cree_le',cree_le) ORDER BY cree_le DESC), '[]'::jsonb) FROM notations_missions WHERE note_id = v_uid AND masque = false),
    'scoring_breakdown_historique', (SELECT COALESCE(jsonb_agg(jsonb_build_object('score_total',score_total,'niveau',niveau,'en_periode_probatoire',en_periode_probatoire,'composantes_actives_count',composantes_actives_count,'litiges_malus',litiges_malus,'absence_sans_prevenir_malus',absence_sans_prevenir_malus,'bonus_super_actif',bonus_super_actif,'raison_recalcul',raison_recalcul,'cree_le',cree_le) ORDER BY cree_le DESC), '[]'::jsonb) FROM scoring_breakdown WHERE soignant_id = v_uid)
  ) INTO v_result;

  PERFORM public.fn_ecrire_audit_safe(
    p_acteur_id := v_uid,
    p_type_acteur := 'SOIGNANT',
    p_action := 'RGPD_EXPORT_DONNEES',
    p_type_ressource := 'soignant',
    p_id_ressource := v_uid,
    p_details := jsonb_build_object('version', 'v9_avec_messages_litige_mission')
  );

  RETURN v_result;
END;
$function$;

NOTIFY pgrst, 'reload schema';
