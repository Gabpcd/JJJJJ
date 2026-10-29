-- Prérequis figés AVANT la migration internat 20261029080849.
-- Extraction des types, tables et clés primaires utilisés par le témoin PG17.
-- Source : 46df363c4ec2446ccc73e5cc962702f3d44b8618:supabase/schema/public.sql
-- Blob source : 442a0d1c73ed1c15b0b0e47cc52fa159fb162753.
-- Aucune donnée, routine, permission ou destination de connexion.

CREATE TYPE "public"."canal_notification" AS ENUM (
    'EMAIL',
    'SMS',
    'PUSH',
    'IN_APP'
);

CREATE TYPE "public"."categorie_litige" AS ENUM (
    'PRESENCE',
    'FINANCIER',
    'CONDITIONS',
    'COMPORTEMENT',
    'AUTRE'
);

CREATE TYPE "public"."credit_etab_motif" AS ENUM (
    'PARRAINAGE'
);

CREATE TYPE "public"."filtre_audience" AS ENUM (
    'SOIGNANT_RECHERCHE_MISSIONS',
    'ETAB_RECHERCHE_SOIGNANTS'
);

CREATE TYPE "public"."filtre_frequence_alerte" AS ENUM (
    'IMMEDIATE',
    'QUOTIDIENNE',
    'HEBDOMADAIRE'
);

CREATE TYPE "public"."mode_remboursement_avoir" AS ENUM (
    'N_A',
    'AUTO_STRIPE',
    'VIREMENT_MANUEL'
);

CREATE TYPE "public"."niveau_prevoyance_souhaite" AS ENUM (
    'BRONZE',
    'ARGENT',
    'OR',
    'INDIFFERENT'
);

CREATE TYPE "public"."niveau_qualitatif" AS ENUM (
    'BRONZE',
    'ARGENT',
    'OR',
    'PLATINE'
);

CREATE TYPE "public"."parrainage_etab_statut" AS ENUM (
    'PENDING',
    'VALIDATED',
    'EXPIRED'
);

CREATE TYPE "public"."presence_status_enum" AS ENUM (
    'ONLINE',
    'AWAY',
    'OFFLINE'
);

CREATE TYPE "public"."sens_notation" AS ENUM (
    'ETAB_VERS_SOIGNANT',
    'SOIGNANT_VERS_ETAB'
);

CREATE TYPE "public"."serie_email_statut" AS ENUM (
    'PLANIFIE',
    'ENVOYE',
    'SKIPPED',
    'ERREUR'
);

CREATE TYPE "public"."serie_onboarding_etape" AS ENUM (
    'J0',
    'J1',
    'J3',
    'J7'
);

CREATE TYPE "public"."serie_onboarding_type" AS ENUM (
    'SOIGNANT_ONBOARDING',
    'ETAB_ONBOARDING'
);

CREATE TYPE "public"."statut_compte_soignant" AS ENUM (
    'ACTIF',
    'SUSPENDU',
    'SUPPRIME',
    'EN_REVISION_ADMIN'
);

CREATE TYPE "public"."statut_litige_facture" AS ENUM (
    'NORMAL',
    'EN_ATTENTE_LITIGE',
    'LITIGE_RESOLU_AJUSTE',
    'LITIGE_RESOLU_CONFIRME'
);

CREATE TYPE "public"."statut_mission" AS ENUM (
    'OUVERTE',
    'ASSIGNEE',
    'EN_COURS',
    'TERMINEE',
    'ANNULEE_PAR_ETABLISSEMENT',
    'ANNULEE_PAR_SOIGNANT',
    'ABSENCE',
    'LITIGE',
    'EXPIREE'
);

CREATE TYPE "public"."statut_verification" AS ENUM (
    'EN_ATTENTE',
    'VERIFIE',
    'REJETE',
    'EXPIRE',
    'REVUE_MANUELLE_REQUISE',
    'API_INDISPONIBLE'
);

CREATE TYPE "public"."strategie_facturation" AS ENUM (
    'FINALE_UNIQUE',
    'HEBDO_ET_FINALE'
);

CREATE TYPE "public"."swipe_direction" AS ENUM (
    'LIKE',
    'DISLIKE',
    'SUPER_LIKE',
    'FAVORI'
);

CREATE TYPE "public"."type_contrat" AS ENUM (
    'CDD',
    'VACATION',
    'LIBERAL',
    'SALARIE'
);

CREATE TYPE "public"."type_contrat_applique_enum" AS ENUM (
    'LIBERAL',
    'SALARIE'
);

CREATE TYPE "public"."type_document" AS ENUM (
    'CARTE_IDENTITE',
    'PASSEPORT',
    'TITRE_SEJOUR',
    'DIPLOME',
    'RPPS_ADELI',
    'RCP_ASSURANCE',
    'VACCINATIONS',
    'CASIER_JUDICIAIRE',
    'RIB',
    'KBIS',
    'ATTESTATION_URSSAF',
    'AUTORISATION_EXERCICE',
    'MEDECINE_TRAVAIL',
    'FORMATION_OBLIGATOIRE',
    'AUTRE',
    'CARTE_ORDRE',
    'ATTESTATION_CPAM',
    'NOTE_HONORAIRES',
    'ATTESTATION_3200H',
    'ARRET_MALADIE',
    'ATTESTATION_SCOLARITE',
    'LICENCE_REMPLACEMENT',
    'BULLETIN_PAIE',
    'ATTESTATION_EMPLOYEUR',
    'CERTIFICAT_TRAVAIL'
);

CREATE TYPE "public"."type_document_facture" AS ENUM (
    'FACTURE',
    'AVOIR'
);

CREATE TYPE "public"."type_etablissement" AS ENUM (
    'HOPITAL_PUBLIC',
    'CLINIQUE_PRIVEE',
    'EHPAD',
    'SSIAD',
    'HAD',
    'CENTRE_SANTE',
    'LABO',
    'IME',
    'MAS',
    'FAM',
    'PHARMACIE_OFFICINE',
    'ESPIC',
    'CABINET_MEDICAL',
    'CABINET_DENTAIRE',
    'CABINET_IDEL',
    'CABINET_SAGE_FEMME',
    'CABINET_KINE',
    'CABINET_ORTHO',
    'CABINET_ERGO',
    'CABINET_PSYCHOMOT'
);

CREATE TYPE "public"."type_evenement_notification" AS ENUM (
    'NOUVELLE_MISSION_MATCHANT_FILTRE',
    'CANDIDATURE_RECUE',
    'CANDIDATURE_ACCEPTEE',
    'MISSION_ASSIGNEE',
    'RAPPEL_J1_MISSION',
    'POINTAGE_MANQUANT',
    'FACTURE_EMISE',
    'PAIEMENT_RECU',
    'CONTRAT_TRAVAIL_DEPOSE',
    'LITIGE_OUVERT',
    'LITIGE_RESOLU',
    'DOCUMENT_EXPIRANT',
    'MANDAT_RE_SIGNATURE',
    'SERIE_ONBOARDING',
    'URGENCE',
    'NOUVEAU_SOIGNANT_MATCHANT_FILTRE',
    'FAVORI_NOUVELLE_MISSION',
    'NOTATION_RAPPEL'
);

CREATE TYPE "public"."type_litige" AS ENUM (
    'ABSENCE_SOIGNANT',
    'DEPART_ANTICIPE',
    'RETARD_IMPORTANT',
    'DESACCORD_MONTANT_FACTURE',
    'DESACCORD_HEURES_POINTAGE',
    'NON_PAIEMENT',
    'FRAIS_COMPLEMENTAIRES',
    'CONDITIONS_MISSION_NON_RESPECTEES',
    'SECURITE_DANGER',
    'COMPORTEMENT_SOIGNANT',
    'COMPORTEMENT_ETABLISSEMENT',
    'AUTRE'
);

CREATE TYPE "public"."type_profession" AS ENUM (
    'IDE',
    'AS',
    'AES',
    'IBODE',
    'IADE',
    'SAGE_FEMME',
    'KINE',
    'MEDECIN',
    'PHARMACIEN',
    'MANIPULATEUR_RADIO',
    'PREPARATEUR_PHARMA',
    'DIETETICIEN',
    'ERGOTHERAPEUTE',
    'PSYCHOMOTRICIEN',
    'ORTHOPHONISTE',
    'DENTISTE',
    'AUXILIAIRE_PUERICULTURE'
);

CREATE TABLE IF NOT EXISTS "public"."admins_groupe_sante" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "groupe_id" "uuid" NOT NULL,
    "utilisateur_id" "uuid" NOT NULL,
    "role" "text" DEFAULT 'LECTEUR'::"text",
    "cree_le" timestamp with time zone DEFAULT "now"(),
    CONSTRAINT "admins_groupe_sante_role_check" CHECK (("role" = ANY (ARRAY['PROPRIETAIRE'::"text", 'ADMINISTRATEUR'::"text", 'FACTURATION'::"text", 'LECTEUR'::"text"])))
);

ALTER TABLE ONLY "public"."admins_groupe_sante"
    ADD CONSTRAINT "admins_groupe_sante_pkey" PRIMARY KEY ("id");

CREATE TABLE IF NOT EXISTS "public"."attestations_heures_externes" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "soignant_id" "uuid" NOT NULL,
    "semaine_du" "date" NOT NULL,
    "heures_salarie" numeric DEFAULT 0,
    "employeur_principal" "text",
    "attestation_honneur" boolean DEFAULT false,
    "cree_le" timestamp with time zone DEFAULT "now"(),
    "modifie_le" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "attestations_heures_externes_employeur_check" CHECK (((COALESCE("heures_salarie", (0)::numeric) = (0)::numeric) OR (("char_length"("btrim"(COALESCE("employeur_principal", ''::"text"))) >= 2) AND ("char_length"("btrim"(COALESCE("employeur_principal", ''::"text"))) <= 200)))),
    CONSTRAINT "attestations_heures_externes_heures_salarie_check" CHECK ((("heures_salarie" IS NULL) OR (("heures_salarie" >= (0)::numeric) AND ("heures_salarie" <= (168)::numeric)))),
    CONSTRAINT "attestations_heures_externes_honneur_check" CHECK (((COALESCE("heures_salarie", (0)::numeric) = (0)::numeric) OR ("attestation_honneur" IS TRUE))),
    CONSTRAINT "attestations_heures_externes_semaine_lundi_check" CHECK (("semaine_du" = ("date_trunc"('week'::"text", ("semaine_du")::timestamp with time zone))::"date"))
);

ALTER TABLE ONLY "public"."attestations_heures_externes"
    ADD CONSTRAINT "attestations_heures_externes_pkey" PRIMARY KEY ("id");

CREATE TABLE IF NOT EXISTS "public"."candidatures" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "mission_id" "uuid" NOT NULL,
    "soignant_id" "uuid" NOT NULL,
    "message" "text",
    "statut" "text" DEFAULT 'EN_ATTENTE'::"text",
    "motif_refus" "text",
    "cree_le" timestamp with time zone DEFAULT "now"(),
    "traite_le" timestamp with time zone,
    "type_contrat_choisi" "text",
    "acceptee_a" timestamp with time zone,
    CONSTRAINT "candidatures_statut_check" CHECK (("statut" = ANY (ARRAY['EN_ATTENTE'::"text", 'EN_ATTENTE_VALIDATION_ETAB'::"text", 'ACCEPTEE'::"text", 'REFUSEE'::"text", 'ANNULEE'::"text", 'PROPOSEE'::"text", 'EXPIREE'::"text"]))),
    CONSTRAINT "check_type_contrat_choisi" CHECK ((("type_contrat_choisi" IS NULL) OR ("type_contrat_choisi" = ANY (ARRAY['SALARIE'::"text", 'LIBERAL'::"text"]))))
);

ALTER TABLE ONLY "public"."candidatures"
    ADD CONSTRAINT "candidatures_pkey" PRIMARY KEY ("id");

CREATE TABLE IF NOT EXISTS "public"."contrats_mission" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "mission_id" "uuid" NOT NULL,
    "etablissement_id" "uuid" NOT NULL,
    "soignant_id" "uuid" NOT NULL,
    "type_contrat" "text" NOT NULL,
    "numero_contrat" "text" NOT NULL,
    "contenu_html" "text",
    "signature_etablissement" boolean DEFAULT false,
    "signature_etablissement_le" timestamp with time zone,
    "signature_soignant" boolean DEFAULT false,
    "signature_soignant_le" timestamp with time zone,
    "statut" "text" DEFAULT 'BROUILLON'::"text",
    "pdf_cle_s3" "text",
    "cree_le" timestamp with time zone DEFAULT "now"(),
    "modifie_le" timestamp with time zone DEFAULT "now"(),
    "signature_image_soignant" "text",
    "signature_image_etablissement" "text",
    "signature_ip_soignant" "inet",
    "signature_ip_etablissement" "inet",
    "signature_navigateur_soignant" "text",
    "signature_navigateur_etablissement" "text",
    "rappel_dpae_affiche" boolean DEFAULT false,
    "rappel_dpae_affiche_le" timestamp with time zone,
    "dpae_effectuee" boolean DEFAULT false,
    "dpae_effectuee_le" timestamp with time zone,
    "mode_signature" "text" DEFAULT 'CANVAS'::"text",
    "dpae_numero" "text",
    "storage_path" "text",
    "hash_document" "text",
    "template_slug" "text",
    "contenu_html_rendu_le" timestamp with time zone,
    CONSTRAINT "contrats_mission_mode_signature_check" CHECK (("mode_signature" = ANY (ARRAY['CANVAS'::"text", 'JOLENE_OTP'::"text"]))),
    CONSTRAINT "contrats_mission_statut_check" CHECK (("statut" = ANY (ARRAY['BROUILLON'::"text", 'EN_ATTENTE_SIGNATURES'::"text", 'SIGNE_ETABLISSEMENT'::"text", 'SIGNE_SOIGNANT'::"text", 'SIGNE_COMPLET'::"text", 'ANNULE'::"text", 'EXPIRE'::"text"]))),
    CONSTRAINT "contrats_mission_type_contrat_check" CHECK (("type_contrat" = ANY (ARRAY['CDDU'::"text", 'VACATION'::"text", 'REMPLACEMENT_LIBERAL'::"text", 'CDD'::"text"])))
);

ALTER TABLE ONLY "public"."contrats_mission"
    ADD CONSTRAINT "contrats_mission_pkey" PRIMARY KEY ("id");

CREATE TABLE IF NOT EXISTS "public"."documents_requis_par_profession" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "profession" "public"."type_profession" NOT NULL,
    "type_document" "public"."type_document" NOT NULL,
    "est_critique" boolean DEFAULT true,
    "a_expiration" boolean DEFAULT true,
    "duree_validite_mois" integer,
    "description" "text",
    "type_exercice_requis" "text" DEFAULT 'TOUS'::"text" NOT NULL,
    CONSTRAINT "chk_type_exercice_requis" CHECK (("type_exercice_requis" = ANY (ARRAY['SALARIE_ONLY'::"text", 'LIBERAL_ONLY'::"text", 'TOUS'::"text"])))
);

ALTER TABLE ONLY "public"."documents_requis_par_profession"
    ADD CONSTRAINT "documents_requis_par_profession_pkey" PRIMARY KEY ("id");

CREATE TABLE IF NOT EXISTS "public"."documents_soignants" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "soignant_id" "uuid" NOT NULL,
    "type_document" "public"."type_document" NOT NULL,
    "libelle" "text",
    "s3_bucket" "text" DEFAULT 'jolene-documents'::"text" NOT NULL,
    "s3_cle" "text" NOT NULL,
    "s3_version_id" "text",
    "nom_fichier" "text" NOT NULL,
    "type_mime" "text",
    "taille_octets" bigint,
    "valide_depuis" "date",
    "valide_jusqua" "date",
    "statut_verification" "public"."statut_verification" DEFAULT 'EN_ATTENTE'::"public"."statut_verification",
    "verifie_par" "uuid",
    "verifie_le" timestamp with time zone,
    "motif_rejet" "text",
    "est_critique" boolean DEFAULT false,
    "rappel_j30_envoye" boolean DEFAULT false,
    "rappel_j7_envoye" boolean DEFAULT false,
    "rappel_expire_envoye" boolean DEFAULT false,
    "televerse_le" timestamp with time zone DEFAULT "now"(),
    "modifie_le" timestamp with time zone DEFAULT "now"(),
    "supprime_le" timestamp with time zone,
    "resultat_ia" "jsonb",
    "nom_extrait_ia" "text",
    "prenom_extrait_ia" "text",
    "coherence_nom" boolean,
    "score_confiance_ia" numeric,
    "verification_attempt_id" "uuid",
    "revoque_le" timestamp with time zone,
    "revoque_raison" "text",
    "remplace_par_document_id" "uuid",
    CONSTRAINT "documents_soignants_revoque_raison_check" CHECK (((("revoque_le" IS NULL) AND ("revoque_raison" IS NULL) AND ("remplace_par_document_id" IS NULL)) OR (("revoque_le" IS NOT NULL) AND ("revoque_raison" = ANY (ARRAY['REMPLACEMENT'::"text", 'RETRAIT'::"text"])))))
);

ALTER TABLE ONLY "public"."documents_soignants"
    ADD CONSTRAINT "documents_soignants_pkey" PRIMARY KEY ("id");

CREATE TABLE IF NOT EXISTS "public"."equipe_admin" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid",
    "nom" "text" NOT NULL,
    "prenom" "text" NOT NULL,
    "email" "text" NOT NULL,
    "poste" "text" DEFAULT 'Opérations'::"text" NOT NULL,
    "salaire_brut_mensuel" numeric(10,2) DEFAULT 0,
    "date_embauche" "date",
    "acces_groupes" "text"[] DEFAULT ARRAY['Dashboard'::"text"] NOT NULL,
    "actif" boolean DEFAULT true NOT NULL,
    "cree_le" timestamp with time zone DEFAULT "now"() NOT NULL,
    "maj_le" timestamp with time zone DEFAULT "now"() NOT NULL
);

ALTER TABLE ONLY "public"."equipe_admin"
    ADD CONSTRAINT "equipe_admin_pkey" PRIMARY KEY ("id");

CREATE TABLE IF NOT EXISTS "public"."equivalences_scolarite" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "formation" "text" NOT NULL,
    "libelle_formation" "text" NOT NULL,
    "annee_validee_min" integer NOT NULL,
    "profession_autorisee" "public"."type_profession" NOT NULL,
    "base_reglementaire" "text",
    "actif" boolean DEFAULT true NOT NULL,
    "cree_le" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "equivalences_scolarite_annee_validee_min_check" CHECK (("annee_validee_min" >= 1))
);

ALTER TABLE ONLY "public"."equivalences_scolarite"
    ADD CONSTRAINT "equivalences_scolarite_pkey" PRIMARY KEY ("id");

CREATE TABLE IF NOT EXISTS "public"."etablissements" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "nom" "text" NOT NULL,
    "siret" character varying(14) NOT NULL,
    "finess" character varying(9),
    "type" "public"."type_etablissement" NOT NULL,
    "groupe_sante_id" "uuid",
    "adresse_rue" "text" NOT NULL,
    "adresse_ville" "text" NOT NULL,
    "adresse_code_postal" character varying(5) NOT NULL,
    "adresse_departement" character varying(3),
    "adresse_lat" numeric(10,7),
    "adresse_lng" numeric(10,7),
    "email_contact" "text" NOT NULL,
    "telephone_contact" character varying(20),
    "formule_abonnement" "text" DEFAULT 'GRATUIT'::"text",
    "rist_plafond_actif" boolean DEFAULT true,
    "rist_taux_base_horaire" numeric(8,2) DEFAULT 25.00,
    "taux_majoration_nuit_pourcent" numeric(5,2) DEFAULT 25.00,
    "taux_majoration_dimanche_pourcent" numeric(5,2) DEFAULT 50.00,
    "taux_majoration_ferie_pourcent" numeric(5,2) DEFAULT 100.00,
    "cree_le" timestamp with time zone DEFAULT "now"(),
    "modifie_le" timestamp with time zone DEFAULT "now"(),
    "supprime_le" timestamp with time zone,
    "stripe_customer_id" "text",
    "taux_commission_negocie" numeric(5,2) DEFAULT 15.00,
    "mode_facturation" "text" DEFAULT 'PAR_MISSION'::"text",
    "palier_commission_id" "uuid",
    "missions_mois_precedent" integer DEFAULT 0,
    "palier_recalcule_le" "date",
    "chorus_pro_actif" boolean DEFAULT false,
    "chorus_pro_identifiant" "text",
    "delai_paiement_jours" integer DEFAULT 30,
    "convention_collective" "text",
    "couleur_theme" "text" DEFAULT '#17A2B8'::"text",
    "logo_url" "text",
    "mode_paiement_commission" "text" DEFAULT 'FACTURE_MENSUELLE'::"text",
    "contrat_url" "text",
    "contrat_uploade_le" timestamp with time zone,
    "contrat_valide" boolean DEFAULT false,
    "stripe_account_id" "text",
    "siret_verifie" boolean DEFAULT false,
    "siret_verifie_le" timestamp with time zone,
    "finess_verifie" boolean DEFAULT false,
    "finess_verifie_le" timestamp with time zone,
    "statut_verification" "text" DEFAULT 'EN_ATTENTE'::"text",
    "verifie_par" "uuid",
    "verifie_le" timestamp with time zone,
    "motif_rejet" "text",
    "peut_publier_missions" boolean DEFAULT false,
    "siret_raison_sociale" "text",
    "siret_categorie_juridique" "text",
    "siret_code_naf" "text",
    "siret_est_actif" boolean,
    "est_secteur_public" boolean DEFAULT false,
    "note_moyenne" numeric(3,2) DEFAULT NULL::numeric,
    "nb_evaluations" integer DEFAULT 0,
    "description" "text",
    "horaires_ouverture" "jsonb",
    "stripe_sepa_payment_method_id" "text",
    "sms_actif" boolean DEFAULT false,
    "sms_consent_le" timestamp with time zone,
    "heure_debut_nuit" time without time zone DEFAULT '21:00:00'::time without time zone,
    "heure_fin_nuit" time without time zone DEFAULT '06:00:00'::time without time zone,
    "bloque_auto_le" timestamp with time zone,
    "bloque_auto_raisons" "jsonb",
    "contrat_service_signe" boolean DEFAULT false NOT NULL,
    "contrat_service_signe_le" timestamp with time zone,
    "rib_s3_key" "text",
    "code_parrainage" "text",
    "parraine_par_id" "uuid",
    "score_qualite" numeric,
    "niveau" "public"."niveau_qualitatif",
    "tolerance_pointage_m" integer DEFAULT 100 NOT NULL,
    "onboarding_etapes_completees" "jsonb" DEFAULT '[]'::"jsonb" NOT NULL,
    "onboarding_termine_le" timestamp with time zone,
    "telephone_verifie" boolean DEFAULT false NOT NULL,
    "telephone_verifie_le" timestamp with time zone,
    "telephone_en_attente_verification" "text",
    "finess_raison_sociale" "text",
    "finess_categorie" "text",
    "finess_secteur" "text",
    "finess_est_public" boolean,
    "dirigeants" "jsonb",
    "representant_nom" "text",
    "representant_prenom" "text",
    "representant_identite_verifiee" boolean DEFAULT false NOT NULL,
    "representant_identite_verifiee_le" timestamp with time zone,
    "rattachement_methode" "text",
    "rattachement_verifie" boolean DEFAULT false NOT NULL,
    "rattachement_verifie_le" timestamp with time zone,
    "email_contact_verifie" boolean DEFAULT false NOT NULL,
    "email_contact_verifie_le" timestamp with time zone,
    "representant_piece_s3_key" "text",
    "representant_piece_type_mime" "text",
    "representant_piece_type_document" "text",
    "representant_identite_resultat_ia" "jsonb",
    "email_contact_token" "text",
    "email_contact_token_expire_le" timestamp with time zone,
    "contrat_ia_resultat" "jsonb",
    "contrat_ia_coherent" boolean,
    "contrat_ia_verifie_le" timestamp with time zone,
    "rib_ia_resultat" "jsonb",
    "rib_ia_coherent" boolean,
    "rib_ia_verifie_le" timestamp with time zone,
    "utm_source" "text",
    "utm_medium" "text",
    "utm_campaign" "text",
    "utm_content" "text",
    "utm_term" "text",
    "http_referrer" "text",
    "ref_capture" "text",
    "source_acquisition" "text",
    "bfa_eligible" boolean DEFAULT false NOT NULL,
    "bfa_taux" numeric,
    "bfa_contrat_signe_le" "date",
    "coherence_identite" "text",
    "justificatif_fonction_s3_key" "text",
    "justificatif_fonction_type" "text",
    "justificatif_fonction_type_mime" "text",
    "justificatif_fonction_verifie" boolean,
    "justificatif_fonction_verifie_le" timestamp with time zone,
    "justificatif_fonction_resultat_ia" "jsonb",
    "iban_last4" "text",
    "est_compte_test" boolean DEFAULT false NOT NULL,
    "jour_paie_habituel" smallint,
    "verification_source_version" bigint DEFAULT 0 NOT NULL,
    "rib_verifie_s3_key" "text",
    "rib_verifie_source_version" bigint,
    CONSTRAINT "chk_etab_telephone_format" CHECK ((("telephone_contact" IS NULL) OR (("telephone_contact")::"text" ~ '^\+?[0-9\s\-\.]{8,20}$'::"text"))),
    CONSTRAINT "chk_heure_debut_nuit" CHECK ((("heure_debut_nuit" >= '19:00:00'::time without time zone) AND ("heure_debut_nuit" <= '23:59:00'::time without time zone))),
    CONSTRAINT "chk_heure_fin_nuit" CHECK ((("heure_fin_nuit" >= '04:00:00'::time without time zone) AND ("heure_fin_nuit" <= '08:00:00'::time without time zone))),
    CONSTRAINT "chk_taux_maj_dim_min" CHECK (("taux_majoration_dimanche_pourcent" >= (25)::numeric)),
    CONSTRAINT "chk_taux_maj_fer_min" CHECK (("taux_majoration_ferie_pourcent" >= (50)::numeric)),
    CONSTRAINT "chk_taux_maj_nuit_min" CHECK (("taux_majoration_nuit_pourcent" >= (25)::numeric)),
    CONSTRAINT "etablissements_convention_collective_check" CHECK (("convention_collective" = ANY (ARRAY['CCN_51_FEHAP'::"text", 'CCN_66_SOCIAL'::"text", 'CCN_FHP_PRIVE'::"text", 'CCN_PHARMACIE'::"text", 'FPH_PUBLIQUE'::"text", 'AUTRE'::"text", NULL::"text"]))),
    CONSTRAINT "etablissements_formule_abonnement_check" CHECK (("formule_abonnement" = ANY (ARRAY['GRATUIT'::"text", 'STARTER'::"text", 'PRO'::"text", 'ENTERPRISE'::"text"]))),
    CONSTRAINT "etablissements_jour_paie_check" CHECK ((("jour_paie_habituel" >= 1) AND ("jour_paie_habituel" <= 31))),
    CONSTRAINT "etablissements_mode_facturation_check" CHECK (("mode_facturation" = ANY (ARRAY['PAR_MISSION'::"text", 'MENSUEL'::"text"]))),
    CONSTRAINT "etablissements_mode_paiement_commission_check" CHECK (("mode_paiement_commission" = ANY (ARRAY['FACTURE_MENSUELLE'::"text", 'SEPA_DEBIT'::"text", 'CHORUS_PRO'::"text"]))),
    CONSTRAINT "etablissements_rattachement_methode_check" CHECK ((("rattachement_methode" IS NULL) OR ("rattachement_methode" = ANY (ARRAY['AUTO_DIRIGEANT'::"text", 'JUSTIFICATIF'::"text", 'ADMIN'::"text"])))),
    CONSTRAINT "etablissements_representant_piece_type_check" CHECK ((("representant_piece_type_document" IS NULL) OR ("representant_piece_type_document" = ANY (ARRAY['CARTE_IDENTITE'::"text", 'PASSEPORT'::"text", 'TITRE_SEJOUR'::"text"])))),
    CONSTRAINT "etablissements_rib_provenance_courante_check" CHECK ((("rib_ia_coherent" IS DISTINCT FROM true) OR (("rib_ia_verifie_le" IS NOT NULL) AND ("rib_verifie_s3_key" IS NOT NULL) AND ("rib_verifie_s3_key" = "rib_s3_key") AND ("rib_verifie_source_version" IS NOT NULL)))),
    CONSTRAINT "etablissements_statut_verification_check" CHECK (("statut_verification" = ANY (ARRAY['EN_ATTENTE'::"text", 'EN_COURS'::"text", 'VERIFIE'::"text", 'REJETE'::"text", 'SUSPENDU'::"text"]))),
    CONSTRAINT "etablissements_tolerance_pointage_m_check" CHECK ((("tolerance_pointage_m" >= 30) AND ("tolerance_pointage_m" <= 1000)))
);

ALTER TABLE ONLY "public"."etablissements"
    ADD CONSTRAINT "etablissements_pkey" PRIMARY KEY ("id");

CREATE TABLE IF NOT EXISTS "public"."evenements_score_soignant" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "soignant_id" "uuid" NOT NULL,
    "type_evenement" "text" NOT NULL,
    "points" integer NOT NULL,
    "motif" "text" NOT NULL,
    "contestable" boolean DEFAULT true NOT NULL,
    "reclamation_id" "uuid",
    "decision_admin" "text",
    "points_corriges" integer,
    "motif_admin" "text",
    "traite_par_admin_id" "uuid",
    "traite_le" timestamp with time zone,
    "mission_id" "uuid",
    "candidature_id" "uuid",
    "litige_id" "uuid",
    "justificatif_storage_path" "text",
    "details" "jsonb" DEFAULT '{}'::"jsonb",
    "cree_le" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "evenements_score_soignant_decision_admin_check" CHECK ((("decision_admin" IS NULL) OR ("decision_admin" = ANY (ARRAY['MAINTENIR'::"text", 'REDUIRE'::"text", 'ANNULER'::"text"])))),
    CONSTRAINT "evenements_score_soignant_type_evenement_check" CHECK (("type_evenement" = ANY (ARRAY['ANNULATION_12_24H'::"text", 'ANNULATION_1_12H'::"text", 'ANNULATION_MOINS_1H'::"text", 'ASAP_ANNULEE_APRES_FENETRE'::"text", 'NO_SHOW'::"text", 'LITIGE_TORT_RECONNU'::"text", 'NOTE_BASSE_RECUE'::"text", 'EVALUATION_NEGATIVE'::"text", 'BONUS_AMBASSADEUR'::"text", 'BONUS_FIDELITE'::"text", 'FRAUDE_GPS'::"text", 'AUTRE'::"text"])))
);

ALTER TABLE ONLY "public"."evenements_score_soignant"
    ADD CONSTRAINT "evenements_score_soignant_pkey" PRIMARY KEY ("id");

CREATE TABLE IF NOT EXISTS "public"."exclusions" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "exclu_par" "uuid" NOT NULL,
    "exclu_id" "uuid" NOT NULL,
    "type_exclu_par" "text" NOT NULL,
    "motif" "text",
    "cree_le" timestamp with time zone DEFAULT "now"(),
    CONSTRAINT "exclusions_type_exclu_par_check" CHECK (("type_exclu_par" = ANY (ARRAY['SOIGNANT'::"text", 'ETABLISSEMENT'::"text"])))
);

ALTER TABLE ONLY "public"."exclusions"
    ADD CONSTRAINT "exclusions_pkey" PRIMARY KEY ("id");

CREATE TABLE IF NOT EXISTS "public"."externalisation_actions" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "type_action" "text" NOT NULL,
    "payload" "jsonb" NOT NULL,
    "source" "text" NOT NULL,
    "source_id" "uuid",
    "statut" "text" DEFAULT 'PENDING'::"text" NOT NULL,
    "tentatives" integer DEFAULT 0 NOT NULL,
    "derniere_tentative_le" timestamp with time zone,
    "derniere_erreur" "text",
    "resultat" "jsonb",
    "cree_le" timestamp with time zone DEFAULT "now"() NOT NULL,
    "traite_le" timestamp with time zone,
    "next_retry_at" timestamp with time zone,
    "cron_lock_at" timestamp with time zone,
    "cron_lock_par" "text",
    CONSTRAINT "externalisation_actions_source_check" CHECK (("source" = ANY (ARRAY['LITIGE_EXEC'::"text", 'ANNULATION_MISSION'::"text", 'AUTRE'::"text", 'CRON_ANTI_TRICHE'::"text", 'CRON_ALERTES'::"text", 'parrainage_soignant'::"text", 'remboursement_avoir'::"text"]))),
    CONSTRAINT "externalisation_actions_statut_check" CHECK (("statut" = ANY (ARRAY['PENDING'::"text", 'PROCESSING'::"text", 'DONE'::"text", 'ERROR'::"text", 'PENDING_AIFE'::"text", 'CANCELLED'::"text"]))),
    CONSTRAINT "externalisation_actions_type_action_check" CHECK (("type_action" = ANY (ARRAY['STRIPE_REFUND_PARTIEL'::"text", 'STRIPE_REFUND_TOTAL'::"text", 'STRIPE_PAYMENT'::"text", 'STRIPE_PAYOUT'::"text", 'CHORUS_RECYCLER_FACTURE'::"text", 'CHORUS_RECYCLE_FACTURE'::"text", 'DPAE_ANNULATION'::"text", 'DPAE_ANNULATION_NOTIF'::"text", 'EMAIL_NOTIF'::"text", 'SMS_NOTIF'::"text", 'PUSH_NOTIF'::"text", 'PUSH_CANDIDATURE_RECUE'::"text", 'AVOIR_PDF_GENERATION'::"text", 'RECOMPENSE_PARRAINAGE_SOIGNANT'::"text", 'REMBOURSEMENT_AVOIR_SWAN'::"text"])))
);

ALTER TABLE ONLY "public"."externalisation_actions"
    ADD CONSTRAINT "externalisation_actions_pkey" PRIMARY KEY ("id");

CREATE TABLE IF NOT EXISTS "public"."factures" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "etablissement_id" "uuid" NOT NULL,
    "numero_facture" "text" NOT NULL,
    "periode_debut" "date",
    "periode_fin" "date",
    "montant_ht" numeric(10,2) NOT NULL,
    "taux_tva" numeric(5,2) DEFAULT 20.00,
    "montant_tva" numeric(10,2) NOT NULL,
    "montant_ttc" numeric(10,2) NOT NULL,
    "nombre_missions" integer DEFAULT 0,
    "stripe_invoice_id" "text",
    "stripe_payment_intent_id" "text",
    "stripe_hosted_url" "text",
    "statut" "text" DEFAULT 'BROUILLON'::"text",
    "date_emission" timestamp with time zone,
    "date_echeance" "date",
    "date_paiement" timestamp with time zone,
    "cree_le" timestamp with time zone DEFAULT "now"(),
    "modifie_le" timestamp with time zone DEFAULT "now"(),
    "chorus_pro_id" "text",
    "chorus_pro_statut" "text" DEFAULT 'NON_APPLICABLE'::"text",
    "chorus_pro_deposee_le" timestamp with time zone,
    "est_secteur_public" boolean DEFAULT false,
    "mode_paiement" "text" DEFAULT 'STRIPE'::"text",
    "virement_confirme_par" "uuid",
    "virement_confirme_le" timestamp with time zone,
    "virement_reference" "text",
    "chorus_pro_numero_flux" "text",
    "chorus_pro_date_depot" timestamp with time zone,
    "chorus_pro_date_acceptation" timestamp with time zone,
    "mission_id" "uuid",
    "type_document" "text" DEFAULT 'FACTURE'::"text" NOT NULL,
    "facture_precedente_id" "uuid",
    "montant_signe" numeric(12,2) GENERATED ALWAYS AS (
CASE
    WHEN ("type_document" = 'AVOIR'::"text") THEN (- "montant_ht")
    ELSE "montant_ht"
END) STORED,
    "relance_1_le" timestamp with time zone,
    "relance_2_le" timestamp with time zone,
    "bloque_le" timestamp with time zone,
    "facture_honoraire_id" "uuid",
    "montant_avoirs_imputes" numeric(10,2) DEFAULT 0 NOT NULL,
    "montant_a_payer" numeric(10,2) GENERATED ALWAYS AS (("montant_ttc" - "montant_avoirs_imputes")) STORED,
    "rapprochement_paiement_requis" boolean DEFAULT false NOT NULL,
    CONSTRAINT "factures_chorus_pro_statut_check" CHECK (("chorus_pro_statut" = ANY (ARRAY['NON_APPLICABLE'::"text", 'A_DEPOSER'::"text", 'DEPOSEE'::"text", 'RECUE'::"text", 'MANDATEE'::"text", 'PAYEE'::"text", 'REJETEE'::"text"]))),
    CONSTRAINT "factures_imputation_bornes" CHECK ((("montant_avoirs_imputes" >= (0)::numeric) AND ("montant_avoirs_imputes" <= "montant_ttc") AND (("montant_avoirs_imputes" = (0)::numeric) OR ("type_document" = 'FACTURE'::"text")))),
    CONSTRAINT "factures_mode_paiement_check" CHECK (("mode_paiement" = ANY (ARRAY['STRIPE'::"text", 'VIREMENT'::"text", 'CHORUS_PRO'::"text", 'AVOIR'::"text"]))),
    CONSTRAINT "factures_reglement_avoir_coherent" CHECK ((("mode_paiement" IS DISTINCT FROM 'AVOIR'::"text") OR (("type_document" = 'FACTURE'::"text") AND (NOT ("statut" IS DISTINCT FROM 'PAYEE'::"text")) AND ("date_paiement" IS NOT NULL) AND ("montant_ttc" > (0)::numeric) AND ("montant_avoirs_imputes" = "montant_ttc") AND ("stripe_invoice_id" IS NULL) AND ("stripe_payment_intent_id" IS NULL) AND ("stripe_hosted_url" IS NULL) AND ("virement_reference" IS NULL)))),
    CONSTRAINT "factures_statut_check" CHECK (("statut" = ANY (ARRAY['BROUILLON'::"text", 'EMISE'::"text", 'VIREMENT_DECLARE'::"text", 'PAYEE'::"text", 'EN_RETARD'::"text", 'ANNULEE'::"text", 'REMPLACEE'::"text", 'ERREUR_GENERATION'::"text"]))),
    CONSTRAINT "factures_type_document_check" CHECK (("type_document" = ANY (ARRAY['FACTURE'::"text", 'AVOIR'::"text", 'FACTURE_COMPLEMENTAIRE'::"text"])))
);

ALTER TABLE ONLY "public"."factures"
    ADD CONSTRAINT "factures_pkey" PRIMARY KEY ("id");

CREATE TABLE IF NOT EXISTS "public"."favoris_etab_soignant" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "etablissement_id" "uuid" NOT NULL,
    "soignant_id" "uuid" NOT NULL,
    "cree_le" timestamp with time zone DEFAULT "now"()
);

ALTER TABLE ONLY "public"."favoris_etab_soignant"
    ADD CONSTRAINT "favoris_pkey" PRIMARY KEY ("id");

CREATE TABLE IF NOT EXISTS "public"."file_revue_manuelle" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "type_entite" "text" NOT NULL,
    "id_entite" "uuid" NOT NULL,
    "service_en_echec" "text" NOT NULL,
    "motif_echec" "text",
    "donnees_originales" "jsonb",
    "statut" "text" DEFAULT 'EN_ATTENTE'::"text",
    "priorite" integer DEFAULT 1,
    "assigne_a" "uuid",
    "notes_resolution" "text",
    "cree_le" timestamp with time zone DEFAULT "now"(),
    "revu_le" timestamp with time zone,
    "resolu_le" timestamp with time zone,
    "expire_le" timestamp with time zone DEFAULT ("now"() + '24:00:00'::interval),
    CONSTRAINT "file_revue_manuelle_priorite_check" CHECK ((("priorite" >= 1) AND ("priorite" <= 5))),
    CONSTRAINT "file_revue_manuelle_statut_check" CHECK (("statut" = ANY (ARRAY['EN_ATTENTE'::"text", 'EN_COURS_REVUE'::"text", 'RESOLU_AUTO'::"text", 'RESOLU_MANUELLEMENT'::"text", 'ESCALADE'::"text", 'EXPIRE'::"text"]))),
    CONSTRAINT "file_revue_manuelle_type_entite_check" CHECK (("type_entite" = ANY (ARRAY['VERIFICATION_SOIGNANT'::"text", 'SIGNATURE_MISSION'::"text", 'PAIEMENT'::"text", 'TELEVERSEMENT_DOCUMENT'::"text", 'ALERTE_FRAUDE'::"text", 'SOIGNANT'::"text", 'COHERENCE_IDENTITE'::"text", 'ETABLISSEMENT'::"text"])))
);

ALTER TABLE ONLY "public"."file_revue_manuelle"
    ADD CONSTRAINT "file_revue_manuelle_pkey" PRIMARY KEY ("id");

CREATE TABLE IF NOT EXISTS "public"."filtres_sauvegardes" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "utilisateur_id" "uuid" NOT NULL,
    "nom" "text" NOT NULL,
    "audience" "public"."filtre_audience" NOT NULL,
    "filtres" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "alerte_active" boolean DEFAULT false NOT NULL,
    "frequence_alerte" "public"."filtre_frequence_alerte" DEFAULT 'QUOTIDIENNE'::"public"."filtre_frequence_alerte" NOT NULL,
    "dernier_check_le" timestamp with time zone DEFAULT "now"() NOT NULL,
    "nb_resultats_dernier_check" integer DEFAULT 0 NOT NULL,
    "cree_le" timestamp with time zone DEFAULT "now"() NOT NULL,
    "mis_a_jour_le" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "filtres_sauvegardes_nom_check" CHECK ((("length"("nom") >= 1) AND ("length"("nom") <= 100)))
);

ALTER TABLE ONLY "public"."filtres_sauvegardes"
    ADD CONSTRAINT "filtres_sauvegardes_pkey" PRIMARY KEY ("id");

CREATE TABLE IF NOT EXISTS "public"."heures_externes" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "soignant_id" "uuid" NOT NULL,
    "employeur_nom" "text" NOT NULL,
    "employeur_type" "text",
    "date_debut" "date" NOT NULL,
    "date_fin" "date" NOT NULL,
    "heures_declarees" numeric(10,2) NOT NULL,
    "document_id" "uuid",
    "type_preuve" "text",
    "statut" "text" DEFAULT 'EN_ATTENTE'::"text",
    "validee_par" "uuid",
    "validee_le" timestamp with time zone,
    "motif_rejet" "text",
    "cree_le" timestamp with time zone DEFAULT "now"(),
    "modifie_le" timestamp with time zone DEFAULT "now"(),
    CONSTRAINT "heures_externes_statut_check" CHECK (("statut" = ANY (ARRAY['EN_ATTENTE'::"text", 'VALIDEE'::"text", 'REJETEE'::"text", 'VERIFICATION_EN_COURS'::"text"]))),
    CONSTRAINT "heures_externes_type_preuve_check" CHECK (("type_preuve" = ANY (ARRAY['BULLETIN_PAIE'::"text", 'ATTESTATION_EMPLOYEUR'::"text", 'CERTIFICAT_TRAVAIL'::"text", 'RELEVE_HEURES'::"text", 'AUTRE'::"text"])))
);

ALTER TABLE ONLY "public"."heures_externes"
    ADD CONSTRAINT "heures_externes_pkey" PRIMARY KEY ("id");

CREATE TABLE IF NOT EXISTS "public"."heures_externes_soignants" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "soignant_id" "uuid" NOT NULL,
    "etablissement_nom" "text" NOT NULL,
    "etablissement_type" "text",
    "date_debut" "date" NOT NULL,
    "date_fin" "date" NOT NULL,
    "heures_declarees" integer NOT NULL,
    "attestation_url" "text",
    "attestation_nom_fichier" "text",
    "statut_validation" "text" DEFAULT 'EN_ATTENTE'::"text",
    "commentaire_validation" "text",
    "valide_par" "uuid",
    "valide_le" timestamp with time zone,
    "cree_le" timestamp with time zone DEFAULT "now"(),
    "mis_a_jour_le" timestamp with time zone DEFAULT "now"(),
    "heures_extraites_ia" integer,
    "resultat_ia" "jsonb",
    "coherence_ia" boolean,
    "verifie_ia_le" timestamp with time zone,
    "version_source" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "empreinte_preuve_sha256" "text",
    "source_validation_serveur" "text",
    "empreinte_snapshot_source" "text",
    CONSTRAINT "heures_externes_soignants_check" CHECK (("date_fin" >= "date_debut")),
    CONSTRAINT "heures_externes_soignants_heures_declarees_check" CHECK ((("heures_declarees" > 0) AND ("heures_declarees" <= 10000))),
    CONSTRAINT "heures_externes_soignants_statut_validation_check" CHECK (("statut_validation" = ANY (ARRAY['EN_ATTENTE'::"text", 'VALIDE'::"text", 'REJETE'::"text"])))
);

ALTER TABLE ONLY "public"."heures_externes_soignants"
    ADD CONSTRAINT "heures_externes_soignants_pkey" PRIMARY KEY ("id");

CREATE TABLE IF NOT EXISTS "public"."journaux_audit" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "acteur_id" "uuid",
    "type_acteur" "text" NOT NULL,
    "ip_acteur" "inet",
    "navigateur_acteur" "text",
    "action" "text" NOT NULL,
    "type_ressource" "text",
    "id_ressource" "uuid",
    "cle_s3_ressource" "text",
    "details" "jsonb",
    "cree_le" timestamp with time zone DEFAULT "now"(),
    CONSTRAINT "journaux_audit_action_check" CHECK (("action" = ANY (ARRAY['ANNULATION_EMPECHEMENT_IMPERIEUX'::"text", 'INSCRIPTION'::"text", 'CONNEXION'::"text", 'DECONNEXION'::"text", 'MODIFICATION_PROFIL'::"text", 'SUPPRESSION_COMPTE'::"text", 'UPLOAD_DOCUMENT'::"text", 'TELECHARGEMENT_DOCUMENT'::"text", 'VERIFICATION_DOCUMENT'::"text", 'VERIFICATION_RPPS'::"text", 'CREATION_MISSION'::"text", 'MODIFICATION_MISSION'::"text", 'ANNULATION_MISSION'::"text", 'CANDIDATURE'::"text", 'ASSIGNATION'::"text", 'POINTAGE'::"text", 'SIGNATURE_CONTRAT'::"text", 'EVALUATION'::"text", 'PAIEMENT'::"text", 'FACTURATION'::"text", 'DONNEES_PERSO_CONSULTATION'::"text", 'DONNEES_PERSO_EXPORT'::"text", 'DONNEES_PERSO_SUPPRESSION'::"text", 'ADMIN_ACTION'::"text", 'SYSTEM'::"text", 'RIB_CONSULTE'::"text", 'RIB_PARTAGE'::"text", 'CONTRAT_SIGNE'::"text", 'DOCUMENT_CONSULTATION'::"text", 'DOCUMENT_TELEVERSEMENT'::"text", 'DONNEES_PERSO_MODIFICATION'::"text", 'EXPORT_RH_PAIE'::"text", 'FINANCE_FACTURE_PAYEE'::"text", 'MISSION_ASSIGNATION'::"text", 'MISSION_CREATION'::"text", 'RGPD_EXPORT_DONNEES'::"text", 'RGPD_SUPPRESSION_COMPTE'::"text", 'RGPD_SUPPRESSION_COMPTE_ETABLISSEMENT'::"text", 'DEGEL_APPLIED'::"text", 'OVERRIDE_CHAMP_POST_GEL'::"text", 'GEL_APPLIED'::"text", 'OVERRIDE_ANTI_SEED'::"text", 'CONNECT_METADATA_MANQUANTE'::"text", 'DOCUMENT_VERIFICATION_AUTO'::"text", 'FACTURE_COMMISSION_PAYEE_SKIP_ANOMALIE'::"text", 'FACTURE_HONORAIRES_PAYEE_SKIP_ANOMALIE'::"text", 'FINANCE_CHARGE_EXPIRED'::"text", 'FINANCE_CHARGE_FAILED'::"text", 'FINANCE_CHARGE_PENDING'::"text", 'FINANCE_CHARGE_REFUNDED'::"text", 'FINANCE_DISPUTE_CLOSE'::"text", 'FINANCE_DISPUTE_OUVERTE'::"text", 'FINANCE_PAYOUT_CANCELED'::"text", 'FINANCE_PAYOUT_CREATED'::"text", 'FINANCE_PAYOUT_FAILED'::"text", 'FINANCE_PAYOUT_PAID'::"text", 'FINANCE_SEPA_CAPTURE'::"text", 'FINANCE_TRANSFER_CONNECT'::"text", 'FINANCE_TRANSFER_CREATED'::"text", 'FINANCE_TRANSFER_FAILED'::"text", 'FINANCE_TRANSFER_REVERSED'::"text", 'FINANCE_TRANSFER_UPDATED'::"text", 'STRIPE_CHECKOUT_ORPHANED_RECOVERED'::"text", 'STRIPE_CONNECT_ACCOUNT_DELETED'::"text", 'ATTESTATION_SANTE_SIGNEE'::"text", 'EXCLUSION_CREEE'::"text", 'EXCLUSION_SUPPRIMEE'::"text", 'FACTURE_GENEREE'::"text", 'MISSION_ANNULATION_SERIE'::"text", 'MISSION_MODIFICATION'::"text", 'PAIEMENT_SOIGNANT_DECLARE_ETAB'::"text", 'RECLAMATION_CREEE'::"text", 'ADMIN_CONSULTATION_ETABLISSEMENT'::"text", 'ADMIN_CONSULTATION_SOIGNANT'::"text", 'DOCUMENT_SUPPRESSION'::"text", 'HEURES_EXTERNES_DECLAREES'::"text", 'MISSION_ANNULATION'::"text", 'NOTE_HONORAIRES_GENEREE'::"text", 'PRESENCE_CONTESTATION'::"text", 'PRESENCE_POINTAGE_ARRIVEE'::"text", 'PRESENCE_VALIDATION'::"text", 'PRESENCE_VALIDATION_LOT'::"text", 'RGPD_CONSENTEMENT_DONNE'::"text", 'PAIEMENT_MONTANT_ECART'::"text", 'FACTURE_COMMISSION_CREATED_VIA_STRIPE'::"text", 'TAUX_COMMISSION_MODIFIE'::"text", 'LITIGE_GEL_SCOPE_MODIFIE'::"text", 'PREFERENCE_NOTIFICATION_MODIFIEE'::"text", 'NOTIFICATION_SKIPPED'::"text", 'SERIE_EMAIL_ENVOYE'::"text", 'SERIE_EMAIL_SKIPPED'::"text", 'FILTRE_CREE'::"text", 'FILTRE_MODIFIE'::"text", 'FILTRE_SUPPRIME'::"text", 'ALERTE_ACTIVEE'::"text", 'ALERTE_DESACTIVEE'::"text", 'ALERTE_ENVOYEE'::"text", 'POOL_URGENCE_NOTIFICATIONS_ENVOYEES'::"text", 'POOL_URGENCE_ACCEPTATION_RAPIDE'::"text", 'POOL_URGENCE_VALIDATION_ETAB'::"text", 'POOL_URGENCE_REFUS_ETAB'::"text", 'POOL_URGENCE_SMS_TOGGLE'::"text", 'FAVORI_AJOUTE'::"text", 'FAVORI_RETIRE'::"text", 'SCORE_FIABILITE_PENALITE_LITIGE'::"text", 'PARRAINAGE_ETAB_APPLIQUE'::"text", 'PARRAINAGE_ETAB_VALIDE'::"text", 'CREDIT_PARRAINAGE_CREE'::"text", 'CREDIT_PARRAINAGE_APPLIQUE'::"text", 'PARRAINAGE_ETAB_ANOMALIE'::"text", 'PARRAINAGE_SOIGNANT_FILLEUL_ACTIF'::"text", 'PARRAINAGE_SOIGNANT_SEUIL_ATTEINT'::"text", 'PARRAINAGE_SOIGNANT_PRIME_VERSEE'::"text", 'PARRAINAGE_SOIGNANT_FRAUDE'::"text", 'INSCRIPTION_LISTE_ATTENTE_PREVOYANCE'::"text", 'SCORE_RECALCULE_V2'::"text", 'IBAN_RENSEIGNE'::"text", 'IBAN_MODIFIE'::"text", 'AVOIR_REMBOURSEMENT_CONFIRME'::"text", 'ETABLISSEMENT_MODIFICATION'::"text", 'LITIGE_ACCORD_CLOTURE'::"text", 'LITIGE_AUTO_CREATION'::"text", 'LITIGE_CLOTURE_AMIABLE'::"text", 'LITIGE_CREATION'::"text", 'LITIGE_ESCALADE_AUTO'::"text", 'LITIGE_FORCE_CREATION'::"text", 'LITIGE_OUVERTURE'::"text", 'LITIGE_OUVERTURE_LEGACY'::"text", 'LITIGE_RECATEGORISATION_LEGACY'::"text", 'LITIGE_REPONSE'::"text", 'LITIGE_RESOLUTION'::"text", 'PRESENCE_ALERTE_FRAUDE'::"text", 'RGPD_SUPPRESSION_DONNEES'::"text", 'TVA_MODIFICATION'::"text", 'API_KEY_CREEE'::"text", 'API_KEY_REVOQUEE'::"text", 'API_KEY_SUPPRIMEE'::"text", 'FACTURE_MARQUEE_EN_RETARD'::"text", 'HEURES_EXTERNES_VALIDATION_MANUELLE'::"text", 'MISSION_ANNULEE_PAR_SOIGNANT'::"text", 'MISSION_ANNULEE_PAR_ETABLISSEMENT'::"text", 'MISSION_LITIGE'::"text", 'MISSION_TYPE_CONTRAT_MODIFIE'::"text", 'MODERATION_DOCUMENT'::"text", 'COHERENCE_IDENTITE_VERIFIEE'::"text", 'MODERATION_EVALUATION'::"text", 'COHERENCE_DOCUMENTS_ALERTE'::"text", 'ESCROW_INITIE'::"text", 'ESCROW_DEBIT_INITIE'::"text", 'ESCROW_DEBITE'::"text", 'ESCROW_ETAB_GELE'::"text", 'ESCROW_ETAB_DEGELE'::"text", 'ESCROW_REMBOURSEMENT_ENFILE'::"text", 'ESCROW_REMBOURSE'::"text", 'ESCROW_DISPONIBLE'::"text", 'ESCROW_RELEASE_PAYE'::"text", 'ESCROW_RELEASE_ATTENTE_FONDS'::"text", 'PRESENCE_RELANCE_VALIDATION'::"text", 'SUSPENSION_COMPTE'::"text", 'REACTIVATION_COMPTE'::"text"]))),
    CONSTRAINT "journaux_audit_type_acteur_check" CHECK (("type_acteur" = ANY (ARRAY['SOIGNANT'::"text", 'ADMIN_ETABLISSEMENT'::"text", 'ADMIN_PLATEFORME'::"text", 'ADMIN_GROUPE'::"text", 'SYSTEME'::"text", 'SERVICE_API'::"text", 'ADMIN'::"text", 'ETABLISSEMENT'::"text", 'SYSTEM'::"text", 'DEPRECATED_CALLER'::"text"])))
);

ALTER TABLE ONLY "public"."journaux_audit"
    ADD CONSTRAINT "journaux_audit_pkey" PRIMARY KEY ("id");

CREATE TABLE IF NOT EXISTS "public"."litiges" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "presence_id" "uuid",
    "mission_id" "uuid" NOT NULL,
    "soignant_id" "uuid" NOT NULL,
    "etablissement_id" "uuid" NOT NULL,
    "initie_par" "text" NOT NULL,
    "motif" "text" NOT NULL,
    "reponse" "text",
    "statut" "text" DEFAULT 'OUVERT'::"text",
    "resolu_par" "uuid",
    "resolution" "text",
    "cree_le" timestamp with time zone DEFAULT "now"(),
    "resolu_le" timestamp with time zone,
    "accord_soignant" boolean DEFAULT false,
    "accord_etablissement" boolean DEFAULT false,
    "accord_soignant_le" timestamp with time zone,
    "accord_etablissement_le" timestamp with time zone,
    "paiement_soignant_id" "uuid",
    "type_litige" "public"."type_litige" DEFAULT 'AUTRE'::"public"."type_litige" NOT NULL,
    "categorie_litige" "public"."categorie_litige" DEFAULT 'AUTRE'::"public"."categorie_litige" NOT NULL,
    "facture_id" "uuid",
    "est_informatif" boolean DEFAULT false NOT NULL,
    "type_legacy" boolean DEFAULT false NOT NULL,
    "montant_tresorerie_bloquee" numeric(12,2),
    "derniers_rappels_envoyes" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "escalade_auto_le" timestamp with time zone,
    "escalade_auto_motif" "text",
    "gel_facture_scope" "text" DEFAULT 'MISSION_ENTIERE'::"text" NOT NULL,
    "periode_debut" "date",
    "periode_fin" "date",
    "payload_modifications" "jsonb",
    "modifications_executees" boolean DEFAULT false NOT NULL,
    "modifications_executees_a" timestamp with time zone,
    "modifications_executees_par" "uuid",
    CONSTRAINT "litiges_gel_facture_scope_check" CHECK (("gel_facture_scope" = ANY (ARRAY['MISSION_ENTIERE'::"text", 'FACTURE_UNIQUE'::"text", 'AUCUN'::"text", 'PERIODE_LITIGIEUSE'::"text"]))),
    CONSTRAINT "litiges_initie_par_check" CHECK (("initie_par" = ANY (ARRAY['SOIGNANT'::"text", 'ETABLISSEMENT'::"text", 'SYSTEME'::"text"]))),
    CONSTRAINT "litiges_statut_check" CHECK (("statut" = ANY (ARRAY['OUVERT'::"text", 'EN_DISCUSSION'::"text", 'EN_MEDIATION'::"text", 'RESOLU_SOIGNANT'::"text", 'RESOLU_ETABLISSEMENT'::"text", 'RESOLU_ADMIN'::"text", 'FERME'::"text", 'MEDIATION_EN_COURS'::"text", 'RESOLU_ACCORD_PARTIES'::"text", 'REVUE_ADMIN'::"text", 'RESOLU_FAVEUR_SOIGNANT'::"text", 'RESOLU_FAVEUR_ETAB'::"text", 'RESOLU_PARTAGE'::"text"])))
);

ALTER TABLE ONLY "public"."litiges"
    ADD CONSTRAINT "litiges_pkey" PRIMARY KEY ("id");

CREATE TABLE IF NOT EXISTS "public"."matrice_modes_exercice" (
    "profession" "text" NOT NULL,
    "categorie_etablissement" "text" NOT NULL,
    "niveau" "text" NOT NULL,
    "source_libelle" "text" NOT NULL,
    "source_force" "text" NOT NULL,
    "source_url" "text",
    "source_url_complementaire" "text",
    CONSTRAINT "matrice_modes_exercice_categorie_etablissement_check" CHECK (("categorie_etablissement" = ANY (ARRAY['cabinet_liberal'::"text", 'prive'::"text", 'centre_sante'::"text", 'public'::"text"]))),
    CONSTRAINT "matrice_modes_exercice_niveau_check" CHECK (("niveau" = ANY (ARRAY['AUTORISE'::"text", 'NON_PROPOSE'::"text", 'BLOQUE'::"text"]))),
    CONSTRAINT "matrice_modes_exercice_source_force_check" CHECK (("source_force" = ANY (ARRAY['JUGE'::"text", 'DOCTRINE'::"text", 'LEGAL'::"text", 'CONFORMITE_JOLENE'::"text"])))
);

ALTER TABLE ONLY "public"."matrice_modes_exercice"
    ADD CONSTRAINT "matrice_modes_exercice_pkey" PRIMARY KEY ("profession", "categorie_etablissement");

CREATE TABLE IF NOT EXISTS "public"."membres_etablissement" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "etablissement_id" "uuid" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "role" "text" NOT NULL,
    "invite_par" "uuid",
    "invite_le" timestamp with time zone,
    "accepte_le" timestamp with time zone DEFAULT "now"() NOT NULL,
    "actif" boolean DEFAULT true NOT NULL,
    "cree_le" timestamp with time zone DEFAULT "now"() NOT NULL,
    "maj_le" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "membres_etablissement_role_check" CHECK (("role" = ANY (ARRAY['PROPRIETAIRE'::"text", 'ADMIN_GROUPE'::"text", 'RH'::"text", 'POINTAGE_ONLY'::"text", 'LECTURE_SEULE'::"text"])))
);

ALTER TABLE ONLY "public"."membres_etablissement"
    ADD CONSTRAINT "membres_etablissement_pkey" PRIMARY KEY ("id");

CREATE TABLE IF NOT EXISTS "public"."mission_creneaux" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "mission_id" "uuid" NOT NULL,
    "debut" timestamp with time zone NOT NULL,
    "fin" timestamp with time zone,
    "est_pause" boolean DEFAULT false NOT NULL,
    "type_pause" "text",
    "ordre" smallint DEFAULT 1 NOT NULL,
    "cree_le" timestamp with time zone DEFAULT "now"() NOT NULL,
    "modifie_le" timestamp with time zone DEFAULT "now"() NOT NULL,
    "type_creneau" "text" DEFAULT 'PREVISIONNEL'::"text" NOT NULL,
    CONSTRAINT "chk_fin_previsionnel" CHECK ((("type_creneau" = 'EFFECTIF'::"text") OR ("fin" IS NOT NULL))),
    CONSTRAINT "chk_type_creneau" CHECK (("type_creneau" = ANY (ARRAY['PREVISIONNEL'::"text", 'EFFECTIF'::"text"]))),
    CONSTRAINT "ck_creneau_coherent" CHECK ((("fin" IS NULL) OR ("fin" > "debut"))),
    CONSTRAINT "ck_creneau_max_24h" CHECK ((EXTRACT(epoch FROM ("fin" - "debut")) <= (86400)::numeric)),
    CONSTRAINT "ck_type_pause_coherent" CHECK (((("est_pause" = false) AND ("type_pause" IS NULL)) OR ("est_pause" = true)))
);

ALTER TABLE ONLY "public"."mission_creneaux"
    ADD CONSTRAINT "mission_creneaux_pkey" PRIMARY KEY ("id");

CREATE TABLE IF NOT EXISTS "public"."missions" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "etablissement_id" "uuid" NOT NULL,
    "intitule" "text" NOT NULL,
    "description" "text",
    "profession_requise" "public"."type_profession" NOT NULL,
    "service" "text",
    "debut_le" timestamp with time zone NOT NULL,
    "fin_le" timestamp with time zone NOT NULL,
    "duree_heures" numeric(7,2),
    "taux_horaire_base" numeric(8,2) NOT NULL,
    "taux_rist_plafonne" numeric(8,2),
    "rist_plafond_applique" boolean DEFAULT false,
    "heures_nuit" numeric(5,2) DEFAULT 0,
    "heures_dimanche" numeric(5,2) DEFAULT 0,
    "heures_ferie" numeric(5,2) DEFAULT 0,
    "montant_majoration_nuit" numeric(8,2) DEFAULT 0,
    "montant_majoration_dimanche" numeric(8,2) DEFAULT 0,
    "montant_majoration_ferie" numeric(8,2) DEFAULT 0,
    "taux_ifm" numeric(5,4) DEFAULT 0.10,
    "taux_icp" numeric(5,4) DEFAULT 0.10,
    "montant_ifm" numeric(8,2) DEFAULT 0,
    "montant_icp" numeric(8,2) DEFAULT 0,
    "total_brut" numeric(10,2) DEFAULT 0,
    "net_a_payer" numeric(10,2) DEFAULT 0,
    "est_urgente" boolean DEFAULT false,
    "niveau_urgence" integer DEFAULT 0,
    "statut" "public"."statut_mission" DEFAULT 'OUVERTE'::"public"."statut_mission",
    "soignant_assigne_id" "uuid",
    "cree_le" timestamp with time zone DEFAULT "now"(),
    "modifie_le" timestamp with time zone DEFAULT "now"(),
    "taux_commission" numeric(5,2) DEFAULT 15.00,
    "montant_commission_ht" numeric(10,2),
    "montant_commission_tva" numeric(10,2),
    "montant_commission_ttc" numeric(10,2),
    "commission_facturee" boolean DEFAULT false,
    "facture_id" "uuid",
    "type_paiement_soignant" "text" DEFAULT 'BULLETIN_PAIE'::"text",
    "numero_note_honoraires" "text",
    "code_arrivee" "text",
    "code_depart" "text",
    "net_estime" numeric,
    "mode_attribution" "text" DEFAULT 'PREMIER_ARRIVE'::"text",
    "annulee_le" timestamp with time zone,
    "annulee_par" "uuid",
    "terminee_le" timestamp with time zone,
    "motif_annulation" "text",
    "serie_id" "uuid",
    "type_contrat_recherche" "text" DEFAULT 'TOUS'::"text" NOT NULL,
    "stripe_payment_intent_id" "text",
    "stripe_transfer_id" "text",
    "mode_paiement_soignant" "text" DEFAULT 'DIRECT'::"text",
    "choix_contrat_soignant" "text",
    "nb_creneaux" smallint DEFAULT 0 NOT NULL,
    "taux_horaire_base_fige" numeric,
    "taux_majoration_nuit_fige" numeric,
    "taux_majoration_dimanche_fige" numeric,
    "taux_majoration_ferie_fige" numeric,
    "heure_debut_nuit_fige" time without time zone,
    "heure_fin_nuit_fige" time without time zone,
    "taux_commission_fige" numeric,
    "fige_le" timestamp with time zone,
    "debut_effectif" timestamp with time zone,
    "fin_effective" timestamp with time zone,
    "duree_heures_effective" numeric,
    "code_pointage_actif" "text",
    "code_pointage_hmac" "text",
    "prochain_type_scan" "text" DEFAULT 'OUVERTURE'::"text",
    "nb_scans" smallint DEFAULT 0,
    "regularisation_sociale_requise" boolean DEFAULT false NOT NULL,
    "commission_a_recalculer" boolean DEFAULT false NOT NULL,
    "type_contrat_applique" "public"."type_contrat_applique_enum",
    "relance_paiement_1_le" timestamp with time zone,
    "relance_paiement_2_le" timestamp with time zone,
    "specialite_medicale_requise" "text",
    "accepte_non_specialises" boolean DEFAULT true,
    "strategie_facturation" "public"."strategie_facturation" DEFAULT 'FINALE_UNIQUE'::"public"."strategie_facturation" NOT NULL,
    "absence_sans_prevenir" boolean DEFAULT false NOT NULL,
    "est_asap" boolean DEFAULT false NOT NULL,
    "relances_sans_candidat" integer DEFAULT 0 NOT NULL,
    "derniere_relance_sans_candidat_le" timestamp with time zone,
    "boostee_le" timestamp with time zone,
    "montant_boost_ht" numeric,
    "garantie_remplacement" boolean DEFAULT false NOT NULL,
    "presence_confirmee_le" timestamp with time zone,
    "remplacement_de_mission_id" "uuid",
    "est_arret_maladie" boolean DEFAULT false NOT NULL,
    "arret_maladie_declare_le" timestamp with time zone,
    "mode_remuneration" "text" DEFAULT 'TAUX_HORAIRE'::"text" NOT NULL,
    "retrocession_pct" numeric,
    "montant_honoraires_bruts" numeric,
    "justificatif_honoraires_cle" "text",
    "honoraires_confirmes_le" timestamp with time zone,
    "derniere_relance_candidatures_le" timestamp with time zone,
    "mission_source" "text",
    "nature_tva_prestation" "text",
    "nature_tva_declaree_par" "uuid",
    "nature_tva_declaree_le" timestamp with time zone,
    "nature_tva_confirmee_soignant" "text",
    "nature_tva_confirmee_par" "uuid",
    "nature_tva_confirmee_le" timestamp with time zone,
    "statut_validation_tva" "text" DEFAULT 'NON_REQUISE'::"text" NOT NULL,
    "revue_tva_motif" "text",
    "revue_tva_resolue_par" "uuid",
    "revue_tva_resolue_le" timestamp with time zone,
    CONSTRAINT "chk_duree_positive" CHECK ((("duree_heures" IS NULL) OR (("duree_heures" >= (0)::numeric) AND ("duree_heures" <= (17568)::numeric)))),
    CONSTRAINT "chk_missions_dates" CHECK (("debut_le" < "fin_le")),
    CONSTRAINT "chk_prochain_type_scan" CHECK (("prochain_type_scan" = ANY (ARRAY['OUVERTURE'::"text", 'FERMETURE'::"text"]))),
    CONSTRAINT "chk_taux_commission" CHECK ((("taux_commission" IS NULL) OR (("taux_commission" >= (0)::numeric) AND ("taux_commission" <= (30)::numeric)))),
    CONSTRAINT "chk_taux_horaire_raisonnable" CHECK ((("taux_horaire_base" = (0)::numeric) OR (("taux_horaire_base" > (0)::numeric) AND ("taux_horaire_base" <= (1000)::numeric)))),
    CONSTRAINT "chk_type_contrat_recherche" CHECK (("type_contrat_recherche" = ANY (ARRAY['TOUS'::"text", 'SALARIE'::"text", 'LIBERAL'::"text"]))),
    CONSTRAINT "ck_max_732_creneaux" CHECK ((("nb_creneaux" >= 0) AND ("nb_creneaux" <= 732))),
    CONSTRAINT "missions_mission_source_check" CHECK (("mission_source" = ANY (ARRAY['SWIPE'::"text", 'CANDIDATURE'::"text", 'REBOOK'::"text", 'PROPOSITION_DIRECTE'::"text", 'REMPLACEMENT'::"text", 'REPUBLICATION'::"text"]))),
    CONSTRAINT "missions_mode_attribution_check" CHECK (("mode_attribution" = ANY (ARRAY['PREMIER_ARRIVE'::"text", 'CANDIDATURE'::"text"]))),
    CONSTRAINT "missions_mode_paiement_soignant_check" CHECK (("mode_paiement_soignant" = ANY (ARRAY['DIRECT'::"text", 'STRIPE_CONNECT'::"text", 'VIREMENT'::"text"]))),
    CONSTRAINT "missions_mode_remuneration_check" CHECK (("mode_remuneration" = ANY (ARRAY['TAUX_HORAIRE'::"text", 'RETROCESSION'::"text"]))),
    CONSTRAINT "missions_nature_tva_confirmee_soignant_check" CHECK ((("nature_tva_confirmee_soignant" IS NULL) OR ("nature_tva_confirmee_soignant" = ANY (ARRAY['SOIN_THERAPEUTIQUE_EXONERE'::"text", 'PRESTATION_TAXABLE'::"text"])))),
    CONSTRAINT "missions_nature_tva_prestation_check" CHECK ((("nature_tva_prestation" IS NULL) OR ("nature_tva_prestation" = ANY (ARRAY['SOIN_THERAPEUTIQUE_EXONERE'::"text", 'PRESTATION_TAXABLE'::"text"])))),
    CONSTRAINT "missions_niveau_urgence_check" CHECK ((("niveau_urgence" >= 0) AND ("niveau_urgence" <= 3))),
    CONSTRAINT "missions_retrocession_pct_check" CHECK ((("retrocession_pct" IS NULL) OR (("retrocession_pct" > (0)::numeric) AND ("retrocession_pct" <= (100)::numeric)))),
    CONSTRAINT "missions_statut_validation_tva_check" CHECK (("statut_validation_tva" = ANY (ARRAY['NON_REQUISE'::"text", 'A_CONFIRMER'::"text", 'CONFIRMEE'::"text", 'A_REVOIR'::"text"]))),
    CONSTRAINT "missions_type_paiement_soignant_check" CHECK (("type_paiement_soignant" = ANY (ARRAY['BULLETIN_PAIE'::"text", 'NOTE_HONORAIRES'::"text"])))
);

ALTER TABLE ONLY "public"."missions"
    ADD CONSTRAINT "missions_pkey" PRIMARY KEY ("id");

CREATE TABLE IF NOT EXISTS "public"."missions_sauvegardees" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "soignant_id" "uuid" NOT NULL,
    "mission_id" "uuid" NOT NULL,
    "cree_le" timestamp with time zone DEFAULT "now"() NOT NULL,
    "notifie_expiration" boolean DEFAULT false NOT NULL
);

ALTER TABLE ONLY "public"."missions_sauvegardees"
    ADD CONSTRAINT "missions_sauvegardees_pkey" PRIMARY KEY ("id");

CREATE TABLE IF NOT EXISTS "public"."notations_missions" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "mission_id" "uuid" NOT NULL,
    "notateur_id" "uuid",
    "note_id" "uuid" NOT NULL,
    "sens" "public"."sens_notation" NOT NULL,
    "critere_1" integer NOT NULL,
    "critere_2" integer NOT NULL,
    "critere_3" integer NOT NULL,
    "critere_4" integer NOT NULL,
    "commentaire" "text",
    "signale" boolean DEFAULT false NOT NULL,
    "masque" boolean DEFAULT false NOT NULL,
    "masque_par" "uuid",
    "masque_le" timestamp with time zone,
    "cree_le" timestamp with time zone DEFAULT "now"() NOT NULL,
    "mis_a_jour_le" timestamp with time zone DEFAULT "now"() NOT NULL,
    "notateur_anonymise" boolean DEFAULT false NOT NULL,
    "publie_le" timestamp with time zone,
    CONSTRAINT "notations_missions_auteur_anonymise_check" CHECK ((("notateur_id" IS NOT NULL) OR ("notateur_anonymise" IS TRUE))),
    CONSTRAINT "notations_missions_commentaire_check" CHECK ((("commentaire" IS NULL) OR ("length"("commentaire") <= 2000))),
    CONSTRAINT "notations_missions_critere_1_check" CHECK ((("critere_1" >= 1) AND ("critere_1" <= 5))),
    CONSTRAINT "notations_missions_critere_2_check" CHECK ((("critere_2" >= 1) AND ("critere_2" <= 5))),
    CONSTRAINT "notations_missions_critere_3_check" CHECK ((("critere_3" >= 1) AND ("critere_3" <= 5))),
    CONSTRAINT "notations_missions_critere_4_check" CHECK ((("critere_4" >= 1) AND ("critere_4" <= 5)))
);

ALTER TABLE ONLY "public"."notations_missions"
    ADD CONSTRAINT "notations_missions_pkey" PRIMARY KEY ("id");

CREATE TABLE IF NOT EXISTS "public"."notifications" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "destinataire_id" "uuid" NOT NULL,
    "type_destinataire" "text" NOT NULL,
    "type" "text" NOT NULL,
    "titre" "text" NOT NULL,
    "corps" "text" NOT NULL,
    "lien" "text",
    "type_ressource" "text",
    "id_ressource" "uuid",
    "lue" boolean DEFAULT false,
    "lue_le" timestamp with time zone,
    "push_envoyee" boolean DEFAULT false,
    "push_envoyee_le" timestamp with time zone,
    "email_envoye" boolean DEFAULT false,
    "email_envoye_le" timestamp with time zone,
    "cree_le" timestamp with time zone DEFAULT "now"(),
    CONSTRAINT "notifications_type_check" CHECK (("type" = ANY (ARRAY['CANDIDATURE_ACCEPTEE'::"text", 'CANDIDATURE_REFUSEE'::"text", 'CANDIDATURE_PROPOSEE'::"text", 'CANDIDATURE_RECUE'::"text", 'MISSION_ACCEPTEE'::"text", 'MISSION_ANNULEE'::"text", 'MISSION_TERMINEE'::"text", 'MISSION_URGENTE'::"text", 'MISSION_NON_POURVUE'::"text", 'MISSION_ASSIGNEE'::"text", 'MISSION_A_POURVOIR'::"text", 'CONTRAT_A_SIGNER'::"text", 'CONTRAT_SIGNE'::"text", 'FACTURE_EMISE'::"text", 'FACTURE_PAYEE'::"text", 'DOCUMENT_EXPIRANT'::"text", 'RAPPEL_DOCUMENTS'::"text", 'DOCUMENT_VERIFIE'::"text", 'DOCUMENT_REJETE'::"text", 'MESSAGE_RECU'::"text", 'MESSAGE_ADMIN'::"text", 'POINTAGE_ARRIVEE'::"text", 'POINTAGE_DEPART'::"text", 'EVALUATION_RECUE'::"text", 'PARRAINAGE'::"text", 'CREDIT_PARRAINAGE'::"text", 'PARRAINAGE_PRIME_VERSEE'::"text", 'RAPPEL_MISSION'::"text", 'RAPPEL_CANDIDATURES'::"text", 'POOL_URGENCE'::"text", 'POOL_URGENCE_ACCEPTATION'::"text", 'SYSTEM'::"text", 'LITIGE_OUVERT'::"text", 'LITIGE_REPONSE'::"text", 'LITIGE_RESOLU'::"text", 'LITIGE_MEDIATION'::"text", 'LITIGE_RESOLU_AJUSTE'::"text", 'LITIGE_ESCALADE_ADMIN'::"text", 'LITIGE_MEDIATION_PRIORITAIRE'::"text", 'LITIGE_RAPPEL_J1'::"text", 'LITIGE_RAPPEL_J3'::"text", 'LITIGE_RAPPEL_J5'::"text", 'CHORUS_DEPOSEE'::"text", 'CHORUS_MISE_A_DISPOSITION'::"text", 'CHORUS_PAIEMENT_EN_COURS'::"text", 'CHORUS_PAIEMENT_COMPTABILISE'::"text", 'CHORUS_REJETEE'::"text", 'FAVORI_NOUVELLE_MISSION'::"text", 'AVOIR_EMIS'::"text", 'COMMISSION_AJUSTEE'::"text", 'REMBOURSEMENT_MANUEL_A_FAIRE'::"text", 'REMBOURSEMENT_CONFIRME'::"text", 'MATCHING_SUPER_LIKE'::"text", 'FAVORI_MISSION_EXPIRE'::"text", 'RAPPEL_VALIDATION_PRESENCE'::"text", 'CONTESTATION_PRESENCE'::"text", 'PRESENCE_VALIDEE'::"text"]))),
    CONSTRAINT "notifications_type_destinataire_check" CHECK (("type_destinataire" = ANY (ARRAY['SOIGNANT'::"text", 'ETABLISSEMENT'::"text", 'ADMIN'::"text"])))
);

ALTER TABLE ONLY "public"."notifications"
    ADD CONSTRAINT "notifications_pkey" PRIMARY KEY ("id");

CREATE TABLE IF NOT EXISTS "public"."parcours_inscription" (
    "user_id" "uuid" NOT NULL,
    "type_compte" "text" NOT NULL,
    "donnees" "jsonb" DEFAULT '{}'::"jsonb" NOT NULL,
    "consentement_cgu_le" timestamp with time zone DEFAULT "now"() NOT NULL,
    "consentement_cgv_le" timestamp with time zone,
    "cree_le" timestamp with time zone DEFAULT "now"() NOT NULL,
    "modifie_le" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "parcours_inscription_check" CHECK ((("type_compte" <> 'ETABLISSEMENT'::"text") OR ("consentement_cgv_le" IS NOT NULL))),
    CONSTRAINT "parcours_inscription_donnees_check" CHECK ((("jsonb_typeof"("donnees") = 'object'::"text") AND ("octet_length"(("donnees")::"text") <= 32768))),
    CONSTRAINT "parcours_inscription_type_compte_check" CHECK (("type_compte" = ANY (ARRAY['SOIGNANT'::"text", 'ETABLISSEMENT'::"text"])))
);

ALTER TABLE ONLY "public"."parcours_inscription"
    ADD CONSTRAINT "parcours_inscription_pkey" PRIMARY KEY ("user_id");

CREATE TABLE IF NOT EXISTS "public"."preferences_notifications" (
    "utilisateur_id" "uuid" NOT NULL,
    "canal_email" boolean DEFAULT true NOT NULL,
    "canal_sms" boolean DEFAULT false NOT NULL,
    "canal_push" boolean DEFAULT true NOT NULL,
    "canal_in_app" boolean DEFAULT true NOT NULL,
    "cree_le" timestamp with time zone DEFAULT "now"() NOT NULL,
    "mis_a_jour_le" timestamp with time zone DEFAULT "now"() NOT NULL
);

ALTER TABLE ONLY "public"."preferences_notifications"
    ADD CONSTRAINT "preferences_notifications_pkey" PRIMARY KEY ("utilisateur_id");

CREATE TABLE IF NOT EXISTS "public"."preferences_notifications_par_evenement" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "utilisateur_id" "uuid" NOT NULL,
    "type_evenement" "public"."type_evenement_notification" NOT NULL,
    "canal" "public"."canal_notification" NOT NULL,
    "actif" boolean DEFAULT true NOT NULL,
    "cree_le" timestamp with time zone DEFAULT "now"() NOT NULL,
    "mis_a_jour_le" timestamp with time zone DEFAULT "now"() NOT NULL
);

ALTER TABLE ONLY "public"."preferences_notifications_par_evenement"
    ADD CONSTRAINT "preferences_notifications_par_evenement_pkey" PRIMARY KEY ("id");

CREATE TABLE IF NOT EXISTS "public"."presences" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "mission_id" "uuid" NOT NULL,
    "soignant_id" "uuid" NOT NULL,
    "pointage_arrivee_le" timestamp with time zone,
    "arrivee_lat" numeric(10,7),
    "arrivee_lng" numeric(10,7),
    "arrivee_precision_gps_m" numeric(8,2),
    "arrivee_id_terminal" "text",
    "arrivee_modele_terminal" "text",
    "arrivee_ip" "inet",
    "pointage_depart_le" timestamp with time zone,
    "depart_lat" numeric(10,7),
    "depart_lng" numeric(10,7),
    "depart_precision_gps_m" numeric(8,2),
    "depart_id_terminal" "text",
    "depart_ip" "inet",
    "distance_etablissement_m" numeric(10,2),
    "perimetre_gps_valide" boolean,
    "alerte_teleportation" boolean DEFAULT false,
    "alertes_fraude" "jsonb" DEFAULT '[]'::"jsonb",
    "valide_par_etablissement" boolean DEFAULT false,
    "valide_le" timestamp with time zone,
    "motif_litige" "text",
    "cree_le" timestamp with time zone DEFAULT "now"(),
    "modifie_le" timestamp with time zone DEFAULT "now"(),
    "methode_pointage_arrivee" "text" DEFAULT 'GPS'::"text",
    "methode_pointage_depart" "text" DEFAULT 'GPS'::"text",
    "pause_debut_le" timestamp with time zone,
    "pause_fin_le" timestamp with time zone,
    "duree_pause_min" numeric DEFAULT 0,
    "duree_brute_min" numeric,
    "duree_nette_min" numeric,
    "heures_reelles" numeric,
    "retard_min" numeric DEFAULT 0,
    "depart_anticipe_min" numeric DEFAULT 0,
    "heures_ajustees_litige" numeric(6,2),
    "ajustement_litige_id" "uuid",
    "litige_auto_cree_le" timestamp with time zone,
    "depart_modele_terminal" "text",
    "valide_auto_72h_le" timestamp with time zone,
    "arrivee_mock_detected" boolean DEFAULT false NOT NULL,
    "depart_mock_detected" boolean DEFAULT false NOT NULL,
    "qr_token_arrivee" "text",
    "qr_token_depart" "text",
    "coherence_verifiee_le" timestamp with time zone,
    "coherence_incidents" "jsonb" DEFAULT '[]'::"jsonb",
    CONSTRAINT "chk_methode_arrivee" CHECK ((("methode_pointage_arrivee" IS NULL) OR ("methode_pointage_arrivee" = ANY (ARRAY['GPS'::"text", 'CODE'::"text", 'QR'::"text", 'MANUEL'::"text", 'ADMIN'::"text"])))),
    CONSTRAINT "chk_methode_depart" CHECK ((("methode_pointage_depart" IS NULL) OR ("methode_pointage_depart" = ANY (ARRAY['GPS'::"text", 'CODE'::"text", 'QR'::"text", 'MANUEL'::"text", 'ADMIN'::"text"])))),
    CONSTRAINT "presences_methode_pointage_arrivee_check" CHECK (("methode_pointage_arrivee" = ANY (ARRAY['GPS'::"text", 'CODE'::"text", 'QR'::"text"]))),
    CONSTRAINT "presences_methode_pointage_depart_check" CHECK (("methode_pointage_depart" = ANY (ARRAY['GPS'::"text", 'CODE'::"text", 'QR'::"text"])))
);

ALTER TABLE ONLY "public"."presences"
    ADD CONSTRAINT "presences_pkey" PRIMARY KEY ("id");

CREATE TABLE IF NOT EXISTS "public"."professions_liberal_eligible" (
    "profession" "public"."type_profession" NOT NULL,
    "code_ape" character varying(6) NOT NULL,
    "libelle_urssaf" "text" NOT NULL,
    "plafond_micro" numeric(10,2) DEFAULT 77700.00,
    "ordre_obligatoire" boolean DEFAULT false,
    "nom_ordre" "text"
);

ALTER TABLE ONLY "public"."professions_liberal_eligible"
    ADD CONSTRAINT "professions_liberal_eligible_pkey" PRIMARY KEY ("profession");

CREATE TABLE IF NOT EXISTS "public"."scoring_breakdown" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "soignant_id" "uuid" NOT NULL,
    "score_total" numeric NOT NULL,
    "niveau" "public"."niveau_qualitatif" NOT NULL,
    "en_periode_probatoire" boolean DEFAULT false NOT NULL,
    "notation_etab_soignant_pct" numeric,
    "notation_etab_soignant_poids" numeric,
    "presentisme_pct" numeric,
    "presentisme_poids" numeric,
    "ponctualite_pct" numeric,
    "ponctualite_poids" numeric,
    "reactivite_pct" numeric,
    "reactivite_poids" numeric,
    "anciennete_volume_pct" numeric,
    "anciennete_volume_poids" numeric,
    "notation_soignant_etab_pct" numeric,
    "notation_soignant_etab_poids" numeric,
    "litiges_malus" numeric DEFAULT 0 NOT NULL,
    "absence_sans_prevenir_malus" numeric DEFAULT 0 NOT NULL,
    "bonus_super_actif" numeric DEFAULT 0 NOT NULL,
    "composantes_inactives_json" "jsonb",
    "composantes_actives_count" integer NOT NULL,
    "redistribution_json" "jsonb",
    "raison_recalcul" "text",
    "cree_le" timestamp with time zone DEFAULT "now"() NOT NULL
);

ALTER TABLE ONLY "public"."scoring_breakdown"
    ADD CONSTRAINT "scoring_breakdown_pkey" PRIMARY KEY ("id");

CREATE TABLE IF NOT EXISTS "public"."soignants" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "prenom" "text" NOT NULL,
    "nom" "text" NOT NULL,
    "email" "text" NOT NULL,
    "telephone" character varying(20),
    "date_naissance" "date",
    "profession" "public"."type_profession",
    "numero_rpps" character varying(11),
    "numero_adeli" character varying(9),
    "type_contrat" "public"."type_contrat" DEFAULT 'CDD'::"public"."type_contrat",
    "score_fiabilite" numeric(5,2) DEFAULT 50.00,
    "total_missions_terminees" integer DEFAULT 0,
    "total_missions_annulees" integer DEFAULT 0,
    "total_retards_pointage" integer DEFAULT 0,
    "total_absences" integer DEFAULT 0,
    "heures_cumulees" numeric(10,2) DEFAULT 0,
    "eligible_conversion_3200h" boolean DEFAULT false,
    "prevoyance_inscrit" boolean DEFAULT false,
    "prevoyance_fournisseur" "text",
    "prevoyance_numero_contrat" "text",
    "adresse_lat" numeric(10,7),
    "adresse_lng" numeric(10,7),
    "rayon_deplacement_km" integer DEFAULT 30,
    "tous_documents_valides" boolean DEFAULT false,
    "identite_verifiee" boolean DEFAULT false,
    "diplome_verifie" boolean DEFAULT false,
    "rpps_verifie" boolean DEFAULT false,
    "statut_verification_aria" "public"."statut_verification" DEFAULT 'EN_ATTENTE'::"public"."statut_verification",
    "cree_le" timestamp with time zone DEFAULT "now"(),
    "modifie_le" timestamp with time zone DEFAULT "now"(),
    "derniere_activite_le" timestamp with time zone DEFAULT "now"(),
    "supprime_le" timestamp with time zone,
    "types_contrat_acceptes" "text",
    "numero_secu" character varying(15),
    "siret_liberal" character varying(14),
    "date_passage_liberal" "date",
    "statut_liberal" "text" DEFAULT 'NON_LIBERAL'::"text",
    "code_ape" character varying(6),
    "adresse_rue" "text",
    "adresse_ville" "text",
    "adresse_code_postal" character varying(5),
    "heures_plateforme" numeric(10,2) DEFAULT 0,
    "rpps_profession_api" "text",
    "rpps_nom_api" "text",
    "rpps_verifie_le" timestamp with time zone,
    "consentement_gps" boolean DEFAULT false,
    "consentement_gps_le" timestamp with time zone,
    "assujetti_tva" boolean DEFAULT false,
    "numero_tva" "text",
    "attestation_vaccinations" boolean DEFAULT false,
    "attestation_vaccinations_le" timestamp with time zone,
    "attestation_medecine_travail" boolean DEFAULT false,
    "attestation_medecine_travail_le" timestamp with time zone,
    "attestation_sante_signee_le" timestamp with time zone,
    "code_parrainage" "text",
    "parraine_par" "uuid",
    "avatar_url" "text",
    "premiere_mission_le" timestamp with time zone,
    "disponible_urgence" boolean DEFAULT false,
    "urgence_rayon_km" integer DEFAULT 15,
    "urgence_creneaux" "jsonb" DEFAULT '[]'::"jsonb",
    "total_missions_urgence" integer DEFAULT 0,
    "bio" "text",
    "annees_experience" integer,
    "specialites" "text"[],
    "compteur_notes_honoraires" integer DEFAULT 0,
    "est_cumul_activite" boolean DEFAULT false,
    "attestation_cumul_le" timestamp with time zone,
    "type_exercice" "text" DEFAULT 'SALARIE'::"text",
    "attestation_cumul_activite" boolean DEFAULT false NOT NULL,
    "est_salarie_etablissement" boolean,
    "taux_horaire_minimum" numeric,
    "badge_ambassadeur" boolean DEFAULT false NOT NULL,
    "priorite_missions_urgentes" boolean DEFAULT false NOT NULL,
    "ville_recherche" "text",
    "ville_urgence" "text",
    "stripe_account_id" "text",
    "validation_3200h_statut" "text" DEFAULT 'NON_DEMANDE'::"text",
    "validation_3200h_le" timestamp with time zone,
    "validation_3200h_par" "uuid",
    "iban_last4" "text",
    "rib_partage_le" timestamp with time zone,
    "note_moyenne" numeric(3,2) DEFAULT NULL::numeric,
    "nb_evaluations" integer DEFAULT 0,
    "coherence_identite" "text" DEFAULT 'NON_VERIFIE'::"text",
    "coherence_details" "jsonb",
    "rpps_prenom_api" "text",
    "psc_sub" "text",
    "psc_linked_le" timestamp with time zone,
    "psc_last_login" timestamp with time zone,
    "mandat_facturation_signe" boolean DEFAULT false,
    "mandat_facturation_signe_le" timestamp with time zone,
    "mandat_facturation_version" "text",
    "sms_actif" boolean DEFAULT false,
    "sms_consent_le" timestamp with time zone,
    "specialite_medicale" "text",
    "specialite_code" "text",
    "specialite_source" "text" DEFAULT 'RPPS'::"text",
    "specialite_verifiee" boolean DEFAULT false,
    "specialite_verifiee_le" timestamp with time zone,
    "accepte_missions_generalistes" boolean DEFAULT true,
    "numero_securite_sociale" "text",
    "defacto_opt_in" boolean DEFAULT false NOT NULL,
    "pool_urgence_sms_opt_in" boolean DEFAULT false NOT NULL,
    "total_litiges_perdus" integer DEFAULT 0 NOT NULL,
    "statut_compte" "public"."statut_compte_soignant" DEFAULT 'ACTIF'::"public"."statut_compte_soignant" NOT NULL,
    "niveau" "public"."niveau_qualitatif",
    "en_periode_probatoire" boolean DEFAULT true NOT NULL,
    "score_breakdown_id" "uuid",
    "suspension_raison" "text",
    "suspension_le" timestamp with time zone,
    "nb_absences_sans_prevenir_6_mois" integer DEFAULT 0 NOT NULL,
    "sms_alertes_actives" boolean DEFAULT true,
    "sexe" "text",
    "lieu_naissance_commune" "text",
    "lieu_naissance_departement" "text",
    "pays_naissance" "text" DEFAULT 'France'::"text",
    "nationalite" "text" DEFAULT 'Française'::"text",
    "onboarding_etapes_completees" "jsonb" DEFAULT '[]'::"jsonb" NOT NULL,
    "onboarding_termine_le" timestamp with time zone,
    "telephone_verifie" boolean DEFAULT false NOT NULL,
    "telephone_verifie_le" timestamp with time zone,
    "telephone_en_attente_verification" "text",
    "iban_virement" "text",
    "iban_titulaire" "text",
    "adeli_verifie" boolean DEFAULT false,
    "adeli_verifie_le" timestamp with time zone,
    "adeli_nom_api" "text",
    "adeli_prenom_api" "text",
    "adeli_profession_api" "text",
    "nir_verifie" boolean DEFAULT false NOT NULL,
    "utm_source" "text",
    "utm_medium" "text",
    "utm_campaign" "text",
    "utm_content" "text",
    "utm_term" "text",
    "http_referrer" "text",
    "ref_capture" "text",
    "source_acquisition" "text",
    "preference_contrat_mixte" "text",
    "est_etudiant" boolean DEFAULT false NOT NULL,
    "etudiant_details" "text",
    "scolarite_formation" "text",
    "scolarite_annee_validee" integer,
    "scolarite_profession_autorisee" "public"."type_profession",
    "scolarite_verifiee" boolean DEFAULT false NOT NULL,
    "scolarite_verifiee_le" timestamp with time zone,
    "licence_remplacement_verifiee" boolean DEFAULT false NOT NULL,
    "licence_remplacement_le" timestamp with time zone,
    "licence_remplacement_valide_jusqua" "date",
    "licence_remplacement_specialite" "text",
    "est_compte_test" boolean DEFAULT false NOT NULL,
    "regime_fiscal" "text" DEFAULT 'MICRO_BNC'::"text" NOT NULL,
    "regime_fiscal_confirme" boolean DEFAULT false NOT NULL,
    "siret_liberal_verifie" boolean DEFAULT false NOT NULL,
    "siret_liberal_verifie_le" timestamp with time zone,
    "siret_liberal_raison_sociale" "text",
    "siret_liberal_coherence_identite" boolean,
    "specialite_medicale_declaree" "text",
    "iban_source_document_id" "uuid",
    "iban_verifie_le" timestamp with time zone,
    "iban_titulaire_coherent" boolean DEFAULT false NOT NULL,
    "iban_identite_document_id" "uuid",
    "iban_source_s3_cle" "text",
    "iban_empreinte_sha256" "text",
    "siret_liberal_source_verification" "text",
    "siret_liberal_preuve_siret" character varying(14),
    "siret_liberal_preuve_identite_document_id" "uuid",
    "siret_liberal_preuve_identite_document_modifie_le" timestamp with time zone,
    "siret_liberal_preuve_identite_s3_bucket" "text",
    "siret_liberal_preuve_identite_s3_cle" "text",
    "siret_liberal_preuve_identite_s3_version_id" "text",
    "siret_liberal_preuve_identite_storage_object_id" "uuid",
    "siret_liberal_preuve_identite_storage_updated_at" timestamp with time zone,
    "siret_liberal_preuve_identite_valide_jusqua" "date",
    "siret_liberal_preuve_identite_empreinte_sha256" "text",
    "regime_tva_honoraires" "text",
    "statut_tva_honoraires" "text",
    CONSTRAINT "chk_rayon_raisonnable" CHECK ((("rayon_deplacement_km" >= 1) AND ("rayon_deplacement_km" <= 200))),
    CONSTRAINT "chk_telephone_format" CHECK ((("telephone" IS NULL) OR (("telephone")::"text" ~ '^\+?[0-9\s\-\.]{8,20}$'::"text"))),
    CONSTRAINT "soignants_coherence_identite_check" CHECK (("coherence_identite" = ANY (ARRAY['NON_VERIFIE'::"text", 'COHERENT'::"text", 'INCOHERENT'::"text", 'EN_ATTENTE_REVUE'::"text"]))),
    CONSTRAINT "soignants_iban_provenance_coherente_check" CHECK ((("iban_titulaire_coherent" IS FALSE) OR (("iban_source_document_id" IS NOT NULL) AND ("iban_identite_document_id" IS NOT NULL) AND (NULLIF("iban_source_s3_cle", ''::"text") IS NOT NULL) AND ("iban_empreinte_sha256" ~ '^[0-9a-f]{64}$'::"text") AND ("iban_verifie_le" IS NOT NULL)))),
    CONSTRAINT "soignants_numero_securite_sociale_format" CHECK ((("numero_securite_sociale" IS NULL) OR ("numero_securite_sociale" ~ '^[0-9]{13,15}$'::"text"))),
    CONSTRAINT "soignants_preference_contrat_mixte_check" CHECK (("preference_contrat_mixte" = ANY (ARRAY['SALARIE'::"text", 'LIBERAL'::"text"]))),
    CONSTRAINT "soignants_regime_fiscal_check" CHECK (("regime_fiscal" = ANY (ARRAY['MICRO_BNC'::"text", 'DECLARATION_CONTROLEE'::"text"]))),
    CONSTRAINT "soignants_regime_tva_honoraires_check" CHECK ((("regime_tva_honoraires" IS NULL) OR ("regime_tva_honoraires" = ANY (ARRAY['EXONERE_ART_261_4_1'::"text", 'FRANCHISE_EN_BASE_ART_293_B'::"text", 'ASSUJETTI_TVA'::"text"])))),
    CONSTRAINT "soignants_score_fiabilite_check" CHECK ((("score_fiabilite" >= (0)::numeric) AND ("score_fiabilite" <= (100)::numeric))),
    CONSTRAINT "soignants_sexe_check" CHECK ((("sexe" IS NULL) OR ("sexe" = ANY (ARRAY['M'::"text", 'F'::"text"])))),
    CONSTRAINT "soignants_siret_liberal_preuve_manuelle_complete_check" CHECK ((("siret_liberal_source_verification" IS DISTINCT FROM 'REVUE_MANUELLE_IDENTITE'::"text") OR (("siret_liberal_preuve_siret" IS NOT NULL) AND (("siret_liberal_preuve_siret")::"text" ~ '^[0-9]{14}$'::"text") AND ("siret_liberal_preuve_identite_document_id" IS NOT NULL) AND ("siret_liberal_preuve_identite_document_modifie_le" IS NOT NULL) AND (NOT ("siret_liberal_preuve_identite_s3_bucket" IS DISTINCT FROM 'jolene-documents'::"text")) AND (NULLIF("siret_liberal_preuve_identite_s3_cle", ''::"text") IS NOT NULL) AND ("siret_liberal_preuve_identite_storage_object_id" IS NOT NULL) AND ("siret_liberal_preuve_identite_storage_updated_at" IS NOT NULL) AND ("siret_liberal_preuve_identite_valide_jusqua" IS NOT NULL) AND ("siret_liberal_preuve_identite_empreinte_sha256" IS NOT NULL) AND ("siret_liberal_preuve_identite_empreinte_sha256" ~ '^[0-9a-f]{64}$'::"text")))),
    CONSTRAINT "soignants_siret_liberal_source_verification_check" CHECK ((("siret_liberal_source_verification" IS NULL) OR ("siret_liberal_source_verification" = ANY (ARRAY['REGISTRE_OFFICIEL'::"text", 'REVUE_MANUELLE_IDENTITE'::"text"])))),
    CONSTRAINT "soignants_specialite_source_check" CHECK ((("specialite_source" IS NULL) OR ("specialite_source" = ANY (ARRAY['RPPS'::"text", 'MANUEL'::"text"])))),
    CONSTRAINT "soignants_statut_liberal_check" CHECK (("statut_liberal" = ANY (ARRAY['NON_LIBERAL'::"text", 'EN_COURS'::"text", 'ACTIF'::"text"]))),
    CONSTRAINT "soignants_statut_tva_honoraires_check" CHECK ((("statut_tva_honoraires" IS NULL) OR ("statut_tva_honoraires" = ANY (ARRAY['FRANCHISE_EN_BASE'::"text", 'REDEVABLE_TVA'::"text"])))),
    CONSTRAINT "soignants_type_exercice_check" CHECK (("type_exercice" = ANY (ARRAY['SALARIE'::"text", 'LIBERAL'::"text", 'MIXTE'::"text"]))),
    CONSTRAINT "soignants_validation_3200h_statut_check" CHECK (("validation_3200h_statut" = ANY (ARRAY['NON_DEMANDE'::"text", 'EN_ATTENTE'::"text", 'VALIDEE'::"text", 'REFUSEE'::"text"])))
);

ALTER TABLE ONLY "public"."soignants"
    ADD CONSTRAINT "soignants_pkey" PRIMARY KEY ("id");

CREATE TABLE IF NOT EXISTS "public"."specialites_medicales" (
    "code" "text" NOT NULL,
    "label" "text" NOT NULL,
    "profession_parent" "text" NOT NULL,
    "actif" boolean DEFAULT true,
    "cree_le" timestamp with time zone DEFAULT "now"()
);

ALTER TABLE ONLY "public"."specialites_medicales"
    ADD CONSTRAINT "specialites_medicales_pkey" PRIMARY KEY ("code");

CREATE TABLE IF NOT EXISTS "public"."suivi_conversion_3200h" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "soignant_id" "uuid" NOT NULL,
    "profession_cible_liberal" "text",
    "heures_a_inscription" numeric(10,2) DEFAULT 0,
    "heures_actuelles" numeric(10,2) DEFAULT 0,
    "progression_pourcent" numeric(5,2) GENERATED ALWAYS AS (LEAST(100.0, (("heures_actuelles" / 3200.0) * 100.0))) STORED,
    "jalon_800h_atteint" boolean DEFAULT false,
    "jalon_1600h_atteint" boolean DEFAULT false,
    "jalon_2400h_atteint" boolean DEFAULT false,
    "jalon_3200h_atteint" boolean DEFAULT false,
    "avantages_debloques" "jsonb" DEFAULT '[]'::"jsonb",
    "cree_le" timestamp with time zone DEFAULT "now"(),
    "modifie_le" timestamp with time zone DEFAULT "now"()
);

ALTER TABLE ONLY "public"."suivi_conversion_3200h"
    ADD CONSTRAINT "suivi_conversion_3200h_pkey" PRIMARY KEY ("id");

CREATE TABLE IF NOT EXISTS "public"."swipes" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "soignant_id" "uuid" NOT NULL,
    "mission_id" "uuid" NOT NULL,
    "direction" "public"."swipe_direction" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);

ALTER TABLE ONLY "public"."swipes"
    ADD CONSTRAINT "swipes_pkey" PRIMARY KEY ("id");

CREATE TABLE IF NOT EXISTS "public"."templates_contrat" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "type_contrat" "text" NOT NULL,
    "nom" "text" NOT NULL,
    "contenu_html" "text" NOT NULL,
    "variables" "jsonb" DEFAULT '[]'::"jsonb" NOT NULL,
    "version" integer DEFAULT 1,
    "est_actif" boolean DEFAULT true,
    "cree_le" timestamp with time zone DEFAULT "now"(),
    "modifie_le" timestamp with time zone DEFAULT "now"()
);

ALTER TABLE ONLY "public"."templates_contrat"
    ADD CONSTRAINT "templates_contrat_pkey" PRIMARY KEY ("id");
