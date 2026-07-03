-- ============================================================
-- Baseline structure prod Jolene — extrait le 2026-07-03
-- Pseudo-DDL reconstruit depuis information_schema.columns
-- + pg_constraint (PK/FK/UNIQUE/CHECK) en fin de fichier.
-- NE PAS appliquer tel quel — document de référence.
-- ============================================================

CREATE TABLE admin_invocations (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  admin_user_id uuid NOT NULL,
  target_function text NOT NULL,
  target_payload jsonb,
  reason text NOT NULL,
  dry_run boolean NOT NULL DEFAULT false,
  is_test boolean NOT NULL DEFAULT false,
  invoked_at timestamp with time zone NOT NULL DEFAULT now(),
  status_returned integer,
  duration_ms integer,
  response_excerpt text,
  completed_at timestamp with time zone,
  internal_status text NOT NULL DEFAULT 'PENDING'::text,
  request_id uuid DEFAULT gen_random_uuid()
);

CREATE TABLE admins_groupe_sante (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  groupe_id uuid NOT NULL,
  utilisateur_id uuid NOT NULL,
  role text DEFAULT 'LECTEUR'::text,
  cree_le timestamp with time zone DEFAULT now()
);

CREATE TABLE alertes_systeme (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  type_alerte text NOT NULL,
  severite text NOT NULL,
  source text NOT NULL,
  message text NOT NULL,
  details jsonb DEFAULT '{}'::jsonb,
  resolu_le timestamp with time zone,
  email_envoye_le timestamp with time zone,
  cree_le timestamp with time zone NOT NULL DEFAULT now()
);

CREATE TABLE api_keys (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  etablissement_id uuid,
  groupe_sante_id uuid,
  cle_api text NOT NULL,
  cle_secret text,
  nom text NOT NULL,
  permissions text[] DEFAULT ARRAY['missions:read'::text, 'missions:write'::text],
  actif boolean DEFAULT true,
  derniere_utilisation timestamp with time zone,
  cree_le timestamp with time zone DEFAULT now(),
  expire_le timestamp with time zone,
  cle_secret_hash text
);

CREATE TABLE articles_aide (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  slug text NOT NULL,
  titre text NOT NULL,
  contenu text NOT NULL,
  audience text NOT NULL,
  categorie text NOT NULL,
  ordre_affichage integer NOT NULL DEFAULT 100,
  publie boolean NOT NULL DEFAULT true,
  cree_le timestamp with time zone NOT NULL DEFAULT now(),
  mis_a_jour_le timestamp with time zone NOT NULL DEFAULT now()
);

CREATE TABLE assurance_config (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  etablissement_id uuid NOT NULL,
  assurance_auto boolean DEFAULT true,
  type_couverture text DEFAULT 'RC_MISSION'::text,
  montant_couverture_eur numeric(10,2) DEFAULT 1000000,
  prise_en_charge text DEFAULT 'ETABLISSEMENT'::text,
  part_soignant_pourcent numeric(5,2) DEFAULT 0,
  provider text DEFAULT 'WAKAM'::text,
  provider_contrat_cadre text,
  actif boolean DEFAULT true,
  cree_le timestamp with time zone DEFAULT now()
);

CREATE TABLE assurances_mission (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  mission_id uuid NOT NULL,
  soignant_id uuid NOT NULL,
  etablissement_id uuid NOT NULL,
  type text NOT NULL DEFAULT 'RC_MISSION'::text,
  statut text NOT NULL DEFAULT 'ACTIVE'::text,
  montant_couverture_eur numeric(10,2) NOT NULL DEFAULT 1000000,
  franchise_eur numeric(8,2) DEFAULT 0,
  prime_ht_eur numeric(8,2) NOT NULL,
  prime_ttc_eur numeric(8,2) NOT NULL,
  taux_tva numeric(4,2) DEFAULT 20.00,
  debut_couverture timestamp with time zone NOT NULL,
  fin_couverture timestamp with time zone NOT NULL,
  provider text DEFAULT 'WAKAM'::text,
  provider_police_id text,
  provider_sinistre_id text,
  provider_reference text,
  souscrit_par text DEFAULT 'AUTO'::text,
  accepte_conditions boolean DEFAULT false,
  accepte_le timestamp with time zone,
  sinistre_declare_le timestamp with time zone,
  sinistre_description text,
  sinistre_montant_estime numeric(10,2),
  sinistre_statut text,
  cree_le timestamp with time zone DEFAULT now(),
  modifie_le timestamp with time zone DEFAULT now()
);

CREATE TABLE attestations_heures_externes (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  soignant_id uuid NOT NULL,
  semaine_du date NOT NULL,
  heures_salarie numeric DEFAULT 0,
  employeur_principal text,
  attestation_honneur boolean DEFAULT false,
  cree_le timestamp with time zone DEFAULT now()
);

CREATE TABLE avoirs (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  facture_origine_id uuid,
  facture_origine_type text NOT NULL,
  numero text NOT NULL,
  montant_ht numeric(12,2) NOT NULL,
  montant_ttc numeric(12,2) NOT NULL,
  motif text NOT NULL,
  source_litige_id uuid,
  source_mission_id uuid,
  pdf_storage_path text,
  emis_par uuid NOT NULL,
  emis_le timestamp with time zone NOT NULL DEFAULT now(),
  details jsonb DEFAULT '{}'::jsonb,
  cree_le timestamp with time zone NOT NULL DEFAULT now()
);

CREATE TABLE badges_soignant (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  soignant_id uuid NOT NULL,
  badge_type text NOT NULL,
  earned_at timestamp with time zone NOT NULL DEFAULT now(),
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb
);

CREATE TABLE bfa_suivi (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  etablissement_id uuid,
  groupe_id uuid,
  annee integer NOT NULL,
  missions_cumulees integer DEFAULT 0,
  commissions_cumulees numeric(12,2) DEFAULT 0,
  palier_bfa text DEFAULT 'AUCUN'::text,
  taux_bfa numeric(5,2) DEFAULT 0,
  montant_bfa numeric(10,2) DEFAULT 0,
  bfa_verse boolean DEFAULT false,
  date_versement date,
  calcule_le timestamp with time zone DEFAULT now(),
  cree_le timestamp with time zone DEFAULT now()
);

CREATE TABLE bulletins_paie (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  numero_bulletin text NOT NULL,
  soignant_id uuid NOT NULL,
  mission_id uuid NOT NULL,
  etablissement_id uuid NOT NULL,
  periode_debut date NOT NULL,
  periode_fin date NOT NULL,
  salaire_brut numeric NOT NULL,
  total_cotisations_salariales numeric NOT NULL DEFAULT 0,
  total_cotisations_patronales numeric NOT NULL DEFAULT 0,
  net_avant_impot numeric NOT NULL,
  ifm numeric NOT NULL DEFAULT 0,
  icp numeric NOT NULL DEFAULT 0,
  statut text NOT NULL DEFAULT 'EMIS'::text,
  date_emission date NOT NULL DEFAULT CURRENT_DATE,
  date_paiement date,
  pdf_s3_key text,
  cree_le timestamp with time zone NOT NULL DEFAULT now(),
  modifie_le timestamp with time zone NOT NULL DEFAULT now()
);

CREATE TABLE calendar_connections (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  utilisateur_id uuid NOT NULL,
  provider text NOT NULL,
  access_token text,
  refresh_token text,
  token_expires_at timestamp with time zone,
  calendar_id text,
  sync_enabled boolean DEFAULT true,
  last_sync_at timestamp with time zone,
  last_sync_error text,
  cree_le timestamp with time zone DEFAULT now(),
  modifie_le timestamp with time zone DEFAULT now()
);

CREATE TABLE calendar_events_sync (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  connection_id uuid NOT NULL,
  mission_id uuid NOT NULL,
  external_event_id text,
  last_synced_at timestamp with time zone,
  sync_direction text DEFAULT 'PUSH'::text,
  cree_le timestamp with time zone DEFAULT now()
);

CREATE TABLE candidatures (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  mission_id uuid NOT NULL,
  soignant_id uuid NOT NULL,
  message text,
  statut text DEFAULT 'EN_ATTENTE'::text,
  motif_refus text,
  cree_le timestamp with time zone DEFAULT now(),
  traite_le timestamp with time zone,
  type_contrat_choisi text,
  acceptee_a timestamp with time zone
);

CREATE TABLE cessions_creance (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  soignant_id uuid NOT NULL,
  facture_honoraire_id uuid NOT NULL,
  montant numeric(10,2) NOT NULL,
  version_texte text NOT NULL,
  contenu_hash text,
  signed_at timestamp with time zone NOT NULL DEFAULT now(),
  ip_address text,
  user_agent text,
  cree_le timestamp with time zone NOT NULL DEFAULT now()
);

CREATE TABLE chorus_pro_config (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  etablissement_id uuid NOT NULL,
  numero_structure text NOT NULL,
  code_service text,
  identifiant_cpro text,
  actif boolean DEFAULT true,
  cree_le timestamp with time zone DEFAULT now()
);

CREATE TABLE chorus_submissions (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  invoice_id uuid NOT NULL,
  piste_request_id text,
  payload_xml text,
  response_raw jsonb,
  submission_type text NOT NULL DEFAULT 'SAISIE_API'::text,
  status text NOT NULL DEFAULT 'pending_credentials'::text,
  error_code text,
  error_message text,
  submitted_at timestamp with time zone,
  last_checked_at timestamp with time zone,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  type_document text NOT NULL DEFAULT 'FACTURE'::text,
  avoir_reference_invoice text
);

CREATE TABLE codes_secours_mission (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  mission_id uuid NOT NULL,
  code_hash text NOT NULL,
  type text NOT NULL DEFAULT 'UNIVERSEL'::text,
  genere_le timestamp with time zone NOT NULL DEFAULT now(),
  expire_le timestamp with time zone NOT NULL,
  utilise boolean NOT NULL DEFAULT false,
  utilise_le timestamp with time zone,
  utilise_par uuid,
  cree_par uuid NOT NULL,
  cree_le timestamp with time zone NOT NULL DEFAULT now()
);

CREATE TABLE conformite_travail (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  soignant_id uuid NOT NULL,
  mission_id uuid NOT NULL,
  type_controle text NOT NULL,
  resultat text NOT NULL,
  details_violation jsonb,
  derogation_par uuid,
  motif_derogation text,
  controle_le timestamp with time zone DEFAULT now()
);

CREATE TABLE consentements_ping_gps (
  soignant_id uuid NOT NULL,
  consenti boolean NOT NULL DEFAULT false,
  consenti_le timestamp with time zone,
  retire_le timestamp with time zone,
  version_cgu text DEFAULT 'v1'::text,
  cree_le timestamp with time zone NOT NULL DEFAULT now(),
  maj_le timestamp with time zone NOT NULL DEFAULT now()
);

CREATE TABLE contrats_mission (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  mission_id uuid NOT NULL,
  etablissement_id uuid NOT NULL,
  soignant_id uuid NOT NULL,
  type_contrat text NOT NULL,
  numero_contrat text NOT NULL,
  contenu_html text,
  signature_etablissement boolean DEFAULT false,
  signature_etablissement_le timestamp with time zone,
  signature_soignant boolean DEFAULT false,
  signature_soignant_le timestamp with time zone,
  statut text DEFAULT 'BROUILLON'::text,
  pdf_cle_s3 text,
  cree_le timestamp with time zone DEFAULT now(),
  modifie_le timestamp with time zone DEFAULT now(),
  signature_image_soignant text,
  signature_image_etablissement text,
  signature_ip_soignant inet,
  signature_ip_etablissement inet,
  signature_navigateur_soignant text,
  signature_navigateur_etablissement text,
  rappel_dpae_affiche boolean DEFAULT false,
  rappel_dpae_affiche_le timestamp with time zone,
  dpae_effectuee boolean DEFAULT false,
  dpae_effectuee_le timestamp with time zone,
  mode_signature text DEFAULT 'CANVAS'::text,
  dpae_numero text,
  storage_path text,
  hash_document text,
  template_slug text,
  contenu_html_rendu_le timestamp with time zone
);

CREATE TABLE contrats_service_signatures (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  etablissement_id uuid NOT NULL,
  version text NOT NULL DEFAULT 'v1.0'::text,
  signed_at timestamp with time zone NOT NULL DEFAULT now(),
  ip_address text,
  user_agent text,
  contenu_hash text,
  pdf_url text,
  revoked_at timestamp with time zone,
  motif_revocation text,
  cree_le timestamp with time zone NOT NULL DEFAULT now(),
  signature_s3_key text
);

CREATE TABLE contrats_travail_missions (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  mission_id uuid NOT NULL,
  etablissement_id uuid NOT NULL,
  soignant_id uuid,
  pdf_s3_key text NOT NULL,
  nom_fichier text,
  taille_octets integer,
  uploaded_at timestamp with time zone NOT NULL DEFAULT now(),
  uploaded_by uuid NOT NULL,
  cree_le timestamp with time zone NOT NULL DEFAULT now(),
  ia_resultat jsonb,
  ia_coherent boolean,
  ia_verifie_le timestamp with time zone
);

CREATE TABLE conversations (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  participant_1_id uuid NOT NULL,
  participant_2_id uuid NOT NULL,
  mission_id uuid,
  dernier_message_le timestamp with time zone,
  cree_le timestamp with time zone DEFAULT now(),
  archived_at timestamp with time zone
);

CREATE TABLE conversions_liberal (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  soignant_id uuid NOT NULL,
  heures_plateforme_au_demarrage numeric(10,2) NOT NULL,
  heures_externes_validees numeric(10,2) DEFAULT 0,
  heures_totales numeric(10,2) NOT NULL,
  statut text DEFAULT 'INITIE'::text,
  free_transition_eligible boolean DEFAULT false,
  taux_prise_en_charge integer DEFAULT 0,
  montant_pris_en_charge numeric(8,2) DEFAULT 0,
  indy_active boolean DEFAULT false,
  indy_lien_affiliation text,
  qonto_active boolean DEFAULT false,
  qonto_lien_affiliation text,
  macsf_active boolean DEFAULT false,
  macsf_lien_affiliation text,
  guide_pdf_genere boolean DEFAULT false,
  guide_pdf_cle_s3 text,
  demarre_le timestamp with time zone DEFAULT now(),
  siret_recu_le date,
  complete_le timestamp with time zone,
  cree_le timestamp with time zone DEFAULT now(),
  modifie_le timestamp with time zone DEFAULT now()
);

CREATE TABLE cotisations_sociales (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  mission_id uuid NOT NULL,
  soignant_id uuid NOT NULL,
  type_contrat text NOT NULL,
  salaire_brut numeric NOT NULL,
  csg_deductible numeric NOT NULL DEFAULT 0,
  csg_non_deductible numeric NOT NULL DEFAULT 0,
  crds numeric NOT NULL DEFAULT 0,
  securite_sociale_maladie numeric NOT NULL DEFAULT 0,
  securite_sociale_vieillesse_plafonnee numeric NOT NULL DEFAULT 0,
  securite_sociale_vieillesse_deplafonnee numeric NOT NULL DEFAULT 0,
  retraite_complementaire_t1 numeric NOT NULL DEFAULT 0,
  retraite_complementaire_t2 numeric NOT NULL DEFAULT 0,
  assurance_chomage numeric NOT NULL DEFAULT 0,
  contribution_equilibre_general numeric NOT NULL DEFAULT 0,
  patronal_securite_sociale numeric NOT NULL DEFAULT 0,
  patronal_allocations_familiales numeric NOT NULL DEFAULT 0,
  patronal_accident_travail numeric NOT NULL DEFAULT 0,
  patronal_retraite_complementaire numeric NOT NULL DEFAULT 0,
  patronal_chomage numeric NOT NULL DEFAULT 0,
  patronal_fnal numeric NOT NULL DEFAULT 0,
  patronal_formation numeric NOT NULL DEFAULT 0,
  patronal_transport numeric NOT NULL DEFAULT 0,
  total_cotisations_salariales numeric NOT NULL DEFAULT 0,
  total_cotisations_patronales numeric NOT NULL DEFAULT 0,
  net_avant_impot numeric NOT NULL DEFAULT 0,
  cout_total_employeur numeric NOT NULL DEFAULT 0,
  ifm numeric NOT NULL DEFAULT 0,
  icp numeric NOT NULL DEFAULT 0,
  calcule_le timestamp with time zone DEFAULT now(),
  cree_le timestamp with time zone DEFAULT now()
);

CREATE TABLE credits_etablissement (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  etablissement_id uuid NOT NULL,
  montant_eur numeric NOT NULL,
  motif credit_etab_motif NOT NULL,
  parrainage_id uuid,
  applique_le timestamp with time zone,
  facture_id uuid,
  cree_le timestamp with time zone NOT NULL DEFAULT now()
);

CREATE TABLE demandes_rgpd (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  demandeur_id uuid NOT NULL,
  type_demandeur text NOT NULL,
  type_demande text NOT NULL,
  statut text DEFAULT 'EN_ATTENTE'::text,
  motif text,
  traite_par uuid,
  traite_le timestamp with time zone,
  cle_s3_export text,
  resultat_json jsonb,
  cree_le timestamp with time zone DEFAULT now(),
  termine_le timestamp with time zone
);

CREATE TABLE documents_requis_par_profession (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  profession type_profession NOT NULL,
  type_document type_document NOT NULL,
  est_critique boolean DEFAULT true,
  a_expiration boolean DEFAULT true,
  duree_validite_mois integer,
  description text,
  type_exercice_requis text NOT NULL DEFAULT 'TOUS'::text
);

CREATE TABLE documents_soignants (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  soignant_id uuid NOT NULL,
  type_document type_document NOT NULL,
  libelle text,
  s3_bucket text NOT NULL DEFAULT 'jolene-documents'::text,
  s3_cle text NOT NULL,
  s3_version_id text,
  nom_fichier text NOT NULL,
  type_mime text,
  taille_octets bigint,
  valide_depuis date,
  valide_jusqua date,
  statut_verification statut_verification DEFAULT 'EN_ATTENTE'::statut_verification,
  verifie_par uuid,
  verifie_le timestamp with time zone,
  motif_rejet text,
  est_critique boolean DEFAULT false,
  rappel_j30_envoye boolean DEFAULT false,
  rappel_j7_envoye boolean DEFAULT false,
  rappel_expire_envoye boolean DEFAULT false,
  televerse_le timestamp with time zone DEFAULT now(),
  modifie_le timestamp with time zone DEFAULT now(),
  supprime_le timestamp with time zone,
  resultat_ia jsonb,
  nom_extrait_ia text,
  prenom_extrait_ia text,
  coherence_nom boolean,
  score_confiance_ia numeric
);

CREATE TABLE email_queue (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  type text NOT NULL,
  destinataire_id uuid,
  destinataire_email text,
  data jsonb DEFAULT '{}'::jsonb,
  envoye boolean DEFAULT false,
  envoye_le timestamp with time zone,
  erreur text,
  cree_le timestamp with time zone NOT NULL DEFAULT now(),
  statut text NOT NULL DEFAULT 'EN_ATTENTE'::text
);

CREATE TABLE emails_envoyes (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  destinataire_email text NOT NULL,
  destinataire_id uuid,
  type text NOT NULL,
  sujet text NOT NULL,
  provider_id text,
  statut text DEFAULT 'ENVOYE'::text,
  erreur text,
  cree_le timestamp with time zone DEFAULT now()
);

CREATE TABLE emails_post_mission (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  mission_id uuid NOT NULL,
  cible text NOT NULL,
  envoye_le timestamp with time zone NOT NULL DEFAULT now()
);

CREATE TABLE equipe_admin (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  user_id uuid,
  nom text NOT NULL,
  prenom text NOT NULL,
  email text NOT NULL,
  poste text NOT NULL DEFAULT 'Opérations'::text,
  salaire_brut_mensuel numeric(10,2) DEFAULT 0,
  date_embauche date,
  acces_groupes text[] NOT NULL DEFAULT ARRAY['Dashboard'::text],
  actif boolean NOT NULL DEFAULT true,
  cree_le timestamp with time zone NOT NULL DEFAULT now(),
  maj_le timestamp with time zone NOT NULL DEFAULT now()
);

CREATE TABLE equipe_membres (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  equipe_id uuid NOT NULL,
  soignant_id uuid NOT NULL,
  role_equipe text DEFAULT 'MEMBRE'::text,
  depuis_le timestamp with time zone DEFAULT now()
);

CREATE TABLE equipes (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  etablissement_id uuid NOT NULL,
  nom text NOT NULL,
  service text,
  couleur text DEFAULT '#E04590'::text,
  cree_le timestamp with time zone DEFAULT now(),
  supprime_le timestamp with time zone
);

CREATE TABLE equivalences_scolarite (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  formation text NOT NULL,
  libelle_formation text NOT NULL,
  annee_validee_min integer NOT NULL,
  profession_autorisee type_profession NOT NULL,
  base_reglementaire text,
  actif boolean NOT NULL DEFAULT true,
  cree_le timestamp with time zone NOT NULL DEFAULT now()
);

CREATE TABLE etablissements (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  nom text NOT NULL,
  siret varchar(14) NOT NULL,
  finess varchar(9),
  type type_etablissement NOT NULL,
  groupe_sante_id uuid,
  adresse_rue text NOT NULL,
  adresse_ville text NOT NULL,
  adresse_code_postal varchar(5) NOT NULL,
  adresse_departement varchar(3),
  adresse_lat numeric(10,7),
  adresse_lng numeric(10,7),
  email_contact text NOT NULL,
  telephone_contact varchar(20),
  formule_abonnement text DEFAULT 'GRATUIT'::text,
  rist_plafond_actif boolean DEFAULT true,
  rist_taux_base_horaire numeric(8,2) DEFAULT 25.00,
  taux_majoration_nuit_pourcent numeric(5,2) DEFAULT 25.00,
  taux_majoration_dimanche_pourcent numeric(5,2) DEFAULT 50.00,
  taux_majoration_ferie_pourcent numeric(5,2) DEFAULT 100.00,
  cree_le timestamp with time zone DEFAULT now(),
  modifie_le timestamp with time zone DEFAULT now(),
  supprime_le timestamp with time zone,
  stripe_customer_id text,
  taux_commission_negocie numeric(5,2) DEFAULT 15.00,
  mode_facturation text DEFAULT 'PAR_MISSION'::text,
  palier_commission_id uuid,
  missions_mois_precedent integer DEFAULT 0,
  palier_recalcule_le date,
  chorus_pro_actif boolean DEFAULT false,
  chorus_pro_identifiant text,
  delai_paiement_jours integer DEFAULT 30,
  convention_collective text,
  couleur_theme text DEFAULT '#17A2B8'::text,
  logo_url text,
  mode_paiement_commission text DEFAULT 'FACTURE_MENSUELLE'::text,
  contrat_url text,
  contrat_uploade_le timestamp with time zone,
  contrat_valide boolean DEFAULT false,
  stripe_account_id text,
  siret_verifie boolean DEFAULT false,
  siret_verifie_le timestamp with time zone,
  finess_verifie boolean DEFAULT false,
  finess_verifie_le timestamp with time zone,
  statut_verification text DEFAULT 'EN_ATTENTE'::text,
  verifie_par uuid,
  verifie_le timestamp with time zone,
  motif_rejet text,
  peut_publier_missions boolean DEFAULT false,
  siret_raison_sociale text,
  siret_categorie_juridique text,
  siret_code_naf text,
  siret_est_actif boolean,
  est_secteur_public boolean DEFAULT false,
  note_moyenne numeric(3,2) DEFAULT NULL::numeric,
  nb_evaluations integer DEFAULT 0,
  description text,
  horaires_ouverture jsonb,
  stripe_sepa_payment_method_id text,
  sms_actif boolean DEFAULT false,
  sms_consent_le timestamp with time zone,
  heure_debut_nuit time without time zone DEFAULT '21:00:00'::time without time zone,
  heure_fin_nuit time without time zone DEFAULT '06:00:00'::time without time zone,
  bloque_auto_le timestamp with time zone,
  bloque_auto_raisons jsonb,
  contrat_service_signe boolean NOT NULL DEFAULT false,
  contrat_service_signe_le timestamp with time zone,
  rib_s3_key text,
  code_parrainage text,
  parraine_par_id uuid,
  score_qualite numeric,
  niveau niveau_qualitatif,
  tolerance_pointage_m integer NOT NULL DEFAULT 100,
  onboarding_etapes_completees jsonb NOT NULL DEFAULT '[]'::jsonb,
  onboarding_termine_le timestamp with time zone,
  telephone_verifie boolean NOT NULL DEFAULT false,
  telephone_verifie_le timestamp with time zone,
  telephone_en_attente_verification text,
  finess_raison_sociale text,
  finess_categorie text,
  finess_secteur text,
  finess_est_public boolean,
  dirigeants jsonb,
  representant_nom text,
  representant_prenom text,
  representant_identite_verifiee boolean NOT NULL DEFAULT false,
  representant_identite_verifiee_le timestamp with time zone,
  rattachement_methode text,
  rattachement_verifie boolean NOT NULL DEFAULT false,
  rattachement_verifie_le timestamp with time zone,
  email_contact_verifie boolean NOT NULL DEFAULT false,
  email_contact_verifie_le timestamp with time zone,
  representant_piece_s3_key text,
  representant_piece_type_mime text,
  representant_piece_type_document text,
  representant_identite_resultat_ia jsonb,
  email_contact_token text,
  email_contact_token_expire_le timestamp with time zone,
  contrat_ia_resultat jsonb,
  contrat_ia_coherent boolean,
  contrat_ia_verifie_le timestamp with time zone,
  rib_ia_resultat jsonb,
  rib_ia_coherent boolean,
  rib_ia_verifie_le timestamp with time zone,
  utm_source text,
  utm_medium text,
  utm_campaign text,
  utm_content text,
  utm_term text,
  http_referrer text,
  ref_capture text,
  source_acquisition text,
  bfa_eligible boolean NOT NULL DEFAULT false,
  bfa_taux numeric,
  bfa_contrat_signe_le date,
  coherence_identite text,
  justificatif_fonction_s3_key text,
  justificatif_fonction_type text,
  justificatif_fonction_type_mime text,
  justificatif_fonction_verifie boolean,
  justificatif_fonction_verifie_le timestamp with time zone,
  justificatif_fonction_resultat_ia jsonb,
  iban_last4 text,
  est_compte_test boolean NOT NULL DEFAULT false,
  jour_paie_habituel smallint
);

CREATE TABLE evaluations (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  mission_id uuid NOT NULL,
  evaluateur_id uuid NOT NULL,
  evalue_id uuid NOT NULL,
  type_evaluateur text NOT NULL,
  note integer NOT NULL,
  commentaire text,
  visible boolean DEFAULT true,
  cree_le timestamp with time zone DEFAULT now()
);

CREATE TABLE evenements_score_etab (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  etablissement_id uuid NOT NULL,
  type_evenement text NOT NULL,
  points integer NOT NULL,
  motif text NOT NULL,
  contestable boolean NOT NULL DEFAULT true,
  reclamation_id uuid,
  decision_admin text,
  points_corriges integer,
  motif_admin text,
  traite_par_admin_id uuid,
  traite_le timestamp with time zone,
  mission_id uuid,
  litige_id uuid,
  facture_id uuid,
  justificatif_storage_path text,
  details jsonb DEFAULT '{}'::jsonb,
  cree_le timestamp with time zone NOT NULL DEFAULT now()
);

CREATE TABLE evenements_score_soignant (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  soignant_id uuid NOT NULL,
  type_evenement text NOT NULL,
  points integer NOT NULL,
  motif text NOT NULL,
  contestable boolean NOT NULL DEFAULT true,
  reclamation_id uuid,
  decision_admin text,
  points_corriges integer,
  motif_admin text,
  traite_par_admin_id uuid,
  traite_le timestamp with time zone,
  mission_id uuid,
  candidature_id uuid,
  litige_id uuid,
  justificatif_storage_path text,
  details jsonb DEFAULT '{}'::jsonb,
  cree_le timestamp with time zone NOT NULL DEFAULT now()
);

CREATE TABLE exclusions (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  exclu_par uuid NOT NULL,
  exclu_id uuid NOT NULL,
  type_exclu_par text NOT NULL,
  motif text,
  cree_le timestamp with time zone DEFAULT now()
);

CREATE TABLE externalisation_actions (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  type_action text NOT NULL,
  payload jsonb NOT NULL,
  source text NOT NULL,
  source_id uuid,
  statut text NOT NULL DEFAULT 'PENDING'::text,
  tentatives integer NOT NULL DEFAULT 0,
  derniere_tentative_le timestamp with time zone,
  derniere_erreur text,
  resultat jsonb,
  cree_le timestamp with time zone NOT NULL DEFAULT now(),
  traite_le timestamp with time zone,
  next_retry_at timestamp with time zone,
  cron_lock_at timestamp with time zone,
  cron_lock_par text
);

CREATE TABLE factor_advances (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  facture_honoraire_id uuid NOT NULL,
  soignant_id uuid NOT NULL,
  etablissement_id uuid NOT NULL,
  mission_id uuid,
  provider text NOT NULL DEFAULT 'defacto'::text,
  provider_advance_id text,
  provider_invoice_id text,
  montant_facture_ttc numeric(10,2) NOT NULL,
  frais_factor numeric(10,2),
  frais_jolene numeric(10,2) DEFAULT 0,
  montant_net_soignant numeric(10,2),
  statut text NOT NULL DEFAULT 'DEMANDEE'::text,
  motif_rejet text,
  cree_le timestamp with time zone NOT NULL DEFAULT now(),
  approuvee_le timestamp with time zone,
  financee_le timestamp with time zone,
  recouvree_le timestamp with time zone,
  modifie_le timestamp with time zone NOT NULL DEFAULT now(),
  raw_response jsonb
);

CREATE TABLE factoring_partners (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  legal_name text NOT NULL,
  siret text NOT NULL,
  iban text NOT NULL,
  bic text,
  address text,
  contact_email text,
  subrogation_template text,
  webhook_url text,
  api_credentials jsonb,
  active boolean NOT NULL DEFAULT true,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone DEFAULT now()
);

CREATE TABLE factures (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  etablissement_id uuid NOT NULL,
  numero_facture text NOT NULL,
  periode_debut date,
  periode_fin date,
  montant_ht numeric(10,2) NOT NULL,
  taux_tva numeric(5,2) DEFAULT 20.00,
  montant_tva numeric(10,2) NOT NULL,
  montant_ttc numeric(10,2) NOT NULL,
  nombre_missions integer DEFAULT 0,
  stripe_invoice_id text,
  stripe_payment_intent_id text,
  stripe_hosted_url text,
  statut text DEFAULT 'BROUILLON'::text,
  date_emission timestamp with time zone,
  date_echeance date,
  date_paiement timestamp with time zone,
  cree_le timestamp with time zone DEFAULT now(),
  modifie_le timestamp with time zone DEFAULT now(),
  chorus_pro_id text,
  chorus_pro_statut text DEFAULT 'NON_APPLICABLE'::text,
  chorus_pro_deposee_le timestamp with time zone,
  est_secteur_public boolean DEFAULT false,
  mode_paiement text DEFAULT 'STRIPE'::text,
  virement_confirme_par uuid,
  virement_confirme_le timestamp with time zone,
  virement_reference text,
  chorus_pro_numero_flux text,
  chorus_pro_date_depot timestamp with time zone,
  chorus_pro_date_acceptation timestamp with time zone,
  mission_id uuid,
  type_document text NOT NULL DEFAULT 'FACTURE'::text,
  facture_precedente_id uuid,
  montant_signe numeric(12,2),
  relance_1_le timestamp with time zone,
  relance_2_le timestamp with time zone,
  bloque_le timestamp with time zone
);

CREATE TABLE factures_honoraires (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  numero_facture text NOT NULL,
  soignant_id uuid NOT NULL,
  etablissement_id uuid NOT NULL,
  mission_id uuid,
  montant_ht numeric(10,2) NOT NULL,
  montant_tva numeric(10,2) NOT NULL DEFAULT 0,
  montant_ttc numeric(10,2) NOT NULL,
  taux_tva numeric(4,2) DEFAULT 0,
  exoneration_tva boolean DEFAULT true,
  date_emission date NOT NULL DEFAULT CURRENT_DATE,
  date_echeance date,
  date_paiement date,
  statut text NOT NULL DEFAULT 'BROUILLON'::text,
  mandat_version text,
  pdf_s3_key text,
  cree_le timestamp with time zone NOT NULL DEFAULT now(),
  modifie_le timestamp with time zone NOT NULL DEFAULT now(),
  factor_assigned boolean NOT NULL DEFAULT false,
  factor_id uuid,
  subrogation_mention text,
  facturx_xml_url text,
  chorus_submission_id uuid,
  chorus_submission_status text,
  chorus_last_sync_at timestamp with time zone,
  is_public_sector boolean NOT NULL DEFAULT false,
  siret_client text,
  service_code_chorus text,
  engagement_juridique text,
  updated_at timestamp with time zone DEFAULT now(),
  template_version text NOT NULL DEFAULT 'v1'::text,
  admin_notes text,
  type_document type_document_facture NOT NULL DEFAULT 'FACTURE'::type_document_facture,
  statut_litige statut_litige_facture NOT NULL DEFAULT 'NORMAL'::statut_litige_facture,
  litige_id uuid,
  facture_precedente_id uuid,
  mode_remboursement mode_remboursement_avoir NOT NULL DEFAULT 'N_A'::mode_remboursement_avoir,
  date_remboursement timestamp with time zone,
  reference_remboursement text,
  montant_signe numeric(12,2),
  pdf_a_regenerer boolean NOT NULL DEFAULT false,
  stripe_payment_intent_id text,
  chorus_avoir_reference_invoice text,
  periode_debut date NOT NULL,
  periode_fin date NOT NULL,
  numero_semaine_iso smallint,
  annee_iso smallint,
  est_facture_finale_mission boolean NOT NULL DEFAULT true
);

CREATE TABLE favoris_etab_soignant (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  etablissement_id uuid NOT NULL,
  soignant_id uuid NOT NULL,
  cree_le timestamp with time zone DEFAULT now()
);

CREATE TABLE favoris_soignant_etab (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  soignant_id uuid NOT NULL,
  etablissement_id uuid NOT NULL,
  cree_le timestamp with time zone NOT NULL DEFAULT now()
);

CREATE TABLE file_revue_manuelle (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  type_entite text NOT NULL,
  id_entite uuid NOT NULL,
  service_en_echec text NOT NULL,
  motif_echec text,
  donnees_originales jsonb,
  statut text DEFAULT 'EN_ATTENTE'::text,
  priorite integer DEFAULT 1,
  assigne_a uuid,
  notes_resolution text,
  cree_le timestamp with time zone DEFAULT now(),
  revu_le timestamp with time zone,
  resolu_le timestamp with time zone,
  expire_le timestamp with time zone DEFAULT (now() + '24:00:00'::interval)
);

CREATE TABLE filtres_sauvegardes (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  utilisateur_id uuid NOT NULL,
  nom text NOT NULL,
  audience filtre_audience NOT NULL,
  filtres jsonb NOT NULL DEFAULT '{}'::jsonb,
  alerte_active boolean NOT NULL DEFAULT false,
  frequence_alerte filtre_frequence_alerte NOT NULL DEFAULT 'QUOTIDIENNE'::filtre_frequence_alerte,
  dernier_check_le timestamp with time zone NOT NULL DEFAULT now(),
  nb_resultats_dernier_check integer NOT NULL DEFAULT 0,
  cree_le timestamp with time zone NOT NULL DEFAULT now(),
  mis_a_jour_le timestamp with time zone NOT NULL DEFAULT now()
);

CREATE TABLE fondateur_documents (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  titre text NOT NULL,
  categorie text NOT NULL DEFAULT 'NOTE'::text,
  contenu text,
  url_externe text,
  cree_le timestamp with time zone NOT NULL DEFAULT now(),
  maj_le timestamp with time zone NOT NULL DEFAULT now()
);

CREATE TABLE groupes_sante (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  nom text NOT NULL,
  siren varchar(9),
  groupe_parent_id uuid,
  email_admin text,
  telephone_admin varchar(20),
  raison_sociale_facturation text,
  siret_facturation varchar(14),
  adresse_facturation text,
  remise_groupe_pourcent numeric(5,2) DEFAULT 0,
  rist_plafond_personnalise boolean DEFAULT false,
  formule_abonnement text DEFAULT 'ENTERPRISE'::text,
  cree_le timestamp with time zone DEFAULT now(),
  modifie_le timestamp with time zone DEFAULT now(),
  supprime_le timestamp with time zone,
  logo_url text,
  couleur_primaire text DEFAULT '#17A2B8'::text,
  couleur_secondaire text DEFAULT '#0F172A'::text,
  nom_marque text,
  domaine_custom text,
  bfa_eligible boolean DEFAULT false,
  bfa_contrat_signe_le timestamp with time zone,
  taux_commission_negocie numeric,
  contrat_debut date,
  contrat_fin date,
  bfa_taux numeric
);

CREATE TABLE growth_config (
  cle text NOT NULL,
  valeur text,
  maj_le timestamp with time zone NOT NULL DEFAULT now()
);

CREATE TABLE health_check (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  service text NOT NULL,
  statut text DEFAULT 'OK'::text,
  latence_ms integer,
  details jsonb,
  verifie_le timestamp with time zone DEFAULT now()
);

CREATE TABLE heures_externes (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  soignant_id uuid NOT NULL,
  employeur_nom text NOT NULL,
  employeur_type text,
  date_debut date NOT NULL,
  date_fin date NOT NULL,
  heures_declarees numeric(10,2) NOT NULL,
  document_id uuid,
  type_preuve text,
  statut text DEFAULT 'EN_ATTENTE'::text,
  validee_par uuid,
  validee_le timestamp with time zone,
  motif_rejet text,
  cree_le timestamp with time zone DEFAULT now(),
  modifie_le timestamp with time zone DEFAULT now()
);

CREATE TABLE heures_externes_soignants (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  soignant_id uuid NOT NULL,
  etablissement_nom text NOT NULL,
  etablissement_type text,
  date_debut date NOT NULL,
  date_fin date NOT NULL,
  heures_declarees integer NOT NULL,
  attestation_url text,
  attestation_nom_fichier text,
  statut_validation text DEFAULT 'EN_ATTENTE'::text,
  commentaire_validation text,
  valide_par uuid,
  valide_le timestamp with time zone,
  cree_le timestamp with time zone DEFAULT now(),
  mis_a_jour_le timestamp with time zone DEFAULT now(),
  heures_extraites_ia integer,
  resultat_ia jsonb,
  coherence_ia boolean,
  verifie_ia_le timestamp with time zone
);

CREATE TABLE historique_blocages_etablissements (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  etablissement_id uuid NOT NULL,
  action text NOT NULL,
  raisons jsonb,
  cree_le timestamp with time zone NOT NULL DEFAULT now()
);

CREATE TABLE investisseurs_pipeline (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  nom text NOT NULL,
  type text NOT NULL DEFAULT 'VC'::text,
  contact_nom text,
  contact_email text,
  statut text NOT NULL DEFAULT 'A_CONTACTER'::text,
  montant_vise numeric(12,2),
  notes text,
  derniere_interaction timestamp with time zone,
  cree_le timestamp with time zone NOT NULL DEFAULT now(),
  maj_le timestamp with time zone NOT NULL DEFAULT now()
);

CREATE TABLE invitations_etablissement (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  etablissement_id uuid NOT NULL,
  email_invite text NOT NULL,
  role_propose text NOT NULL,
  token text NOT NULL DEFAULT encode(gen_random_bytes(24), 'hex'::text),
  expire_le timestamp with time zone NOT NULL DEFAULT (now() + '7 days'::interval),
  statut text NOT NULL DEFAULT 'EN_ATTENTE'::text,
  invite_par uuid NOT NULL,
  invite_le timestamp with time zone NOT NULL DEFAULT now(),
  acceptee_le timestamp with time zone,
  acceptee_par_user_id uuid,
  cree_le timestamp with time zone NOT NULL DEFAULT now()
);

CREATE TABLE invoice_audit_log (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  invoice_id uuid NOT NULL,
  action text NOT NULL,
  actor_id uuid,
  payload_before jsonb,
  payload_after jsonb,
  created_at timestamp with time zone NOT NULL DEFAULT now()
);

CREATE TABLE journaux_audit (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  acteur_id uuid,
  type_acteur text NOT NULL,
  ip_acteur inet,
  navigateur_acteur text,
  action text NOT NULL,
  type_ressource text,
  id_ressource uuid,
  cle_s3_ressource text,
  details jsonb,
  cree_le timestamp with time zone DEFAULT now()
);

CREATE TABLE jours_feries_fr (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  date_ferie date NOT NULL,
  nom text NOT NULL,
  est_recurrent boolean DEFAULT false,
  mois_recurrent integer,
  jour_recurrent integer,
  annee integer,
  cree_le timestamp with time zone DEFAULT now()
);

CREATE TABLE liste_attente_premium (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  utilisateur_id uuid,
  email text NOT NULL,
  type_offre text NOT NULL,
  cree_le timestamp with time zone DEFAULT now()
);

CREATE TABLE litiges (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  presence_id uuid,
  mission_id uuid NOT NULL,
  soignant_id uuid NOT NULL,
  etablissement_id uuid NOT NULL,
  initie_par text NOT NULL,
  motif text NOT NULL,
  reponse text,
  statut text DEFAULT 'OUVERT'::text,
  resolu_par uuid,
  resolution text,
  cree_le timestamp with time zone DEFAULT now(),
  resolu_le timestamp with time zone,
  accord_soignant boolean DEFAULT false,
  accord_etablissement boolean DEFAULT false,
  accord_soignant_le timestamp with time zone,
  accord_etablissement_le timestamp with time zone,
  paiement_soignant_id uuid,
  type_litige type_litige NOT NULL DEFAULT 'AUTRE'::type_litige,
  categorie_litige categorie_litige NOT NULL DEFAULT 'AUTRE'::categorie_litige,
  facture_id uuid,
  est_informatif boolean NOT NULL DEFAULT false,
  type_legacy boolean NOT NULL DEFAULT false,
  montant_tresorerie_bloquee numeric(12,2),
  derniers_rappels_envoyes jsonb NOT NULL DEFAULT '{}'::jsonb,
  escalade_auto_le timestamp with time zone,
  escalade_auto_motif text,
  gel_facture_scope text NOT NULL DEFAULT 'MISSION_ENTIERE'::text,
  periode_debut date,
  periode_fin date,
  payload_modifications jsonb,
  modifications_executees boolean NOT NULL DEFAULT false,
  modifications_executees_a timestamp with time zone,
  modifications_executees_par uuid
);

CREATE TABLE mandats_facturation_signatures (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  soignant_id uuid NOT NULL,
  version text NOT NULL,
  signed_at timestamp with time zone NOT NULL DEFAULT now(),
  ip_address text,
  user_agent text,
  contenu_hash text,
  cree_le timestamp with time zone NOT NULL DEFAULT now(),
  pdf_url text,
  revoked_at timestamp with time zone
);

CREATE TABLE marche_taux_medians (
  profession text NOT NULL,
  taux_median numeric NOT NULL,
  nb_missions integer NOT NULL DEFAULT 0,
  calcule_le timestamp with time zone NOT NULL DEFAULT now()
);

CREATE TABLE matching_preferences_soignant (
  soignant_id uuid NOT NULL,
  pref_nuit numeric NOT NULL DEFAULT 0.5,
  pref_jour numeric NOT NULL DEFAULT 0.5,
  pref_weekend numeric NOT NULL DEFAULT 0.5,
  pref_semaine numeric NOT NULL DEFAULT 0.5,
  nb_signaux integer NOT NULL DEFAULT 0,
  maj_le timestamp with time zone NOT NULL DEFAULT now()
);

CREATE TABLE matching_scores (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  soignant_id uuid NOT NULL,
  mission_id uuid NOT NULL,
  score_global integer NOT NULL,
  breakdown jsonb NOT NULL DEFAULT '{}'::jsonb,
  calcule_le timestamp with time zone NOT NULL DEFAULT now()
);

CREATE TABLE membres_etablissement (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  etablissement_id uuid NOT NULL,
  user_id uuid NOT NULL,
  role text NOT NULL,
  invite_par uuid,
  invite_le timestamp with time zone,
  accepte_le timestamp with time zone NOT NULL DEFAULT now(),
  actif boolean NOT NULL DEFAULT true,
  cree_le timestamp with time zone NOT NULL DEFAULT now(),
  maj_le timestamp with time zone NOT NULL DEFAULT now()
);

CREATE TABLE messages_chat (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  conversation_id uuid NOT NULL,
  auteur_id uuid NOT NULL,
  contenu text NOT NULL,
  lu boolean DEFAULT false,
  est_admin boolean DEFAULT false,
  cree_le timestamp with time zone DEFAULT now()
);

CREATE TABLE messages_contact (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  expediteur_id uuid,
  expediteur_role text,
  expediteur_nom text,
  expediteur_email text,
  sujet text NOT NULL,
  corps text NOT NULL,
  source text NOT NULL DEFAULT 'aide'::text,
  statut text NOT NULL DEFAULT 'NOUVEAU'::text,
  cree_le timestamp with time zone NOT NULL DEFAULT now(),
  traite_le timestamp with time zone,
  traite_par uuid
);

CREATE TABLE messages_litige (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  litige_id uuid NOT NULL,
  auteur_id uuid NOT NULL,
  type_auteur text NOT NULL,
  contenu text NOT NULL,
  cree_le timestamp with time zone DEFAULT now()
);

CREATE TABLE messages_mission (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  mission_id uuid NOT NULL,
  auteur_id uuid NOT NULL,
  type_auteur text NOT NULL,
  contenu text NOT NULL,
  lu boolean DEFAULT false,
  cree_le timestamp with time zone DEFAULT now()
);

CREATE TABLE mission_creneaux (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  mission_id uuid NOT NULL,
  debut timestamp with time zone NOT NULL,
  fin timestamp with time zone,
  est_pause boolean NOT NULL DEFAULT false,
  type_pause text,
  ordre smallint NOT NULL DEFAULT 1,
  cree_le timestamp with time zone NOT NULL DEFAULT now(),
  modifie_le timestamp with time zone NOT NULL DEFAULT now(),
  type_creneau text NOT NULL DEFAULT 'PREVISIONNEL'::text
);

CREATE TABLE mission_series (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  etablissement_id uuid NOT NULL,
  cree_par uuid DEFAULT auth.uid(),
  motif text,
  nb_missions_prevues integer NOT NULL DEFAULT 1,
  cree_le timestamp with time zone NOT NULL DEFAULT now(),
  modifie_le timestamp with time zone NOT NULL DEFAULT now()
);

CREATE TABLE missions (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  etablissement_id uuid NOT NULL,
  intitule text NOT NULL,
  description text,
  profession_requise type_profession NOT NULL,
  service text,
  debut_le timestamp with time zone NOT NULL,
  fin_le timestamp with time zone NOT NULL,
  duree_heures numeric(5,2),
  taux_horaire_base numeric(8,2) NOT NULL,
  taux_rist_plafonne numeric(8,2),
  rist_plafond_applique boolean DEFAULT false,
  heures_nuit numeric(5,2) DEFAULT 0,
  heures_dimanche numeric(5,2) DEFAULT 0,
  heures_ferie numeric(5,2) DEFAULT 0,
  montant_majoration_nuit numeric(8,2) DEFAULT 0,
  montant_majoration_dimanche numeric(8,2) DEFAULT 0,
  montant_majoration_ferie numeric(8,2) DEFAULT 0,
  taux_ifm numeric(5,4) DEFAULT 0.10,
  taux_icp numeric(5,4) DEFAULT 0.10,
  montant_ifm numeric(8,2) DEFAULT 0,
  montant_icp numeric(8,2) DEFAULT 0,
  total_brut numeric(10,2) DEFAULT 0,
  net_a_payer numeric(10,2) DEFAULT 0,
  est_urgente boolean DEFAULT false,
  niveau_urgence integer DEFAULT 0,
  statut statut_mission DEFAULT 'OUVERTE'::statut_mission,
  soignant_assigne_id uuid,
  cree_le timestamp with time zone DEFAULT now(),
  modifie_le timestamp with time zone DEFAULT now(),
  taux_commission numeric(5,2) DEFAULT 15.00,
  montant_commission_ht numeric(10,2),
  montant_commission_tva numeric(10,2),
  montant_commission_ttc numeric(10,2),
  commission_facturee boolean DEFAULT false,
  facture_id uuid,
  type_paiement_soignant text DEFAULT 'BULLETIN_PAIE'::text,
  numero_note_honoraires text,
  code_arrivee text,
  code_depart text,
  net_estime numeric,
  mode_attribution text DEFAULT 'PREMIER_ARRIVE'::text,
  annulee_le timestamp with time zone,
  annulee_par uuid,
  terminee_le timestamp with time zone,
  motif_annulation text,
  serie_id uuid,
  type_contrat_recherche text NOT NULL DEFAULT 'TOUS'::text,
  stripe_payment_intent_id text,
  stripe_transfer_id text,
  mode_paiement_soignant text DEFAULT 'DIRECT'::text,
  choix_contrat_soignant text,
  nb_creneaux smallint NOT NULL DEFAULT 0,
  taux_horaire_base_fige numeric,
  taux_majoration_nuit_fige numeric,
  taux_majoration_dimanche_fige numeric,
  taux_majoration_ferie_fige numeric,
  heure_debut_nuit_fige time without time zone,
  heure_fin_nuit_fige time without time zone,
  taux_commission_fige numeric,
  fige_le timestamp with time zone,
  debut_effectif timestamp with time zone,
  fin_effective timestamp with time zone,
  duree_heures_effective numeric,
  code_pointage_actif text,
  code_pointage_hmac text,
  prochain_type_scan text DEFAULT 'OUVERTURE'::text,
  nb_scans smallint DEFAULT 0,
  regularisation_sociale_requise boolean NOT NULL DEFAULT false,
  commission_a_recalculer boolean NOT NULL DEFAULT false,
  type_contrat_applique type_contrat_applique_enum,
  relance_paiement_1_le timestamp with time zone,
  relance_paiement_2_le timestamp with time zone,
  specialite_medicale_requise text,
  accepte_non_specialises boolean DEFAULT true,
  strategie_facturation strategie_facturation NOT NULL DEFAULT 'FINALE_UNIQUE'::strategie_facturation,
  absence_sans_prevenir boolean NOT NULL DEFAULT false,
  est_asap boolean NOT NULL DEFAULT false,
  relances_sans_candidat integer NOT NULL DEFAULT 0,
  derniere_relance_sans_candidat_le timestamp with time zone,
  boostee_le timestamp with time zone,
  montant_boost_ht numeric,
  garantie_remplacement boolean NOT NULL DEFAULT false,
  presence_confirmee_le timestamp with time zone,
  remplacement_de_mission_id uuid,
  est_arret_maladie boolean NOT NULL DEFAULT false,
  arret_maladie_declare_le timestamp with time zone,
  mode_remuneration text NOT NULL DEFAULT 'TAUX_HORAIRE'::text,
  retrocession_pct numeric,
  montant_honoraires_bruts numeric,
  justificatif_honoraires_cle text,
  honoraires_confirmes_le timestamp with time zone,
  derniere_relance_candidatures_le timestamp with time zone,
  mission_source text
);

CREATE TABLE missions_sauvegardees (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  soignant_id uuid NOT NULL,
  mission_id uuid NOT NULL,
  cree_le timestamp with time zone NOT NULL DEFAULT now(),
  notifie_expiration boolean NOT NULL DEFAULT false
);

CREATE TABLE notations_missions (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  mission_id uuid NOT NULL,
  notateur_id uuid NOT NULL,
  note_id uuid NOT NULL,
  sens sens_notation NOT NULL,
  critere_1 integer NOT NULL,
  critere_2 integer NOT NULL,
  critere_3 integer NOT NULL,
  critere_4 integer NOT NULL,
  commentaire text,
  signale boolean NOT NULL DEFAULT false,
  masque boolean NOT NULL DEFAULT false,
  masque_par uuid,
  masque_le timestamp with time zone,
  cree_le timestamp with time zone NOT NULL DEFAULT now(),
  mis_a_jour_le timestamp with time zone NOT NULL DEFAULT now(),
  notateur_anonymise boolean NOT NULL DEFAULT false
);

CREATE TABLE notifications (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  destinataire_id uuid NOT NULL,
  type_destinataire text NOT NULL,
  type text NOT NULL,
  titre text NOT NULL,
  corps text NOT NULL,
  lien text,
  type_ressource text,
  id_ressource uuid,
  lue boolean DEFAULT false,
  lue_le timestamp with time zone,
  push_envoyee boolean DEFAULT false,
  push_envoyee_le timestamp with time zone,
  email_envoye boolean DEFAULT false,
  email_envoye_le timestamp with time zone,
  cree_le timestamp with time zone DEFAULT now()
);

CREATE TABLE notifications_notation_j1 (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  mission_id uuid NOT NULL,
  sens sens_notation NOT NULL,
  destinataire_id uuid NOT NULL,
  envoye_le timestamp with time zone NOT NULL DEFAULT now()
);

CREATE TABLE otps_telephone (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  telephone text NOT NULL,
  code_hash text NOT NULL,
  tentatives integer NOT NULL DEFAULT 0,
  utilise boolean NOT NULL DEFAULT false,
  cree_le timestamp with time zone NOT NULL DEFAULT now(),
  expire_le timestamp with time zone NOT NULL DEFAULT (now() + '00:10:00'::interval)
);

CREATE TABLE paiements_mission (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  mission_id uuid NOT NULL,
  etablissement_id uuid NOT NULL,
  montant_ht numeric NOT NULL,
  montant_tva numeric NOT NULL,
  montant_ttc numeric NOT NULL,
  stripe_payment_intent_id text,
  stripe_charge_id text,
  statut text DEFAULT 'EN_ATTENTE'::text,
  cree_le timestamp with time zone DEFAULT now(),
  capture_le timestamp with time zone,
  rembourse_le timestamp with time zone
);

CREATE TABLE paiements_soignant (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  mission_id uuid NOT NULL,
  soignant_id uuid NOT NULL,
  etablissement_id uuid NOT NULL,
  montant_net numeric NOT NULL,
  methode text NOT NULL,
  reference_virement text,
  date_paiement date,
  confirme_par_etablissement boolean DEFAULT false,
  confirme_par_etablissement_le timestamp with time zone,
  confirme_par_soignant boolean DEFAULT false,
  confirme_par_soignant_le timestamp with time zone,
  conteste boolean DEFAULT false,
  motif_contestation text,
  statut text NOT NULL DEFAULT 'EN_ATTENTE'::text,
  cree_le timestamp with time zone DEFAULT now(),
  modifie_le timestamp with time zone DEFAULT now(),
  echeance_le date,
  relance_1_le timestamp with time zone,
  relance_2_le timestamp with time zone,
  stripe_transfer_id text
);

CREATE TABLE paliers_bfa (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  nom text NOT NULL,
  missions_min integer NOT NULL,
  missions_max integer,
  taux_bfa numeric(5,2) NOT NULL,
  ordre integer NOT NULL,
  est_actif boolean DEFAULT true,
  cree_le timestamp with time zone DEFAULT now()
);

CREATE TABLE paliers_commission (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  nom text NOT NULL,
  missions_min integer NOT NULL,
  missions_max integer,
  taux_commission numeric(5,2) NOT NULL,
  ordre integer NOT NULL,
  est_actif boolean DEFAULT true,
  cree_le timestamp with time zone DEFAULT now()
);

CREATE TABLE parametres_litiges (
  cle text NOT NULL,
  valeur text NOT NULL,
  description text NOT NULL,
  modifie_le timestamp with time zone NOT NULL DEFAULT now(),
  modifie_par uuid
);

CREATE TABLE parametres_systeme (
  cle text NOT NULL,
  valeur numeric NOT NULL,
  label text NOT NULL,
  description text,
  unite text,
  val_min numeric,
  val_max numeric,
  categorie text NOT NULL DEFAULT 'GENERAL'::text,
  avertissement text,
  cablee boolean NOT NULL DEFAULT true,
  maj_le timestamp with time zone NOT NULL DEFAULT now()
);

CREATE TABLE parcours_liberal_soignants (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  soignant_id uuid NOT NULL,
  demarre_le timestamp with time zone DEFAULT now(),
  termine_le timestamp with time zone,
  parcours_kine text,
  etapes jsonb DEFAULT '{}'::jsonb,
  cree_le timestamp with time zone DEFAULT now(),
  mis_a_jour_le timestamp with time zone DEFAULT now()
);

CREATE TABLE parrainage_fraude_signals (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  parrainage_id uuid NOT NULL,
  type text NOT NULL,
  detail jsonb NOT NULL DEFAULT '{}'::jsonb,
  cree_le timestamp with time zone NOT NULL DEFAULT now()
);

CREATE TABLE parrainages (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  parrain_id uuid NOT NULL,
  filleul_id uuid NOT NULL,
  code_parrainage text NOT NULL,
  statut text DEFAULT 'EN_ATTENTE'::text,
  bonus_heures_parrain numeric DEFAULT 50,
  bonus_heures_filleul numeric DEFAULT 50,
  valide_le timestamp with time zone,
  cree_le timestamp with time zone DEFAULT now(),
  commission_cumulee_filleul numeric NOT NULL DEFAULT 0,
  filleul_active_le timestamp with time zone,
  prime_versee_le timestamp with time zone,
  gmv_cumule_filleul numeric NOT NULL DEFAULT 0
);

CREATE TABLE parrainages_etablissements (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  parrain_etab_id uuid NOT NULL,
  filleul_etab_id uuid NOT NULL,
  code_parrainage text NOT NULL,
  statut parrainage_etab_statut NOT NULL DEFAULT 'PENDING'::parrainage_etab_statut,
  valide_le timestamp with time zone,
  cree_le timestamp with time zone NOT NULL DEFAULT now(),
  mis_a_jour_le timestamp with time zone NOT NULL DEFAULT now()
);

CREATE TABLE partages_rib (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  soignant_id uuid NOT NULL,
  etablissement_id uuid NOT NULL,
  mission_id uuid NOT NULL,
  contrat_id uuid NOT NULL,
  actif boolean DEFAULT false,
  document_rib_id uuid,
  partage_le timestamp with time zone DEFAULT now(),
  consulte_le timestamp with time zone,
  consulte_par uuid,
  expire_le timestamp with time zone DEFAULT (now() + '30 days'::interval)
);

CREATE TABLE pauses_presence (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  presence_id uuid NOT NULL,
  soignant_id uuid NOT NULL,
  debut_le timestamp with time zone NOT NULL DEFAULT now(),
  fin_le timestamp with time zone,
  duree_min numeric,
  motif text DEFAULT 'DEJEUNER'::text,
  cree_le timestamp with time zone DEFAULT now()
);

CREATE TABLE pings_gps_mission (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  mission_id uuid NOT NULL,
  soignant_id uuid NOT NULL,
  lat numeric(10,7) NOT NULL,
  lng numeric(10,7) NOT NULL,
  precision_m numeric(8,2),
  vitesse_ms numeric(8,2),
  cap_deg numeric(6,2),
  altitude_m numeric(8,2),
  source text NOT NULL DEFAULT 'BACKGROUND'::text,
  mock_detected boolean DEFAULT false,
  horodatage timestamp with time zone NOT NULL,
  recu_le timestamp with time zone NOT NULL DEFAULT now(),
  terminal_id text
);

CREATE TABLE plans_prevoyance (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  nom text NOT NULL,
  fournisseur text NOT NULL,
  type text NOT NULL,
  description text,
  prime_mensuelle numeric(8,2) NOT NULL,
  heures_minimum_requises numeric(10,2) DEFAULT 0,
  missions_minimum_requises integer DEFAULT 0,
  subvention_plateforme_pourcent numeric(5,2) DEFAULT 0,
  subvention_max_mensuelle numeric(8,2) DEFAULT 0,
  est_actif boolean DEFAULT true,
  cree_le timestamp with time zone DEFAULT now()
);

CREATE TABLE preferences_notifications (
  utilisateur_id uuid NOT NULL,
  canal_email boolean NOT NULL DEFAULT true,
  canal_sms boolean NOT NULL DEFAULT false,
  canal_push boolean NOT NULL DEFAULT true,
  canal_in_app boolean NOT NULL DEFAULT true,
  cree_le timestamp with time zone NOT NULL DEFAULT now(),
  mis_a_jour_le timestamp with time zone NOT NULL DEFAULT now()
);

CREATE TABLE preferences_notifications_par_evenement (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  utilisateur_id uuid NOT NULL,
  type_evenement type_evenement_notification NOT NULL,
  canal canal_notification NOT NULL,
  actif boolean NOT NULL DEFAULT true,
  cree_le timestamp with time zone NOT NULL DEFAULT now(),
  mis_a_jour_le timestamp with time zone NOT NULL DEFAULT now()
);

CREATE TABLE presence_status (
  user_id uuid NOT NULL,
  last_seen_at timestamp with time zone NOT NULL DEFAULT now(),
  status presence_status_enum NOT NULL DEFAULT 'ONLINE'::presence_status_enum,
  maj_le timestamp with time zone NOT NULL DEFAULT now()
);

CREATE TABLE presences (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  mission_id uuid NOT NULL,
  soignant_id uuid NOT NULL,
  pointage_arrivee_le timestamp with time zone,
  arrivee_lat numeric(10,7),
  arrivee_lng numeric(10,7),
  arrivee_precision_gps_m numeric(8,2),
  arrivee_id_terminal text,
  arrivee_modele_terminal text,
  arrivee_ip inet,
  pointage_depart_le timestamp with time zone,
  depart_lat numeric(10,7),
  depart_lng numeric(10,7),
  depart_precision_gps_m numeric(8,2),
  depart_id_terminal text,
  depart_ip inet,
  distance_etablissement_m numeric(10,2),
  perimetre_gps_valide boolean,
  alerte_teleportation boolean DEFAULT false,
  alertes_fraude jsonb DEFAULT '[]'::jsonb,
  valide_par_etablissement boolean DEFAULT false,
  valide_le timestamp with time zone,
  motif_litige text,
  cree_le timestamp with time zone DEFAULT now(),
  modifie_le timestamp with time zone DEFAULT now(),
  methode_pointage_arrivee text DEFAULT 'GPS'::text,
  methode_pointage_depart text DEFAULT 'GPS'::text,
  pause_debut_le timestamp with time zone,
  pause_fin_le timestamp with time zone,
  duree_pause_min numeric DEFAULT 0,
  duree_brute_min numeric,
  duree_nette_min numeric,
  heures_reelles numeric,
  retard_min numeric DEFAULT 0,
  depart_anticipe_min numeric DEFAULT 0,
  heures_ajustees_litige numeric(6,2),
  ajustement_litige_id uuid,
  litige_auto_cree_le timestamp with time zone,
  depart_modele_terminal text,
  valide_auto_72h_le timestamp with time zone,
  arrivee_mock_detected boolean NOT NULL DEFAULT false,
  depart_mock_detected boolean NOT NULL DEFAULT false,
  qr_token_arrivee text,
  qr_token_depart text,
  coherence_verifiee_le timestamp with time zone,
  coherence_incidents jsonb DEFAULT '[]'::jsonb
);

CREATE TABLE prevoyance_liste_attente (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  soignant_id uuid,
  email text NOT NULL,
  niveau_souhaite niveau_prevoyance_souhaite NOT NULL DEFAULT 'INDIFFERENT'::niveau_prevoyance_souhaite,
  cree_le timestamp with time zone NOT NULL DEFAULT now(),
  mis_a_jour_le timestamp with time zone NOT NULL DEFAULT now()
);

CREATE TABLE professions_liberal_eligible (
  profession type_profession NOT NULL,
  code_ape varchar(6) NOT NULL,
  libelle_urssaf text NOT NULL,
  plafond_micro numeric(10,2) DEFAULT 77700.00,
  ordre_obligatoire boolean DEFAULT false,
  nom_ordre text
);

CREATE TABLE prospects_etablissements (
  finess text NOT NULL,
  siret text,
  nom text NOT NULL,
  type_jolene text NOT NULL,
  categorie_lib text,
  telephone text,
  email text,
  adresse text,
  code_postal text,
  ville text,
  departement text,
  favori boolean NOT NULL DEFAULT false,
  maj_le timestamp with time zone NOT NULL DEFAULT now(),
  email_envoye_le timestamp with time zone,
  enrichi_le timestamp with time zone
);

CREATE TABLE prospects_soignants (
  cle text NOT NULL,
  nom text NOT NULL,
  prenom text,
  profession text NOT NULL,
  enseigne text,
  telephone text,
  email text,
  adresse text,
  code_postal text,
  ville text,
  departement text,
  favori boolean NOT NULL DEFAULT false,
  maj_le timestamp with time zone NOT NULL DEFAULT now(),
  email_envoye_le timestamp with time zone,
  enrichi_le timestamp with time zone,
  est_etudiant boolean NOT NULL DEFAULT false,
  ecole text,
  formation text
);

CREATE TABLE psc_auth_sessions (
  state text NOT NULL,
  nonce text NOT NULL,
  code_verifier text NOT NULL,
  intention text NOT NULL DEFAULT 'login'::text,
  cree_le timestamp with time zone NOT NULL DEFAULT now(),
  expire_le timestamp with time zone NOT NULL DEFAULT (now() + '00:15:00'::interval)
);

CREATE TABLE qr_codes_mission (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  mission_id uuid NOT NULL,
  token text NOT NULL,
  type text NOT NULL DEFAULT 'UNIVERSEL'::text,
  genere_le timestamp with time zone NOT NULL DEFAULT now(),
  expire_le timestamp with time zone NOT NULL,
  nb_scans integer NOT NULL DEFAULT 0,
  dernier_scan_le timestamp with time zone,
  actif boolean NOT NULL DEFAULT true,
  cree_par uuid NOT NULL,
  cree_le timestamp with time zone NOT NULL DEFAULT now()
);

CREATE TABLE rappels_contrat_travail (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  mission_id uuid NOT NULL,
  envoye_le date NOT NULL DEFAULT CURRENT_DATE,
  cible_etab boolean NOT NULL DEFAULT false,
  cible_soignant boolean NOT NULL DEFAULT false,
  cree_le timestamp with time zone NOT NULL DEFAULT now()
);

CREATE TABLE rate_limits (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  cle text NOT NULL,
  action text NOT NULL,
  tentatives integer DEFAULT 1,
  premiere_tentative timestamp with time zone DEFAULT now(),
  derniere_tentative timestamp with time zone DEFAULT now()
);

CREATE TABLE reclamations (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  utilisateur_id uuid NOT NULL,
  type_utilisateur text NOT NULL,
  categorie text NOT NULL,
  sujet text NOT NULL,
  details text NOT NULL,
  mission_id uuid,
  statut text NOT NULL DEFAULT 'EN_ATTENTE'::text,
  priorite text NOT NULL DEFAULT 'NORMALE'::text,
  reponse_admin text,
  traite_par uuid,
  traite_le timestamp with time zone,
  cree_le timestamp with time zone NOT NULL DEFAULT now()
);

CREATE TABLE reclamations_score (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  evenement_type text NOT NULL,
  evenement_soignant_id uuid,
  evenement_etab_id uuid,
  contesteur_id uuid NOT NULL,
  motif_categorie text NOT NULL,
  texte_libre text NOT NULL,
  justificatif_storage_path text,
  statut text NOT NULL DEFAULT 'PENDING'::text,
  decision_admin text,
  motif_admin text,
  traitee_par_admin_id uuid,
  traitee_le timestamp with time zone,
  cree_le timestamp with time zone NOT NULL DEFAULT now(),
  modifiee_le timestamp with time zone NOT NULL DEFAULT now()
);

CREATE TABLE reclamations_scoring (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  soignant_id uuid NOT NULL,
  mission_id uuid NOT NULL,
  motif text NOT NULL,
  justificatif_url text,
  details text,
  statut text DEFAULT 'EN_ATTENTE'::text,
  points_restaures integer DEFAULT 0,
  traite_par uuid,
  traite_le timestamp with time zone,
  cree_le timestamp with time zone DEFAULT now()
);

CREATE TABLE regles_exercice_profession (
  profession type_profession NOT NULL,
  types_exercice_autorises text[] NOT NULL,
  description text
);

CREATE TABLE relances_soignants (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  soignant_id uuid NOT NULL,
  type text NOT NULL DEFAULT 'REACTIVATION'::text,
  envoye_le timestamp with time zone NOT NULL DEFAULT now()
);

CREATE TABLE rist_plafonds (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  profession type_profession NOT NULL,
  type_contrat type_contrat NOT NULL,
  taux_horaire_brut_fph numeric(8,2) NOT NULL,
  coefficient_plafond numeric(4,2) DEFAULT 1.30,
  plafond_calcule numeric(8,2),
  en_vigueur_depuis date NOT NULL DEFAULT '2023-10-05'::date,
  en_vigueur_jusqua date,
  cree_le timestamp with time zone DEFAULT now(),
  modifie_le timestamp with time zone DEFAULT now()
);

CREATE TABLE rpps_test (
  rpps text NOT NULL,
  nom text NOT NULL,
  prenom text NOT NULL,
  profession text NOT NULL,
  specialite_medicale text,
  date_naissance date,
  cree_le timestamp with time zone NOT NULL DEFAULT now()
);

CREATE TABLE sales_annuaires (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  nom text NOT NULL,
  url text NOT NULL,
  categorie text NOT NULL DEFAULT 'GENERAL'::text,
  autorite text NOT NULL DEFAULT 'MOYENNE'::text,
  gratuit boolean NOT NULL DEFAULT true,
  comment_soumettre text,
  texte_a_soumettre text,
  statut text NOT NULL DEFAULT 'A_SOUMETTRE'::text,
  lien_obtenu text,
  notes text,
  favori boolean NOT NULL DEFAULT false,
  cree_le timestamp with time zone NOT NULL DEFAULT now(),
  maj_le timestamp with time zone NOT NULL DEFAULT now()
);

CREATE TABLE sales_contacts (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  type text NOT NULL DEFAULT 'SOIGNANT'::text,
  nom text NOT NULL,
  profession text,
  telephone text,
  email text,
  ville text,
  groupe_id uuid,
  statut text NOT NULL DEFAULT 'PROSPECT'::text,
  notes text,
  cree_le timestamp with time zone NOT NULL DEFAULT now(),
  maj_le timestamp with time zone NOT NULL DEFAULT now(),
  favori boolean NOT NULL DEFAULT false,
  archive boolean NOT NULL DEFAULT false,
  finess text,
  reponse text,
  a_rappeler boolean NOT NULL DEFAULT false,
  departement text,
  type_etab text,
  dernier_contact_le timestamp with time zone
);

CREATE TABLE sales_groupes (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  nom text NOT NULL,
  plateforme text NOT NULL DEFAULT 'WHATSAPP'::text,
  profession text NOT NULL DEFAULT 'TOUTES'::text,
  region text,
  url text,
  membres integer,
  audience text NOT NULL DEFAULT 'MIXTE'::text,
  statut text NOT NULL DEFAULT 'A_VERIFIER'::text,
  notes text,
  cree_le timestamp with time zone NOT NULL DEFAULT now(),
  maj_le timestamp with time zone NOT NULL DEFAULT now(),
  favori boolean NOT NULL DEFAULT false
);

CREATE TABLE sales_templates (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  nom text NOT NULL,
  cible text NOT NULL DEFAULT 'GROUPE'::text,
  profession text,
  contenu text NOT NULL,
  cree_le timestamp with time zone NOT NULL DEFAULT now(),
  sujet text
);

CREATE TABLE scans_pointage (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  mission_id uuid NOT NULL,
  soignant_id uuid NOT NULL,
  code_saisi text NOT NULL,
  numero_scan smallint NOT NULL,
  type_scan text NOT NULL,
  scanne_le timestamp with time zone NOT NULL DEFAULT now(),
  horodatage_arrondi timestamp with time zone NOT NULL,
  creneau_effectif_id uuid,
  est_en_avance boolean NOT NULL DEFAULT false,
  validation_etab_requise boolean NOT NULL DEFAULT false,
  valide_par_etab boolean NOT NULL DEFAULT false,
  valide_le timestamp with time zone,
  valide_par uuid,
  latitude numeric,
  longitude numeric,
  precision_gps_m numeric,
  id_terminal text,
  ip_address inet,
  distance_etablissement_m numeric,
  cree_le timestamp with time zone NOT NULL DEFAULT now()
);

CREATE TABLE scoring_breakdown (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  soignant_id uuid NOT NULL,
  score_total numeric NOT NULL,
  niveau niveau_qualitatif NOT NULL,
  en_periode_probatoire boolean NOT NULL DEFAULT false,
  notation_etab_soignant_pct numeric,
  notation_etab_soignant_poids numeric,
  presentisme_pct numeric,
  presentisme_poids numeric,
  ponctualite_pct numeric,
  ponctualite_poids numeric,
  reactivite_pct numeric,
  reactivite_poids numeric,
  anciennete_volume_pct numeric,
  anciennete_volume_poids numeric,
  notation_soignant_etab_pct numeric,
  notation_soignant_etab_poids numeric,
  litiges_malus numeric NOT NULL DEFAULT 0,
  absence_sans_prevenir_malus numeric NOT NULL DEFAULT 0,
  bonus_super_actif numeric NOT NULL DEFAULT 0,
  composantes_inactives_json jsonb,
  composantes_actives_count integer NOT NULL,
  redistribution_json jsonb,
  raison_recalcul text,
  cree_le timestamp with time zone NOT NULL DEFAULT now()
);

CREATE TABLE serie_email_envois (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  utilisateur_id uuid NOT NULL,
  serie serie_onboarding_type NOT NULL,
  etape serie_onboarding_etape NOT NULL,
  planifie_le timestamp with time zone NOT NULL,
  envoye_le timestamp with time zone,
  skip_raison text,
  statut serie_email_statut NOT NULL DEFAULT 'PLANIFIE'::serie_email_statut,
  erreur_message text,
  tentatives integer NOT NULL DEFAULT 0,
  cree_le timestamp with time zone NOT NULL DEFAULT now(),
  mis_a_jour_le timestamp with time zone NOT NULL DEFAULT now()
);

CREATE TABLE shift_affectations (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  shift_id uuid NOT NULL,
  soignant_id uuid NOT NULL,
  mission_id uuid,
  statut text DEFAULT 'AFFECTE'::text,
  cree_le timestamp with time zone DEFAULT now()
);

CREATE TABLE shifts (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  etablissement_id uuid NOT NULL,
  equipe_id uuid,
  intitule text NOT NULL,
  service text,
  jour date NOT NULL,
  heure_debut time without time zone NOT NULL,
  heure_fin time without time zone NOT NULL,
  profession_requise text,
  nb_postes integer DEFAULT 1,
  nb_pourvus integer DEFAULT 0,
  recurrence text,
  notes text,
  cree_le timestamp with time zone DEFAULT now(),
  modifie_le timestamp with time zone DEFAULT now()
);

CREATE TABLE signalements (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  signaleur_id uuid NOT NULL,
  signaleur_type text NOT NULL,
  cible_id uuid NOT NULL,
  cible_type text NOT NULL,
  categorie text NOT NULL,
  motif text NOT NULL,
  mission_id uuid,
  statut text NOT NULL DEFAULT 'OUVERT'::text,
  resolution text,
  traite_par uuid,
  traite_le timestamp with time zone,
  cree_le timestamp with time zone NOT NULL DEFAULT now()
);

CREATE TABLE signature_rate_limit_ip (
  ip_signature inet NOT NULL,
  fenetre_debut timestamp with time zone NOT NULL DEFAULT now(),
  nb_envois integer NOT NULL DEFAULT 1,
  derniere_action timestamp with time zone NOT NULL DEFAULT now()
);

CREATE TABLE signatures_contrats (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  contrat_id uuid NOT NULL,
  signataire_user_id uuid NOT NULL,
  signataire_role text NOT NULL,
  signe_a timestamp with time zone,
  ip_signature inet,
  user_agent text,
  hash_document text,
  otp_envoye_a timestamp with time zone,
  otp_valide_a timestamp with time zone,
  otp_code_hash text,
  otp_tentatives integer DEFAULT 0,
  psc_session_active boolean DEFAULT false,
  rpps_verifie boolean DEFAULT false,
  traits_identite_verifies boolean DEFAULT false,
  statut_signature text NOT NULL DEFAULT 'en_attente'::text,
  audit_trail jsonb DEFAULT '{}'::jsonb,
  signature_image_base64 text,
  cree_le timestamp with time zone DEFAULT now(),
  modifie_le timestamp with time zone DEFAULT now(),
  sms_envoyes_count integer DEFAULT 0,
  sms_premier_envoi_a timestamp with time zone
);

CREATE TABLE sms_envoyes (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  destinataire_id uuid,
  telephone text NOT NULL,
  type text NOT NULL,
  contenu text NOT NULL,
  provider_id text,
  statut text DEFAULT 'ENVOYE'::text,
  erreur text,
  cout_eur numeric(6,4),
  cree_le timestamp with time zone NOT NULL DEFAULT now(),
  idempotency_key text
);

CREATE TABLE soignants (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  prenom text NOT NULL,
  nom text NOT NULL,
  email text NOT NULL,
  telephone varchar(20),
  date_naissance date,
  profession type_profession,
  numero_rpps varchar(11),
  numero_adeli varchar(9),
  type_contrat type_contrat DEFAULT 'CDD'::type_contrat,
  score_fiabilite numeric(5,2) DEFAULT 50.00,
  total_missions_terminees integer DEFAULT 0,
  total_missions_annulees integer DEFAULT 0,
  total_retards_pointage integer DEFAULT 0,
  total_absences integer DEFAULT 0,
  heures_cumulees numeric(10,2) DEFAULT 0,
  eligible_conversion_3200h boolean DEFAULT false,
  prevoyance_inscrit boolean DEFAULT false,
  prevoyance_fournisseur text,
  prevoyance_numero_contrat text,
  adresse_lat numeric(10,7),
  adresse_lng numeric(10,7),
  rayon_deplacement_km integer DEFAULT 30,
  tous_documents_valides boolean DEFAULT false,
  identite_verifiee boolean DEFAULT false,
  diplome_verifie boolean DEFAULT false,
  rpps_verifie boolean DEFAULT false,
  statut_verification_aria statut_verification DEFAULT 'EN_ATTENTE'::statut_verification,
  cree_le timestamp with time zone DEFAULT now(),
  modifie_le timestamp with time zone DEFAULT now(),
  derniere_activite_le timestamp with time zone DEFAULT now(),
  supprime_le timestamp with time zone,
  types_contrat_acceptes text,
  numero_secu varchar(15),
  siret_liberal varchar(14),
  date_passage_liberal date,
  statut_liberal text DEFAULT 'NON_LIBERAL'::text,
  code_ape varchar(6),
  adresse_rue text,
  adresse_ville text,
  adresse_code_postal varchar(5),
  heures_plateforme numeric(10,2) DEFAULT 0,
  rpps_profession_api text,
  rpps_nom_api text,
  rpps_verifie_le timestamp with time zone,
  consentement_gps boolean DEFAULT false,
  consentement_gps_le timestamp with time zone,
  assujetti_tva boolean DEFAULT false,
  numero_tva text,
  attestation_vaccinations boolean DEFAULT false,
  attestation_vaccinations_le timestamp with time zone,
  attestation_medecine_travail boolean DEFAULT false,
  attestation_medecine_travail_le timestamp with time zone,
  attestation_sante_signee_le timestamp with time zone,
  code_parrainage text,
  parraine_par uuid,
  avatar_url text,
  premiere_mission_le timestamp with time zone,
  disponible_urgence boolean DEFAULT false,
  urgence_rayon_km integer DEFAULT 15,
  urgence_creneaux jsonb DEFAULT '[]'::jsonb,
  total_missions_urgence integer DEFAULT 0,
  bio text,
  annees_experience integer,
  specialites text[],
  compteur_notes_honoraires integer DEFAULT 0,
  est_cumul_activite boolean DEFAULT false,
  attestation_cumul_le timestamp with time zone,
  type_exercice text DEFAULT 'SALARIE'::text,
  attestation_cumul_activite boolean NOT NULL DEFAULT false,
  est_salarie_etablissement boolean,
  taux_horaire_minimum numeric,
  badge_ambassadeur boolean NOT NULL DEFAULT false,
  priorite_missions_urgentes boolean NOT NULL DEFAULT false,
  ville_recherche text,
  ville_urgence text,
  stripe_account_id text,
  validation_3200h_statut text DEFAULT 'NON_DEMANDE'::text,
  validation_3200h_le timestamp with time zone,
  validation_3200h_par uuid,
  iban_last4 text,
  rib_partage_le timestamp with time zone,
  note_moyenne numeric(3,2) DEFAULT NULL::numeric,
  nb_evaluations integer DEFAULT 0,
  coherence_identite text DEFAULT 'NON_VERIFIE'::text,
  coherence_details jsonb,
  rpps_prenom_api text,
  psc_sub text,
  psc_linked_le timestamp with time zone,
  psc_last_login timestamp with time zone,
  mandat_facturation_signe boolean DEFAULT false,
  mandat_facturation_signe_le timestamp with time zone,
  mandat_facturation_version text,
  sms_actif boolean DEFAULT false,
  sms_consent_le timestamp with time zone,
  specialite_medicale text,
  specialite_code text,
  specialite_source text DEFAULT 'RPPS'::text,
  specialite_verifiee boolean DEFAULT false,
  specialite_verifiee_le timestamp with time zone,
  accepte_missions_generalistes boolean DEFAULT true,
  numero_securite_sociale text,
  defacto_opt_in boolean NOT NULL DEFAULT false,
  pool_urgence_sms_opt_in boolean NOT NULL DEFAULT false,
  total_litiges_perdus integer NOT NULL DEFAULT 0,
  statut_compte statut_compte_soignant NOT NULL DEFAULT 'ACTIF'::statut_compte_soignant,
  niveau niveau_qualitatif,
  en_periode_probatoire boolean NOT NULL DEFAULT true,
  score_breakdown_id uuid,
  suspension_raison text,
  suspension_le timestamp with time zone,
  nb_absences_sans_prevenir_6_mois integer NOT NULL DEFAULT 0,
  sms_alertes_actives boolean DEFAULT true,
  sexe text,
  lieu_naissance_commune text,
  lieu_naissance_departement text,
  pays_naissance text DEFAULT 'France'::text,
  nationalite text DEFAULT 'Française'::text,
  onboarding_etapes_completees jsonb NOT NULL DEFAULT '[]'::jsonb,
  onboarding_termine_le timestamp with time zone,
  telephone_verifie boolean NOT NULL DEFAULT false,
  telephone_verifie_le timestamp with time zone,
  telephone_en_attente_verification text,
  iban_virement text,
  iban_titulaire text,
  adeli_verifie boolean DEFAULT false,
  adeli_verifie_le timestamp with time zone,
  adeli_nom_api text,
  adeli_prenom_api text,
  adeli_profession_api text,
  nir_verifie boolean NOT NULL DEFAULT false,
  utm_source text,
  utm_medium text,
  utm_campaign text,
  utm_content text,
  utm_term text,
  http_referrer text,
  ref_capture text,
  source_acquisition text,
  preference_contrat_mixte text,
  est_etudiant boolean NOT NULL DEFAULT false,
  etudiant_details text,
  scolarite_formation text,
  scolarite_annee_validee integer,
  scolarite_profession_autorisee type_profession,
  scolarite_verifiee boolean NOT NULL DEFAULT false,
  scolarite_verifiee_le timestamp with time zone,
  licence_remplacement_verifiee boolean NOT NULL DEFAULT false,
  licence_remplacement_le timestamp with time zone,
  licence_remplacement_valide_jusqua date,
  licence_remplacement_specialite text,
  est_compte_test boolean NOT NULL DEFAULT false,
  regime_fiscal text NOT NULL DEFAULT 'MICRO_BNC'::text,
  regime_fiscal_confirme boolean NOT NULL DEFAULT false
);

CREATE TABLE souscriptions_prevoyance (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  soignant_id uuid NOT NULL,
  plan_id uuid NOT NULL,
  statut text DEFAULT 'ACTIF'::text,
  date_debut date NOT NULL DEFAULT CURRENT_DATE,
  date_fin date,
  total_primes_payees numeric(10,2) DEFAULT 0,
  total_subventions_recues numeric(10,2) DEFAULT 0,
  cree_le timestamp with time zone DEFAULT now(),
  modifie_le timestamp with time zone DEFAULT now()
);

CREATE TABLE specialites_medicales (
  code text NOT NULL,
  label text NOT NULL,
  profession_parent text NOT NULL,
  actif boolean DEFAULT true,
  cree_le timestamp with time zone DEFAULT now()
);

CREATE TABLE statut_services_api (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  nom_service text NOT NULL,
  statut text DEFAULT 'OPERATIONNEL'::text,
  dernier_controle_le timestamp with time zone DEFAULT now(),
  dernier_succes_le timestamp with time zone,
  dernier_echec_le timestamp with time zone,
  nombre_echecs integer DEFAULT 0,
  etat_disjoncteur text DEFAULT 'FERME'::text,
  disjoncteur_ouvert_le timestamp with time zone,
  details jsonb,
  modifie_le timestamp with time zone DEFAULT now()
);

CREATE TABLE streaks_soignant (
  soignant_id uuid NOT NULL,
  streak_count integer NOT NULL DEFAULT 0,
  last_activity_date date NOT NULL DEFAULT CURRENT_DATE,
  max_streak integer NOT NULL DEFAULT 0,
  updated_at timestamp with time zone NOT NULL DEFAULT now()
);

CREATE TABLE stripe_connect_onboarding (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  soignant_id uuid NOT NULL,
  stripe_account_id text,
  stripe_account_type text DEFAULT 'express'::text,
  onboarding_complete boolean DEFAULT false,
  charges_enabled boolean DEFAULT false,
  payouts_enabled boolean DEFAULT false,
  details_submitted boolean DEFAULT false,
  country text DEFAULT 'FR'::text,
  business_type text DEFAULT 'individual'::text,
  iban_last4 text,
  statut text DEFAULT 'NON_DEMANDE'::text,
  erreur_onboarding text,
  cree_le timestamp with time zone DEFAULT now(),
  modifie_le timestamp with time zone DEFAULT now(),
  onboarding_complete_le timestamp with time zone,
  type_exercice text DEFAULT 'LIBERAL'::text
);

CREATE TABLE stripe_refunds_queue (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  avoir_id uuid NOT NULL,
  facture_origine_id uuid NOT NULL,
  stripe_payment_intent_id text NOT NULL,
  montant_cts integer NOT NULL,
  statut text NOT NULL DEFAULT 'EN_ATTENTE'::text,
  stripe_refund_id text,
  erreur text,
  tentatives integer NOT NULL DEFAULT 0,
  cree_le timestamp with time zone NOT NULL DEFAULT now(),
  traite_le timestamp with time zone,
  dernier_essai_le timestamp with time zone
);

CREATE TABLE stripe_transfers (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  mission_id uuid NOT NULL,
  facture_id uuid,
  soignant_id uuid NOT NULL,
  etablissement_id uuid NOT NULL,
  montant_total numeric NOT NULL,
  montant_commission numeric NOT NULL,
  montant_soignant numeric NOT NULL,
  stripe_payment_intent_id text,
  stripe_charge_id text,
  stripe_transfer_id text,
  stripe_payout_id text,
  statut text NOT NULL DEFAULT 'EN_ATTENTE'::text,
  erreur text,
  charge_le timestamp with time zone,
  transfere_le timestamp with time zone,
  paye_le timestamp with time zone,
  cree_le timestamp with time zone DEFAULT now(),
  dispute_id text,
  dispute_statut text,
  dispute_reason text,
  dispute_cree_le timestamp with time zone,
  reversed_le timestamp with time zone
);

CREATE TABLE stripe_webhook_events (
  event_id text NOT NULL,
  event_type text NOT NULL,
  recu_le timestamp with time zone NOT NULL DEFAULT now(),
  traite_le timestamp with time zone,
  erreur text,
  payload jsonb
);

CREATE TABLE suivi_conversion_3200h (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  soignant_id uuid NOT NULL,
  profession_cible_liberal text,
  heures_a_inscription numeric(10,2) DEFAULT 0,
  heures_actuelles numeric(10,2) DEFAULT 0,
  progression_pourcent numeric(5,2),
  jalon_800h_atteint boolean DEFAULT false,
  jalon_1600h_atteint boolean DEFAULT false,
  jalon_2400h_atteint boolean DEFAULT false,
  jalon_3200h_atteint boolean DEFAULT false,
  avantages_debloques jsonb DEFAULT '[]'::jsonb,
  cree_le timestamp with time zone DEFAULT now(),
  modifie_le timestamp with time zone DEFAULT now()
);

CREATE TABLE super_swipes_quota (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  soignant_id uuid NOT NULL,
  date date NOT NULL DEFAULT CURRENT_DATE,
  count integer NOT NULL DEFAULT 0
);

CREATE TABLE swipes (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  soignant_id uuid NOT NULL,
  mission_id uuid NOT NULL,
  direction swipe_direction NOT NULL,
  created_at timestamp with time zone NOT NULL DEFAULT now()
);

CREATE TABLE templates_contrat (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  type_contrat text NOT NULL,
  nom text NOT NULL,
  contenu_html text NOT NULL,
  variables jsonb NOT NULL DEFAULT '[]'::jsonb,
  version integer DEFAULT 1,
  est_actif boolean DEFAULT true,
  cree_le timestamp with time zone DEFAULT now(),
  modifie_le timestamp with time zone DEFAULT now()
);

CREATE TABLE tokens_calendrier (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  soignant_id uuid NOT NULL,
  token text NOT NULL DEFAULT encode(gen_random_bytes(32), 'hex'::text),
  cree_le timestamp with time zone DEFAULT now(),
  expire_le timestamp with time zone DEFAULT (now() + '1 year'::interval)
);

CREATE TABLE tokens_push (
  id uuid NOT NULL DEFAULT uuid_generate_v4(),
  utilisateur_id uuid NOT NULL,
  token text NOT NULL,
  plateforme text DEFAULT 'WEB'::text,
  actif boolean DEFAULT true,
  derniere_utilisation timestamp with time zone DEFAULT now(),
  cree_le timestamp with time zone DEFAULT now(),
  endpoint text,
  p256dh text,
  auth_key text
);

CREATE TABLE typing_status (
  conversation_id uuid NOT NULL,
  user_id uuid NOT NULL,
  started_at timestamp with time zone NOT NULL DEFAULT now()
);

-- ============================================================
-- CONTRAINTES (pg_constraint / pg_get_constraintdef)
-- ============================================================

ALTER TABLE admin_invocations ADD CONSTRAINT admin_invocations_pkey PRIMARY KEY (id);
ALTER TABLE admin_invocations ADD CONSTRAINT admin_invocations_admin_user_id_fkey FOREIGN KEY (admin_user_id) REFERENCES auth.users(id);
ALTER TABLE admin_invocations ADD CONSTRAINT admin_invocations_internal_status_check CHECK ((internal_status = ANY (ARRAY['PENDING'::text, 'INVOKED'::text, 'COMPLETED'::text, 'CRASHED'::text])));
ALTER TABLE admins_groupe_sante ADD CONSTRAINT admins_groupe_sante_pkey PRIMARY KEY (id);
ALTER TABLE admins_groupe_sante ADD CONSTRAINT admins_groupe_sante_groupe_id_utilisateur_id_key UNIQUE (groupe_id, utilisateur_id);
ALTER TABLE admins_groupe_sante ADD CONSTRAINT admins_groupe_sante_groupe_id_fkey FOREIGN KEY (groupe_id) REFERENCES groupes_sante(id) ON DELETE CASCADE;
ALTER TABLE admins_groupe_sante ADD CONSTRAINT admins_groupe_sante_role_check CHECK ((role = ANY (ARRAY['PROPRIETAIRE'::text, 'ADMINISTRATEUR'::text, 'FACTURATION'::text, 'LECTEUR'::text])));
ALTER TABLE alertes_systeme ADD CONSTRAINT alertes_systeme_pkey PRIMARY KEY (id);
ALTER TABLE alertes_systeme ADD CONSTRAINT alertes_systeme_severite_check CHECK ((severite = ANY (ARRAY['INFO'::text, 'WARNING'::text, 'CRITICAL'::text])));
ALTER TABLE api_keys ADD CONSTRAINT api_keys_pkey PRIMARY KEY (id);
ALTER TABLE api_keys ADD CONSTRAINT api_keys_cle_api_key UNIQUE (cle_api);
ALTER TABLE api_keys ADD CONSTRAINT api_keys_etablissement_id_fkey FOREIGN KEY (etablissement_id) REFERENCES etablissements(id);
ALTER TABLE api_keys ADD CONSTRAINT api_keys_groupe_sante_id_fkey FOREIGN KEY (groupe_sante_id) REFERENCES groupes_sante(id);
ALTER TABLE articles_aide ADD CONSTRAINT articles_aide_pkey PRIMARY KEY (id);
ALTER TABLE articles_aide ADD CONSTRAINT articles_aide_slug_key UNIQUE (slug);
ALTER TABLE articles_aide ADD CONSTRAINT articles_aide_audience_check CHECK ((audience = ANY (ARRAY['SOIGNANT'::text, 'ETABLISSEMENT'::text, 'COMMUN'::text])));
ALTER TABLE assurance_config ADD CONSTRAINT assurance_config_pkey PRIMARY KEY (id);
ALTER TABLE assurance_config ADD CONSTRAINT assurance_config_etablissement_id_key UNIQUE (etablissement_id);
ALTER TABLE assurance_config ADD CONSTRAINT assurance_config_etablissement_id_fkey FOREIGN KEY (etablissement_id) REFERENCES etablissements(id);
ALTER TABLE assurances_mission ADD CONSTRAINT assurances_mission_pkey PRIMARY KEY (id);
ALTER TABLE assurances_mission ADD CONSTRAINT assurances_mission_etablissement_id_fkey FOREIGN KEY (etablissement_id) REFERENCES etablissements(id);
ALTER TABLE assurances_mission ADD CONSTRAINT assurances_mission_mission_id_fkey FOREIGN KEY (mission_id) REFERENCES missions(id);
ALTER TABLE attestations_heures_externes ADD CONSTRAINT attestations_heures_externes_pkey PRIMARY KEY (id);
ALTER TABLE attestations_heures_externes ADD CONSTRAINT attestations_heures_externes_soignant_id_semaine_du_key UNIQUE (soignant_id, semaine_du);
ALTER TABLE attestations_heures_externes ADD CONSTRAINT attestations_heures_externes_soignant_id_fkey FOREIGN KEY (soignant_id) REFERENCES soignants(id);
ALTER TABLE avoirs ADD CONSTRAINT avoirs_pkey PRIMARY KEY (id);
ALTER TABLE avoirs ADD CONSTRAINT avoirs_source_litige_id_fkey FOREIGN KEY (source_litige_id) REFERENCES litiges(id) ON DELETE SET NULL;
ALTER TABLE avoirs ADD CONSTRAINT avoirs_source_mission_id_fkey FOREIGN KEY (source_mission_id) REFERENCES missions(id) ON DELETE SET NULL;
ALTER TABLE avoirs ADD CONSTRAINT avoirs_facture_origine_type_check CHECK ((facture_origine_type = ANY (ARRAY['FACTURE_ETAB'::text, 'FACTURE_HONORAIRES_SOIGNANT'::text, 'BULLETIN_PAIE'::text])));
ALTER TABLE avoirs ADD CONSTRAINT avoirs_montant_ht_check CHECK ((montant_ht >= (0)::numeric));
ALTER TABLE avoirs ADD CONSTRAINT avoirs_montant_ttc_check CHECK ((montant_ttc >= (0)::numeric));
ALTER TABLE avoirs ADD CONSTRAINT avoirs_motif_check CHECK ((motif = ANY (ARRAY['LITIGE_ACCORD_MUTUEL'::text, 'LITIGE_MEDIATION_ADMIN'::text, 'ANNULATION_MISSION_ETAB'::text, 'ANNULATION_MISSION_SOIGNANT'::text, 'MODIFICATION_HORAIRES'::text, 'COMPENSATION_PARTIELLE'::text, 'AUTRE'::text])));
ALTER TABLE badges_soignant ADD CONSTRAINT badges_soignant_pkey PRIMARY KEY (id);
ALTER TABLE badges_soignant ADD CONSTRAINT badges_soignant_soignant_id_badge_type_key UNIQUE (soignant_id, badge_type);
ALTER TABLE badges_soignant ADD CONSTRAINT badges_soignant_soignant_id_fkey FOREIGN KEY (soignant_id) REFERENCES soignants(id) ON DELETE CASCADE;
ALTER TABLE bfa_suivi ADD CONSTRAINT bfa_suivi_pkey PRIMARY KEY (id);
ALTER TABLE bfa_suivi ADD CONSTRAINT bfa_suivi_etablissement_id_annee_key UNIQUE (etablissement_id, annee);
ALTER TABLE bfa_suivi ADD CONSTRAINT bfa_suivi_groupe_id_annee_key UNIQUE (groupe_id, annee);
ALTER TABLE bfa_suivi ADD CONSTRAINT bfa_suivi_etablissement_id_fkey FOREIGN KEY (etablissement_id) REFERENCES etablissements(id);
ALTER TABLE bfa_suivi ADD CONSTRAINT bfa_suivi_groupe_id_fkey FOREIGN KEY (groupe_id) REFERENCES groupes_sante(id);
ALTER TABLE bfa_suivi ADD CONSTRAINT bfa_suivi_palier_bfa_check CHECK ((palier_bfa = ANY (ARRAY['AUCUN'::text, 'BRONZE'::text, 'ARGENT'::text, 'OR'::text])));
ALTER TABLE bulletins_paie ADD CONSTRAINT bulletins_paie_pkey PRIMARY KEY (id);
ALTER TABLE bulletins_paie ADD CONSTRAINT bulletins_paie_unique_mission UNIQUE (mission_id);
ALTER TABLE bulletins_paie ADD CONSTRAINT bulletins_paie_unique_numero_par_soignant UNIQUE (soignant_id, numero_bulletin);
ALTER TABLE bulletins_paie ADD CONSTRAINT bulletins_paie_etablissement_id_fkey FOREIGN KEY (etablissement_id) REFERENCES etablissements(id);
ALTER TABLE bulletins_paie ADD CONSTRAINT bulletins_paie_mission_id_fkey FOREIGN KEY (mission_id) REFERENCES missions(id);
ALTER TABLE bulletins_paie ADD CONSTRAINT bulletins_paie_soignant_id_fkey FOREIGN KEY (soignant_id) REFERENCES soignants(id);
ALTER TABLE bulletins_paie ADD CONSTRAINT bulletins_paie_statut_check CHECK ((statut = ANY (ARRAY['EMIS'::text, 'PAYE'::text, 'ANNULE'::text])));
ALTER TABLE calendar_connections ADD CONSTRAINT calendar_connections_pkey PRIMARY KEY (id);
ALTER TABLE calendar_connections ADD CONSTRAINT calendar_connections_utilisateur_id_provider_key UNIQUE (utilisateur_id, provider);
ALTER TABLE calendar_events_sync ADD CONSTRAINT calendar_events_sync_pkey PRIMARY KEY (id);
ALTER TABLE calendar_events_sync ADD CONSTRAINT calendar_events_sync_connection_id_fkey FOREIGN KEY (connection_id) REFERENCES calendar_connections(id) ON DELETE CASCADE;
ALTER TABLE calendar_events_sync ADD CONSTRAINT calendar_events_sync_mission_id_fkey FOREIGN KEY (mission_id) REFERENCES missions(id);
ALTER TABLE candidatures ADD CONSTRAINT candidatures_pkey PRIMARY KEY (id);
ALTER TABLE candidatures ADD CONSTRAINT candidatures_mission_id_soignant_id_key UNIQUE (mission_id, soignant_id);
ALTER TABLE candidatures ADD CONSTRAINT candidatures_mission_id_fkey FOREIGN KEY (mission_id) REFERENCES missions(id);
ALTER TABLE candidatures ADD CONSTRAINT candidatures_soignant_id_fkey FOREIGN KEY (soignant_id) REFERENCES soignants(id);
ALTER TABLE candidatures ADD CONSTRAINT candidatures_statut_check CHECK ((statut = ANY (ARRAY['EN_ATTENTE'::text, 'EN_ATTENTE_VALIDATION_ETAB'::text, 'ACCEPTEE'::text, 'REFUSEE'::text, 'ANNULEE'::text, 'PROPOSEE'::text, 'EXPIREE'::text])));
ALTER TABLE candidatures ADD CONSTRAINT check_type_contrat_choisi CHECK (((type_contrat_choisi IS NULL) OR (type_contrat_choisi = ANY (ARRAY['SALARIE'::text, 'LIBERAL'::text]))));
ALTER TABLE cessions_creance ADD CONSTRAINT cessions_creance_pkey PRIMARY KEY (id);
ALTER TABLE cessions_creance ADD CONSTRAINT cessions_creance_facture_honoraire_id_fkey FOREIGN KEY (facture_honoraire_id) REFERENCES factures_honoraires(id) ON DELETE CASCADE;
ALTER TABLE cessions_creance ADD CONSTRAINT cessions_creance_soignant_id_fkey FOREIGN KEY (soignant_id) REFERENCES soignants(id);
ALTER TABLE chorus_pro_config ADD CONSTRAINT chorus_pro_config_pkey PRIMARY KEY (id);
ALTER TABLE chorus_pro_config ADD CONSTRAINT chorus_pro_config_etablissement_id_key UNIQUE (etablissement_id);
ALTER TABLE chorus_pro_config ADD CONSTRAINT chorus_pro_config_etablissement_id_fkey FOREIGN KEY (etablissement_id) REFERENCES etablissements(id);
ALTER TABLE chorus_submissions ADD CONSTRAINT chorus_submissions_pkey PRIMARY KEY (id);
ALTER TABLE chorus_submissions ADD CONSTRAINT chorus_submissions_invoice_id_fkey FOREIGN KEY (invoice_id) REFERENCES factures_honoraires(id) ON DELETE RESTRICT;
ALTER TABLE chorus_submissions ADD CONSTRAINT chorus_submissions_status_check CHECK ((status = ANY (ARRAY['pending_credentials'::text, 'pending'::text, 'submitted'::text, 'accepted'::text, 'rejected'::text, 'error'::text])));
ALTER TABLE chorus_submissions ADD CONSTRAINT chorus_submissions_submission_type_check CHECK ((submission_type = ANY (ARRAY['DEPOT_PDF_API'::text, 'SAISIE_API'::text])));
ALTER TABLE chorus_submissions ADD CONSTRAINT chorus_submissions_type_document_check CHECK ((type_document = ANY (ARRAY['FACTURE'::text, 'AVOIR'::text])));
ALTER TABLE codes_secours_mission ADD CONSTRAINT codes_secours_mission_pkey PRIMARY KEY (id);
ALTER TABLE codes_secours_mission ADD CONSTRAINT codes_secours_mission_mission_id_fkey FOREIGN KEY (mission_id) REFERENCES missions(id) ON DELETE CASCADE;
ALTER TABLE codes_secours_mission ADD CONSTRAINT codes_secours_mission_type_check CHECK ((type = ANY (ARRAY['ARRIVEE'::text, 'DEPART'::text, 'UNIVERSEL'::text])));
ALTER TABLE conformite_travail ADD CONSTRAINT conformite_travail_pkey PRIMARY KEY (id);
ALTER TABLE conformite_travail ADD CONSTRAINT conformite_travail_mission_id_fkey FOREIGN KEY (mission_id) REFERENCES missions(id);
ALTER TABLE conformite_travail ADD CONSTRAINT conformite_travail_soignant_id_fkey FOREIGN KEY (soignant_id) REFERENCES soignants(id);
ALTER TABLE conformite_travail ADD CONSTRAINT conformite_travail_resultat_check CHECK ((resultat = ANY (ARRAY['CONFORME'::text, 'VIOLATION_BLOQUEE'::text, 'VIOLATION_ALERTEE'::text, 'DEROGATION_AUTORISEE'::text])));
ALTER TABLE conformite_travail ADD CONSTRAINT conformite_travail_type_controle_check CHECK ((type_controle = ANY (ARRAY['REPOS_11H'::text, 'REPOS_HEBDO_35H'::text, 'PLAFOND_48H_HEBDO'::text, 'MOYENNE_44H_12_SEMAINES'::text, 'PLAFOND_10H_JOUR'::text, 'PLAFOND_RIST'::text, 'LIMITE_TRAVAIL_NUIT'::text, 'VALIDITE_DOCUMENTS'::text])));
ALTER TABLE consentements_ping_gps ADD CONSTRAINT consentements_ping_gps_pkey PRIMARY KEY (soignant_id);
ALTER TABLE consentements_ping_gps ADD CONSTRAINT consentements_ping_gps_soignant_id_fkey FOREIGN KEY (soignant_id) REFERENCES auth.users(id) ON DELETE CASCADE;
ALTER TABLE contrats_mission ADD CONSTRAINT contrats_mission_pkey PRIMARY KEY (id);
ALTER TABLE contrats_mission ADD CONSTRAINT contrats_mission_numero_contrat_key UNIQUE (numero_contrat);
ALTER TABLE contrats_mission ADD CONSTRAINT contrats_mission_etablissement_id_fkey FOREIGN KEY (etablissement_id) REFERENCES etablissements(id);
ALTER TABLE contrats_mission ADD CONSTRAINT contrats_mission_mission_id_fkey FOREIGN KEY (mission_id) REFERENCES missions(id);
ALTER TABLE contrats_mission ADD CONSTRAINT contrats_mission_soignant_id_fkey FOREIGN KEY (soignant_id) REFERENCES soignants(id);
ALTER TABLE contrats_mission ADD CONSTRAINT contrats_mission_mode_signature_check CHECK ((mode_signature = ANY (ARRAY['CANVAS'::text, 'JOLENE_OTP'::text])));
ALTER TABLE contrats_mission ADD CONSTRAINT contrats_mission_statut_check CHECK ((statut = ANY (ARRAY['BROUILLON'::text, 'EN_ATTENTE_SIGNATURES'::text, 'SIGNE_ETABLISSEMENT'::text, 'SIGNE_SOIGNANT'::text, 'SIGNE_COMPLET'::text, 'ANNULE'::text, 'EXPIRE'::text])));
ALTER TABLE contrats_mission ADD CONSTRAINT contrats_mission_type_contrat_check CHECK ((type_contrat = ANY (ARRAY['CDDU'::text, 'VACATION'::text, 'REMPLACEMENT_LIBERAL'::text, 'CDD'::text])));
ALTER TABLE contrats_service_signatures ADD CONSTRAINT contrats_service_signatures_pkey PRIMARY KEY (id);
ALTER TABLE contrats_service_signatures ADD CONSTRAINT contrats_service_signatures_etablissement_id_fkey FOREIGN KEY (etablissement_id) REFERENCES etablissements(id);
ALTER TABLE contrats_travail_missions ADD CONSTRAINT contrats_travail_missions_pkey PRIMARY KEY (id);
ALTER TABLE contrats_travail_missions ADD CONSTRAINT contrats_travail_missions_mission_id_key UNIQUE (mission_id);
ALTER TABLE contrats_travail_missions ADD CONSTRAINT contrats_travail_missions_etablissement_id_fkey FOREIGN KEY (etablissement_id) REFERENCES etablissements(id);
ALTER TABLE contrats_travail_missions ADD CONSTRAINT contrats_travail_missions_mission_id_fkey FOREIGN KEY (mission_id) REFERENCES missions(id);
ALTER TABLE contrats_travail_missions ADD CONSTRAINT contrats_travail_missions_soignant_id_fkey FOREIGN KEY (soignant_id) REFERENCES soignants(id);
ALTER TABLE conversations ADD CONSTRAINT conversations_pkey PRIMARY KEY (id);
ALTER TABLE conversations ADD CONSTRAINT conversations_participant_1_id_participant_2_id_mission_id_key UNIQUE (participant_1_id, participant_2_id, mission_id);
ALTER TABLE conversations ADD CONSTRAINT conversations_mission_id_fkey FOREIGN KEY (mission_id) REFERENCES missions(id);
ALTER TABLE conversions_liberal ADD CONSTRAINT conversions_liberal_pkey PRIMARY KEY (id);
ALTER TABLE conversions_liberal ADD CONSTRAINT conversions_liberal_soignant_id_fkey FOREIGN KEY (soignant_id) REFERENCES soignants(id);
ALTER TABLE conversions_liberal ADD CONSTRAINT conversions_liberal_statut_check CHECK ((statut = ANY (ARRAY['INITIE'::text, 'URSSAF_EN_COURS'::text, 'SIRET_RECU'::text, 'CPAM_EN_COURS'::text, 'ORDRE_EN_COURS'::text, 'RCP_EN_COURS'::text, 'COMPLET'::text, 'ABANDONNE'::text])));
ALTER TABLE cotisations_sociales ADD CONSTRAINT cotisations_sociales_pkey PRIMARY KEY (id);
ALTER TABLE cotisations_sociales ADD CONSTRAINT cotisations_sociales_mission_id_fkey FOREIGN KEY (mission_id) REFERENCES missions(id);
ALTER TABLE cotisations_sociales ADD CONSTRAINT cotisations_sociales_soignant_id_fkey FOREIGN KEY (soignant_id) REFERENCES soignants(id);
ALTER TABLE cotisations_sociales ADD CONSTRAINT cotisations_sociales_type_contrat_check CHECK ((type_contrat = ANY (ARRAY['CDD'::text, 'CDDU'::text, 'REMPLACEMENT_LIBERAL'::text])));
ALTER TABLE credits_etablissement ADD CONSTRAINT credits_etablissement_pkey PRIMARY KEY (id);
ALTER TABLE credits_etablissement ADD CONSTRAINT credits_etablissement_etablissement_id_fkey FOREIGN KEY (etablissement_id) REFERENCES etablissements(id) ON DELETE CASCADE;
ALTER TABLE credits_etablissement ADD CONSTRAINT credits_etablissement_facture_id_fkey FOREIGN KEY (facture_id) REFERENCES factures(id) ON DELETE SET NULL;
ALTER TABLE credits_etablissement ADD CONSTRAINT credits_etablissement_parrainage_id_fkey FOREIGN KEY (parrainage_id) REFERENCES parrainages_etablissements(id) ON DELETE SET NULL;
ALTER TABLE credits_etablissement ADD CONSTRAINT credits_etablissement_montant_eur_check CHECK ((montant_eur > (0)::numeric));
ALTER TABLE demandes_rgpd ADD CONSTRAINT demandes_rgpd_pkey PRIMARY KEY (id);
ALTER TABLE demandes_rgpd ADD CONSTRAINT demandes_rgpd_statut_check CHECK ((statut = ANY (ARRAY['EN_ATTENTE'::text, 'EN_COURS'::text, 'TERMINEE'::text, 'REJETEE'::text, 'PARTIELLE'::text])));
ALTER TABLE demandes_rgpd ADD CONSTRAINT demandes_rgpd_type_demande_check CHECK ((type_demande = ANY (ARRAY['ACCES'::text, 'RECTIFICATION'::text, 'EFFACEMENT'::text, 'PORTABILITE'::text, 'LIMITATION'::text, 'OPPOSITION'::text, 'PURGE_AUTOMATIQUE'::text])));
ALTER TABLE demandes_rgpd ADD CONSTRAINT demandes_rgpd_type_demandeur_check CHECK ((type_demandeur = ANY (ARRAY['SOIGNANT'::text, 'ADMIN_ETABLISSEMENT'::text])));
ALTER TABLE documents_requis_par_profession ADD CONSTRAINT documents_requis_par_profession_pkey PRIMARY KEY (id);
ALTER TABLE documents_requis_par_profession ADD CONSTRAINT documents_requis_par_profession_profession_type_document_key UNIQUE (profession, type_document);
ALTER TABLE documents_requis_par_profession ADD CONSTRAINT chk_type_exercice_requis CHECK ((type_exercice_requis = ANY (ARRAY['SALARIE_ONLY'::text, 'LIBERAL_ONLY'::text, 'TOUS'::text])));
ALTER TABLE documents_soignants ADD CONSTRAINT documents_soignants_pkey PRIMARY KEY (id);
ALTER TABLE documents_soignants ADD CONSTRAINT documents_soignants_soignant_id_fkey FOREIGN KEY (soignant_id) REFERENCES soignants(id) ON DELETE CASCADE;
ALTER TABLE email_queue ADD CONSTRAINT email_queue_pkey PRIMARY KEY (id);
ALTER TABLE email_queue ADD CONSTRAINT email_queue_statut_check CHECK ((statut = ANY (ARRAY['EN_ATTENTE'::text, 'ENVOYE'::text, 'ANNULE'::text, 'ERREUR'::text])));
ALTER TABLE emails_envoyes ADD CONSTRAINT emails_envoyes_pkey PRIMARY KEY (id);
ALTER TABLE emails_envoyes ADD CONSTRAINT emails_envoyes_statut_check CHECK ((statut = ANY (ARRAY['ENVOYE'::text, 'DELIVRE'::text, 'OUVERT'::text, 'ERREUR'::text])));
ALTER TABLE emails_envoyes ADD CONSTRAINT emails_envoyes_type_check CHECK ((type = ANY (ARRAY['BIENVENUE_SOIGNANT'::text, 'BIENVENUE_ETABLISSEMENT'::text, 'MISSION_ACCEPTEE'::text, 'MISSION_ANNULEE'::text, 'MISSION_TERMINEE'::text, 'MISSION_RAPPEL'::text, 'FACTURE_MENSUELLE'::text, 'FACTURE_PAYEE'::text, 'DOCUMENT_EXPIRANT'::text, 'RECAP_HEBDO_SOIGNANT'::text, 'RECAP_HEBDO_ETABLISSEMENT'::text, 'CONVERSION_LIBERAL'::text, 'RESET_MOT_DE_PASSE'::text, 'GENERAL'::text])));
ALTER TABLE emails_post_mission ADD CONSTRAINT emails_post_mission_pkey PRIMARY KEY (id);
ALTER TABLE emails_post_mission ADD CONSTRAINT emails_post_mission_mission_id_cible_key UNIQUE (mission_id, cible);
ALTER TABLE equipe_admin ADD CONSTRAINT equipe_admin_pkey PRIMARY KEY (id);
ALTER TABLE equipe_admin ADD CONSTRAINT equipe_admin_user_id_key UNIQUE (user_id);
ALTER TABLE equipe_membres ADD CONSTRAINT equipe_membres_pkey PRIMARY KEY (id);
ALTER TABLE equipe_membres ADD CONSTRAINT equipe_membres_equipe_id_fkey FOREIGN KEY (equipe_id) REFERENCES equipes(id) ON DELETE CASCADE;
ALTER TABLE equipes ADD CONSTRAINT equipes_pkey PRIMARY KEY (id);
ALTER TABLE equipes ADD CONSTRAINT equipes_etablissement_id_fkey FOREIGN KEY (etablissement_id) REFERENCES etablissements(id);
ALTER TABLE equivalences_scolarite ADD CONSTRAINT equivalences_scolarite_pkey PRIMARY KEY (id);
ALTER TABLE equivalences_scolarite ADD CONSTRAINT uq_equiv_scolarite UNIQUE (formation, annee_validee_min, profession_autorisee);
ALTER TABLE equivalences_scolarite ADD CONSTRAINT equivalences_scolarite_annee_validee_min_check CHECK ((annee_validee_min >= 1));
ALTER TABLE etablissements ADD CONSTRAINT etablissements_pkey PRIMARY KEY (id);
ALTER TABLE etablissements ADD CONSTRAINT etablissements_code_parrainage_key UNIQUE (code_parrainage);
ALTER TABLE etablissements ADD CONSTRAINT etablissements_finess_key UNIQUE (finess);
ALTER TABLE etablissements ADD CONSTRAINT etablissements_siret_key UNIQUE (siret);
ALTER TABLE etablissements ADD CONSTRAINT etablissements_groupe_sante_id_fkey FOREIGN KEY (groupe_sante_id) REFERENCES groupes_sante(id);
ALTER TABLE etablissements ADD CONSTRAINT etablissements_palier_commission_id_fkey FOREIGN KEY (palier_commission_id) REFERENCES paliers_commission(id);
ALTER TABLE etablissements ADD CONSTRAINT etablissements_parraine_par_id_fkey FOREIGN KEY (parraine_par_id) REFERENCES etablissements(id) ON DELETE SET NULL;
ALTER TABLE etablissements ADD CONSTRAINT chk_etab_telephone_format CHECK (((telephone_contact IS NULL) OR ((telephone_contact)::text ~ '^\+?[0-9\s\-\.]{8,20}$'::text)));
ALTER TABLE etablissements ADD CONSTRAINT chk_heure_debut_nuit CHECK (((heure_debut_nuit >= '19:00:00'::time without time zone) AND (heure_debut_nuit <= '23:59:00'::time without time zone)));
ALTER TABLE etablissements ADD CONSTRAINT chk_heure_fin_nuit CHECK (((heure_fin_nuit >= '04:00:00'::time without time zone) AND (heure_fin_nuit <= '08:00:00'::time without time zone)));
ALTER TABLE etablissements ADD CONSTRAINT chk_taux_maj_dim_min CHECK ((taux_majoration_dimanche_pourcent >= (25)::numeric));
ALTER TABLE etablissements ADD CONSTRAINT chk_taux_maj_fer_min CHECK ((taux_majoration_ferie_pourcent >= (50)::numeric));
ALTER TABLE etablissements ADD CONSTRAINT chk_taux_maj_nuit_min CHECK ((taux_majoration_nuit_pourcent >= (25)::numeric));
ALTER TABLE etablissements ADD CONSTRAINT etablissements_convention_collective_check CHECK ((convention_collective = ANY (ARRAY['CCN_51_FEHAP'::text, 'CCN_66_SOCIAL'::text, 'CCN_FHP_PRIVE'::text, 'CCN_PHARMACIE'::text, 'FPH_PUBLIQUE'::text, 'AUTRE'::text, NULL::text])));
ALTER TABLE etablissements ADD CONSTRAINT etablissements_formule_abonnement_check CHECK ((formule_abonnement = ANY (ARRAY['GRATUIT'::text, 'STARTER'::text, 'PRO'::text, 'ENTERPRISE'::text])));
ALTER TABLE etablissements ADD CONSTRAINT etablissements_jour_paie_check CHECK (((jour_paie_habituel >= 1) AND (jour_paie_habituel <= 31)));
ALTER TABLE etablissements ADD CONSTRAINT etablissements_mode_facturation_check CHECK ((mode_facturation = ANY (ARRAY['PAR_MISSION'::text, 'MENSUEL'::text])));
ALTER TABLE etablissements ADD CONSTRAINT etablissements_mode_paiement_commission_check CHECK ((mode_paiement_commission = ANY (ARRAY['STRIPE_RESERVATION'::text, 'FACTURE_MENSUELLE'::text, 'SEPA_DEBIT'::text, 'CHORUS_PRO'::text])));
ALTER TABLE etablissements ADD CONSTRAINT etablissements_rattachement_methode_check CHECK (((rattachement_methode IS NULL) OR (rattachement_methode = ANY (ARRAY['AUTO_DIRIGEANT'::text, 'EMAIL_PRO'::text, 'ADMIN'::text]))));
ALTER TABLE etablissements ADD CONSTRAINT etablissements_representant_piece_type_check CHECK (((representant_piece_type_document IS NULL) OR (representant_piece_type_document = ANY (ARRAY['CARTE_IDENTITE'::text, 'PASSEPORT'::text, 'TITRE_SEJOUR'::text]))));
ALTER TABLE etablissements ADD CONSTRAINT etablissements_statut_verification_check CHECK ((statut_verification = ANY (ARRAY['EN_ATTENTE'::text, 'EN_COURS'::text, 'VERIFIE'::text, 'REJETE'::text, 'SUSPENDU'::text])));
ALTER TABLE etablissements ADD CONSTRAINT etablissements_tolerance_pointage_m_check CHECK (((tolerance_pointage_m >= 30) AND (tolerance_pointage_m <= 1000)));
ALTER TABLE evaluations ADD CONSTRAINT evaluations_pkey PRIMARY KEY (id);
ALTER TABLE evaluations ADD CONSTRAINT evaluations_mission_id_evaluateur_id_key UNIQUE (mission_id, evaluateur_id);
ALTER TABLE evaluations ADD CONSTRAINT evaluations_mission_id_fkey FOREIGN KEY (mission_id) REFERENCES missions(id);
ALTER TABLE evaluations ADD CONSTRAINT chk_note_1_5 CHECK (((note >= 1) AND (note <= 5)));
ALTER TABLE evaluations ADD CONSTRAINT evaluations_type_evaluateur_check CHECK ((type_evaluateur = ANY (ARRAY['SOIGNANT'::text, 'ETABLISSEMENT'::text])));
ALTER TABLE evenements_score_etab ADD CONSTRAINT evenements_score_etab_pkey PRIMARY KEY (id);
ALTER TABLE evenements_score_etab ADD CONSTRAINT evenements_score_etab_litige_id_fkey FOREIGN KEY (litige_id) REFERENCES litiges(id) ON DELETE SET NULL;
ALTER TABLE evenements_score_etab ADD CONSTRAINT evenements_score_etab_mission_id_fkey FOREIGN KEY (mission_id) REFERENCES missions(id) ON DELETE SET NULL;
ALTER TABLE evenements_score_etab ADD CONSTRAINT evenements_score_etab_decision_admin_check CHECK (((decision_admin IS NULL) OR (decision_admin = ANY (ARRAY['MAINTENIR'::text, 'REDUIRE'::text, 'ANNULER'::text]))));
ALTER TABLE evenements_score_etab ADD CONSTRAINT evenements_score_etab_type_evenement_check CHECK ((type_evenement = ANY (ARRAY['ANNULATION_AVANT_CONTRAT'::text, 'ANNULATION_CDD_SIGNE'::text, 'ANNULATION_LIBERAL_SIGNE'::text, 'ANNULATION_APRES_POINTAGE'::text, 'PAIEMENT_RETARD'::text, 'LITIGE_TORT_RECONNU'::text, 'NOTE_BASSE_RECUE'::text, 'AUTRE'::text])));
ALTER TABLE evenements_score_soignant ADD CONSTRAINT evenements_score_soignant_pkey PRIMARY KEY (id);
ALTER TABLE evenements_score_soignant ADD CONSTRAINT evenements_score_soignant_candidature_id_fkey FOREIGN KEY (candidature_id) REFERENCES candidatures(id) ON DELETE SET NULL;
ALTER TABLE evenements_score_soignant ADD CONSTRAINT evenements_score_soignant_litige_id_fkey FOREIGN KEY (litige_id) REFERENCES litiges(id) ON DELETE SET NULL;
ALTER TABLE evenements_score_soignant ADD CONSTRAINT evenements_score_soignant_mission_id_fkey FOREIGN KEY (mission_id) REFERENCES missions(id) ON DELETE SET NULL;
ALTER TABLE evenements_score_soignant ADD CONSTRAINT evenements_score_soignant_decision_admin_check CHECK (((decision_admin IS NULL) OR (decision_admin = ANY (ARRAY['MAINTENIR'::text, 'REDUIRE'::text, 'ANNULER'::text]))));
ALTER TABLE evenements_score_soignant ADD CONSTRAINT evenements_score_soignant_type_evenement_check CHECK ((type_evenement = ANY (ARRAY['ANNULATION_12_24H'::text, 'ANNULATION_1_12H'::text, 'ASAP_ANNULEE_APRES_FENETRE'::text, 'NO_SHOW'::text, 'LITIGE_TORT_RECONNU'::text, 'NOTE_BASSE_RECUE'::text, 'EVALUATION_NEGATIVE'::text, 'BONUS_AMBASSADEUR'::text, 'BONUS_FIDELITE'::text, 'FRAUDE_GPS'::text, 'AUTRE'::text])));
ALTER TABLE exclusions ADD CONSTRAINT exclusions_pkey PRIMARY KEY (id);
ALTER TABLE exclusions ADD CONSTRAINT exclusions_exclu_par_exclu_id_key UNIQUE (exclu_par, exclu_id);
ALTER TABLE exclusions ADD CONSTRAINT exclusions_type_exclu_par_check CHECK ((type_exclu_par = ANY (ARRAY['SOIGNANT'::text, 'ETABLISSEMENT'::text])));
ALTER TABLE externalisation_actions ADD CONSTRAINT externalisation_actions_pkey PRIMARY KEY (id);
ALTER TABLE externalisation_actions ADD CONSTRAINT externalisation_actions_source_check CHECK ((source = ANY (ARRAY['LITIGE_EXEC'::text, 'ANNULATION_MISSION'::text, 'AUTRE'::text, 'CRON_ANTI_TRICHE'::text, 'CRON_ALERTES'::text, 'parrainage_soignant'::text, 'remboursement_avoir'::text])));
ALTER TABLE externalisation_actions ADD CONSTRAINT externalisation_actions_statut_check CHECK ((statut = ANY (ARRAY['PENDING'::text, 'PROCESSING'::text, 'DONE'::text, 'ERROR'::text, 'PENDING_AIFE'::text, 'CANCELLED'::text])));
ALTER TABLE externalisation_actions ADD CONSTRAINT externalisation_actions_type_action_check CHECK ((type_action = ANY (ARRAY['STRIPE_REFUND_PARTIEL'::text, 'STRIPE_REFUND_TOTAL'::text, 'STRIPE_PAYMENT'::text, 'STRIPE_PAYOUT'::text, 'CHORUS_RECYCLER_FACTURE'::text, 'CHORUS_RECYCLE_FACTURE'::text, 'DPAE_ANNULATION'::text, 'DPAE_ANNULATION_NOTIF'::text, 'EMAIL_NOTIF'::text, 'PUSH_NOTIF'::text, 'AVOIR_PDF_GENERATION'::text, 'RECOMPENSE_PARRAINAGE_SOIGNANT'::text, 'REMBOURSEMENT_AVOIR_SWAN'::text])));
ALTER TABLE factor_advances ADD CONSTRAINT factor_advances_pkey PRIMARY KEY (id);
ALTER TABLE factor_advances ADD CONSTRAINT factor_advances_etablissement_id_fkey FOREIGN KEY (etablissement_id) REFERENCES etablissements(id);
ALTER TABLE factor_advances ADD CONSTRAINT factor_advances_facture_honoraire_id_fkey FOREIGN KEY (facture_honoraire_id) REFERENCES factures_honoraires(id) ON DELETE CASCADE;
ALTER TABLE factor_advances ADD CONSTRAINT factor_advances_mission_id_fkey FOREIGN KEY (mission_id) REFERENCES missions(id);
ALTER TABLE factor_advances ADD CONSTRAINT factor_advances_soignant_id_fkey FOREIGN KEY (soignant_id) REFERENCES soignants(id);
ALTER TABLE factor_advances ADD CONSTRAINT factor_advances_statut_check CHECK ((statut = ANY (ARRAY['DEMANDEE'::text, 'EN_ANALYSE'::text, 'APPROUVEE'::text, 'REJETEE'::text, 'FINANCEE'::text, 'RECOUVREE'::text, 'IMPAYEE'::text, 'ANNULEE'::text])));
ALTER TABLE factoring_partners ADD CONSTRAINT factoring_partners_pkey PRIMARY KEY (id);
ALTER TABLE factures ADD CONSTRAINT factures_pkey PRIMARY KEY (id);
ALTER TABLE factures ADD CONSTRAINT factures_numero_facture_key UNIQUE (numero_facture);
ALTER TABLE factures ADD CONSTRAINT factures_etablissement_id_fkey FOREIGN KEY (etablissement_id) REFERENCES etablissements(id);
ALTER TABLE factures ADD CONSTRAINT factures_facture_precedente_id_fkey FOREIGN KEY (facture_precedente_id) REFERENCES factures(id) ON DELETE SET NULL;
ALTER TABLE factures ADD CONSTRAINT factures_mission_id_fkey FOREIGN KEY (mission_id) REFERENCES missions(id);
ALTER TABLE factures ADD CONSTRAINT factures_chorus_pro_statut_check CHECK ((chorus_pro_statut = ANY (ARRAY['NON_APPLICABLE'::text, 'A_DEPOSER'::text, 'DEPOSEE'::text, 'RECUE'::text, 'MANDATEE'::text, 'PAYEE'::text, 'REJETEE'::text])));
ALTER TABLE factures ADD CONSTRAINT factures_mode_paiement_check CHECK ((mode_paiement = ANY (ARRAY['STRIPE'::text, 'VIREMENT'::text, 'CHORUS_PRO'::text])));
ALTER TABLE factures ADD CONSTRAINT factures_statut_check CHECK ((statut = ANY (ARRAY['BROUILLON'::text, 'EMISE'::text, 'VIREMENT_DECLARE'::text, 'PAYEE'::text, 'EN_RETARD'::text, 'ANNULEE'::text])));
ALTER TABLE factures ADD CONSTRAINT factures_type_document_check CHECK ((type_document = ANY (ARRAY['FACTURE'::text, 'AVOIR'::text, 'FACTURE_COMPLEMENTAIRE'::text])));
ALTER TABLE factures_honoraires ADD CONSTRAINT factures_honoraires_pkey PRIMARY KEY (id);
ALTER TABLE factures_honoraires ADD CONSTRAINT factures_honoraires_numero_facture_key UNIQUE (numero_facture);
ALTER TABLE factures_honoraires ADD CONSTRAINT factures_honoraires_etablissement_id_fkey FOREIGN KEY (etablissement_id) REFERENCES etablissements(id);
ALTER TABLE factures_honoraires ADD CONSTRAINT factures_honoraires_facture_precedente_id_fkey FOREIGN KEY (facture_precedente_id) REFERENCES factures_honoraires(id) ON DELETE SET NULL;
ALTER TABLE factures_honoraires ADD CONSTRAINT factures_honoraires_litige_id_fkey FOREIGN KEY (litige_id) REFERENCES litiges(id) ON DELETE SET NULL;
ALTER TABLE factures_honoraires ADD CONSTRAINT factures_honoraires_mission_id_fkey FOREIGN KEY (mission_id) REFERENCES missions(id);
ALTER TABLE factures_honoraires ADD CONSTRAINT factures_honoraires_soignant_id_fkey FOREIGN KEY (soignant_id) REFERENCES soignants(id);
ALTER TABLE factures_honoraires ADD CONSTRAINT factures_honoraires_statut_check CHECK ((statut = ANY (ARRAY['BROUILLON'::text, 'EN_GENERATION'::text, 'EMISE'::text, 'PAYEE'::text, 'ANNULEE'::text, 'FACTORISEE'::text, 'EN_RETARD'::text, 'REMPLACEE'::text, 'ERREUR_GENERATION'::text, 'REMBOURSE'::text])));
ALTER TABLE favoris_etab_soignant ADD CONSTRAINT favoris_pkey PRIMARY KEY (id);
ALTER TABLE favoris_etab_soignant ADD CONSTRAINT favoris_etablissement_id_soignant_id_key UNIQUE (etablissement_id, soignant_id);
ALTER TABLE favoris_soignant_etab ADD CONSTRAINT favoris_soignant_etab_pkey PRIMARY KEY (id);
ALTER TABLE favoris_soignant_etab ADD CONSTRAINT favoris_soignant_etab_soignant_id_etablissement_id_key UNIQUE (soignant_id, etablissement_id);
ALTER TABLE favoris_soignant_etab ADD CONSTRAINT favoris_soignant_etab_etablissement_id_fkey FOREIGN KEY (etablissement_id) REFERENCES etablissements(id) ON DELETE CASCADE;
ALTER TABLE favoris_soignant_etab ADD CONSTRAINT favoris_soignant_etab_soignant_id_fkey FOREIGN KEY (soignant_id) REFERENCES soignants(id) ON DELETE CASCADE;
ALTER TABLE file_revue_manuelle ADD CONSTRAINT file_revue_manuelle_pkey PRIMARY KEY (id);
ALTER TABLE file_revue_manuelle ADD CONSTRAINT file_revue_manuelle_priorite_check CHECK (((priorite >= 1) AND (priorite <= 5)));
ALTER TABLE file_revue_manuelle ADD CONSTRAINT file_revue_manuelle_statut_check CHECK ((statut = ANY (ARRAY['EN_ATTENTE'::text, 'EN_COURS_REVUE'::text, 'RESOLU_AUTO'::text, 'RESOLU_MANUELLEMENT'::text, 'ESCALADE'::text, 'EXPIRE'::text])));
ALTER TABLE file_revue_manuelle ADD CONSTRAINT file_revue_manuelle_type_entite_check CHECK ((type_entite = ANY (ARRAY['VERIFICATION_SOIGNANT'::text, 'SIGNATURE_MISSION'::text, 'PAIEMENT'::text, 'TELEVERSEMENT_DOCUMENT'::text, 'ALERTE_FRAUDE'::text, 'SOIGNANT'::text, 'COHERENCE_IDENTITE'::text, 'ETABLISSEMENT'::text])));
ALTER TABLE filtres_sauvegardes ADD CONSTRAINT filtres_sauvegardes_pkey PRIMARY KEY (id);
ALTER TABLE filtres_sauvegardes ADD CONSTRAINT filtres_sauvegardes_utilisateur_id_nom_key UNIQUE (utilisateur_id, nom);
ALTER TABLE filtres_sauvegardes ADD CONSTRAINT filtres_sauvegardes_utilisateur_id_fkey FOREIGN KEY (utilisateur_id) REFERENCES auth.users(id) ON DELETE CASCADE;
ALTER TABLE filtres_sauvegardes ADD CONSTRAINT filtres_sauvegardes_nom_check CHECK (((length(nom) >= 1) AND (length(nom) <= 100)));
ALTER TABLE fondateur_documents ADD CONSTRAINT fondateur_documents_pkey PRIMARY KEY (id);
ALTER TABLE fondateur_documents ADD CONSTRAINT fondateur_documents_categorie_check CHECK ((categorie = ANY (ARRAY['NOTE'::text, 'BUSINESS_PLAN'::text, 'DECK'::text, 'FINANCIER'::text, 'LEGAL'::text, 'AUTRE'::text])));
ALTER TABLE groupes_sante ADD CONSTRAINT groupes_sante_pkey PRIMARY KEY (id);
ALTER TABLE groupes_sante ADD CONSTRAINT groupes_sante_siren_key UNIQUE (siren);
ALTER TABLE groupes_sante ADD CONSTRAINT groupes_sante_groupe_parent_id_fkey FOREIGN KEY (groupe_parent_id) REFERENCES groupes_sante(id);
ALTER TABLE groupes_sante ADD CONSTRAINT groupes_sante_formule_abonnement_check CHECK ((formule_abonnement = ANY (ARRAY['GRATUIT'::text, 'STARTER'::text, 'PRO'::text, 'ENTERPRISE'::text])));
ALTER TABLE groupes_sante ADD CONSTRAINT groupes_sante_taux_commission_range CHECK (((taux_commission_negocie IS NULL) OR ((taux_commission_negocie >= (0)::numeric) AND (taux_commission_negocie <= (100)::numeric))));
ALTER TABLE growth_config ADD CONSTRAINT growth_config_pkey PRIMARY KEY (cle);
ALTER TABLE health_check ADD CONSTRAINT health_check_pkey PRIMARY KEY (id);
ALTER TABLE health_check ADD CONSTRAINT health_check_statut_check CHECK ((statut = ANY (ARRAY['OK'::text, 'DEGRADÉ'::text, 'DOWN'::text])));
ALTER TABLE heures_externes ADD CONSTRAINT heures_externes_pkey PRIMARY KEY (id);
ALTER TABLE heures_externes ADD CONSTRAINT heures_externes_document_id_fkey FOREIGN KEY (document_id) REFERENCES documents_soignants(id);
ALTER TABLE heures_externes ADD CONSTRAINT heures_externes_soignant_id_fkey FOREIGN KEY (soignant_id) REFERENCES soignants(id);
ALTER TABLE heures_externes ADD CONSTRAINT heures_externes_statut_check CHECK ((statut = ANY (ARRAY['EN_ATTENTE'::text, 'VALIDEE'::text, 'REJETEE'::text, 'VERIFICATION_EN_COURS'::text])));
ALTER TABLE heures_externes ADD CONSTRAINT heures_externes_type_preuve_check CHECK ((type_preuve = ANY (ARRAY['BULLETIN_PAIE'::text, 'ATTESTATION_EMPLOYEUR'::text, 'CERTIFICAT_TRAVAIL'::text, 'RELEVE_HEURES'::text, 'AUTRE'::text])));
ALTER TABLE heures_externes_soignants ADD CONSTRAINT heures_externes_soignants_pkey PRIMARY KEY (id);
ALTER TABLE heures_externes_soignants ADD CONSTRAINT heures_externes_soignants_soignant_id_fkey FOREIGN KEY (soignant_id) REFERENCES soignants(id) ON DELETE CASCADE;
ALTER TABLE heures_externes_soignants ADD CONSTRAINT heures_externes_soignants_valide_par_fkey FOREIGN KEY (valide_par) REFERENCES auth.users(id);
ALTER TABLE heures_externes_soignants ADD CONSTRAINT heures_externes_soignants_check CHECK ((date_fin >= date_debut));
ALTER TABLE heures_externes_soignants ADD CONSTRAINT heures_externes_soignants_heures_declarees_check CHECK (((heures_declarees > 0) AND (heures_declarees <= 10000)));
ALTER TABLE heures_externes_soignants ADD CONSTRAINT heures_externes_soignants_statut_validation_check CHECK ((statut_validation = ANY (ARRAY['EN_ATTENTE'::text, 'VALIDE'::text, 'REJETE'::text])));
ALTER TABLE historique_blocages_etablissements ADD CONSTRAINT historique_blocages_etablissements_pkey PRIMARY KEY (id);
ALTER TABLE historique_blocages_etablissements ADD CONSTRAINT historique_blocages_etablissements_etablissement_id_fkey FOREIGN KEY (etablissement_id) REFERENCES etablissements(id);
ALTER TABLE historique_blocages_etablissements ADD CONSTRAINT historique_blocages_etablissements_action_check CHECK ((action = ANY (ARRAY['BLOCAGE'::text, 'DEBLOCAGE'::text])));
ALTER TABLE investisseurs_pipeline ADD CONSTRAINT investisseurs_pipeline_pkey PRIMARY KEY (id);
ALTER TABLE investisseurs_pipeline ADD CONSTRAINT investisseurs_pipeline_statut_check CHECK ((statut = ANY (ARRAY['A_CONTACTER'::text, 'CONTACTE'::text, 'INTRO_FAITE'::text, 'PITCH'::text, 'DUE_DILIGENCE'::text, 'TERM_SHEET'::text, 'SIGNE'::text, 'DECLINE'::text])));
ALTER TABLE invitations_etablissement ADD CONSTRAINT invitations_etablissement_pkey PRIMARY KEY (id);
ALTER TABLE invitations_etablissement ADD CONSTRAINT invitations_etablissement_token_key UNIQUE (token);
ALTER TABLE invitations_etablissement ADD CONSTRAINT invitations_etablissement_acceptee_par_user_id_fkey FOREIGN KEY (acceptee_par_user_id) REFERENCES auth.users(id) ON DELETE SET NULL;
ALTER TABLE invitations_etablissement ADD CONSTRAINT invitations_etablissement_etablissement_id_fkey FOREIGN KEY (etablissement_id) REFERENCES etablissements(id) ON DELETE CASCADE;
ALTER TABLE invitations_etablissement ADD CONSTRAINT invitations_etablissement_invite_par_fkey FOREIGN KEY (invite_par) REFERENCES auth.users(id) ON DELETE CASCADE;
ALTER TABLE invitations_etablissement ADD CONSTRAINT invitations_etablissement_role_propose_check CHECK ((role_propose = ANY (ARRAY['ADMIN_GROUPE'::text, 'RH'::text, 'POINTAGE_ONLY'::text, 'LECTURE_SEULE'::text])));
ALTER TABLE invitations_etablissement ADD CONSTRAINT invitations_etablissement_statut_check CHECK ((statut = ANY (ARRAY['EN_ATTENTE'::text, 'ACCEPTEE'::text, 'EXPIREE'::text, 'ANNULEE'::text])));
ALTER TABLE invoice_audit_log ADD CONSTRAINT invoice_audit_log_pkey PRIMARY KEY (id);
ALTER TABLE invoice_audit_log ADD CONSTRAINT invoice_audit_log_invoice_id_fkey FOREIGN KEY (invoice_id) REFERENCES factures_honoraires(id) ON DELETE RESTRICT;
ALTER TABLE journaux_audit ADD CONSTRAINT journaux_audit_pkey PRIMARY KEY (id);
ALTER TABLE journaux_audit ADD CONSTRAINT journaux_audit_action_check CHECK ((action = ANY (ARRAY['INSCRIPTION'::text, 'CONNEXION'::text, 'DECONNEXION'::text, 'MODIFICATION_PROFIL'::text, 'SUPPRESSION_COMPTE'::text, 'UPLOAD_DOCUMENT'::text, 'TELECHARGEMENT_DOCUMENT'::text, 'VERIFICATION_DOCUMENT'::text, 'VERIFICATION_RPPS'::text, 'CREATION_MISSION'::text, 'MODIFICATION_MISSION'::text, 'ANNULATION_MISSION'::text, 'CANDIDATURE'::text, 'ASSIGNATION'::text, 'POINTAGE'::text, 'SIGNATURE_CONTRAT'::text, 'EVALUATION'::text, 'PAIEMENT'::text, 'FACTURATION'::text, 'DONNEES_PERSO_CONSULTATION'::text, 'DONNEES_PERSO_EXPORT'::text, 'DONNEES_PERSO_SUPPRESSION'::text, 'ADMIN_ACTION'::text, 'SYSTEM'::text, 'RIB_CONSULTE'::text, 'RIB_PARTAGE'::text, 'CONTRAT_SIGNE'::text, 'DOCUMENT_CONSULTATION'::text, 'DOCUMENT_TELEVERSEMENT'::text, 'DONNEES_PERSO_MODIFICATION'::text, 'EXPORT_RH_PAIE'::text, 'FINANCE_FACTURE_PAYEE'::text, 'MISSION_ASSIGNATION'::text, 'MISSION_CREATION'::text, 'RGPD_EXPORT_DONNEES'::text, 'RGPD_SUPPRESSION_COMPTE'::text, 'RGPD_SUPPRESSION_COMPTE_ETABLISSEMENT'::text, 'DEGEL_APPLIED'::text, 'OVERRIDE_CHAMP_POST_GEL'::text, 'GEL_APPLIED'::text, 'OVERRIDE_ANTI_SEED'::text, 'CONNECT_METADATA_MANQUANTE'::text, 'DOCUMENT_VERIFICATION_AUTO'::text, 'FACTURE_COMMISSION_PAYEE_SKIP_ANOMALIE'::text, 'FACTURE_HONORAIRES_PAYEE_SKIP_ANOMALIE'::text, 'FINANCE_CHARGE_EXPIRED'::text, 'FINANCE_CHARGE_FAILED'::text, 'FINANCE_CHARGE_PENDING'::text, 'FINANCE_CHARGE_REFUNDED'::text, 'FINANCE_DISPUTE_CLOSE'::text, 'FINANCE_DISPUTE_OUVERTE'::text, 'FINANCE_PAYOUT_CANCELED'::text, 'FINANCE_PAYOUT_CREATED'::text, 'FINANCE_PAYOUT_FAILED'::text, 'FINANCE_PAYOUT_PAID'::text, 'FINANCE_SEPA_CAPTURE'::text, 'FINANCE_TRANSFER_CONNECT'::text, 'FINANCE_TRANSFER_CREATED'::text, 'FINANCE_TRANSFER_FAILED'::text, 'FINANCE_TRANSFER_REVERSED'::text, 'FINANCE_TRANSFER_UPDATED'::text, 'STRIPE_CHECKOUT_ORPHANED_RECOVERED'::text, 'STRIPE_CONNECT_ACCOUNT_DELETED'::text, 'ATTESTATION_SANTE_SIGNEE'::text, 'EXCLUSION_CREEE'::text, 'EXCLUSION_SUPPRIMEE'::text, 'FACTURE_GENEREE'::text, 'MISSION_ANNULATION_SERIE'::text, 'MISSION_MODIFICATION'::text, 'PAIEMENT_SOIGNANT_DECLARE_ETAB'::text, 'RECLAMATION_CREEE'::text, 'ADMIN_CONSULTATION_ETABLISSEMENT'::text, 'ADMIN_CONSULTATION_SOIGNANT'::text, 'DOCUMENT_SUPPRESSION'::text, 'HEURES_EXTERNES_DECLAREES'::text, 'MISSION_ANNULATION'::text, 'NOTE_HONORAIRES_GENEREE'::text, 'PRESENCE_CONTESTATION'::text, 'PRESENCE_POINTAGE_ARRIVEE'::text, 'PRESENCE_VALIDATION'::text, 'PRESENCE_VALIDATION_LOT'::text, 'RGPD_CONSENTEMENT_DONNE'::text, 'PAIEMENT_MONTANT_ECART'::text, 'FACTURE_COMMISSION_CREATED_VIA_STRIPE'::text, 'TAUX_COMMISSION_MODIFIE'::text, 'LITIGE_GEL_SCOPE_MODIFIE'::text, 'PREFERENCE_NOTIFICATION_MODIFIEE'::text, 'NOTIFICATION_SKIPPED'::text, 'SERIE_EMAIL_ENVOYE'::text, 'SERIE_EMAIL_SKIPPED'::text, 'FILTRE_CREE'::text, 'FILTRE_MODIFIE'::text, 'FILTRE_SUPPRIME'::text, 'ALERTE_ACTIVEE'::text, 'ALERTE_DESACTIVEE'::text, 'ALERTE_ENVOYEE'::text, 'POOL_URGENCE_NOTIFICATIONS_ENVOYEES'::text, 'POOL_URGENCE_ACCEPTATION_RAPIDE'::text, 'POOL_URGENCE_VALIDATION_ETAB'::text, 'POOL_URGENCE_REFUS_ETAB'::text, 'POOL_URGENCE_SMS_TOGGLE'::text, 'FAVORI_AJOUTE'::text, 'FAVORI_RETIRE'::text, 'SCORE_FIABILITE_PENALITE_LITIGE'::text, 'PARRAINAGE_ETAB_APPLIQUE'::text, 'PARRAINAGE_ETAB_VALIDE'::text, 'CREDIT_PARRAINAGE_CREE'::text, 'CREDIT_PARRAINAGE_APPLIQUE'::text, 'PARRAINAGE_ETAB_ANOMALIE'::text, 'PARRAINAGE_SOIGNANT_FILLEUL_ACTIF'::text, 'PARRAINAGE_SOIGNANT_SEUIL_ATTEINT'::text, 'PARRAINAGE_SOIGNANT_PRIME_VERSEE'::text, 'PARRAINAGE_SOIGNANT_FRAUDE'::text, 'INSCRIPTION_LISTE_ATTENTE_PREVOYANCE'::text, 'SCORE_RECALCULE_V2'::text, 'IBAN_RENSEIGNE'::text, 'IBAN_MODIFIE'::text, 'AVOIR_REMBOURSEMENT_CONFIRME'::text, 'ETABLISSEMENT_MODIFICATION'::text, 'LITIGE_ACCORD_CLOTURE'::text, 'LITIGE_AUTO_CREATION'::text, 'LITIGE_CLOTURE_AMIABLE'::text, 'LITIGE_CREATION'::text, 'LITIGE_ESCALADE_AUTO'::text, 'LITIGE_FORCE_CREATION'::text, 'LITIGE_OUVERTURE'::text, 'LITIGE_OUVERTURE_LEGACY'::text, 'LITIGE_RECATEGORISATION_LEGACY'::text, 'LITIGE_REPONSE'::text, 'LITIGE_RESOLUTION'::text, 'PRESENCE_ALERTE_FRAUDE'::text, 'RGPD_SUPPRESSION_DONNEES'::text, 'TVA_MODIFICATION'::text, 'API_KEY_CREEE'::text, 'API_KEY_REVOQUEE'::text, 'API_KEY_SUPPRIMEE'::text, 'FACTURE_MARQUEE_EN_RETARD'::text, 'HEURES_EXTERNES_VALIDATION_MANUELLE'::text, 'MISSION_ANNULEE_PAR_SOIGNANT'::text, 'MISSION_ANNULEE_PAR_ETABLISSEMENT'::text, 'MISSION_LITIGE'::text, 'MISSION_TYPE_CONTRAT_MODIFIE'::text, 'MODERATION_DOCUMENT'::text, 'COHERENCE_IDENTITE_VERIFIEE'::text, 'MODERATION_EVALUATION'::text, 'COHERENCE_DOCUMENTS_ALERTE'::text])));
ALTER TABLE journaux_audit ADD CONSTRAINT journaux_audit_type_acteur_check CHECK ((type_acteur = ANY (ARRAY['SOIGNANT'::text, 'ADMIN_ETABLISSEMENT'::text, 'ADMIN_PLATEFORME'::text, 'ADMIN_GROUPE'::text, 'SYSTEME'::text, 'SERVICE_API'::text, 'ADMIN'::text, 'ETABLISSEMENT'::text, 'SYSTEM'::text, 'DEPRECATED_CALLER'::text])));
ALTER TABLE jours_feries_fr ADD CONSTRAINT jours_feries_fr_pkey PRIMARY KEY (id);
ALTER TABLE jours_feries_fr ADD CONSTRAINT jours_feries_fr_date_ferie_key UNIQUE (date_ferie);
ALTER TABLE liste_attente_premium ADD CONSTRAINT liste_attente_premium_pkey PRIMARY KEY (id);
ALTER TABLE liste_attente_premium ADD CONSTRAINT uq_liste_attente UNIQUE (email, type_offre);
ALTER TABLE liste_attente_premium ADD CONSTRAINT liste_attente_premium_type_offre_check CHECK ((type_offre = ANY (ARRAY['PREMIUM_SOIGNANT'::text, 'PACK_LIBERAL'::text, 'PACK_ETABLISSEMENT'::text])));
ALTER TABLE litiges ADD CONSTRAINT litiges_pkey PRIMARY KEY (id);
ALTER TABLE litiges ADD CONSTRAINT litiges_etablissement_id_fkey FOREIGN KEY (etablissement_id) REFERENCES etablissements(id) ON DELETE CASCADE;
ALTER TABLE litiges ADD CONSTRAINT litiges_facture_id_fkey FOREIGN KEY (facture_id) REFERENCES factures_honoraires(id) ON DELETE SET NULL;
ALTER TABLE litiges ADD CONSTRAINT litiges_mission_id_fkey FOREIGN KEY (mission_id) REFERENCES missions(id);
ALTER TABLE litiges ADD CONSTRAINT litiges_paiement_soignant_id_fkey FOREIGN KEY (paiement_soignant_id) REFERENCES paiements_soignant(id);
ALTER TABLE litiges ADD CONSTRAINT litiges_presence_id_fkey FOREIGN KEY (presence_id) REFERENCES presences(id);
ALTER TABLE litiges ADD CONSTRAINT litiges_soignant_id_fkey FOREIGN KEY (soignant_id) REFERENCES soignants(id) ON DELETE CASCADE;
ALTER TABLE litiges ADD CONSTRAINT litiges_gel_facture_scope_check CHECK ((gel_facture_scope = ANY (ARRAY['MISSION_ENTIERE'::text, 'FACTURE_UNIQUE'::text, 'AUCUN'::text, 'PERIODE_LITIGIEUSE'::text])));
ALTER TABLE litiges ADD CONSTRAINT litiges_initie_par_check CHECK ((initie_par = ANY (ARRAY['SOIGNANT'::text, 'ETABLISSEMENT'::text, 'SYSTEME'::text])));
ALTER TABLE litiges ADD CONSTRAINT litiges_statut_check CHECK ((statut = ANY (ARRAY['OUVERT'::text, 'EN_DISCUSSION'::text, 'EN_MEDIATION'::text, 'RESOLU_SOIGNANT'::text, 'RESOLU_ETABLISSEMENT'::text, 'RESOLU_ADMIN'::text, 'FERME'::text, 'MEDIATION_EN_COURS'::text, 'RESOLU_ACCORD_PARTIES'::text, 'REVUE_ADMIN'::text, 'RESOLU_FAVEUR_SOIGNANT'::text, 'RESOLU_FAVEUR_ETAB'::text, 'RESOLU_PARTAGE'::text])));
ALTER TABLE mandats_facturation_signatures ADD CONSTRAINT mandats_facturation_signatures_pkey PRIMARY KEY (id);
ALTER TABLE mandats_facturation_signatures ADD CONSTRAINT mandats_facturation_signatures_soignant_id_fkey FOREIGN KEY (soignant_id) REFERENCES soignants(id) ON DELETE CASCADE;
ALTER TABLE marche_taux_medians ADD CONSTRAINT marche_taux_medians_pkey PRIMARY KEY (profession);
ALTER TABLE matching_preferences_soignant ADD CONSTRAINT matching_preferences_soignant_pkey PRIMARY KEY (soignant_id);
ALTER TABLE matching_preferences_soignant ADD CONSTRAINT matching_preferences_soignant_soignant_id_fkey FOREIGN KEY (soignant_id) REFERENCES soignants(id) ON DELETE CASCADE;
ALTER TABLE matching_scores ADD CONSTRAINT matching_scores_pkey PRIMARY KEY (id);
ALTER TABLE matching_scores ADD CONSTRAINT matching_scores_soignant_id_mission_id_key UNIQUE (soignant_id, mission_id);
ALTER TABLE matching_scores ADD CONSTRAINT matching_scores_mission_id_fkey FOREIGN KEY (mission_id) REFERENCES missions(id) ON DELETE CASCADE;
ALTER TABLE matching_scores ADD CONSTRAINT matching_scores_soignant_id_fkey FOREIGN KEY (soignant_id) REFERENCES soignants(id) ON DELETE CASCADE;
ALTER TABLE matching_scores ADD CONSTRAINT matching_scores_score_global_check CHECK (((score_global >= 0) AND (score_global <= 100)));
ALTER TABLE membres_etablissement ADD CONSTRAINT membres_etablissement_pkey PRIMARY KEY (id);
ALTER TABLE membres_etablissement ADD CONSTRAINT membres_etablissement_etablissement_id_user_id_key UNIQUE (etablissement_id, user_id);
ALTER TABLE membres_etablissement ADD CONSTRAINT membres_etablissement_etablissement_id_fkey FOREIGN KEY (etablissement_id) REFERENCES etablissements(id) ON DELETE CASCADE;
ALTER TABLE membres_etablissement ADD CONSTRAINT membres_etablissement_invite_par_fkey FOREIGN KEY (invite_par) REFERENCES auth.users(id) ON DELETE SET NULL;
ALTER TABLE membres_etablissement ADD CONSTRAINT membres_etablissement_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;
ALTER TABLE membres_etablissement ADD CONSTRAINT membres_etablissement_role_check CHECK ((role = ANY (ARRAY['PROPRIETAIRE'::text, 'ADMIN_GROUPE'::text, 'RH'::text, 'POINTAGE_ONLY'::text, 'LECTURE_SEULE'::text])));
ALTER TABLE messages_chat ADD CONSTRAINT messages_chat_pkey PRIMARY KEY (id);
ALTER TABLE messages_chat ADD CONSTRAINT messages_chat_conversation_id_fkey FOREIGN KEY (conversation_id) REFERENCES conversations(id);
ALTER TABLE messages_contact ADD CONSTRAINT messages_contact_pkey PRIMARY KEY (id);
ALTER TABLE messages_contact ADD CONSTRAINT messages_contact_statut_check CHECK ((statut = ANY (ARRAY['NOUVEAU'::text, 'EN_COURS'::text, 'TRAITE'::text])));
ALTER TABLE messages_litige ADD CONSTRAINT messages_litige_pkey PRIMARY KEY (id);
ALTER TABLE messages_litige ADD CONSTRAINT messages_litige_litige_id_fkey FOREIGN KEY (litige_id) REFERENCES litiges(id);
ALTER TABLE messages_litige ADD CONSTRAINT messages_litige_type_auteur_check CHECK ((type_auteur = ANY (ARRAY['ETABLISSEMENT'::text, 'SOIGNANT'::text, 'ADMIN'::text])));
ALTER TABLE messages_mission ADD CONSTRAINT messages_mission_pkey PRIMARY KEY (id);
ALTER TABLE messages_mission ADD CONSTRAINT messages_mission_mission_id_fkey FOREIGN KEY (mission_id) REFERENCES missions(id);
ALTER TABLE messages_mission ADD CONSTRAINT messages_mission_type_auteur_check CHECK ((type_auteur = ANY (ARRAY['SOIGNANT'::text, 'ETABLISSEMENT'::text, 'ADMIN'::text])));
ALTER TABLE mission_creneaux ADD CONSTRAINT mission_creneaux_pkey PRIMARY KEY (id);
ALTER TABLE mission_creneaux ADD CONSTRAINT uq_mission_creneau_ordre UNIQUE (mission_id, ordre);
ALTER TABLE mission_creneaux ADD CONSTRAINT mission_creneaux_mission_id_fkey FOREIGN KEY (mission_id) REFERENCES missions(id) ON DELETE CASCADE;
ALTER TABLE mission_creneaux ADD CONSTRAINT chk_fin_previsionnel CHECK (((type_creneau = 'EFFECTIF'::text) OR (fin IS NOT NULL)));
ALTER TABLE mission_creneaux ADD CONSTRAINT chk_type_creneau CHECK ((type_creneau = ANY (ARRAY['PREVISIONNEL'::text, 'EFFECTIF'::text])));
ALTER TABLE mission_creneaux ADD CONSTRAINT ck_creneau_coherent CHECK (((fin IS NULL) OR (fin > debut)));
ALTER TABLE mission_creneaux ADD CONSTRAINT ck_creneau_max_24h CHECK ((EXTRACT(epoch FROM (fin - debut)) <= (86400)::numeric));
ALTER TABLE mission_creneaux ADD CONSTRAINT ck_type_pause_coherent CHECK ((((est_pause = false) AND (type_pause IS NULL)) OR (est_pause = true)));
ALTER TABLE mission_series ADD CONSTRAINT mission_series_pkey PRIMARY KEY (id);
ALTER TABLE mission_series ADD CONSTRAINT mission_series_etablissement_id_fkey FOREIGN KEY (etablissement_id) REFERENCES etablissements(id);
ALTER TABLE missions ADD CONSTRAINT missions_pkey PRIMARY KEY (id);
ALTER TABLE missions ADD CONSTRAINT missions_etablissement_id_fkey FOREIGN KEY (etablissement_id) REFERENCES etablissements(id);
ALTER TABLE missions ADD CONSTRAINT missions_serie_id_fkey FOREIGN KEY (serie_id) REFERENCES mission_series(id) ON DELETE SET NULL;
ALTER TABLE missions ADD CONSTRAINT missions_soignant_assigne_id_fkey FOREIGN KEY (soignant_assigne_id) REFERENCES soignants(id);
ALTER TABLE missions ADD CONSTRAINT missions_specialite_medicale_requise_fkey FOREIGN KEY (specialite_medicale_requise) REFERENCES specialites_medicales(code);
ALTER TABLE missions ADD CONSTRAINT chk_duree_positive CHECK (((duree_heures IS NULL) OR ((duree_heures >= (0)::numeric) AND (duree_heures <= (168)::numeric))));
ALTER TABLE missions ADD CONSTRAINT chk_missions_dates CHECK ((debut_le < fin_le));
ALTER TABLE missions ADD CONSTRAINT chk_prochain_type_scan CHECK ((prochain_type_scan = ANY (ARRAY['OUVERTURE'::text, 'FERMETURE'::text])));
ALTER TABLE missions ADD CONSTRAINT chk_taux_commission CHECK (((taux_commission IS NULL) OR ((taux_commission >= (0)::numeric) AND (taux_commission <= (30)::numeric))));
ALTER TABLE missions ADD CONSTRAINT chk_taux_horaire_raisonnable CHECK (((taux_horaire_base = (0)::numeric) OR ((taux_horaire_base >= 11.88) AND (taux_horaire_base <= (1000)::numeric))));
ALTER TABLE missions ADD CONSTRAINT chk_type_contrat_recherche CHECK ((type_contrat_recherche = ANY (ARRAY['TOUS'::text, 'SALARIE'::text, 'LIBERAL'::text])));
ALTER TABLE missions ADD CONSTRAINT ck_max_366_creneaux CHECK (((nb_creneaux >= 0) AND (nb_creneaux <= 366)));
ALTER TABLE missions ADD CONSTRAINT missions_mission_source_check CHECK ((mission_source = ANY (ARRAY['SWIPE'::text, 'CANDIDATURE'::text, 'REBOOK'::text, 'PROPOSITION_DIRECTE'::text, 'REMPLACEMENT'::text])));
ALTER TABLE missions ADD CONSTRAINT missions_mode_attribution_check CHECK ((mode_attribution = ANY (ARRAY['PREMIER_ARRIVE'::text, 'CANDIDATURE'::text])));
ALTER TABLE missions ADD CONSTRAINT missions_mode_paiement_soignant_check CHECK ((mode_paiement_soignant = ANY (ARRAY['DIRECT'::text, 'STRIPE_CONNECT'::text, 'VIREMENT'::text])));
ALTER TABLE missions ADD CONSTRAINT missions_mode_remuneration_check CHECK ((mode_remuneration = ANY (ARRAY['TAUX_HORAIRE'::text, 'RETROCESSION'::text])));
ALTER TABLE missions ADD CONSTRAINT missions_niveau_urgence_check CHECK (((niveau_urgence >= 0) AND (niveau_urgence <= 3)));
ALTER TABLE missions ADD CONSTRAINT missions_retrocession_pct_check CHECK (((retrocession_pct IS NULL) OR ((retrocession_pct > (0)::numeric) AND (retrocession_pct <= (100)::numeric))));
ALTER TABLE missions ADD CONSTRAINT missions_type_paiement_soignant_check CHECK ((type_paiement_soignant = ANY (ARRAY['BULLETIN_PAIE'::text, 'NOTE_HONORAIRES'::text])));
ALTER TABLE missions_sauvegardees ADD CONSTRAINT missions_sauvegardees_pkey PRIMARY KEY (id);
ALTER TABLE missions_sauvegardees ADD CONSTRAINT missions_sauvegardees_soignant_id_mission_id_key UNIQUE (soignant_id, mission_id);
ALTER TABLE missions_sauvegardees ADD CONSTRAINT missions_sauvegardees_mission_id_fkey FOREIGN KEY (mission_id) REFERENCES missions(id) ON DELETE CASCADE;
ALTER TABLE missions_sauvegardees ADD CONSTRAINT missions_sauvegardees_soignant_id_fkey FOREIGN KEY (soignant_id) REFERENCES soignants(id) ON DELETE CASCADE;
ALTER TABLE notations_missions ADD CONSTRAINT notations_missions_pkey PRIMARY KEY (id);
ALTER TABLE notations_missions ADD CONSTRAINT notations_missions_mission_id_sens_key UNIQUE (mission_id, sens);
ALTER TABLE notations_missions ADD CONSTRAINT notations_missions_mission_id_fkey FOREIGN KEY (mission_id) REFERENCES missions(id) ON DELETE CASCADE;
ALTER TABLE notations_missions ADD CONSTRAINT notations_missions_commentaire_check CHECK (((commentaire IS NULL) OR (length(commentaire) <= 2000)));
ALTER TABLE notations_missions ADD CONSTRAINT notations_missions_critere_1_check CHECK (((critere_1 >= 1) AND (critere_1 <= 5)));
ALTER TABLE notations_missions ADD CONSTRAINT notations_missions_critere_2_check CHECK (((critere_2 >= 1) AND (critere_2 <= 5)));
ALTER TABLE notations_missions ADD CONSTRAINT notations_missions_critere_3_check CHECK (((critere_3 >= 1) AND (critere_3 <= 5)));
ALTER TABLE notations_missions ADD CONSTRAINT notations_missions_critere_4_check CHECK (((critere_4 >= 1) AND (critere_4 <= 5)));
ALTER TABLE notifications ADD CONSTRAINT notifications_pkey PRIMARY KEY (id);
ALTER TABLE notifications ADD CONSTRAINT notifications_type_check CHECK ((type = ANY (ARRAY['CANDIDATURE_ACCEPTEE'::text, 'CANDIDATURE_REFUSEE'::text, 'CANDIDATURE_PROPOSEE'::text, 'CANDIDATURE_RECUE'::text, 'MISSION_ACCEPTEE'::text, 'MISSION_ANNULEE'::text, 'MISSION_TERMINEE'::text, 'MISSION_URGENTE'::text, 'MISSION_NON_POURVUE'::text, 'MISSION_ASSIGNEE'::text, 'MISSION_A_POURVOIR'::text, 'CONTRAT_A_SIGNER'::text, 'CONTRAT_SIGNE'::text, 'FACTURE_EMISE'::text, 'FACTURE_PAYEE'::text, 'DOCUMENT_EXPIRANT'::text, 'RAPPEL_DOCUMENTS'::text, 'DOCUMENT_VERIFIE'::text, 'DOCUMENT_REJETE'::text, 'MESSAGE_RECU'::text, 'MESSAGE_ADMIN'::text, 'POINTAGE_ARRIVEE'::text, 'POINTAGE_DEPART'::text, 'EVALUATION_RECUE'::text, 'PARRAINAGE'::text, 'CREDIT_PARRAINAGE'::text, 'PARRAINAGE_PRIME_VERSEE'::text, 'RAPPEL_MISSION'::text, 'RAPPEL_CANDIDATURES'::text, 'POOL_URGENCE'::text, 'POOL_URGENCE_ACCEPTATION'::text, 'SYSTEM'::text, 'LITIGE_OUVERT'::text, 'LITIGE_REPONSE'::text, 'LITIGE_RESOLU'::text, 'LITIGE_MEDIATION'::text, 'LITIGE_RESOLU_AJUSTE'::text, 'LITIGE_ESCALADE_ADMIN'::text, 'LITIGE_MEDIATION_PRIORITAIRE'::text, 'LITIGE_RAPPEL_J1'::text, 'LITIGE_RAPPEL_J3'::text, 'LITIGE_RAPPEL_J5'::text, 'CHORUS_DEPOSEE'::text, 'CHORUS_MISE_A_DISPOSITION'::text, 'CHORUS_PAIEMENT_EN_COURS'::text, 'CHORUS_PAIEMENT_COMPTABILISE'::text, 'CHORUS_REJETEE'::text, 'FAVORI_NOUVELLE_MISSION'::text, 'AVOIR_EMIS'::text, 'COMMISSION_AJUSTEE'::text, 'REMBOURSEMENT_MANUEL_A_FAIRE'::text, 'REMBOURSEMENT_CONFIRME'::text, 'MATCHING_SUPER_LIKE'::text, 'FAVORI_MISSION_EXPIRE'::text])));
ALTER TABLE notifications ADD CONSTRAINT notifications_type_destinataire_check CHECK ((type_destinataire = ANY (ARRAY['SOIGNANT'::text, 'ETABLISSEMENT'::text, 'ADMIN'::text])));
ALTER TABLE notifications_notation_j1 ADD CONSTRAINT notifications_notation_j1_pkey PRIMARY KEY (id);
ALTER TABLE notifications_notation_j1 ADD CONSTRAINT notifications_notation_j1_mission_id_sens_key UNIQUE (mission_id, sens);
ALTER TABLE notifications_notation_j1 ADD CONSTRAINT notifications_notation_j1_mission_id_fkey FOREIGN KEY (mission_id) REFERENCES missions(id) ON DELETE CASCADE;
ALTER TABLE otps_telephone ADD CONSTRAINT otps_telephone_pkey PRIMARY KEY (id);
ALTER TABLE otps_telephone ADD CONSTRAINT otps_telephone_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;
ALTER TABLE paiements_mission ADD CONSTRAINT paiements_mission_pkey PRIMARY KEY (id);
ALTER TABLE paiements_mission ADD CONSTRAINT uq_paiements_mission_mission_id UNIQUE (mission_id);
ALTER TABLE paiements_mission ADD CONSTRAINT paiements_mission_etablissement_id_fkey FOREIGN KEY (etablissement_id) REFERENCES etablissements(id);
ALTER TABLE paiements_mission ADD CONSTRAINT paiements_mission_mission_id_fkey FOREIGN KEY (mission_id) REFERENCES missions(id);
ALTER TABLE paiements_mission ADD CONSTRAINT paiements_mission_statut_check CHECK ((statut = ANY (ARRAY['EN_ATTENTE'::text, 'AUTORISE'::text, 'CAPTURE'::text, 'ECHOUE'::text, 'REMBOURSE'::text])));
ALTER TABLE paiements_soignant ADD CONSTRAINT paiements_soignant_pkey PRIMARY KEY (id);
ALTER TABLE paiements_soignant ADD CONSTRAINT paiements_soignant_etablissement_id_fkey FOREIGN KEY (etablissement_id) REFERENCES etablissements(id);
ALTER TABLE paiements_soignant ADD CONSTRAINT paiements_soignant_mission_id_fkey FOREIGN KEY (mission_id) REFERENCES missions(id);
ALTER TABLE paiements_soignant ADD CONSTRAINT paiements_soignant_soignant_id_fkey FOREIGN KEY (soignant_id) REFERENCES soignants(id);
ALTER TABLE paiements_soignant ADD CONSTRAINT paiements_soignant_methode_check CHECK ((methode = ANY (ARRAY['VIREMENT'::text, 'STRIPE_CONNECT'::text, 'CHEQUE'::text, 'NOTE_HONORAIRES'::text, 'BULLETIN_PAIE'::text])));
ALTER TABLE paiements_soignant ADD CONSTRAINT paiements_soignant_statut_check CHECK ((statut = ANY (ARRAY['EN_ATTENTE'::text, 'DECLARE'::text, 'CONFIRME'::text, 'CONTESTE'::text, 'RESOLU'::text])));
ALTER TABLE paliers_bfa ADD CONSTRAINT paliers_bfa_pkey PRIMARY KEY (id);
ALTER TABLE paliers_commission ADD CONSTRAINT paliers_commission_pkey PRIMARY KEY (id);
ALTER TABLE parametres_litiges ADD CONSTRAINT parametres_litiges_pkey PRIMARY KEY (cle);
ALTER TABLE parametres_systeme ADD CONSTRAINT parametres_systeme_pkey PRIMARY KEY (cle);
ALTER TABLE parcours_liberal_soignants ADD CONSTRAINT parcours_liberal_soignants_pkey PRIMARY KEY (id);
ALTER TABLE parcours_liberal_soignants ADD CONSTRAINT parcours_liberal_soignants_soignant_id_key UNIQUE (soignant_id);
ALTER TABLE parcours_liberal_soignants ADD CONSTRAINT parcours_liberal_soignants_soignant_id_fkey FOREIGN KEY (soignant_id) REFERENCES soignants(id) ON DELETE CASCADE;
ALTER TABLE parcours_liberal_soignants ADD CONSTRAINT parcours_liberal_soignants_parcours_kine_check CHECK (((parcours_kine IS NULL) OR (parcours_kine = ANY (ARRAY['HEURES_2240'::text, 'ZONE_SOUS_DOTEE'::text]))));
ALTER TABLE parrainage_fraude_signals ADD CONSTRAINT parrainage_fraude_signals_pkey PRIMARY KEY (id);
ALTER TABLE parrainage_fraude_signals ADD CONSTRAINT parrainage_fraude_signals_parrainage_id_fkey FOREIGN KEY (parrainage_id) REFERENCES parrainages(id) ON DELETE CASCADE;
ALTER TABLE parrainage_fraude_signals ADD CONSTRAINT parrainage_fraude_signals_type_check CHECK ((type = ANY (ARRAY['MEME_IP'::text, 'MEME_DEVICE'::text, 'PATTERN_SUSPECT'::text, 'ADMIN_FLAG'::text])));
ALTER TABLE parrainages ADD CONSTRAINT parrainages_pkey PRIMARY KEY (id);
ALTER TABLE parrainages ADD CONSTRAINT parrainages_parrain_id_filleul_id_key UNIQUE (parrain_id, filleul_id);
ALTER TABLE parrainages ADD CONSTRAINT parrainages_statut_check CHECK ((statut = ANY (ARRAY['EN_ATTENTE'::text, 'FILLEUL_ACTIF'::text, 'VALIDE_EN_ATTENTE_SEUIL'::text, 'PRIME_VERSEE'::text, 'FRAUDE'::text, 'VALIDE'::text, 'EXPIRED'::text, 'ANNULE'::text])));
ALTER TABLE parrainages_etablissements ADD CONSTRAINT parrainages_etablissements_pkey PRIMARY KEY (id);
ALTER TABLE parrainages_etablissements ADD CONSTRAINT parrainages_etablissements_filleul_etab_id_key UNIQUE (filleul_etab_id);
ALTER TABLE parrainages_etablissements ADD CONSTRAINT parrainages_etablissements_filleul_etab_id_fkey FOREIGN KEY (filleul_etab_id) REFERENCES etablissements(id) ON DELETE CASCADE;
ALTER TABLE parrainages_etablissements ADD CONSTRAINT parrainages_etablissements_parrain_etab_id_fkey FOREIGN KEY (parrain_etab_id) REFERENCES etablissements(id) ON DELETE CASCADE;
ALTER TABLE parrainages_etablissements ADD CONSTRAINT parrainages_etablissements_check CHECK ((parrain_etab_id <> filleul_etab_id));
ALTER TABLE partages_rib ADD CONSTRAINT partages_rib_pkey PRIMARY KEY (id);
ALTER TABLE partages_rib ADD CONSTRAINT partages_rib_contrat_id_fkey FOREIGN KEY (contrat_id) REFERENCES contrats_mission(id);
ALTER TABLE partages_rib ADD CONSTRAINT partages_rib_document_rib_id_fkey FOREIGN KEY (document_rib_id) REFERENCES documents_soignants(id);
ALTER TABLE partages_rib ADD CONSTRAINT partages_rib_etablissement_id_fkey FOREIGN KEY (etablissement_id) REFERENCES etablissements(id);
ALTER TABLE partages_rib ADD CONSTRAINT partages_rib_mission_id_fkey FOREIGN KEY (mission_id) REFERENCES missions(id);
ALTER TABLE partages_rib ADD CONSTRAINT partages_rib_soignant_id_fkey FOREIGN KEY (soignant_id) REFERENCES soignants(id);
ALTER TABLE pauses_presence ADD CONSTRAINT pauses_presence_pkey PRIMARY KEY (id);
ALTER TABLE pauses_presence ADD CONSTRAINT pauses_presence_presence_id_fkey FOREIGN KEY (presence_id) REFERENCES presences(id) ON DELETE CASCADE;
ALTER TABLE pauses_presence ADD CONSTRAINT pauses_presence_soignant_id_fkey FOREIGN KEY (soignant_id) REFERENCES soignants(id);
ALTER TABLE pauses_presence ADD CONSTRAINT pauses_presence_motif_check CHECK ((motif = ANY (ARRAY['DEJEUNER'::text, 'REPOS'::text, 'PERSONNEL'::text, 'AUTRE'::text])));
ALTER TABLE pings_gps_mission ADD CONSTRAINT pings_gps_mission_pkey PRIMARY KEY (id);
ALTER TABLE pings_gps_mission ADD CONSTRAINT pings_gps_mission_mission_id_fkey FOREIGN KEY (mission_id) REFERENCES missions(id) ON DELETE CASCADE;
ALTER TABLE pings_gps_mission ADD CONSTRAINT pings_gps_mission_soignant_id_fkey FOREIGN KEY (soignant_id) REFERENCES auth.users(id) ON DELETE CASCADE;
ALTER TABLE pings_gps_mission ADD CONSTRAINT pings_gps_mission_source_check CHECK ((source = ANY (ARRAY['BACKGROUND'::text, 'FOREGROUND'::text, 'POINTAGE_QR'::text, 'POINTAGE_CODE'::text])));
ALTER TABLE plans_prevoyance ADD CONSTRAINT plans_prevoyance_pkey PRIMARY KEY (id);
ALTER TABLE plans_prevoyance ADD CONSTRAINT plans_prevoyance_type_check CHECK ((type = ANY (ARRAY['PREVOYANCE_SANTE'::text, 'PREVOYANCE_INCAPACITE'::text, 'RCP_LIBERAL'::text, 'RETRAITE_COMPLEMENTAIRE'::text])));
ALTER TABLE preferences_notifications ADD CONSTRAINT preferences_notifications_pkey PRIMARY KEY (utilisateur_id);
ALTER TABLE preferences_notifications ADD CONSTRAINT preferences_notifications_utilisateur_id_fkey FOREIGN KEY (utilisateur_id) REFERENCES auth.users(id) ON DELETE CASCADE;
ALTER TABLE preferences_notifications_par_evenement ADD CONSTRAINT preferences_notifications_par_evenement_pkey PRIMARY KEY (id);
ALTER TABLE preferences_notifications_par_evenement ADD CONSTRAINT preferences_notifications_par_utilisateur_id_type_evenement_key UNIQUE (utilisateur_id, type_evenement, canal);
ALTER TABLE preferences_notifications_par_evenement ADD CONSTRAINT preferences_notifications_par_evenement_utilisateur_id_fkey FOREIGN KEY (utilisateur_id) REFERENCES auth.users(id) ON DELETE CASCADE;
ALTER TABLE presence_status ADD CONSTRAINT presence_status_pkey PRIMARY KEY (user_id);
ALTER TABLE presence_status ADD CONSTRAINT presence_status_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;
ALTER TABLE presences ADD CONSTRAINT presences_pkey PRIMARY KEY (id);
ALTER TABLE presences ADD CONSTRAINT presences_mission_id_soignant_id_key UNIQUE (mission_id, soignant_id);
ALTER TABLE presences ADD CONSTRAINT presences_ajustement_litige_id_fkey FOREIGN KEY (ajustement_litige_id) REFERENCES litiges(id) ON DELETE SET NULL;
ALTER TABLE presences ADD CONSTRAINT presences_mission_id_fkey FOREIGN KEY (mission_id) REFERENCES missions(id);
ALTER TABLE presences ADD CONSTRAINT presences_soignant_id_fkey FOREIGN KEY (soignant_id) REFERENCES soignants(id);
ALTER TABLE presences ADD CONSTRAINT chk_methode_arrivee CHECK (((methode_pointage_arrivee IS NULL) OR (methode_pointage_arrivee = ANY (ARRAY['GPS'::text, 'CODE'::text, 'QR'::text, 'MANUEL'::text, 'ADMIN'::text]))));
ALTER TABLE presences ADD CONSTRAINT chk_methode_depart CHECK (((methode_pointage_depart IS NULL) OR (methode_pointage_depart = ANY (ARRAY['GPS'::text, 'CODE'::text, 'QR'::text, 'MANUEL'::text, 'ADMIN'::text]))));
ALTER TABLE presences ADD CONSTRAINT presences_methode_pointage_arrivee_check CHECK ((methode_pointage_arrivee = ANY (ARRAY['GPS'::text, 'CODE'::text, 'QR'::text])));
ALTER TABLE presences ADD CONSTRAINT presences_methode_pointage_depart_check CHECK ((methode_pointage_depart = ANY (ARRAY['GPS'::text, 'CODE'::text, 'QR'::text])));
ALTER TABLE prevoyance_liste_attente ADD CONSTRAINT prevoyance_liste_attente_pkey PRIMARY KEY (id);
ALTER TABLE prevoyance_liste_attente ADD CONSTRAINT prevoyance_liste_attente_email_key UNIQUE (email);
ALTER TABLE prevoyance_liste_attente ADD CONSTRAINT prevoyance_liste_attente_soignant_id_fkey FOREIGN KEY (soignant_id) REFERENCES soignants(id) ON DELETE CASCADE;
ALTER TABLE professions_liberal_eligible ADD CONSTRAINT professions_liberal_eligible_pkey PRIMARY KEY (profession);
ALTER TABLE prospects_etablissements ADD CONSTRAINT prospects_etablissements_pkey PRIMARY KEY (finess);
ALTER TABLE prospects_soignants ADD CONSTRAINT prospects_soignants_pkey PRIMARY KEY (cle);
ALTER TABLE psc_auth_sessions ADD CONSTRAINT psc_auth_sessions_pkey PRIMARY KEY (state);
ALTER TABLE qr_codes_mission ADD CONSTRAINT qr_codes_mission_pkey PRIMARY KEY (id);
ALTER TABLE qr_codes_mission ADD CONSTRAINT qr_codes_mission_token_key UNIQUE (token);
ALTER TABLE qr_codes_mission ADD CONSTRAINT qr_codes_mission_mission_id_fkey FOREIGN KEY (mission_id) REFERENCES missions(id) ON DELETE CASCADE;
ALTER TABLE qr_codes_mission ADD CONSTRAINT qr_codes_mission_type_check CHECK ((type = ANY (ARRAY['ARRIVEE'::text, 'DEPART'::text, 'UNIVERSEL'::text])));
ALTER TABLE rappels_contrat_travail ADD CONSTRAINT rappels_contrat_travail_pkey PRIMARY KEY (id);
ALTER TABLE rappels_contrat_travail ADD CONSTRAINT rappels_contrat_travail_mission_id_fkey FOREIGN KEY (mission_id) REFERENCES missions(id);
ALTER TABLE rate_limits ADD CONSTRAINT rate_limits_pkey PRIMARY KEY (id);
ALTER TABLE reclamations ADD CONSTRAINT reclamations_pkey PRIMARY KEY (id);
ALTER TABLE reclamations ADD CONSTRAINT reclamations_mission_id_fkey FOREIGN KEY (mission_id) REFERENCES missions(id);
ALTER TABLE reclamations ADD CONSTRAINT reclamations_traite_par_fkey FOREIGN KEY (traite_par) REFERENCES auth.users(id);
ALTER TABLE reclamations ADD CONSTRAINT reclamations_utilisateur_id_fkey FOREIGN KEY (utilisateur_id) REFERENCES auth.users(id);
ALTER TABLE reclamations ADD CONSTRAINT reclamations_categorie_check CHECK ((categorie = ANY (ARRAY['MISSION'::text, 'PAIEMENT'::text, 'TECHNIQUE'::text, 'COMPORTEMENT'::text, 'AUTRE'::text])));
ALTER TABLE reclamations ADD CONSTRAINT reclamations_priorite_check CHECK ((priorite = ANY (ARRAY['BASSE'::text, 'NORMALE'::text, 'HAUTE'::text])));
ALTER TABLE reclamations ADD CONSTRAINT reclamations_statut_check CHECK ((statut = ANY (ARRAY['EN_ATTENTE'::text, 'EN_COURS'::text, 'RESOLUE'::text, 'FERMEE'::text])));
ALTER TABLE reclamations ADD CONSTRAINT reclamations_type_utilisateur_check CHECK ((type_utilisateur = ANY (ARRAY['SOIGNANT'::text, 'ETABLISSEMENT'::text])));
ALTER TABLE reclamations_score ADD CONSTRAINT reclamations_score_pkey PRIMARY KEY (id);
ALTER TABLE reclamations_score ADD CONSTRAINT reclamations_score_evenement_etab_id_fkey FOREIGN KEY (evenement_etab_id) REFERENCES evenements_score_etab(id) ON DELETE CASCADE;
ALTER TABLE reclamations_score ADD CONSTRAINT reclamations_score_evenement_soignant_id_fkey FOREIGN KEY (evenement_soignant_id) REFERENCES evenements_score_soignant(id) ON DELETE CASCADE;
ALTER TABLE reclamations_score ADD CONSTRAINT chk_evt_xor CHECK ((((evenement_type = 'SOIGNANT'::text) AND (evenement_soignant_id IS NOT NULL) AND (evenement_etab_id IS NULL)) OR ((evenement_type = 'ETAB'::text) AND (evenement_etab_id IS NOT NULL) AND (evenement_soignant_id IS NULL))));
ALTER TABLE reclamations_score ADD CONSTRAINT reclamations_score_decision_admin_check CHECK (((decision_admin IS NULL) OR (decision_admin = ANY (ARRAY['MAINTENIR'::text, 'REDUIRE'::text, 'ANNULER'::text]))));
ALTER TABLE reclamations_score ADD CONSTRAINT reclamations_score_evenement_type_check CHECK ((evenement_type = ANY (ARRAY['SOIGNANT'::text, 'ETAB'::text])));
ALTER TABLE reclamations_score ADD CONSTRAINT reclamations_score_motif_categorie_check CHECK ((motif_categorie = ANY (ARRAY['URGENCE_MEDICALE'::text, 'DEUIL'::text, 'FORCE_MAJEURE'::text, 'ERREUR_JOLENE'::text, 'CONTEXTE_PARTICULIER'::text, 'AUTRE'::text])));
ALTER TABLE reclamations_score ADD CONSTRAINT reclamations_score_statut_check CHECK ((statut = ANY (ARRAY['PENDING'::text, 'TREATED'::text, 'CANCELLED'::text])));
ALTER TABLE reclamations_scoring ADD CONSTRAINT reclamations_scoring_pkey PRIMARY KEY (id);
ALTER TABLE reclamations_scoring ADD CONSTRAINT reclamations_scoring_mission_id_fkey FOREIGN KEY (mission_id) REFERENCES missions(id);
ALTER TABLE reclamations_scoring ADD CONSTRAINT reclamations_scoring_soignant_id_fkey FOREIGN KEY (soignant_id) REFERENCES soignants(id);
ALTER TABLE reclamations_scoring ADD CONSTRAINT reclamations_scoring_motif_check CHECK ((motif = ANY (ARRAY['ARRET_MALADIE'::text, 'ACCIDENT'::text, 'URGENCE_FAMILIALE'::text, 'ERREUR_ETABLISSEMENT'::text, 'AUTRE'::text])));
ALTER TABLE reclamations_scoring ADD CONSTRAINT reclamations_scoring_statut_check CHECK ((statut = ANY (ARRAY['EN_ATTENTE'::text, 'ACCEPTEE'::text, 'REFUSEE'::text])));
ALTER TABLE regles_exercice_profession ADD CONSTRAINT regles_exercice_profession_pkey PRIMARY KEY (profession);
ALTER TABLE relances_soignants ADD CONSTRAINT relances_soignants_pkey PRIMARY KEY (id);
ALTER TABLE rist_plafonds ADD CONSTRAINT rist_plafonds_pkey PRIMARY KEY (id);
ALTER TABLE rist_plafonds ADD CONSTRAINT rist_plafonds_profession_type_contrat_en_vigueur_depuis_key UNIQUE (profession, type_contrat, en_vigueur_depuis);
ALTER TABLE rpps_test ADD CONSTRAINT rpps_test_pkey PRIMARY KEY (rpps);
ALTER TABLE sales_annuaires ADD CONSTRAINT sales_annuaires_pkey PRIMARY KEY (id);
ALTER TABLE sales_annuaires ADD CONSTRAINT sales_annuaires_autorite_check CHECK ((autorite = ANY (ARRAY['ELEVEE'::text, 'MOYENNE'::text, 'FAIBLE'::text])));
ALTER TABLE sales_annuaires ADD CONSTRAINT sales_annuaires_statut_check CHECK ((statut = ANY (ARRAY['A_SOUMETTRE'::text, 'SOUMIS'::text, 'PUBLIE'::text, 'REFUSE'::text])));
ALTER TABLE sales_contacts ADD CONSTRAINT sales_contacts_pkey PRIMARY KEY (id);
ALTER TABLE sales_contacts ADD CONSTRAINT sales_contacts_groupe_id_fkey FOREIGN KEY (groupe_id) REFERENCES sales_groupes(id) ON DELETE SET NULL;
ALTER TABLE sales_contacts ADD CONSTRAINT sales_contacts_reponse_check CHECK (((reponse IS NULL) OR (reponse = ANY (ARRAY['EN_ATTENTE'::text, 'POSITIVE'::text, 'NEGATIVE'::text]))));
ALTER TABLE sales_contacts ADD CONSTRAINT sales_contacts_statut_check CHECK ((statut = ANY (ARRAY['PROSPECT'::text, 'CONTACTE'::text, 'RELANCE'::text, 'INSCRIT'::text, 'PERDU'::text])));
ALTER TABLE sales_contacts ADD CONSTRAINT sales_contacts_type_check CHECK ((type = ANY (ARRAY['SOIGNANT'::text, 'ETABLISSEMENT'::text])));
ALTER TABLE sales_groupes ADD CONSTRAINT sales_groupes_pkey PRIMARY KEY (id);
ALTER TABLE sales_groupes ADD CONSTRAINT sales_groupes_audience_check CHECK ((audience = ANY (ARRAY['SOIGNANTS'::text, 'ETABLISSEMENTS'::text, 'MIXTE'::text])));
ALTER TABLE sales_groupes ADD CONSTRAINT sales_groupes_plateforme_check CHECK ((plateforme = ANY (ARRAY['WHATSAPP'::text, 'FACEBOOK'::text, 'LINKEDIN'::text, 'TELEGRAM'::text, 'JOBBOARD'::text, 'AUTRE'::text, 'INSTAGRAM'::text, 'TIKTOK'::text, 'SNAPCHAT'::text])));
ALTER TABLE sales_groupes ADD CONSTRAINT sales_groupes_statut_check CHECK ((statut = ANY (ARRAY['ACTIF'::text, 'A_VERIFIER'::text, 'INACTIF'::text])));
ALTER TABLE sales_templates ADD CONSTRAINT sales_templates_pkey PRIMARY KEY (id);
ALTER TABLE sales_templates ADD CONSTRAINT sales_templates_cible_check CHECK ((cible = ANY (ARRAY['GROUPE'::text, 'SOIGNANT'::text, 'ETABLISSEMENT'::text])));
ALTER TABLE scans_pointage ADD CONSTRAINT scans_pointage_pkey PRIMARY KEY (id);
ALTER TABLE scans_pointage ADD CONSTRAINT scans_pointage_creneau_effectif_id_fkey FOREIGN KEY (creneau_effectif_id) REFERENCES mission_creneaux(id) ON DELETE CASCADE;
ALTER TABLE scans_pointage ADD CONSTRAINT scans_pointage_mission_id_fkey FOREIGN KEY (mission_id) REFERENCES missions(id);
ALTER TABLE scans_pointage ADD CONSTRAINT scans_pointage_soignant_id_fkey FOREIGN KEY (soignant_id) REFERENCES auth.users(id);
ALTER TABLE scans_pointage ADD CONSTRAINT scans_pointage_valide_par_fkey FOREIGN KEY (valide_par) REFERENCES auth.users(id);
ALTER TABLE scans_pointage ADD CONSTRAINT scans_pointage_type_scan_check CHECK ((type_scan = ANY (ARRAY['OUVERTURE'::text, 'FERMETURE'::text])));
ALTER TABLE scoring_breakdown ADD CONSTRAINT scoring_breakdown_pkey PRIMARY KEY (id);
ALTER TABLE scoring_breakdown ADD CONSTRAINT scoring_breakdown_soignant_id_fkey FOREIGN KEY (soignant_id) REFERENCES soignants(id) ON DELETE CASCADE;
ALTER TABLE serie_email_envois ADD CONSTRAINT serie_email_envois_pkey PRIMARY KEY (id);
ALTER TABLE serie_email_envois ADD CONSTRAINT serie_email_envois_utilisateur_id_serie_etape_key UNIQUE (utilisateur_id, serie, etape);
ALTER TABLE serie_email_envois ADD CONSTRAINT serie_email_envois_utilisateur_id_fkey FOREIGN KEY (utilisateur_id) REFERENCES auth.users(id) ON DELETE CASCADE;
ALTER TABLE shift_affectations ADD CONSTRAINT shift_affectations_pkey PRIMARY KEY (id);
ALTER TABLE shift_affectations ADD CONSTRAINT shift_affectations_mission_id_fkey FOREIGN KEY (mission_id) REFERENCES missions(id);
ALTER TABLE shift_affectations ADD CONSTRAINT shift_affectations_shift_id_fkey FOREIGN KEY (shift_id) REFERENCES shifts(id) ON DELETE CASCADE;
ALTER TABLE shifts ADD CONSTRAINT shifts_pkey PRIMARY KEY (id);
ALTER TABLE shifts ADD CONSTRAINT shifts_equipe_id_fkey FOREIGN KEY (equipe_id) REFERENCES equipes(id);
ALTER TABLE shifts ADD CONSTRAINT shifts_etablissement_id_fkey FOREIGN KEY (etablissement_id) REFERENCES etablissements(id);
ALTER TABLE signalements ADD CONSTRAINT signalements_pkey PRIMARY KEY (id);
ALTER TABLE signalements ADD CONSTRAINT signalements_categorie_check CHECK ((categorie = ANY (ARRAY['COMPORTEMENT_INAPPROPRIE'::text, 'FRAUDE_SUSPECTEE'::text, 'FAUX_DOCUMENT'::text, 'NON_PROFESSIONNALISME'::text, 'SECURITE_DANGER'::text, 'USURPATION_IDENTITE'::text, 'AUTRE'::text])));
ALTER TABLE signalements ADD CONSTRAINT signalements_cible_type_check CHECK ((cible_type = ANY (ARRAY['SOIGNANT'::text, 'ETABLISSEMENT'::text])));
ALTER TABLE signalements ADD CONSTRAINT signalements_signaleur_type_check CHECK ((signaleur_type = ANY (ARRAY['SOIGNANT'::text, 'ETABLISSEMENT'::text])));
ALTER TABLE signalements ADD CONSTRAINT signalements_statut_check CHECK ((statut = ANY (ARRAY['OUVERT'::text, 'EN_COURS'::text, 'TRAITE'::text, 'REJETE'::text])));
ALTER TABLE signature_rate_limit_ip ADD CONSTRAINT signature_rate_limit_ip_pkey PRIMARY KEY (ip_signature, fenetre_debut);
ALTER TABLE signatures_contrats ADD CONSTRAINT signatures_contrats_pkey PRIMARY KEY (id);
ALTER TABLE signatures_contrats ADD CONSTRAINT signatures_contrats_contrat_id_signataire_role_key UNIQUE (contrat_id, signataire_role);
ALTER TABLE signatures_contrats ADD CONSTRAINT signatures_contrats_contrat_id_fkey FOREIGN KEY (contrat_id) REFERENCES contrats_mission(id) ON DELETE CASCADE;
ALTER TABLE signatures_contrats ADD CONSTRAINT signatures_contrats_signataire_role_check CHECK ((signataire_role = ANY (ARRAY['etablissement'::text, 'soignant'::text])));
ALTER TABLE signatures_contrats ADD CONSTRAINT signatures_contrats_statut_signature_check CHECK ((statut_signature = ANY (ARRAY['en_attente'::text, 'otp_envoye'::text, 'signe'::text, 'refuse'::text, 'expire'::text])));
ALTER TABLE sms_envoyes ADD CONSTRAINT sms_envoyes_pkey PRIMARY KEY (id);
ALTER TABLE soignants ADD CONSTRAINT soignants_pkey PRIMARY KEY (id);
ALTER TABLE soignants ADD CONSTRAINT soignants_code_parrainage_key UNIQUE (code_parrainage);
ALTER TABLE soignants ADD CONSTRAINT soignants_email_key UNIQUE (email);
ALTER TABLE soignants ADD CONSTRAINT soignants_numero_adeli_key UNIQUE (numero_adeli);
ALTER TABLE soignants ADD CONSTRAINT soignants_numero_rpps_key UNIQUE (numero_rpps);
ALTER TABLE soignants ADD CONSTRAINT soignants_psc_sub_key UNIQUE (psc_sub);
ALTER TABLE soignants ADD CONSTRAINT fk_soignants_score_breakdown FOREIGN KEY (score_breakdown_id) REFERENCES scoring_breakdown(id) ON DELETE SET NULL;
ALTER TABLE soignants ADD CONSTRAINT soignants_specialite_medicale_fkey FOREIGN KEY (specialite_medicale) REFERENCES specialites_medicales(code);
ALTER TABLE soignants ADD CONSTRAINT chk_rayon_raisonnable CHECK (((rayon_deplacement_km >= 1) AND (rayon_deplacement_km <= 200)));
ALTER TABLE soignants ADD CONSTRAINT chk_telephone_format CHECK (((telephone IS NULL) OR ((telephone)::text ~ '^\+?[0-9\s\-\.]{8,20}$'::text)));
ALTER TABLE soignants ADD CONSTRAINT soignants_coherence_identite_check CHECK ((coherence_identite = ANY (ARRAY['NON_VERIFIE'::text, 'COHERENT'::text, 'INCOHERENT'::text, 'EN_ATTENTE_REVUE'::text])));
ALTER TABLE soignants ADD CONSTRAINT soignants_numero_securite_sociale_format CHECK (((numero_securite_sociale IS NULL) OR (numero_securite_sociale ~ '^[0-9]{13,15}$'::text)));
ALTER TABLE soignants ADD CONSTRAINT soignants_preference_contrat_mixte_check CHECK ((preference_contrat_mixte = ANY (ARRAY['SALARIE'::text, 'LIBERAL'::text])));
ALTER TABLE soignants ADD CONSTRAINT soignants_regime_fiscal_check CHECK ((regime_fiscal = ANY (ARRAY['MICRO_BNC'::text, 'DECLARATION_CONTROLEE'::text])));
ALTER TABLE soignants ADD CONSTRAINT soignants_score_fiabilite_check CHECK (((score_fiabilite >= (0)::numeric) AND (score_fiabilite <= (100)::numeric)));
ALTER TABLE soignants ADD CONSTRAINT soignants_sexe_check CHECK (((sexe IS NULL) OR (sexe = ANY (ARRAY['M'::text, 'F'::text]))));
ALTER TABLE soignants ADD CONSTRAINT soignants_specialite_source_check CHECK (((specialite_source IS NULL) OR (specialite_source = ANY (ARRAY['RPPS'::text, 'MANUEL'::text]))));
ALTER TABLE soignants ADD CONSTRAINT soignants_statut_liberal_check CHECK ((statut_liberal = ANY (ARRAY['NON_LIBERAL'::text, 'EN_COURS'::text, 'ACTIF'::text])));
ALTER TABLE soignants ADD CONSTRAINT soignants_type_exercice_check CHECK ((type_exercice = ANY (ARRAY['SALARIE'::text, 'LIBERAL'::text, 'MIXTE'::text])));
ALTER TABLE soignants ADD CONSTRAINT soignants_validation_3200h_statut_check CHECK ((validation_3200h_statut = ANY (ARRAY['NON_DEMANDE'::text, 'EN_ATTENTE'::text, 'VALIDEE'::text, 'REFUSEE'::text])));
ALTER TABLE souscriptions_prevoyance ADD CONSTRAINT souscriptions_prevoyance_pkey PRIMARY KEY (id);
ALTER TABLE souscriptions_prevoyance ADD CONSTRAINT souscriptions_prevoyance_soignant_id_plan_id_key UNIQUE (soignant_id, plan_id);
ALTER TABLE souscriptions_prevoyance ADD CONSTRAINT souscriptions_prevoyance_plan_id_fkey FOREIGN KEY (plan_id) REFERENCES plans_prevoyance(id);
ALTER TABLE souscriptions_prevoyance ADD CONSTRAINT souscriptions_prevoyance_soignant_id_fkey FOREIGN KEY (soignant_id) REFERENCES soignants(id);
ALTER TABLE souscriptions_prevoyance ADD CONSTRAINT souscriptions_prevoyance_statut_check CHECK ((statut = ANY (ARRAY['EN_ATTENTE'::text, 'ACTIF'::text, 'SUSPENDU'::text, 'RESILIE'::text, 'DIPLOME'::text])));
ALTER TABLE specialites_medicales ADD CONSTRAINT specialites_medicales_pkey PRIMARY KEY (code);
ALTER TABLE statut_services_api ADD CONSTRAINT statut_services_api_pkey PRIMARY KEY (id);
ALTER TABLE statut_services_api ADD CONSTRAINT statut_services_api_nom_service_key UNIQUE (nom_service);
ALTER TABLE statut_services_api ADD CONSTRAINT statut_services_api_etat_disjoncteur_check CHECK ((etat_disjoncteur = ANY (ARRAY['FERME'::text, 'OUVERT'::text, 'SEMI_OUVERT'::text])));
ALTER TABLE statut_services_api ADD CONSTRAINT statut_services_api_nom_service_check CHECK ((nom_service = ANY (ARRAY['ARIA_VERIFICATION'::text, 'YOUSIGN'::text, 'STRIPE'::text, 'SENDINBLUE'::text, 'S3_DOCUMENTS'::text, 'INSEE_SIRET'::text, 'RPPS_ANNUAIRE'::text])));
ALTER TABLE statut_services_api ADD CONSTRAINT statut_services_api_statut_check CHECK ((statut = ANY (ARRAY['OPERATIONNEL'::text, 'DEGRADE'::text, 'HORS_SERVICE'::text, 'MAINTENANCE'::text])));
ALTER TABLE streaks_soignant ADD CONSTRAINT streaks_soignant_pkey PRIMARY KEY (soignant_id);
ALTER TABLE streaks_soignant ADD CONSTRAINT streaks_soignant_soignant_id_fkey FOREIGN KEY (soignant_id) REFERENCES soignants(id) ON DELETE CASCADE;
ALTER TABLE streaks_soignant ADD CONSTRAINT streaks_soignant_max_streak_check CHECK ((max_streak >= 0));
ALTER TABLE streaks_soignant ADD CONSTRAINT streaks_soignant_streak_count_check CHECK ((streak_count >= 0));
ALTER TABLE stripe_connect_onboarding ADD CONSTRAINT stripe_connect_onboarding_pkey PRIMARY KEY (id);
ALTER TABLE stripe_connect_onboarding ADD CONSTRAINT stripe_connect_onboarding_soignant_id_key UNIQUE (soignant_id);
ALTER TABLE stripe_connect_onboarding ADD CONSTRAINT stripe_connect_onboarding_soignant_id_fkey FOREIGN KEY (soignant_id) REFERENCES soignants(id);
ALTER TABLE stripe_connect_onboarding ADD CONSTRAINT stripe_connect_onboarding_statut_check CHECK ((statut = ANY (ARRAY['NON_DEMANDE'::text, 'EN_COURS'::text, 'COMPLET'::text, 'SUSPENDU'::text, 'REJETE'::text, 'SUPPRIME'::text])));
ALTER TABLE stripe_connect_onboarding ADD CONSTRAINT stripe_connect_onboarding_stripe_account_type_check CHECK ((stripe_account_type = ANY (ARRAY['express'::text, 'standard'::text, 'custom'::text])));
ALTER TABLE stripe_connect_onboarding ADD CONSTRAINT stripe_connect_onboarding_type_exercice_check CHECK ((type_exercice = 'LIBERAL'::text));
ALTER TABLE stripe_refunds_queue ADD CONSTRAINT stripe_refunds_queue_pkey PRIMARY KEY (id);
ALTER TABLE stripe_refunds_queue ADD CONSTRAINT stripe_refunds_queue_avoir_id_fkey FOREIGN KEY (avoir_id) REFERENCES factures_honoraires(id) ON DELETE RESTRICT;
ALTER TABLE stripe_refunds_queue ADD CONSTRAINT stripe_refunds_queue_facture_origine_id_fkey FOREIGN KEY (facture_origine_id) REFERENCES factures_honoraires(id) ON DELETE RESTRICT;
ALTER TABLE stripe_refunds_queue ADD CONSTRAINT stripe_refunds_queue_montant_cts_check CHECK ((montant_cts > 0));
ALTER TABLE stripe_refunds_queue ADD CONSTRAINT stripe_refunds_queue_statut_check CHECK ((statut = ANY (ARRAY['EN_ATTENTE'::text, 'EN_COURS'::text, 'TRAITE'::text, 'ECHEC'::text])));
ALTER TABLE stripe_transfers ADD CONSTRAINT stripe_transfers_pkey PRIMARY KEY (id);
ALTER TABLE stripe_transfers ADD CONSTRAINT stripe_transfers_etablissement_id_fkey FOREIGN KEY (etablissement_id) REFERENCES etablissements(id);
ALTER TABLE stripe_transfers ADD CONSTRAINT stripe_transfers_facture_id_fkey FOREIGN KEY (facture_id) REFERENCES factures(id);
ALTER TABLE stripe_transfers ADD CONSTRAINT stripe_transfers_mission_id_fkey FOREIGN KEY (mission_id) REFERENCES missions(id);
ALTER TABLE stripe_transfers ADD CONSTRAINT stripe_transfers_soignant_id_fkey FOREIGN KEY (soignant_id) REFERENCES soignants(id);
ALTER TABLE stripe_transfers ADD CONSTRAINT stripe_transfers_dispute_statut_check CHECK (((dispute_statut IS NULL) OR (dispute_statut = ANY (ARRAY['OUVERT'::text, 'CLOS_won'::text, 'CLOS_lost'::text, 'CLOS_warning_closed'::text, 'CLOS_warning_needs_response'::text, 'CLOS_charge_refunded'::text]))));
ALTER TABLE stripe_transfers ADD CONSTRAINT stripe_transfers_statut_check CHECK ((statut = ANY (ARRAY['EN_ATTENTE'::text, 'CHARGE_REUSSI'::text, 'TRANSFERE'::text, 'PAYE'::text, 'ECHOUE'::text, 'REMBOURSE'::text, 'ANNULEE'::text])));
ALTER TABLE stripe_webhook_events ADD CONSTRAINT stripe_webhook_events_pkey PRIMARY KEY (event_id);
ALTER TABLE suivi_conversion_3200h ADD CONSTRAINT suivi_conversion_3200h_pkey PRIMARY KEY (id);
ALTER TABLE suivi_conversion_3200h ADD CONSTRAINT suivi_conversion_3200h_soignant_id_key UNIQUE (soignant_id);
ALTER TABLE suivi_conversion_3200h ADD CONSTRAINT suivi_conversion_3200h_soignant_id_fkey FOREIGN KEY (soignant_id) REFERENCES soignants(id);
ALTER TABLE super_swipes_quota ADD CONSTRAINT super_swipes_quota_pkey PRIMARY KEY (id);
ALTER TABLE super_swipes_quota ADD CONSTRAINT super_swipes_quota_soignant_id_date_key UNIQUE (soignant_id, date);
ALTER TABLE super_swipes_quota ADD CONSTRAINT super_swipes_quota_soignant_id_fkey FOREIGN KEY (soignant_id) REFERENCES soignants(id) ON DELETE CASCADE;
ALTER TABLE super_swipes_quota ADD CONSTRAINT super_swipes_quota_count_check CHECK ((count >= 0));
ALTER TABLE swipes ADD CONSTRAINT swipes_pkey PRIMARY KEY (id);
ALTER TABLE swipes ADD CONSTRAINT swipes_soignant_id_mission_id_key UNIQUE (soignant_id, mission_id);
ALTER TABLE swipes ADD CONSTRAINT swipes_mission_id_fkey FOREIGN KEY (mission_id) REFERENCES missions(id) ON DELETE CASCADE;
ALTER TABLE swipes ADD CONSTRAINT swipes_soignant_id_fkey FOREIGN KEY (soignant_id) REFERENCES soignants(id) ON DELETE CASCADE;
ALTER TABLE templates_contrat ADD CONSTRAINT templates_contrat_pkey PRIMARY KEY (id);
ALTER TABLE tokens_calendrier ADD CONSTRAINT tokens_calendrier_pkey PRIMARY KEY (id);
ALTER TABLE tokens_calendrier ADD CONSTRAINT tokens_calendrier_soignant_id_key UNIQUE (soignant_id);
ALTER TABLE tokens_calendrier ADD CONSTRAINT tokens_calendrier_soignant_id_fkey FOREIGN KEY (soignant_id) REFERENCES auth.users(id) ON DELETE CASCADE;
ALTER TABLE tokens_push ADD CONSTRAINT tokens_push_pkey PRIMARY KEY (id);
ALTER TABLE tokens_push ADD CONSTRAINT tokens_push_utilisateur_id_token_key UNIQUE (utilisateur_id, token);
ALTER TABLE tokens_push ADD CONSTRAINT tokens_push_plateforme_check CHECK ((plateforme = ANY (ARRAY['WEB'::text, 'IOS'::text, 'ANDROID'::text])));
ALTER TABLE typing_status ADD CONSTRAINT typing_status_pkey PRIMARY KEY (conversation_id, user_id);
ALTER TABLE typing_status ADD CONSTRAINT typing_status_conversation_id_fkey FOREIGN KEY (conversation_id) REFERENCES conversations(id) ON DELETE CASCADE;
ALTER TABLE typing_status ADD CONSTRAINT typing_status_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;
