export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type Database = {
  // Allows to automatically instantiate createClient with right options
  // instead of createClient<Database, { PostgrestVersion: 'XX' }>(URL, KEY)
  __InternalSupabase: {
    PostgrestVersion: "14.1"
  }
  public: {
    Tables: {
      admins_groupe_sante: {
        Row: {
          cree_le: string | null
          groupe_id: string
          id: string
          role: string | null
          utilisateur_id: string
        }
        Insert: {
          cree_le?: string | null
          groupe_id: string
          id?: string
          role?: string | null
          utilisateur_id: string
        }
        Update: {
          cree_le?: string | null
          groupe_id?: string
          id?: string
          role?: string | null
          utilisateur_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "admins_groupe_sante_groupe_id_fkey"
            columns: ["groupe_id"]
            isOneToOne: false
            referencedRelation: "groupes_sante"
            referencedColumns: ["id"]
          },
        ]
      }
      api_keys: {
        Row: {
          actif: boolean | null
          cle_api: string
          cle_secret: string
          cree_le: string | null
          derniere_utilisation: string | null
          etablissement_id: string | null
          expire_le: string | null
          groupe_sante_id: string | null
          id: string
          nom: string
          permissions: string[] | null
        }
        Insert: {
          actif?: boolean | null
          cle_api: string
          cle_secret: string
          cree_le?: string | null
          derniere_utilisation?: string | null
          etablissement_id?: string | null
          expire_le?: string | null
          groupe_sante_id?: string | null
          id?: string
          nom: string
          permissions?: string[] | null
        }
        Update: {
          actif?: boolean | null
          cle_api?: string
          cle_secret?: string
          cree_le?: string | null
          derniere_utilisation?: string | null
          etablissement_id?: string | null
          expire_le?: string | null
          groupe_sante_id?: string | null
          id?: string
          nom?: string
          permissions?: string[] | null
        }
        Relationships: [
          {
            foreignKeyName: "api_keys_etablissement_id_fkey"
            columns: ["etablissement_id"]
            isOneToOne: false
            referencedRelation: "etablissements"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "api_keys_groupe_sante_id_fkey"
            columns: ["groupe_sante_id"]
            isOneToOne: false
            referencedRelation: "groupes_sante"
            referencedColumns: ["id"]
          },
        ]
      }
      attestations_heures_externes: {
        Row: {
          attestation_honneur: boolean | null
          cree_le: string | null
          employeur_principal: string | null
          heures_salarie: number | null
          id: string
          semaine_du: string
          soignant_id: string
        }
        Insert: {
          attestation_honneur?: boolean | null
          cree_le?: string | null
          employeur_principal?: string | null
          heures_salarie?: number | null
          id?: string
          semaine_du: string
          soignant_id: string
        }
        Update: {
          attestation_honneur?: boolean | null
          cree_le?: string | null
          employeur_principal?: string | null
          heures_salarie?: number | null
          id?: string
          semaine_du?: string
          soignant_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "attestations_heures_externes_soignant_id_fkey"
            columns: ["soignant_id"]
            isOneToOne: false
            referencedRelation: "soignants"
            referencedColumns: ["id"]
          },
        ]
      }
      bfa_suivi: {
        Row: {
          annee: number
          bfa_verse: boolean | null
          calcule_le: string | null
          commissions_cumulees: number | null
          cree_le: string | null
          date_versement: string | null
          etablissement_id: string | null
          groupe_id: string | null
          id: string
          missions_cumulees: number | null
          montant_bfa: number | null
          palier_bfa: string | null
          taux_bfa: number | null
        }
        Insert: {
          annee: number
          bfa_verse?: boolean | null
          calcule_le?: string | null
          commissions_cumulees?: number | null
          cree_le?: string | null
          date_versement?: string | null
          etablissement_id?: string | null
          groupe_id?: string | null
          id?: string
          missions_cumulees?: number | null
          montant_bfa?: number | null
          palier_bfa?: string | null
          taux_bfa?: number | null
        }
        Update: {
          annee?: number
          bfa_verse?: boolean | null
          calcule_le?: string | null
          commissions_cumulees?: number | null
          cree_le?: string | null
          date_versement?: string | null
          etablissement_id?: string | null
          groupe_id?: string | null
          id?: string
          missions_cumulees?: number | null
          montant_bfa?: number | null
          palier_bfa?: string | null
          taux_bfa?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "bfa_suivi_etablissement_id_fkey"
            columns: ["etablissement_id"]
            isOneToOne: false
            referencedRelation: "etablissements"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "bfa_suivi_groupe_id_fkey"
            columns: ["groupe_id"]
            isOneToOne: false
            referencedRelation: "groupes_sante"
            referencedColumns: ["id"]
          },
        ]
      }
      candidatures: {
        Row: {
          cree_le: string | null
          id: string
          message: string | null
          mission_id: string
          motif_refus: string | null
          soignant_id: string
          statut: string | null
          traite_le: string | null
        }
        Insert: {
          cree_le?: string | null
          id?: string
          message?: string | null
          mission_id: string
          motif_refus?: string | null
          soignant_id: string
          statut?: string | null
          traite_le?: string | null
        }
        Update: {
          cree_le?: string | null
          id?: string
          message?: string | null
          mission_id?: string
          motif_refus?: string | null
          soignant_id?: string
          statut?: string | null
          traite_le?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "candidatures_mission_id_fkey"
            columns: ["mission_id"]
            isOneToOne: false
            referencedRelation: "missions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "candidatures_soignant_id_fkey"
            columns: ["soignant_id"]
            isOneToOne: false
            referencedRelation: "soignants"
            referencedColumns: ["id"]
          },
        ]
      }
      chorus_pro_config: {
        Row: {
          actif: boolean | null
          code_service: string | null
          cree_le: string | null
          etablissement_id: string
          id: string
          identifiant_cpro: string | null
          numero_structure: string
        }
        Insert: {
          actif?: boolean | null
          code_service?: string | null
          cree_le?: string | null
          etablissement_id: string
          id?: string
          identifiant_cpro?: string | null
          numero_structure: string
        }
        Update: {
          actif?: boolean | null
          code_service?: string | null
          cree_le?: string | null
          etablissement_id?: string
          id?: string
          identifiant_cpro?: string | null
          numero_structure?: string
        }
        Relationships: [
          {
            foreignKeyName: "chorus_pro_config_etablissement_id_fkey"
            columns: ["etablissement_id"]
            isOneToOne: true
            referencedRelation: "etablissements"
            referencedColumns: ["id"]
          },
        ]
      }
      conformite_travail: {
        Row: {
          controle_le: string | null
          derogation_par: string | null
          details_violation: Json | null
          id: string
          mission_id: string
          motif_derogation: string | null
          resultat: string
          soignant_id: string
          type_controle: string
        }
        Insert: {
          controle_le?: string | null
          derogation_par?: string | null
          details_violation?: Json | null
          id?: string
          mission_id: string
          motif_derogation?: string | null
          resultat: string
          soignant_id: string
          type_controle: string
        }
        Update: {
          controle_le?: string | null
          derogation_par?: string | null
          details_violation?: Json | null
          id?: string
          mission_id?: string
          motif_derogation?: string | null
          resultat?: string
          soignant_id?: string
          type_controle?: string
        }
        Relationships: [
          {
            foreignKeyName: "conformite_travail_mission_id_fkey"
            columns: ["mission_id"]
            isOneToOne: false
            referencedRelation: "missions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "conformite_travail_soignant_id_fkey"
            columns: ["soignant_id"]
            isOneToOne: false
            referencedRelation: "soignants"
            referencedColumns: ["id"]
          },
        ]
      }
      contrats_mission: {
        Row: {
          contenu_html: string | null
          cree_le: string | null
          dpae_effectuee: boolean | null
          dpae_effectuee_le: string | null
          etablissement_id: string
          id: string
          mission_id: string
          mode_signature: string | null
          modifie_le: string | null
          numero_contrat: string
          pdf_cle_s3: string | null
          rappel_dpae_affiche: boolean | null
          rappel_dpae_affiche_le: string | null
          signature_etablissement: boolean | null
          signature_etablissement_le: string | null
          signature_image_etablissement: string | null
          signature_image_soignant: string | null
          signature_ip_etablissement: unknown
          signature_ip_soignant: unknown
          signature_navigateur_etablissement: string | null
          signature_navigateur_soignant: string | null
          signature_soignant: boolean | null
          signature_soignant_le: string | null
          soignant_id: string
          statut: string | null
          type_contrat: string
          yousign_document_id: string | null
          yousign_procedure_id: string | null
        }
        Insert: {
          contenu_html?: string | null
          cree_le?: string | null
          dpae_effectuee?: boolean | null
          dpae_effectuee_le?: string | null
          etablissement_id: string
          id?: string
          mission_id: string
          mode_signature?: string | null
          modifie_le?: string | null
          numero_contrat: string
          pdf_cle_s3?: string | null
          rappel_dpae_affiche?: boolean | null
          rappel_dpae_affiche_le?: string | null
          signature_etablissement?: boolean | null
          signature_etablissement_le?: string | null
          signature_image_etablissement?: string | null
          signature_image_soignant?: string | null
          signature_ip_etablissement?: unknown
          signature_ip_soignant?: unknown
          signature_navigateur_etablissement?: string | null
          signature_navigateur_soignant?: string | null
          signature_soignant?: boolean | null
          signature_soignant_le?: string | null
          soignant_id: string
          statut?: string | null
          type_contrat: string
          yousign_document_id?: string | null
          yousign_procedure_id?: string | null
        }
        Update: {
          contenu_html?: string | null
          cree_le?: string | null
          dpae_effectuee?: boolean | null
          dpae_effectuee_le?: string | null
          etablissement_id?: string
          id?: string
          mission_id?: string
          mode_signature?: string | null
          modifie_le?: string | null
          numero_contrat?: string
          pdf_cle_s3?: string | null
          rappel_dpae_affiche?: boolean | null
          rappel_dpae_affiche_le?: string | null
          signature_etablissement?: boolean | null
          signature_etablissement_le?: string | null
          signature_image_etablissement?: string | null
          signature_image_soignant?: string | null
          signature_ip_etablissement?: unknown
          signature_ip_soignant?: unknown
          signature_navigateur_etablissement?: string | null
          signature_navigateur_soignant?: string | null
          signature_soignant?: boolean | null
          signature_soignant_le?: string | null
          soignant_id?: string
          statut?: string | null
          type_contrat?: string
          yousign_document_id?: string | null
          yousign_procedure_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "contrats_mission_etablissement_id_fkey"
            columns: ["etablissement_id"]
            isOneToOne: false
            referencedRelation: "etablissements"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "contrats_mission_mission_id_fkey"
            columns: ["mission_id"]
            isOneToOne: false
            referencedRelation: "missions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "contrats_mission_soignant_id_fkey"
            columns: ["soignant_id"]
            isOneToOne: false
            referencedRelation: "soignants"
            referencedColumns: ["id"]
          },
        ]
      }
      conversations: {
        Row: {
          cree_le: string | null
          dernier_message_le: string | null
          id: string
          mission_id: string | null
          participant_1_id: string
          participant_2_id: string
        }
        Insert: {
          cree_le?: string | null
          dernier_message_le?: string | null
          id?: string
          mission_id?: string | null
          participant_1_id: string
          participant_2_id: string
        }
        Update: {
          cree_le?: string | null
          dernier_message_le?: string | null
          id?: string
          mission_id?: string | null
          participant_1_id?: string
          participant_2_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "conversations_mission_id_fkey"
            columns: ["mission_id"]
            isOneToOne: false
            referencedRelation: "missions"
            referencedColumns: ["id"]
          },
        ]
      }
      conversions_liberal: {
        Row: {
          complete_le: string | null
          cree_le: string | null
          demarre_le: string | null
          free_transition_eligible: boolean | null
          guide_pdf_cle_s3: string | null
          guide_pdf_genere: boolean | null
          heures_externes_validees: number | null
          heures_plateforme_au_demarrage: number
          heures_totales: number
          id: string
          indy_active: boolean | null
          indy_lien_affiliation: string | null
          macsf_active: boolean | null
          macsf_lien_affiliation: string | null
          modifie_le: string | null
          montant_pris_en_charge: number | null
          qonto_active: boolean | null
          qonto_lien_affiliation: string | null
          siret_recu_le: string | null
          soignant_id: string
          statut: string | null
          taux_prise_en_charge: number | null
        }
        Insert: {
          complete_le?: string | null
          cree_le?: string | null
          demarre_le?: string | null
          free_transition_eligible?: boolean | null
          guide_pdf_cle_s3?: string | null
          guide_pdf_genere?: boolean | null
          heures_externes_validees?: number | null
          heures_plateforme_au_demarrage: number
          heures_totales: number
          id?: string
          indy_active?: boolean | null
          indy_lien_affiliation?: string | null
          macsf_active?: boolean | null
          macsf_lien_affiliation?: string | null
          modifie_le?: string | null
          montant_pris_en_charge?: number | null
          qonto_active?: boolean | null
          qonto_lien_affiliation?: string | null
          siret_recu_le?: string | null
          soignant_id: string
          statut?: string | null
          taux_prise_en_charge?: number | null
        }
        Update: {
          complete_le?: string | null
          cree_le?: string | null
          demarre_le?: string | null
          free_transition_eligible?: boolean | null
          guide_pdf_cle_s3?: string | null
          guide_pdf_genere?: boolean | null
          heures_externes_validees?: number | null
          heures_plateforme_au_demarrage?: number
          heures_totales?: number
          id?: string
          indy_active?: boolean | null
          indy_lien_affiliation?: string | null
          macsf_active?: boolean | null
          macsf_lien_affiliation?: string | null
          modifie_le?: string | null
          montant_pris_en_charge?: number | null
          qonto_active?: boolean | null
          qonto_lien_affiliation?: string | null
          siret_recu_le?: string | null
          soignant_id?: string
          statut?: string | null
          taux_prise_en_charge?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "conversions_liberal_soignant_id_fkey"
            columns: ["soignant_id"]
            isOneToOne: false
            referencedRelation: "soignants"
            referencedColumns: ["id"]
          },
        ]
      }
      cotisations_sociales: {
        Row: {
          assurance_chomage: number
          calcule_le: string | null
          contribution_equilibre_general: number
          cout_total_employeur: number
          crds: number
          cree_le: string | null
          csg_deductible: number
          csg_non_deductible: number
          icp: number
          id: string
          ifm: number
          mission_id: string
          net_avant_impot: number
          patronal_accident_travail: number
          patronal_allocations_familiales: number
          patronal_chomage: number
          patronal_fnal: number
          patronal_formation: number
          patronal_retraite_complementaire: number
          patronal_securite_sociale: number
          patronal_transport: number
          retraite_complementaire_t1: number
          retraite_complementaire_t2: number
          salaire_brut: number
          securite_sociale_maladie: number
          securite_sociale_vieillesse_deplafonnee: number
          securite_sociale_vieillesse_plafonnee: number
          soignant_id: string
          total_cotisations_patronales: number
          total_cotisations_salariales: number
          type_contrat: string
        }
        Insert: {
          assurance_chomage?: number
          calcule_le?: string | null
          contribution_equilibre_general?: number
          cout_total_employeur?: number
          crds?: number
          cree_le?: string | null
          csg_deductible?: number
          csg_non_deductible?: number
          icp?: number
          id?: string
          ifm?: number
          mission_id: string
          net_avant_impot?: number
          patronal_accident_travail?: number
          patronal_allocations_familiales?: number
          patronal_chomage?: number
          patronal_fnal?: number
          patronal_formation?: number
          patronal_retraite_complementaire?: number
          patronal_securite_sociale?: number
          patronal_transport?: number
          retraite_complementaire_t1?: number
          retraite_complementaire_t2?: number
          salaire_brut: number
          securite_sociale_maladie?: number
          securite_sociale_vieillesse_deplafonnee?: number
          securite_sociale_vieillesse_plafonnee?: number
          soignant_id: string
          total_cotisations_patronales?: number
          total_cotisations_salariales?: number
          type_contrat: string
        }
        Update: {
          assurance_chomage?: number
          calcule_le?: string | null
          contribution_equilibre_general?: number
          cout_total_employeur?: number
          crds?: number
          cree_le?: string | null
          csg_deductible?: number
          csg_non_deductible?: number
          icp?: number
          id?: string
          ifm?: number
          mission_id?: string
          net_avant_impot?: number
          patronal_accident_travail?: number
          patronal_allocations_familiales?: number
          patronal_chomage?: number
          patronal_fnal?: number
          patronal_formation?: number
          patronal_retraite_complementaire?: number
          patronal_securite_sociale?: number
          patronal_transport?: number
          retraite_complementaire_t1?: number
          retraite_complementaire_t2?: number
          salaire_brut?: number
          securite_sociale_maladie?: number
          securite_sociale_vieillesse_deplafonnee?: number
          securite_sociale_vieillesse_plafonnee?: number
          soignant_id?: string
          total_cotisations_patronales?: number
          total_cotisations_salariales?: number
          type_contrat?: string
        }
        Relationships: [
          {
            foreignKeyName: "cotisations_sociales_mission_id_fkey"
            columns: ["mission_id"]
            isOneToOne: false
            referencedRelation: "missions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "cotisations_sociales_soignant_id_fkey"
            columns: ["soignant_id"]
            isOneToOne: false
            referencedRelation: "soignants"
            referencedColumns: ["id"]
          },
        ]
      }
      demandes_rgpd: {
        Row: {
          cle_s3_export: string | null
          cree_le: string | null
          demandeur_id: string
          id: string
          motif: string | null
          resultat_json: Json | null
          statut: string | null
          termine_le: string | null
          traite_le: string | null
          traite_par: string | null
          type_demande: string
          type_demandeur: string
        }
        Insert: {
          cle_s3_export?: string | null
          cree_le?: string | null
          demandeur_id: string
          id?: string
          motif?: string | null
          resultat_json?: Json | null
          statut?: string | null
          termine_le?: string | null
          traite_le?: string | null
          traite_par?: string | null
          type_demande: string
          type_demandeur: string
        }
        Update: {
          cle_s3_export?: string | null
          cree_le?: string | null
          demandeur_id?: string
          id?: string
          motif?: string | null
          resultat_json?: Json | null
          statut?: string | null
          termine_le?: string | null
          traite_le?: string | null
          traite_par?: string | null
          type_demande?: string
          type_demandeur?: string
        }
        Relationships: []
      }
      documents_requis_par_profession: {
        Row: {
          a_expiration: boolean | null
          description: string | null
          duree_validite_mois: number | null
          est_critique: boolean | null
          id: string
          profession: Database["public"]["Enums"]["type_profession"]
          type_document: Database["public"]["Enums"]["type_document"]
        }
        Insert: {
          a_expiration?: boolean | null
          description?: string | null
          duree_validite_mois?: number | null
          est_critique?: boolean | null
          id?: string
          profession: Database["public"]["Enums"]["type_profession"]
          type_document: Database["public"]["Enums"]["type_document"]
        }
        Update: {
          a_expiration?: boolean | null
          description?: string | null
          duree_validite_mois?: number | null
          est_critique?: boolean | null
          id?: string
          profession?: Database["public"]["Enums"]["type_profession"]
          type_document?: Database["public"]["Enums"]["type_document"]
        }
        Relationships: []
      }
      documents_soignants: {
        Row: {
          coherence_nom: boolean | null
          est_critique: boolean | null
          id: string
          libelle: string | null
          modifie_le: string | null
          motif_rejet: string | null
          nom_extrait_ia: string | null
          nom_fichier: string
          prenom_extrait_ia: string | null
          rappel_expire_envoye: boolean | null
          rappel_j30_envoye: boolean | null
          rappel_j7_envoye: boolean | null
          resultat_ia: Json | null
          s3_bucket: string
          s3_cle: string
          s3_version_id: string | null
          score_confiance_ia: number | null
          soignant_id: string
          statut_verification:
            | Database["public"]["Enums"]["statut_verification"]
            | null
          supprime_le: string | null
          taille_octets: number | null
          televerse_le: string | null
          type_document: Database["public"]["Enums"]["type_document"]
          type_mime: string | null
          valide_depuis: string | null
          valide_jusqua: string | null
          verifie_le: string | null
          verifie_par: string | null
        }
        Insert: {
          coherence_nom?: boolean | null
          est_critique?: boolean | null
          id?: string
          libelle?: string | null
          modifie_le?: string | null
          motif_rejet?: string | null
          nom_extrait_ia?: string | null
          nom_fichier: string
          prenom_extrait_ia?: string | null
          rappel_expire_envoye?: boolean | null
          rappel_j30_envoye?: boolean | null
          rappel_j7_envoye?: boolean | null
          resultat_ia?: Json | null
          s3_bucket?: string
          s3_cle: string
          s3_version_id?: string | null
          score_confiance_ia?: number | null
          soignant_id: string
          statut_verification?:
            | Database["public"]["Enums"]["statut_verification"]
            | null
          supprime_le?: string | null
          taille_octets?: number | null
          televerse_le?: string | null
          type_document: Database["public"]["Enums"]["type_document"]
          type_mime?: string | null
          valide_depuis?: string | null
          valide_jusqua?: string | null
          verifie_le?: string | null
          verifie_par?: string | null
        }
        Update: {
          coherence_nom?: boolean | null
          est_critique?: boolean | null
          id?: string
          libelle?: string | null
          modifie_le?: string | null
          motif_rejet?: string | null
          nom_extrait_ia?: string | null
          nom_fichier?: string
          prenom_extrait_ia?: string | null
          rappel_expire_envoye?: boolean | null
          rappel_j30_envoye?: boolean | null
          rappel_j7_envoye?: boolean | null
          resultat_ia?: Json | null
          s3_bucket?: string
          s3_cle?: string
          s3_version_id?: string | null
          score_confiance_ia?: number | null
          soignant_id?: string
          statut_verification?:
            | Database["public"]["Enums"]["statut_verification"]
            | null
          supprime_le?: string | null
          taille_octets?: number | null
          televerse_le?: string | null
          type_document?: Database["public"]["Enums"]["type_document"]
          type_mime?: string | null
          valide_depuis?: string | null
          valide_jusqua?: string | null
          verifie_le?: string | null
          verifie_par?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "documents_soignants_soignant_id_fkey"
            columns: ["soignant_id"]
            isOneToOne: false
            referencedRelation: "soignants"
            referencedColumns: ["id"]
          },
        ]
      }
      emails_envoyes: {
        Row: {
          cree_le: string | null
          destinataire_email: string
          destinataire_id: string | null
          erreur: string | null
          id: string
          provider_id: string | null
          statut: string | null
          sujet: string
          type: string
        }
        Insert: {
          cree_le?: string | null
          destinataire_email: string
          destinataire_id?: string | null
          erreur?: string | null
          id?: string
          provider_id?: string | null
          statut?: string | null
          sujet: string
          type: string
        }
        Update: {
          cree_le?: string | null
          destinataire_email?: string
          destinataire_id?: string | null
          erreur?: string | null
          id?: string
          provider_id?: string | null
          statut?: string | null
          sujet?: string
          type?: string
        }
        Relationships: []
      }
      etablissements: {
        Row: {
          adresse_code_postal: string
          adresse_departement: string | null
          adresse_lat: number | null
          adresse_lng: number | null
          adresse_rue: string
          adresse_ville: string
          chorus_pro_actif: boolean | null
          chorus_pro_identifiant: string | null
          contrat_uploade_le: string | null
          contrat_url: string | null
          contrat_valide: boolean | null
          convention_collective: string | null
          couleur_theme: string | null
          cree_le: string | null
          delai_paiement_jours: number | null
          email_contact: string
          est_secteur_public: boolean | null
          finess: string | null
          finess_verifie: boolean | null
          finess_verifie_le: string | null
          formule_abonnement: string | null
          groupe_sante_id: string | null
          id: string
          logo_url: string | null
          missions_mois_precedent: number | null
          mode_facturation: string | null
          mode_paiement_commission: string | null
          modifie_le: string | null
          motif_rejet: string | null
          nb_evaluations: number | null
          nom: string
          note_moyenne: number | null
          palier_commission_id: string | null
          palier_recalcule_le: string | null
          peut_publier_missions: boolean | null
          rist_plafond_actif: boolean | null
          rist_taux_base_horaire: number | null
          siret: string
          siret_categorie_juridique: string | null
          siret_code_naf: string | null
          siret_est_actif: boolean | null
          siret_raison_sociale: string | null
          siret_verifie: boolean | null
          siret_verifie_le: string | null
          statut_verification: string | null
          stripe_account_id: string | null
          stripe_customer_id: string | null
          supprime_le: string | null
          taux_commission_negocie: number | null
          taux_majoration_dimanche_pourcent: number | null
          taux_majoration_ferie_pourcent: number | null
          taux_majoration_nuit_pourcent: number | null
          telephone_contact: string | null
          type: Database["public"]["Enums"]["type_etablissement"]
          verifie_le: string | null
          verifie_par: string | null
        }
        Insert: {
          adresse_code_postal: string
          adresse_departement?: string | null
          adresse_lat?: number | null
          adresse_lng?: number | null
          adresse_rue: string
          adresse_ville: string
          chorus_pro_actif?: boolean | null
          chorus_pro_identifiant?: string | null
          contrat_uploade_le?: string | null
          contrat_url?: string | null
          contrat_valide?: boolean | null
          convention_collective?: string | null
          couleur_theme?: string | null
          cree_le?: string | null
          delai_paiement_jours?: number | null
          email_contact: string
          est_secteur_public?: boolean | null
          finess?: string | null
          finess_verifie?: boolean | null
          finess_verifie_le?: string | null
          formule_abonnement?: string | null
          groupe_sante_id?: string | null
          id?: string
          logo_url?: string | null
          missions_mois_precedent?: number | null
          mode_facturation?: string | null
          mode_paiement_commission?: string | null
          modifie_le?: string | null
          motif_rejet?: string | null
          nb_evaluations?: number | null
          nom: string
          note_moyenne?: number | null
          palier_commission_id?: string | null
          palier_recalcule_le?: string | null
          peut_publier_missions?: boolean | null
          rist_plafond_actif?: boolean | null
          rist_taux_base_horaire?: number | null
          siret: string
          siret_categorie_juridique?: string | null
          siret_code_naf?: string | null
          siret_est_actif?: boolean | null
          siret_raison_sociale?: string | null
          siret_verifie?: boolean | null
          siret_verifie_le?: string | null
          statut_verification?: string | null
          stripe_account_id?: string | null
          stripe_customer_id?: string | null
          supprime_le?: string | null
          taux_commission_negocie?: number | null
          taux_majoration_dimanche_pourcent?: number | null
          taux_majoration_ferie_pourcent?: number | null
          taux_majoration_nuit_pourcent?: number | null
          telephone_contact?: string | null
          type: Database["public"]["Enums"]["type_etablissement"]
          verifie_le?: string | null
          verifie_par?: string | null
        }
        Update: {
          adresse_code_postal?: string
          adresse_departement?: string | null
          adresse_lat?: number | null
          adresse_lng?: number | null
          adresse_rue?: string
          adresse_ville?: string
          chorus_pro_actif?: boolean | null
          chorus_pro_identifiant?: string | null
          contrat_uploade_le?: string | null
          contrat_url?: string | null
          contrat_valide?: boolean | null
          convention_collective?: string | null
          couleur_theme?: string | null
          cree_le?: string | null
          delai_paiement_jours?: number | null
          email_contact?: string
          est_secteur_public?: boolean | null
          finess?: string | null
          finess_verifie?: boolean | null
          finess_verifie_le?: string | null
          formule_abonnement?: string | null
          groupe_sante_id?: string | null
          id?: string
          logo_url?: string | null
          missions_mois_precedent?: number | null
          mode_facturation?: string | null
          mode_paiement_commission?: string | null
          modifie_le?: string | null
          motif_rejet?: string | null
          nb_evaluations?: number | null
          nom?: string
          note_moyenne?: number | null
          palier_commission_id?: string | null
          palier_recalcule_le?: string | null
          peut_publier_missions?: boolean | null
          rist_plafond_actif?: boolean | null
          rist_taux_base_horaire?: number | null
          siret?: string
          siret_categorie_juridique?: string | null
          siret_code_naf?: string | null
          siret_est_actif?: boolean | null
          siret_raison_sociale?: string | null
          siret_verifie?: boolean | null
          siret_verifie_le?: string | null
          statut_verification?: string | null
          stripe_account_id?: string | null
          stripe_customer_id?: string | null
          supprime_le?: string | null
          taux_commission_negocie?: number | null
          taux_majoration_dimanche_pourcent?: number | null
          taux_majoration_ferie_pourcent?: number | null
          taux_majoration_nuit_pourcent?: number | null
          telephone_contact?: string | null
          type?: Database["public"]["Enums"]["type_etablissement"]
          verifie_le?: string | null
          verifie_par?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "etablissements_groupe_sante_id_fkey"
            columns: ["groupe_sante_id"]
            isOneToOne: false
            referencedRelation: "groupes_sante"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "etablissements_palier_commission_id_fkey"
            columns: ["palier_commission_id"]
            isOneToOne: false
            referencedRelation: "paliers_commission"
            referencedColumns: ["id"]
          },
        ]
      }
      evaluations: {
        Row: {
          commentaire: string | null
          cree_le: string | null
          evaluateur_id: string
          evalue_id: string
          id: string
          mission_id: string
          note: number
          type_evaluateur: string
          visible: boolean | null
        }
        Insert: {
          commentaire?: string | null
          cree_le?: string | null
          evaluateur_id: string
          evalue_id: string
          id?: string
          mission_id: string
          note: number
          type_evaluateur: string
          visible?: boolean | null
        }
        Update: {
          commentaire?: string | null
          cree_le?: string | null
          evaluateur_id?: string
          evalue_id?: string
          id?: string
          mission_id?: string
          note?: number
          type_evaluateur?: string
          visible?: boolean | null
        }
        Relationships: [
          {
            foreignKeyName: "evaluations_mission_id_fkey"
            columns: ["mission_id"]
            isOneToOne: false
            referencedRelation: "missions"
            referencedColumns: ["id"]
          },
        ]
      }
      exclusions: {
        Row: {
          cree_le: string | null
          exclu_id: string
          exclu_par: string
          id: string
          motif: string | null
          type_exclu_par: string
        }
        Insert: {
          cree_le?: string | null
          exclu_id: string
          exclu_par: string
          id?: string
          motif?: string | null
          type_exclu_par: string
        }
        Update: {
          cree_le?: string | null
          exclu_id?: string
          exclu_par?: string
          id?: string
          motif?: string | null
          type_exclu_par?: string
        }
        Relationships: []
      }
      factures: {
        Row: {
          chorus_pro_date_acceptation: string | null
          chorus_pro_date_depot: string | null
          chorus_pro_deposee_le: string | null
          chorus_pro_id: string | null
          chorus_pro_numero_flux: string | null
          chorus_pro_statut: string | null
          cree_le: string | null
          date_echeance: string | null
          date_emission: string | null
          date_paiement: string | null
          est_secteur_public: boolean | null
          etablissement_id: string
          id: string
          mission_id: string | null
          mode_paiement: string | null
          modifie_le: string | null
          montant_ht: number
          montant_ttc: number
          montant_tva: number
          nombre_missions: number | null
          numero_facture: string
          periode_debut: string | null
          periode_fin: string | null
          statut: string | null
          stripe_hosted_url: string | null
          stripe_invoice_id: string | null
          stripe_payment_intent_id: string | null
          taux_tva: number | null
          virement_confirme_le: string | null
          virement_confirme_par: string | null
          virement_reference: string | null
        }
        Insert: {
          chorus_pro_date_acceptation?: string | null
          chorus_pro_date_depot?: string | null
          chorus_pro_deposee_le?: string | null
          chorus_pro_id?: string | null
          chorus_pro_numero_flux?: string | null
          chorus_pro_statut?: string | null
          cree_le?: string | null
          date_echeance?: string | null
          date_emission?: string | null
          date_paiement?: string | null
          est_secteur_public?: boolean | null
          etablissement_id: string
          id?: string
          mission_id?: string | null
          mode_paiement?: string | null
          modifie_le?: string | null
          montant_ht: number
          montant_ttc: number
          montant_tva: number
          nombre_missions?: number | null
          numero_facture: string
          periode_debut?: string | null
          periode_fin?: string | null
          statut?: string | null
          stripe_hosted_url?: string | null
          stripe_invoice_id?: string | null
          stripe_payment_intent_id?: string | null
          taux_tva?: number | null
          virement_confirme_le?: string | null
          virement_confirme_par?: string | null
          virement_reference?: string | null
        }
        Update: {
          chorus_pro_date_acceptation?: string | null
          chorus_pro_date_depot?: string | null
          chorus_pro_deposee_le?: string | null
          chorus_pro_id?: string | null
          chorus_pro_numero_flux?: string | null
          chorus_pro_statut?: string | null
          cree_le?: string | null
          date_echeance?: string | null
          date_emission?: string | null
          date_paiement?: string | null
          est_secteur_public?: boolean | null
          etablissement_id?: string
          id?: string
          mission_id?: string | null
          mode_paiement?: string | null
          modifie_le?: string | null
          montant_ht?: number
          montant_ttc?: number
          montant_tva?: number
          nombre_missions?: number | null
          numero_facture?: string
          periode_debut?: string | null
          periode_fin?: string | null
          statut?: string | null
          stripe_hosted_url?: string | null
          stripe_invoice_id?: string | null
          stripe_payment_intent_id?: string | null
          taux_tva?: number | null
          virement_confirme_le?: string | null
          virement_confirme_par?: string | null
          virement_reference?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "factures_etablissement_id_fkey"
            columns: ["etablissement_id"]
            isOneToOne: false
            referencedRelation: "etablissements"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "factures_mission_id_fkey"
            columns: ["mission_id"]
            isOneToOne: false
            referencedRelation: "missions"
            referencedColumns: ["id"]
          },
        ]
      }
      favoris: {
        Row: {
          cree_le: string | null
          etablissement_id: string
          id: string
          soignant_id: string
        }
        Insert: {
          cree_le?: string | null
          etablissement_id: string
          id?: string
          soignant_id: string
        }
        Update: {
          cree_le?: string | null
          etablissement_id?: string
          id?: string
          soignant_id?: string
        }
        Relationships: []
      }
      file_revue_manuelle: {
        Row: {
          assigne_a: string | null
          cree_le: string | null
          donnees_originales: Json | null
          expire_le: string | null
          id: string
          id_entite: string
          motif_echec: string | null
          notes_resolution: string | null
          priorite: number | null
          resolu_le: string | null
          revu_le: string | null
          service_en_echec: string
          statut: string | null
          type_entite: string
        }
        Insert: {
          assigne_a?: string | null
          cree_le?: string | null
          donnees_originales?: Json | null
          expire_le?: string | null
          id?: string
          id_entite: string
          motif_echec?: string | null
          notes_resolution?: string | null
          priorite?: number | null
          resolu_le?: string | null
          revu_le?: string | null
          service_en_echec: string
          statut?: string | null
          type_entite: string
        }
        Update: {
          assigne_a?: string | null
          cree_le?: string | null
          donnees_originales?: Json | null
          expire_le?: string | null
          id?: string
          id_entite?: string
          motif_echec?: string | null
          notes_resolution?: string | null
          priorite?: number | null
          resolu_le?: string | null
          revu_le?: string | null
          service_en_echec?: string
          statut?: string | null
          type_entite?: string
        }
        Relationships: []
      }
      groupes_sante: {
        Row: {
          adresse_facturation: string | null
          couleur_primaire: string | null
          couleur_secondaire: string | null
          cree_le: string | null
          domaine_custom: string | null
          email_admin: string | null
          formule_abonnement: string | null
          groupe_parent_id: string | null
          id: string
          logo_url: string | null
          modifie_le: string | null
          nom: string
          nom_marque: string | null
          raison_sociale_facturation: string | null
          remise_groupe_pourcent: number | null
          rist_plafond_personnalise: boolean | null
          siren: string | null
          siret_facturation: string | null
          supprime_le: string | null
          telephone_admin: string | null
        }
        Insert: {
          adresse_facturation?: string | null
          couleur_primaire?: string | null
          couleur_secondaire?: string | null
          cree_le?: string | null
          domaine_custom?: string | null
          email_admin?: string | null
          formule_abonnement?: string | null
          groupe_parent_id?: string | null
          id?: string
          logo_url?: string | null
          modifie_le?: string | null
          nom: string
          nom_marque?: string | null
          raison_sociale_facturation?: string | null
          remise_groupe_pourcent?: number | null
          rist_plafond_personnalise?: boolean | null
          siren?: string | null
          siret_facturation?: string | null
          supprime_le?: string | null
          telephone_admin?: string | null
        }
        Update: {
          adresse_facturation?: string | null
          couleur_primaire?: string | null
          couleur_secondaire?: string | null
          cree_le?: string | null
          domaine_custom?: string | null
          email_admin?: string | null
          formule_abonnement?: string | null
          groupe_parent_id?: string | null
          id?: string
          logo_url?: string | null
          modifie_le?: string | null
          nom?: string
          nom_marque?: string | null
          raison_sociale_facturation?: string | null
          remise_groupe_pourcent?: number | null
          rist_plafond_personnalise?: boolean | null
          siren?: string | null
          siret_facturation?: string | null
          supprime_le?: string | null
          telephone_admin?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "groupes_sante_groupe_parent_id_fkey"
            columns: ["groupe_parent_id"]
            isOneToOne: false
            referencedRelation: "groupes_sante"
            referencedColumns: ["id"]
          },
        ]
      }
      health_check: {
        Row: {
          details: Json | null
          id: string
          latence_ms: number | null
          service: string
          statut: string | null
          verifie_le: string | null
        }
        Insert: {
          details?: Json | null
          id?: string
          latence_ms?: number | null
          service: string
          statut?: string | null
          verifie_le?: string | null
        }
        Update: {
          details?: Json | null
          id?: string
          latence_ms?: number | null
          service?: string
          statut?: string | null
          verifie_le?: string | null
        }
        Relationships: []
      }
      heures_externes: {
        Row: {
          cree_le: string | null
          date_debut: string
          date_fin: string
          document_id: string | null
          employeur_nom: string
          employeur_type: string | null
          heures_declarees: number
          id: string
          modifie_le: string | null
          motif_rejet: string | null
          soignant_id: string
          statut: string | null
          type_preuve: string | null
          validee_le: string | null
          validee_par: string | null
        }
        Insert: {
          cree_le?: string | null
          date_debut: string
          date_fin: string
          document_id?: string | null
          employeur_nom: string
          employeur_type?: string | null
          heures_declarees: number
          id?: string
          modifie_le?: string | null
          motif_rejet?: string | null
          soignant_id: string
          statut?: string | null
          type_preuve?: string | null
          validee_le?: string | null
          validee_par?: string | null
        }
        Update: {
          cree_le?: string | null
          date_debut?: string
          date_fin?: string
          document_id?: string | null
          employeur_nom?: string
          employeur_type?: string | null
          heures_declarees?: number
          id?: string
          modifie_le?: string | null
          motif_rejet?: string | null
          soignant_id?: string
          statut?: string | null
          type_preuve?: string | null
          validee_le?: string | null
          validee_par?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "heures_externes_document_id_fkey"
            columns: ["document_id"]
            isOneToOne: false
            referencedRelation: "documents_soignants"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "heures_externes_soignant_id_fkey"
            columns: ["soignant_id"]
            isOneToOne: false
            referencedRelation: "soignants"
            referencedColumns: ["id"]
          },
        ]
      }
      journaux_audit: {
        Row: {
          acteur_id: string | null
          action: string
          cle_s3_ressource: string | null
          cree_le: string | null
          details: Json | null
          id: string
          id_ressource: string | null
          ip_acteur: unknown
          navigateur_acteur: string | null
          type_acteur: string
          type_ressource: string | null
        }
        Insert: {
          acteur_id?: string | null
          action: string
          cle_s3_ressource?: string | null
          cree_le?: string | null
          details?: Json | null
          id?: string
          id_ressource?: string | null
          ip_acteur?: unknown
          navigateur_acteur?: string | null
          type_acteur: string
          type_ressource?: string | null
        }
        Update: {
          acteur_id?: string | null
          action?: string
          cle_s3_ressource?: string | null
          cree_le?: string | null
          details?: Json | null
          id?: string
          id_ressource?: string | null
          ip_acteur?: unknown
          navigateur_acteur?: string | null
          type_acteur?: string
          type_ressource?: string | null
        }
        Relationships: []
      }
      jours_feries_fr: {
        Row: {
          annee: number | null
          cree_le: string | null
          date_ferie: string
          est_recurrent: boolean | null
          id: string
          jour_recurrent: number | null
          mois_recurrent: number | null
          nom: string
        }
        Insert: {
          annee?: number | null
          cree_le?: string | null
          date_ferie: string
          est_recurrent?: boolean | null
          id?: string
          jour_recurrent?: number | null
          mois_recurrent?: number | null
          nom: string
        }
        Update: {
          annee?: number | null
          cree_le?: string | null
          date_ferie?: string
          est_recurrent?: boolean | null
          id?: string
          jour_recurrent?: number | null
          mois_recurrent?: number | null
          nom?: string
        }
        Relationships: []
      }
      liste_attente_premium: {
        Row: {
          cree_le: string | null
          email: string
          id: string
          type_offre: string
          utilisateur_id: string | null
        }
        Insert: {
          cree_le?: string | null
          email: string
          id?: string
          type_offre: string
          utilisateur_id?: string | null
        }
        Update: {
          cree_le?: string | null
          email?: string
          id?: string
          type_offre?: string
          utilisateur_id?: string | null
        }
        Relationships: []
      }
      litiges: {
        Row: {
          cree_le: string | null
          etablissement_id: string
          id: string
          initie_par: string
          mission_id: string
          motif: string
          presence_id: string
          reponse: string | null
          resolu_le: string | null
          resolu_par: string | null
          resolution: string | null
          soignant_id: string
          statut: string | null
        }
        Insert: {
          cree_le?: string | null
          etablissement_id: string
          id?: string
          initie_par: string
          mission_id: string
          motif: string
          presence_id: string
          reponse?: string | null
          resolu_le?: string | null
          resolu_par?: string | null
          resolution?: string | null
          soignant_id: string
          statut?: string | null
        }
        Update: {
          cree_le?: string | null
          etablissement_id?: string
          id?: string
          initie_par?: string
          mission_id?: string
          motif?: string
          presence_id?: string
          reponse?: string | null
          resolu_le?: string | null
          resolu_par?: string | null
          resolution?: string | null
          soignant_id?: string
          statut?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "litiges_mission_id_fkey"
            columns: ["mission_id"]
            isOneToOne: false
            referencedRelation: "missions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "litiges_presence_id_fkey"
            columns: ["presence_id"]
            isOneToOne: false
            referencedRelation: "presences"
            referencedColumns: ["id"]
          },
        ]
      }
      messages_chat: {
        Row: {
          auteur_id: string
          contenu: string
          conversation_id: string
          cree_le: string | null
          est_admin: boolean | null
          id: string
          lu: boolean | null
        }
        Insert: {
          auteur_id: string
          contenu: string
          conversation_id: string
          cree_le?: string | null
          est_admin?: boolean | null
          id?: string
          lu?: boolean | null
        }
        Update: {
          auteur_id?: string
          contenu?: string
          conversation_id?: string
          cree_le?: string | null
          est_admin?: boolean | null
          id?: string
          lu?: boolean | null
        }
        Relationships: [
          {
            foreignKeyName: "messages_chat_conversation_id_fkey"
            columns: ["conversation_id"]
            isOneToOne: false
            referencedRelation: "conversations"
            referencedColumns: ["id"]
          },
        ]
      }
      messages_mission: {
        Row: {
          auteur_id: string
          contenu: string
          cree_le: string | null
          id: string
          lu: boolean | null
          mission_id: string
          type_auteur: string
        }
        Insert: {
          auteur_id: string
          contenu: string
          cree_le?: string | null
          id?: string
          lu?: boolean | null
          mission_id: string
          type_auteur: string
        }
        Update: {
          auteur_id?: string
          contenu?: string
          cree_le?: string | null
          id?: string
          lu?: boolean | null
          mission_id?: string
          type_auteur?: string
        }
        Relationships: [
          {
            foreignKeyName: "messages_mission_mission_id_fkey"
            columns: ["mission_id"]
            isOneToOne: false
            referencedRelation: "missions"
            referencedColumns: ["id"]
          },
        ]
      }
      missions: {
        Row: {
          annulee_le: string | null
          annulee_par: string | null
          code_arrivee: string | null
          code_depart: string | null
          commission_facturee: boolean | null
          cree_le: string | null
          debut_le: string
          description: string | null
          duree_heures: number | null
          est_urgente: boolean | null
          etablissement_id: string
          facture_id: string | null
          fin_le: string
          heures_dimanche: number | null
          heures_ferie: number | null
          heures_nuit: number | null
          id: string
          intitule: string
          mode_attribution: string | null
          mode_paiement_soignant: string | null
          modifie_le: string | null
          montant_commission_ht: number | null
          montant_commission_ttc: number | null
          montant_commission_tva: number | null
          montant_icp: number | null
          montant_ifm: number | null
          montant_majoration_dimanche: number | null
          montant_majoration_ferie: number | null
          montant_majoration_nuit: number | null
          motif_annulation: string | null
          net_a_payer: number | null
          net_estime: number | null
          niveau_urgence: number | null
          numero_note_honoraires: string | null
          profession_requise: Database["public"]["Enums"]["type_profession"]
          rist_plafond_applique: boolean | null
          serie_id: string | null
          service: string | null
          soignant_assigne_id: string | null
          statut: Database["public"]["Enums"]["statut_mission"] | null
          stripe_payment_intent_id: string | null
          stripe_transfer_id: string | null
          taux_commission: number | null
          taux_horaire_base: number
          taux_icp: number | null
          taux_ifm: number | null
          taux_rist_plafonne: number | null
          terminee_le: string | null
          total_brut: number | null
          type_contrat_recherche: string
          type_paiement_soignant: string | null
          yousign_id_procedure: string | null
          yousign_statut: string | null
        }
        Insert: {
          annulee_le?: string | null
          annulee_par?: string | null
          code_arrivee?: string | null
          code_depart?: string | null
          commission_facturee?: boolean | null
          cree_le?: string | null
          debut_le: string
          description?: string | null
          duree_heures?: number | null
          est_urgente?: boolean | null
          etablissement_id: string
          facture_id?: string | null
          fin_le: string
          heures_dimanche?: number | null
          heures_ferie?: number | null
          heures_nuit?: number | null
          id?: string
          intitule: string
          mode_attribution?: string | null
          mode_paiement_soignant?: string | null
          modifie_le?: string | null
          montant_commission_ht?: number | null
          montant_commission_ttc?: number | null
          montant_commission_tva?: number | null
          montant_icp?: number | null
          montant_ifm?: number | null
          montant_majoration_dimanche?: number | null
          montant_majoration_ferie?: number | null
          montant_majoration_nuit?: number | null
          motif_annulation?: string | null
          net_a_payer?: number | null
          net_estime?: number | null
          niveau_urgence?: number | null
          numero_note_honoraires?: string | null
          profession_requise: Database["public"]["Enums"]["type_profession"]
          rist_plafond_applique?: boolean | null
          serie_id?: string | null
          service?: string | null
          soignant_assigne_id?: string | null
          statut?: Database["public"]["Enums"]["statut_mission"] | null
          stripe_payment_intent_id?: string | null
          stripe_transfer_id?: string | null
          taux_commission?: number | null
          taux_horaire_base: number
          taux_icp?: number | null
          taux_ifm?: number | null
          taux_rist_plafonne?: number | null
          terminee_le?: string | null
          total_brut?: number | null
          type_contrat_recherche?: string
          type_paiement_soignant?: string | null
          yousign_id_procedure?: string | null
          yousign_statut?: string | null
        }
        Update: {
          annulee_le?: string | null
          annulee_par?: string | null
          code_arrivee?: string | null
          code_depart?: string | null
          commission_facturee?: boolean | null
          cree_le?: string | null
          debut_le?: string
          description?: string | null
          duree_heures?: number | null
          est_urgente?: boolean | null
          etablissement_id?: string
          facture_id?: string | null
          fin_le?: string
          heures_dimanche?: number | null
          heures_ferie?: number | null
          heures_nuit?: number | null
          id?: string
          intitule?: string
          mode_attribution?: string | null
          mode_paiement_soignant?: string | null
          modifie_le?: string | null
          montant_commission_ht?: number | null
          montant_commission_ttc?: number | null
          montant_commission_tva?: number | null
          montant_icp?: number | null
          montant_ifm?: number | null
          montant_majoration_dimanche?: number | null
          montant_majoration_ferie?: number | null
          montant_majoration_nuit?: number | null
          motif_annulation?: string | null
          net_a_payer?: number | null
          net_estime?: number | null
          niveau_urgence?: number | null
          numero_note_honoraires?: string | null
          profession_requise?: Database["public"]["Enums"]["type_profession"]
          rist_plafond_applique?: boolean | null
          serie_id?: string | null
          service?: string | null
          soignant_assigne_id?: string | null
          statut?: Database["public"]["Enums"]["statut_mission"] | null
          stripe_payment_intent_id?: string | null
          stripe_transfer_id?: string | null
          taux_commission?: number | null
          taux_horaire_base?: number
          taux_icp?: number | null
          taux_ifm?: number | null
          taux_rist_plafonne?: number | null
          terminee_le?: string | null
          total_brut?: number | null
          type_contrat_recherche?: string
          type_paiement_soignant?: string | null
          yousign_id_procedure?: string | null
          yousign_statut?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "missions_etablissement_id_fkey"
            columns: ["etablissement_id"]
            isOneToOne: false
            referencedRelation: "etablissements"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "missions_soignant_assigne_id_fkey"
            columns: ["soignant_assigne_id"]
            isOneToOne: false
            referencedRelation: "soignants"
            referencedColumns: ["id"]
          },
        ]
      }
      notifications: {
        Row: {
          corps: string
          cree_le: string | null
          destinataire_id: string
          email_envoye: boolean | null
          email_envoye_le: string | null
          id: string
          id_ressource: string | null
          lien: string | null
          lue: boolean | null
          lue_le: string | null
          push_envoyee: boolean | null
          push_envoyee_le: string | null
          titre: string
          type: string
          type_destinataire: string
          type_ressource: string | null
        }
        Insert: {
          corps: string
          cree_le?: string | null
          destinataire_id: string
          email_envoye?: boolean | null
          email_envoye_le?: string | null
          id?: string
          id_ressource?: string | null
          lien?: string | null
          lue?: boolean | null
          lue_le?: string | null
          push_envoyee?: boolean | null
          push_envoyee_le?: string | null
          titre: string
          type: string
          type_destinataire: string
          type_ressource?: string | null
        }
        Update: {
          corps?: string
          cree_le?: string | null
          destinataire_id?: string
          email_envoye?: boolean | null
          email_envoye_le?: string | null
          id?: string
          id_ressource?: string | null
          lien?: string | null
          lue?: boolean | null
          lue_le?: string | null
          push_envoyee?: boolean | null
          push_envoyee_le?: string | null
          titre?: string
          type?: string
          type_destinataire?: string
          type_ressource?: string | null
        }
        Relationships: []
      }
      paiements_mission: {
        Row: {
          capture_le: string | null
          cree_le: string | null
          etablissement_id: string
          id: string
          mission_id: string
          montant_ht: number
          montant_ttc: number
          montant_tva: number
          rembourse_le: string | null
          statut: string | null
          stripe_charge_id: string | null
          stripe_payment_intent_id: string | null
        }
        Insert: {
          capture_le?: string | null
          cree_le?: string | null
          etablissement_id: string
          id?: string
          mission_id: string
          montant_ht: number
          montant_ttc: number
          montant_tva: number
          rembourse_le?: string | null
          statut?: string | null
          stripe_charge_id?: string | null
          stripe_payment_intent_id?: string | null
        }
        Update: {
          capture_le?: string | null
          cree_le?: string | null
          etablissement_id?: string
          id?: string
          mission_id?: string
          montant_ht?: number
          montant_ttc?: number
          montant_tva?: number
          rembourse_le?: string | null
          statut?: string | null
          stripe_charge_id?: string | null
          stripe_payment_intent_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "paiements_mission_etablissement_id_fkey"
            columns: ["etablissement_id"]
            isOneToOne: false
            referencedRelation: "etablissements"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "paiements_mission_mission_id_fkey"
            columns: ["mission_id"]
            isOneToOne: false
            referencedRelation: "missions"
            referencedColumns: ["id"]
          },
        ]
      }
      paiements_soignant: {
        Row: {
          confirme_par_etablissement: boolean | null
          confirme_par_etablissement_le: string | null
          confirme_par_soignant: boolean | null
          confirme_par_soignant_le: string | null
          conteste: boolean | null
          cree_le: string | null
          date_paiement: string | null
          etablissement_id: string
          id: string
          methode: string
          mission_id: string
          modifie_le: string | null
          montant_net: number
          motif_contestation: string | null
          reference_virement: string | null
          soignant_id: string
          statut: string
        }
        Insert: {
          confirme_par_etablissement?: boolean | null
          confirme_par_etablissement_le?: string | null
          confirme_par_soignant?: boolean | null
          confirme_par_soignant_le?: string | null
          conteste?: boolean | null
          cree_le?: string | null
          date_paiement?: string | null
          etablissement_id: string
          id?: string
          methode: string
          mission_id: string
          modifie_le?: string | null
          montant_net: number
          motif_contestation?: string | null
          reference_virement?: string | null
          soignant_id: string
          statut?: string
        }
        Update: {
          confirme_par_etablissement?: boolean | null
          confirme_par_etablissement_le?: string | null
          confirme_par_soignant?: boolean | null
          confirme_par_soignant_le?: string | null
          conteste?: boolean | null
          cree_le?: string | null
          date_paiement?: string | null
          etablissement_id?: string
          id?: string
          methode?: string
          mission_id?: string
          modifie_le?: string | null
          montant_net?: number
          motif_contestation?: string | null
          reference_virement?: string | null
          soignant_id?: string
          statut?: string
        }
        Relationships: [
          {
            foreignKeyName: "paiements_soignant_etablissement_id_fkey"
            columns: ["etablissement_id"]
            isOneToOne: false
            referencedRelation: "etablissements"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "paiements_soignant_mission_id_fkey"
            columns: ["mission_id"]
            isOneToOne: false
            referencedRelation: "missions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "paiements_soignant_soignant_id_fkey"
            columns: ["soignant_id"]
            isOneToOne: false
            referencedRelation: "soignants"
            referencedColumns: ["id"]
          },
        ]
      }
      paliers_bfa: {
        Row: {
          cree_le: string | null
          est_actif: boolean | null
          id: string
          missions_max: number | null
          missions_min: number
          nom: string
          ordre: number
          taux_bfa: number
        }
        Insert: {
          cree_le?: string | null
          est_actif?: boolean | null
          id?: string
          missions_max?: number | null
          missions_min: number
          nom: string
          ordre: number
          taux_bfa: number
        }
        Update: {
          cree_le?: string | null
          est_actif?: boolean | null
          id?: string
          missions_max?: number | null
          missions_min?: number
          nom?: string
          ordre?: number
          taux_bfa?: number
        }
        Relationships: []
      }
      paliers_commission: {
        Row: {
          cree_le: string | null
          est_actif: boolean | null
          id: string
          missions_max: number | null
          missions_min: number
          nom: string
          ordre: number
          taux_commission: number
        }
        Insert: {
          cree_le?: string | null
          est_actif?: boolean | null
          id?: string
          missions_max?: number | null
          missions_min: number
          nom: string
          ordre: number
          taux_commission: number
        }
        Update: {
          cree_le?: string | null
          est_actif?: boolean | null
          id?: string
          missions_max?: number | null
          missions_min?: number
          nom?: string
          ordre?: number
          taux_commission?: number
        }
        Relationships: []
      }
      parrainages: {
        Row: {
          bonus_heures_filleul: number | null
          bonus_heures_parrain: number | null
          code_parrainage: string
          cree_le: string | null
          filleul_id: string
          id: string
          parrain_id: string
          statut: string | null
          valide_le: string | null
        }
        Insert: {
          bonus_heures_filleul?: number | null
          bonus_heures_parrain?: number | null
          code_parrainage: string
          cree_le?: string | null
          filleul_id: string
          id?: string
          parrain_id: string
          statut?: string | null
          valide_le?: string | null
        }
        Update: {
          bonus_heures_filleul?: number | null
          bonus_heures_parrain?: number | null
          code_parrainage?: string
          cree_le?: string | null
          filleul_id?: string
          id?: string
          parrain_id?: string
          statut?: string | null
          valide_le?: string | null
        }
        Relationships: []
      }
      partages_rib: {
        Row: {
          actif: boolean | null
          consulte_le: string | null
          consulte_par: string | null
          contrat_id: string
          document_rib_id: string | null
          etablissement_id: string
          id: string
          mission_id: string
          partage_le: string | null
          soignant_id: string
        }
        Insert: {
          actif?: boolean | null
          consulte_le?: string | null
          consulte_par?: string | null
          contrat_id: string
          document_rib_id?: string | null
          etablissement_id: string
          id?: string
          mission_id: string
          partage_le?: string | null
          soignant_id: string
        }
        Update: {
          actif?: boolean | null
          consulte_le?: string | null
          consulte_par?: string | null
          contrat_id?: string
          document_rib_id?: string | null
          etablissement_id?: string
          id?: string
          mission_id?: string
          partage_le?: string | null
          soignant_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "partages_rib_contrat_id_fkey"
            columns: ["contrat_id"]
            isOneToOne: false
            referencedRelation: "contrats_mission"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "partages_rib_document_rib_id_fkey"
            columns: ["document_rib_id"]
            isOneToOne: false
            referencedRelation: "documents_soignants"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "partages_rib_etablissement_id_fkey"
            columns: ["etablissement_id"]
            isOneToOne: false
            referencedRelation: "etablissements"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "partages_rib_mission_id_fkey"
            columns: ["mission_id"]
            isOneToOne: false
            referencedRelation: "missions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "partages_rib_soignant_id_fkey"
            columns: ["soignant_id"]
            isOneToOne: false
            referencedRelation: "soignants"
            referencedColumns: ["id"]
          },
        ]
      }
      pauses_presence: {
        Row: {
          cree_le: string | null
          debut_le: string
          duree_min: number | null
          fin_le: string | null
          id: string
          motif: string | null
          presence_id: string
          soignant_id: string
        }
        Insert: {
          cree_le?: string | null
          debut_le?: string
          duree_min?: number | null
          fin_le?: string | null
          id?: string
          motif?: string | null
          presence_id: string
          soignant_id: string
        }
        Update: {
          cree_le?: string | null
          debut_le?: string
          duree_min?: number | null
          fin_le?: string | null
          id?: string
          motif?: string | null
          presence_id?: string
          soignant_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "pauses_presence_presence_id_fkey"
            columns: ["presence_id"]
            isOneToOne: false
            referencedRelation: "presences"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "pauses_presence_soignant_id_fkey"
            columns: ["soignant_id"]
            isOneToOne: false
            referencedRelation: "soignants"
            referencedColumns: ["id"]
          },
        ]
      }
      plans_prevoyance: {
        Row: {
          cree_le: string | null
          description: string | null
          est_actif: boolean | null
          fournisseur: string
          heures_minimum_requises: number | null
          id: string
          missions_minimum_requises: number | null
          nom: string
          prime_mensuelle: number
          subvention_max_mensuelle: number | null
          subvention_plateforme_pourcent: number | null
          type: string
        }
        Insert: {
          cree_le?: string | null
          description?: string | null
          est_actif?: boolean | null
          fournisseur: string
          heures_minimum_requises?: number | null
          id?: string
          missions_minimum_requises?: number | null
          nom: string
          prime_mensuelle: number
          subvention_max_mensuelle?: number | null
          subvention_plateforme_pourcent?: number | null
          type: string
        }
        Update: {
          cree_le?: string | null
          description?: string | null
          est_actif?: boolean | null
          fournisseur?: string
          heures_minimum_requises?: number | null
          id?: string
          missions_minimum_requises?: number | null
          nom?: string
          prime_mensuelle?: number
          subvention_max_mensuelle?: number | null
          subvention_plateforme_pourcent?: number | null
          type?: string
        }
        Relationships: []
      }
      presences: {
        Row: {
          alerte_teleportation: boolean | null
          alertes_fraude: Json | null
          arrivee_id_terminal: string | null
          arrivee_ip: unknown
          arrivee_lat: number | null
          arrivee_lng: number | null
          arrivee_modele_terminal: string | null
          arrivee_precision_gps_m: number | null
          cree_le: string | null
          depart_anticipe_min: number | null
          depart_id_terminal: string | null
          depart_ip: unknown
          depart_lat: number | null
          depart_lng: number | null
          depart_precision_gps_m: number | null
          distance_etablissement_m: number | null
          duree_brute_min: number | null
          duree_nette_min: number | null
          duree_pause_min: number | null
          heures_reelles: number | null
          id: string
          methode_pointage_arrivee: string | null
          methode_pointage_depart: string | null
          mission_id: string
          modifie_le: string | null
          motif_litige: string | null
          pause_debut_le: string | null
          pause_fin_le: string | null
          perimetre_gps_valide: boolean | null
          pointage_arrivee_le: string | null
          pointage_depart_le: string | null
          retard_min: number | null
          soignant_id: string
          valide_le: string | null
          valide_par_etablissement: boolean | null
        }
        Insert: {
          alerte_teleportation?: boolean | null
          alertes_fraude?: Json | null
          arrivee_id_terminal?: string | null
          arrivee_ip?: unknown
          arrivee_lat?: number | null
          arrivee_lng?: number | null
          arrivee_modele_terminal?: string | null
          arrivee_precision_gps_m?: number | null
          cree_le?: string | null
          depart_anticipe_min?: number | null
          depart_id_terminal?: string | null
          depart_ip?: unknown
          depart_lat?: number | null
          depart_lng?: number | null
          depart_precision_gps_m?: number | null
          distance_etablissement_m?: number | null
          duree_brute_min?: number | null
          duree_nette_min?: number | null
          duree_pause_min?: number | null
          heures_reelles?: number | null
          id?: string
          methode_pointage_arrivee?: string | null
          methode_pointage_depart?: string | null
          mission_id: string
          modifie_le?: string | null
          motif_litige?: string | null
          pause_debut_le?: string | null
          pause_fin_le?: string | null
          perimetre_gps_valide?: boolean | null
          pointage_arrivee_le?: string | null
          pointage_depart_le?: string | null
          retard_min?: number | null
          soignant_id: string
          valide_le?: string | null
          valide_par_etablissement?: boolean | null
        }
        Update: {
          alerte_teleportation?: boolean | null
          alertes_fraude?: Json | null
          arrivee_id_terminal?: string | null
          arrivee_ip?: unknown
          arrivee_lat?: number | null
          arrivee_lng?: number | null
          arrivee_modele_terminal?: string | null
          arrivee_precision_gps_m?: number | null
          cree_le?: string | null
          depart_anticipe_min?: number | null
          depart_id_terminal?: string | null
          depart_ip?: unknown
          depart_lat?: number | null
          depart_lng?: number | null
          depart_precision_gps_m?: number | null
          distance_etablissement_m?: number | null
          duree_brute_min?: number | null
          duree_nette_min?: number | null
          duree_pause_min?: number | null
          heures_reelles?: number | null
          id?: string
          methode_pointage_arrivee?: string | null
          methode_pointage_depart?: string | null
          mission_id?: string
          modifie_le?: string | null
          motif_litige?: string | null
          pause_debut_le?: string | null
          pause_fin_le?: string | null
          perimetre_gps_valide?: boolean | null
          pointage_arrivee_le?: string | null
          pointage_depart_le?: string | null
          retard_min?: number | null
          soignant_id?: string
          valide_le?: string | null
          valide_par_etablissement?: boolean | null
        }
        Relationships: [
          {
            foreignKeyName: "presences_mission_id_fkey"
            columns: ["mission_id"]
            isOneToOne: false
            referencedRelation: "missions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "presences_soignant_id_fkey"
            columns: ["soignant_id"]
            isOneToOne: false
            referencedRelation: "soignants"
            referencedColumns: ["id"]
          },
        ]
      }
      professions_liberal_eligible: {
        Row: {
          code_ape: string
          libelle_urssaf: string
          nom_ordre: string | null
          ordre_obligatoire: boolean | null
          plafond_micro: number | null
          profession: Database["public"]["Enums"]["type_profession"]
        }
        Insert: {
          code_ape: string
          libelle_urssaf: string
          nom_ordre?: string | null
          ordre_obligatoire?: boolean | null
          plafond_micro?: number | null
          profession: Database["public"]["Enums"]["type_profession"]
        }
        Update: {
          code_ape?: string
          libelle_urssaf?: string
          nom_ordre?: string | null
          ordre_obligatoire?: boolean | null
          plafond_micro?: number | null
          profession?: Database["public"]["Enums"]["type_profession"]
        }
        Relationships: []
      }
      reclamations_scoring: {
        Row: {
          cree_le: string | null
          details: string | null
          id: string
          justificatif_url: string | null
          mission_id: string
          motif: string
          points_restaures: number | null
          soignant_id: string
          statut: string | null
          traite_le: string | null
          traite_par: string | null
        }
        Insert: {
          cree_le?: string | null
          details?: string | null
          id?: string
          justificatif_url?: string | null
          mission_id: string
          motif: string
          points_restaures?: number | null
          soignant_id: string
          statut?: string | null
          traite_le?: string | null
          traite_par?: string | null
        }
        Update: {
          cree_le?: string | null
          details?: string | null
          id?: string
          justificatif_url?: string | null
          mission_id?: string
          motif?: string
          points_restaures?: number | null
          soignant_id?: string
          statut?: string | null
          traite_le?: string | null
          traite_par?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "reclamations_scoring_mission_id_fkey"
            columns: ["mission_id"]
            isOneToOne: false
            referencedRelation: "missions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "reclamations_scoring_soignant_id_fkey"
            columns: ["soignant_id"]
            isOneToOne: false
            referencedRelation: "soignants"
            referencedColumns: ["id"]
          },
        ]
      }
      rist_plafonds: {
        Row: {
          coefficient_plafond: number | null
          cree_le: string | null
          en_vigueur_depuis: string
          en_vigueur_jusqua: string | null
          id: string
          modifie_le: string | null
          plafond_calcule: number | null
          profession: Database["public"]["Enums"]["type_profession"]
          taux_horaire_brut_fph: number
          type_contrat: Database["public"]["Enums"]["type_contrat"]
        }
        Insert: {
          coefficient_plafond?: number | null
          cree_le?: string | null
          en_vigueur_depuis?: string
          en_vigueur_jusqua?: string | null
          id?: string
          modifie_le?: string | null
          plafond_calcule?: number | null
          profession: Database["public"]["Enums"]["type_profession"]
          taux_horaire_brut_fph: number
          type_contrat: Database["public"]["Enums"]["type_contrat"]
        }
        Update: {
          coefficient_plafond?: number | null
          cree_le?: string | null
          en_vigueur_depuis?: string
          en_vigueur_jusqua?: string | null
          id?: string
          modifie_le?: string | null
          plafond_calcule?: number | null
          profession?: Database["public"]["Enums"]["type_profession"]
          taux_horaire_brut_fph?: number
          type_contrat?: Database["public"]["Enums"]["type_contrat"]
        }
        Relationships: []
      }
      rpps_test: {
        Row: {
          nom: string
          prenom: string
          profession: string
          rpps: string
        }
        Insert: {
          nom: string
          prenom: string
          profession: string
          rpps: string
        }
        Update: {
          nom?: string
          prenom?: string
          profession?: string
          rpps?: string
        }
        Relationships: []
      }
      signatures_yousign: {
        Row: {
          contrat_id: string
          cree_le: string | null
          id: string
          signataire_etablissement_id: string | null
          signataire_soignant_id: string | null
          signe_le: string | null
          statut: string | null
          yousign_document_id: string | null
          yousign_signature_request_id: string | null
        }
        Insert: {
          contrat_id: string
          cree_le?: string | null
          id?: string
          signataire_etablissement_id?: string | null
          signataire_soignant_id?: string | null
          signe_le?: string | null
          statut?: string | null
          yousign_document_id?: string | null
          yousign_signature_request_id?: string | null
        }
        Update: {
          contrat_id?: string
          cree_le?: string | null
          id?: string
          signataire_etablissement_id?: string | null
          signataire_soignant_id?: string | null
          signe_le?: string | null
          statut?: string | null
          yousign_document_id?: string | null
          yousign_signature_request_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "signatures_yousign_contrat_id_fkey"
            columns: ["contrat_id"]
            isOneToOne: false
            referencedRelation: "contrats_mission"
            referencedColumns: ["id"]
          },
        ]
      }
      soignants: {
        Row: {
          adresse_code_postal: string | null
          adresse_lat: number | null
          adresse_lng: number | null
          adresse_rue: string | null
          adresse_ville: string | null
          annees_experience: number | null
          assujetti_tva: boolean | null
          attestation_cumul_activite: boolean
          attestation_cumul_le: string | null
          attestation_medecine_travail: boolean | null
          attestation_medecine_travail_le: string | null
          attestation_sante_signee_le: string | null
          attestation_vaccinations: boolean | null
          attestation_vaccinations_le: string | null
          avatar_url: string | null
          badge_ambassadeur: boolean
          bio: string | null
          code_ape: string | null
          code_parrainage: string | null
          coherence_details: Json | null
          coherence_identite: string | null
          compteur_notes_honoraires: number | null
          consentement_gps: boolean | null
          consentement_gps_le: string | null
          cree_le: string | null
          date_naissance: string | null
          date_passage_liberal: string | null
          derniere_activite_le: string | null
          diplome_verifie: boolean | null
          disponible_urgence: boolean | null
          eligible_conversion_3200h: boolean | null
          email: string
          est_cumul_activite: boolean | null
          est_salarie_etablissement: boolean | null
          heures_cumulees: number | null
          heures_plateforme: number | null
          iban_last4: string | null
          id: string
          identite_verifiee: boolean | null
          modifie_le: string | null
          nb_evaluations: number | null
          nom: string
          note_moyenne: number | null
          numero_adeli: string | null
          numero_rpps: string | null
          numero_secu: string | null
          numero_tva: string | null
          parraine_par: string | null
          premiere_mission_le: string | null
          prenom: string
          prevoyance_fournisseur: string | null
          prevoyance_inscrit: boolean | null
          prevoyance_numero_contrat: string | null
          priorite_missions_urgentes: boolean
          profession: Database["public"]["Enums"]["type_profession"]
          rayon_deplacement_km: number | null
          rib_partage_le: string | null
          rpps_nom_api: string | null
          rpps_prenom_api: string | null
          rpps_profession_api: string | null
          rpps_verifie: boolean | null
          rpps_verifie_le: string | null
          score_fiabilite: number | null
          siret_liberal: string | null
          specialites: string[] | null
          statut_liberal: string | null
          statut_verification_aria:
            | Database["public"]["Enums"]["statut_verification"]
            | null
          stripe_account_id: string | null
          supprime_le: string | null
          taux_horaire_minimum: number | null
          telephone: string | null
          total_absences: number | null
          total_missions_annulees: number | null
          total_missions_terminees: number | null
          total_missions_urgence: number | null
          total_retards_pointage: number | null
          tous_documents_valides: boolean | null
          type_contrat: Database["public"]["Enums"]["type_contrat"] | null
          type_exercice: string | null
          types_contrat_acceptes: string | null
          urgence_creneaux: Json | null
          urgence_rayon_km: number | null
          validation_3200h_le: string | null
          validation_3200h_par: string | null
          validation_3200h_statut: string | null
          ville_recherche: string | null
          ville_urgence: string | null
        }
        Insert: {
          adresse_code_postal?: string | null
          adresse_lat?: number | null
          adresse_lng?: number | null
          adresse_rue?: string | null
          adresse_ville?: string | null
          annees_experience?: number | null
          assujetti_tva?: boolean | null
          attestation_cumul_activite?: boolean
          attestation_cumul_le?: string | null
          attestation_medecine_travail?: boolean | null
          attestation_medecine_travail_le?: string | null
          attestation_sante_signee_le?: string | null
          attestation_vaccinations?: boolean | null
          attestation_vaccinations_le?: string | null
          avatar_url?: string | null
          badge_ambassadeur?: boolean
          bio?: string | null
          code_ape?: string | null
          code_parrainage?: string | null
          coherence_details?: Json | null
          coherence_identite?: string | null
          compteur_notes_honoraires?: number | null
          consentement_gps?: boolean | null
          consentement_gps_le?: string | null
          cree_le?: string | null
          date_naissance?: string | null
          date_passage_liberal?: string | null
          derniere_activite_le?: string | null
          diplome_verifie?: boolean | null
          disponible_urgence?: boolean | null
          eligible_conversion_3200h?: boolean | null
          email: string
          est_cumul_activite?: boolean | null
          est_salarie_etablissement?: boolean | null
          heures_cumulees?: number | null
          heures_plateforme?: number | null
          iban_last4?: string | null
          id?: string
          identite_verifiee?: boolean | null
          modifie_le?: string | null
          nb_evaluations?: number | null
          nom: string
          note_moyenne?: number | null
          numero_adeli?: string | null
          numero_rpps?: string | null
          numero_secu?: string | null
          numero_tva?: string | null
          parraine_par?: string | null
          premiere_mission_le?: string | null
          prenom: string
          prevoyance_fournisseur?: string | null
          prevoyance_inscrit?: boolean | null
          prevoyance_numero_contrat?: string | null
          priorite_missions_urgentes?: boolean
          profession: Database["public"]["Enums"]["type_profession"]
          rayon_deplacement_km?: number | null
          rib_partage_le?: string | null
          rpps_nom_api?: string | null
          rpps_prenom_api?: string | null
          rpps_profession_api?: string | null
          rpps_verifie?: boolean | null
          rpps_verifie_le?: string | null
          score_fiabilite?: number | null
          siret_liberal?: string | null
          specialites?: string[] | null
          statut_liberal?: string | null
          statut_verification_aria?:
            | Database["public"]["Enums"]["statut_verification"]
            | null
          stripe_account_id?: string | null
          supprime_le?: string | null
          taux_horaire_minimum?: number | null
          telephone?: string | null
          total_absences?: number | null
          total_missions_annulees?: number | null
          total_missions_terminees?: number | null
          total_missions_urgence?: number | null
          total_retards_pointage?: number | null
          tous_documents_valides?: boolean | null
          type_contrat?: Database["public"]["Enums"]["type_contrat"] | null
          type_exercice?: string | null
          types_contrat_acceptes?: string | null
          urgence_creneaux?: Json | null
          urgence_rayon_km?: number | null
          validation_3200h_le?: string | null
          validation_3200h_par?: string | null
          validation_3200h_statut?: string | null
          ville_recherche?: string | null
          ville_urgence?: string | null
        }
        Update: {
          adresse_code_postal?: string | null
          adresse_lat?: number | null
          adresse_lng?: number | null
          adresse_rue?: string | null
          adresse_ville?: string | null
          annees_experience?: number | null
          assujetti_tva?: boolean | null
          attestation_cumul_activite?: boolean
          attestation_cumul_le?: string | null
          attestation_medecine_travail?: boolean | null
          attestation_medecine_travail_le?: string | null
          attestation_sante_signee_le?: string | null
          attestation_vaccinations?: boolean | null
          attestation_vaccinations_le?: string | null
          avatar_url?: string | null
          badge_ambassadeur?: boolean
          bio?: string | null
          code_ape?: string | null
          code_parrainage?: string | null
          coherence_details?: Json | null
          coherence_identite?: string | null
          compteur_notes_honoraires?: number | null
          consentement_gps?: boolean | null
          consentement_gps_le?: string | null
          cree_le?: string | null
          date_naissance?: string | null
          date_passage_liberal?: string | null
          derniere_activite_le?: string | null
          diplome_verifie?: boolean | null
          disponible_urgence?: boolean | null
          eligible_conversion_3200h?: boolean | null
          email?: string
          est_cumul_activite?: boolean | null
          est_salarie_etablissement?: boolean | null
          heures_cumulees?: number | null
          heures_plateforme?: number | null
          iban_last4?: string | null
          id?: string
          identite_verifiee?: boolean | null
          modifie_le?: string | null
          nb_evaluations?: number | null
          nom?: string
          note_moyenne?: number | null
          numero_adeli?: string | null
          numero_rpps?: string | null
          numero_secu?: string | null
          numero_tva?: string | null
          parraine_par?: string | null
          premiere_mission_le?: string | null
          prenom?: string
          prevoyance_fournisseur?: string | null
          prevoyance_inscrit?: boolean | null
          prevoyance_numero_contrat?: string | null
          priorite_missions_urgentes?: boolean
          profession?: Database["public"]["Enums"]["type_profession"]
          rayon_deplacement_km?: number | null
          rib_partage_le?: string | null
          rpps_nom_api?: string | null
          rpps_prenom_api?: string | null
          rpps_profession_api?: string | null
          rpps_verifie?: boolean | null
          rpps_verifie_le?: string | null
          score_fiabilite?: number | null
          siret_liberal?: string | null
          specialites?: string[] | null
          statut_liberal?: string | null
          statut_verification_aria?:
            | Database["public"]["Enums"]["statut_verification"]
            | null
          stripe_account_id?: string | null
          supprime_le?: string | null
          taux_horaire_minimum?: number | null
          telephone?: string | null
          total_absences?: number | null
          total_missions_annulees?: number | null
          total_missions_terminees?: number | null
          total_missions_urgence?: number | null
          total_retards_pointage?: number | null
          tous_documents_valides?: boolean | null
          type_contrat?: Database["public"]["Enums"]["type_contrat"] | null
          type_exercice?: string | null
          types_contrat_acceptes?: string | null
          urgence_creneaux?: Json | null
          urgence_rayon_km?: number | null
          validation_3200h_le?: string | null
          validation_3200h_par?: string | null
          validation_3200h_statut?: string | null
          ville_recherche?: string | null
          ville_urgence?: string | null
        }
        Relationships: []
      }
      souscriptions_prevoyance: {
        Row: {
          cree_le: string | null
          date_debut: string
          date_fin: string | null
          id: string
          modifie_le: string | null
          plan_id: string
          soignant_id: string
          statut: string | null
          total_primes_payees: number | null
          total_subventions_recues: number | null
        }
        Insert: {
          cree_le?: string | null
          date_debut?: string
          date_fin?: string | null
          id?: string
          modifie_le?: string | null
          plan_id: string
          soignant_id: string
          statut?: string | null
          total_primes_payees?: number | null
          total_subventions_recues?: number | null
        }
        Update: {
          cree_le?: string | null
          date_debut?: string
          date_fin?: string | null
          id?: string
          modifie_le?: string | null
          plan_id?: string
          soignant_id?: string
          statut?: string | null
          total_primes_payees?: number | null
          total_subventions_recues?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "souscriptions_prevoyance_plan_id_fkey"
            columns: ["plan_id"]
            isOneToOne: false
            referencedRelation: "plans_prevoyance"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "souscriptions_prevoyance_soignant_id_fkey"
            columns: ["soignant_id"]
            isOneToOne: false
            referencedRelation: "soignants"
            referencedColumns: ["id"]
          },
        ]
      }
      statut_services_api: {
        Row: {
          dernier_controle_le: string | null
          dernier_echec_le: string | null
          dernier_succes_le: string | null
          details: Json | null
          disjoncteur_ouvert_le: string | null
          etat_disjoncteur: string | null
          id: string
          modifie_le: string | null
          nom_service: string
          nombre_echecs: number | null
          statut: string | null
        }
        Insert: {
          dernier_controle_le?: string | null
          dernier_echec_le?: string | null
          dernier_succes_le?: string | null
          details?: Json | null
          disjoncteur_ouvert_le?: string | null
          etat_disjoncteur?: string | null
          id?: string
          modifie_le?: string | null
          nom_service: string
          nombre_echecs?: number | null
          statut?: string | null
        }
        Update: {
          dernier_controle_le?: string | null
          dernier_echec_le?: string | null
          dernier_succes_le?: string | null
          details?: Json | null
          disjoncteur_ouvert_le?: string | null
          etat_disjoncteur?: string | null
          id?: string
          modifie_le?: string | null
          nom_service?: string
          nombre_echecs?: number | null
          statut?: string | null
        }
        Relationships: []
      }
      stripe_connect_onboarding: {
        Row: {
          business_type: string | null
          charges_enabled: boolean | null
          country: string | null
          cree_le: string | null
          details_submitted: boolean | null
          erreur_onboarding: string | null
          iban_last4: string | null
          id: string
          modifie_le: string | null
          onboarding_complete: boolean | null
          onboarding_complete_le: string | null
          payouts_enabled: boolean | null
          soignant_id: string
          statut: string | null
          stripe_account_id: string | null
          stripe_account_type: string | null
          type_exercice: string | null
        }
        Insert: {
          business_type?: string | null
          charges_enabled?: boolean | null
          country?: string | null
          cree_le?: string | null
          details_submitted?: boolean | null
          erreur_onboarding?: string | null
          iban_last4?: string | null
          id?: string
          modifie_le?: string | null
          onboarding_complete?: boolean | null
          onboarding_complete_le?: string | null
          payouts_enabled?: boolean | null
          soignant_id: string
          statut?: string | null
          stripe_account_id?: string | null
          stripe_account_type?: string | null
          type_exercice?: string | null
        }
        Update: {
          business_type?: string | null
          charges_enabled?: boolean | null
          country?: string | null
          cree_le?: string | null
          details_submitted?: boolean | null
          erreur_onboarding?: string | null
          iban_last4?: string | null
          id?: string
          modifie_le?: string | null
          onboarding_complete?: boolean | null
          onboarding_complete_le?: string | null
          payouts_enabled?: boolean | null
          soignant_id?: string
          statut?: string | null
          stripe_account_id?: string | null
          stripe_account_type?: string | null
          type_exercice?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "stripe_connect_onboarding_soignant_id_fkey"
            columns: ["soignant_id"]
            isOneToOne: true
            referencedRelation: "soignants"
            referencedColumns: ["id"]
          },
        ]
      }
      stripe_transfers: {
        Row: {
          charge_le: string | null
          cree_le: string | null
          erreur: string | null
          etablissement_id: string
          facture_id: string | null
          id: string
          mission_id: string
          montant_commission: number
          montant_soignant: number
          montant_total: number
          paye_le: string | null
          soignant_id: string
          statut: string
          stripe_charge_id: string | null
          stripe_payment_intent_id: string | null
          stripe_payout_id: string | null
          stripe_transfer_id: string | null
          transfere_le: string | null
        }
        Insert: {
          charge_le?: string | null
          cree_le?: string | null
          erreur?: string | null
          etablissement_id: string
          facture_id?: string | null
          id?: string
          mission_id: string
          montant_commission: number
          montant_soignant: number
          montant_total: number
          paye_le?: string | null
          soignant_id: string
          statut?: string
          stripe_charge_id?: string | null
          stripe_payment_intent_id?: string | null
          stripe_payout_id?: string | null
          stripe_transfer_id?: string | null
          transfere_le?: string | null
        }
        Update: {
          charge_le?: string | null
          cree_le?: string | null
          erreur?: string | null
          etablissement_id?: string
          facture_id?: string | null
          id?: string
          mission_id?: string
          montant_commission?: number
          montant_soignant?: number
          montant_total?: number
          paye_le?: string | null
          soignant_id?: string
          statut?: string
          stripe_charge_id?: string | null
          stripe_payment_intent_id?: string | null
          stripe_payout_id?: string | null
          stripe_transfer_id?: string | null
          transfere_le?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "stripe_transfers_etablissement_id_fkey"
            columns: ["etablissement_id"]
            isOneToOne: false
            referencedRelation: "etablissements"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "stripe_transfers_facture_id_fkey"
            columns: ["facture_id"]
            isOneToOne: false
            referencedRelation: "factures"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "stripe_transfers_mission_id_fkey"
            columns: ["mission_id"]
            isOneToOne: false
            referencedRelation: "missions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "stripe_transfers_soignant_id_fkey"
            columns: ["soignant_id"]
            isOneToOne: false
            referencedRelation: "soignants"
            referencedColumns: ["id"]
          },
        ]
      }
      suivi_conversion_3200h: {
        Row: {
          avantages_debloques: Json | null
          cree_le: string | null
          heures_a_inscription: number | null
          heures_actuelles: number | null
          id: string
          jalon_1600h_atteint: boolean | null
          jalon_2400h_atteint: boolean | null
          jalon_3200h_atteint: boolean | null
          jalon_800h_atteint: boolean | null
          modifie_le: string | null
          profession_cible_liberal: string | null
          progression_pourcent: number | null
          soignant_id: string
        }
        Insert: {
          avantages_debloques?: Json | null
          cree_le?: string | null
          heures_a_inscription?: number | null
          heures_actuelles?: number | null
          id?: string
          jalon_1600h_atteint?: boolean | null
          jalon_2400h_atteint?: boolean | null
          jalon_3200h_atteint?: boolean | null
          jalon_800h_atteint?: boolean | null
          modifie_le?: string | null
          profession_cible_liberal?: string | null
          progression_pourcent?: number | null
          soignant_id: string
        }
        Update: {
          avantages_debloques?: Json | null
          cree_le?: string | null
          heures_a_inscription?: number | null
          heures_actuelles?: number | null
          id?: string
          jalon_1600h_atteint?: boolean | null
          jalon_2400h_atteint?: boolean | null
          jalon_3200h_atteint?: boolean | null
          jalon_800h_atteint?: boolean | null
          modifie_le?: string | null
          profession_cible_liberal?: string | null
          progression_pourcent?: number | null
          soignant_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "suivi_conversion_3200h_soignant_id_fkey"
            columns: ["soignant_id"]
            isOneToOne: true
            referencedRelation: "soignants"
            referencedColumns: ["id"]
          },
        ]
      }
      templates_contrat: {
        Row: {
          contenu_html: string
          cree_le: string | null
          est_actif: boolean | null
          id: string
          modifie_le: string | null
          nom: string
          type_contrat: string
          variables: Json
          version: number | null
        }
        Insert: {
          contenu_html: string
          cree_le?: string | null
          est_actif?: boolean | null
          id?: string
          modifie_le?: string | null
          nom: string
          type_contrat: string
          variables?: Json
          version?: number | null
        }
        Update: {
          contenu_html?: string
          cree_le?: string | null
          est_actif?: boolean | null
          id?: string
          modifie_le?: string | null
          nom?: string
          type_contrat?: string
          variables?: Json
          version?: number | null
        }
        Relationships: []
      }
      tokens_calendrier: {
        Row: {
          cree_le: string | null
          expire_le: string | null
          id: string
          soignant_id: string
          token: string
        }
        Insert: {
          cree_le?: string | null
          expire_le?: string | null
          id?: string
          soignant_id: string
          token?: string
        }
        Update: {
          cree_le?: string | null
          expire_le?: string | null
          id?: string
          soignant_id?: string
          token?: string
        }
        Relationships: []
      }
      tokens_push: {
        Row: {
          actif: boolean | null
          cree_le: string | null
          derniere_utilisation: string | null
          id: string
          plateforme: string | null
          token: string
          utilisateur_id: string
        }
        Insert: {
          actif?: boolean | null
          cree_le?: string | null
          derniere_utilisation?: string | null
          id?: string
          plateforme?: string | null
          token: string
          utilisateur_id: string
        }
        Update: {
          actif?: boolean | null
          cree_le?: string | null
          derniere_utilisation?: string | null
          id?: string
          plateforme?: string | null
          token?: string
          utilisateur_id?: string
        }
        Relationships: []
      }
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      est_admin: { Args: never; Returns: boolean }
      est_admin_etablissement: { Args: never; Returns: boolean }
      est_soignant: { Args: never; Returns: boolean }
      fn_accepter_mission: { Args: { p_mission_id: string }; Returns: Json }
      fn_activer_liberal: { Args: never; Returns: Json }
      fn_admin_conformite: { Args: never; Returns: Json }
      fn_admin_conformite_detail: { Args: { p_type: string }; Returns: Json }
      fn_admin_finances: { Args: never; Returns: Json }
      fn_admin_finances_par_etablissement: { Args: never; Returns: Json }
      fn_admin_graphiques: { Args: never; Returns: Json }
      fn_admin_incoherences_identite: {
        Args: never
        Returns: {
          coherence_details: Json
          coherence_identite: string
          identite_verifiee: boolean
          nom: string
          prenom: string
          rpps_verifie: boolean
          soignant_id: string
        }[]
      }
      fn_admin_kpi: { Args: never; Returns: Json }
      fn_admin_planning_global: {
        Args: { p_debut?: string; p_fin?: string }
        Returns: Json
      }
      fn_admin_stripe_connect_stats: { Args: never; Returns: Json }
      fn_alerte_cddu_repetitif: {
        Args: { p_etablissement_id: string; p_soignant_id: string }
        Returns: Json
      }
      fn_annuler_mission: {
        Args: { p_mission_id: string; p_motif?: string }
        Returns: Json
      }
      fn_annuler_mission_etablissement: {
        Args: { p_mission_id: string; p_motif?: string }
        Returns: Json
      }
      fn_annuler_mission_soignant: {
        Args: { p_mission_id: string; p_motif?: string }
        Returns: Json
      }
      fn_annuler_serie: { Args: { p_serie_id: string }; Returns: Json }
      fn_annuler_serie_etablissement: {
        Args: { p_mission_ids: string[] }
        Returns: Json
      }
      fn_anonymiser_gps_anciennes: { Args: never; Returns: undefined }
      fn_appliquer_parrainage: { Args: { p_code: string }; Returns: Json }
      fn_appliquer_remise_groupe: { Args: never; Returns: Json }
      fn_assigner_mission_admin: {
        Args: { p_mission_id: string; p_soignant_id: string }
        Returns: Json
      }
      fn_auto_facturation_mensuelle: { Args: never; Returns: Json }
      fn_auto_valider_presences_72h: { Args: never; Returns: number }
      fn_badge_stats: { Args: never; Returns: Json }
      fn_bfa_info: { Args: { p_annee?: number }; Returns: Json }
      fn_calculer_bfa: {
        Args: {
          p_annee?: number
          p_etablissement_id?: string
          p_groupe_id?: string
        }
        Returns: Json
      }
      fn_calculer_bfa_safe: {
        Args: {
          p_annee?: number
          p_etablissement_id?: string
          p_groupe_id?: string
        }
        Returns: Json
      }
      fn_calculer_bfa_tous: { Args: never; Returns: Json }
      fn_calculer_cotisations: { Args: { p_mission_id: string }; Returns: Json }
      fn_calculer_heures_totales: {
        Args: { p_soignant_id: string }
        Returns: Json
      }
      fn_calculer_remuneration_mission: {
        Args: {
          p_debut: string
          p_etablissement_id: string
          p_fin: string
          p_soignant_id?: string
          p_taux_base: number
        }
        Returns: Json
      }
      fn_calculer_taux_free_transition: {
        Args: { p_soignant_id: string }
        Returns: Json
      }
      fn_calculer_taux_free_transition_safe: {
        Args: { p_soignant_id: string }
        Returns: Json
      }
      fn_charger_demo_investisseur: { Args: never; Returns: Json }
      fn_codes_pointage_mission: {
        Args: { p_mission_id: string }
        Returns: Json
      }
      fn_commission_info_etablissement: { Args: never; Returns: Json }
      fn_compteur_soignants_disponibles: {
        Args: { p_etablissement_id: string }
        Returns: Json
      }
      fn_confirmer_dpae: { Args: { p_contrat_id: string }; Returns: Json }
      fn_confirmer_reception_paiement: {
        Args: { p_paiement_id: string }
        Returns: Json
      }
      fn_confirmer_virement_admin: {
        Args: { p_facture_id: string }
        Returns: Json
      }
      fn_consentir_gps: { Args: { p_accepte: boolean }; Returns: Json }
      fn_consulter_rib_soignant: {
        Args: { p_mission_id: string }
        Returns: Json
      }
      fn_contester_paiement_soignant: {
        Args: { p_motif: string; p_paiement_id: string }
        Returns: Json
      }
      fn_contester_presence: {
        Args: { p_motif: string; p_presence_id: string }
        Returns: Json
      }
      fn_creer_mission: {
        Args: {
          p_debut_le?: string
          p_description?: string
          p_est_urgente?: boolean
          p_fin_le?: string
          p_intitule: string
          p_mode_attribution?: string
          p_niveau_urgence?: number
          p_profession_requise?: Database["public"]["Enums"]["type_profession"]
          p_serie_id?: string
          p_service?: string
          p_taux_horaire_base?: number
        }
        Returns: Json
      }
      fn_creer_notification: {
        Args: {
          p_corps: string
          p_destinataire_id: string
          p_id_ressource?: string
          p_lien?: string
          p_titre: string
          p_type: string
          p_type_destinataire: string
          p_type_ressource?: string
        }
        Returns: string
      }
      fn_creer_serie: {
        Args: {
          p_description?: string
          p_est_urgente?: boolean
          p_intitule: string
          p_missions?: Json
          p_niveau_urgence?: number
          p_profession_requise?: Database["public"]["Enums"]["type_profession"]
          p_service?: string
          p_taux_horaire_base?: number
        }
        Returns: Json
      }
      fn_declarer_paiement_soignant: {
        Args: {
          p_date_paiement?: string
          p_methode?: string
          p_mission_id: string
          p_montant: number
          p_reference?: string
        }
        Returns: Json
      }
      fn_declarer_virement: {
        Args: { p_facture_id: string; p_reference: string }
        Returns: Json
      }
      fn_deposer_chorus: {
        Args: { p_chorus_id?: string; p_facture_id: string }
        Returns: Json
      }
      fn_detecter_teleportation: {
        Args: {
          p_horodatage: string
          p_lat: number
          p_lng: number
          p_soignant_id: string
        }
        Returns: Json
      }
      fn_ecrire_audit: {
        Args: {
          p_acteur_id: string
          p_action: string
          p_cle_s3?: string
          p_details?: Json
          p_id_ressource?: string
          p_ip?: unknown
          p_navigateur?: string
          p_type_acteur: string
          p_type_ressource?: string
        }
        Returns: string
      }
      fn_ecrire_audit_safe: {
        Args: {
          p_acteur_id: string
          p_action: string
          p_cle_s3?: string
          p_details?: Json
          p_id_ressource: string
          p_ip?: unknown
          p_navigateur?: string
          p_type_acteur: string
          p_type_ressource: string
        }
        Returns: Json
      }
      fn_email_documents_expirants: {
        Args: never
        Returns: {
          date_expiration: string
          email: string
          prenom: string
          soignant_id: string
          type_document: string
        }[]
      }
      fn_email_eligible_liberal: {
        Args: never
        Returns: {
          email: string
          heures: number
          montant_offert: number
          prenom: string
          soignant_id: string
          taux_prise_en_charge: number
        }[]
      }
      fn_email_factures_impayees: {
        Args: never
        Returns: {
          email: string
          etablissement_id: string
          jours_depuis: number
          montant_ttc: string
          nom_etablissement: string
          numero_facture: string
        }[]
      }
      fn_email_rappels_j1: {
        Args: never
        Returns: {
          email: string
          etablissement: string
          heure_debut: string
          mission: string
          prenom: string
          soignant_id: string
        }[]
      }
      fn_email_recap_hebdo: {
        Args: never
        Returns: {
          email: string
          gains_semaine: number
          heures_semaine: number
          heures_totales: number
          missions_dispo: number
          missions_terminees: number
          prenom: string
          score: number
          soignant_id: string
        }[]
      }
      fn_enregistrer_siret_liberal: { Args: { p_siret: string }; Returns: Json }
      fn_envoyer_message: {
        Args: { p_contenu: string; p_conversation_id: string }
        Returns: Json
      }
      fn_est_exclu: {
        Args: { p_etablissement_id: string; p_soignant_id: string }
        Returns: boolean
      }
      fn_est_exclu_par_etablissement: {
        Args: { p_etablissement_id: string }
        Returns: boolean
      }
      fn_est_jour_ferie: { Args: { p_date: string }; Returns: boolean }
      fn_etablissement_pour_soignant: {
        Args: { p_etablissement_id: string }
        Returns: Json
      }
      fn_etablissement_public: {
        Args: { p_etablissement_id: string }
        Returns: {
          adresse_code_postal: string
          adresse_departement: string
          adresse_lat: number
          adresse_lng: number
          adresse_rue: string
          adresse_ville: string
          email_contact: string
          finess: string
          id: string
          nom: string
          telephone_contact: string
          type: Database["public"]["Enums"]["type_etablissement"]
        }[]
      }
      fn_etablissements_safe: {
        Args: { p_ids: string[] }
        Returns: {
          adresse_code_postal: string
          adresse_departement: string
          adresse_lat: number
          adresse_lng: number
          adresse_rue: string
          adresse_ville: string
          couleur_theme: string
          finess: string
          id: string
          logo_url: string
          nom: string
          taux_majoration_dimanche_pourcent: number
          taux_majoration_ferie_pourcent: number
          taux_majoration_nuit_pourcent: number
          type: Database["public"]["Enums"]["type_etablissement"]
        }[]
      }
      fn_evaluer_etablissement: {
        Args: { p_commentaire?: string; p_mission_id: string; p_note: number }
        Returns: Json
      }
      fn_evaluer_soignant: {
        Args: { p_commentaire?: string; p_mission_id: string; p_note: number }
        Returns: Json
      }
      fn_exclure_utilisateur: {
        Args: { p_exclu_id: string; p_motif?: string; p_type: string }
        Returns: Json
      }
      fn_export_fec: {
        Args: { p_annee: number }
        Returns: {
          comp_aux_lib: string
          comp_aux_num: string
          compte_lib: string
          compte_num: string
          credit: number
          debit: number
          ecriture_date: string
          ecriture_lib: string
          ecriture_num: string
          idevise: string
          journal_code: string
          journal_lib: string
          montant_devise: number
          piece_date: string
          piece_ref: string
        }[]
      }
      fn_exporter_mes_donnees: { Args: never; Returns: Json }
      fn_generer_code_parrainage: { Args: never; Returns: string }
      fn_generer_facture: { Args: { p_mission_id: string }; Returns: Json }
      fn_generer_facture_mensuelle: {
        Args: { p_etablissement_id: string }
        Returns: Json
      }
      fn_generer_jours_feries: { Args: { p_annee: number }; Returns: undefined }
      fn_generer_numero_contrat: { Args: { p_type: string }; Returns: string }
      fn_generer_numero_contrat_safe: {
        Args: { p_type: string }
        Returns: string
      }
      fn_generer_numero_facture: { Args: never; Returns: string }
      fn_generer_numero_note_honoraires: { Args: never; Returns: string }
      fn_get_my_role: { Args: never; Returns: Json }
      fn_get_stripe_account_soignant: {
        Args: { p_soignant_id: string }
        Returns: string
      }
      fn_health_check: { Args: never; Returns: Json }
      fn_html_escape: { Args: { p_text: string }; Returns: string }
      fn_is_valid_uuid: { Args: { p_text: string }; Returns: boolean }
      fn_maj_activite_soignant: { Args: never; Returns: Json }
      fn_marquer_messages_lus: {
        Args: { p_conversation_id: string }
        Returns: undefined
      }
      fn_matcher_soignants_mission: {
        Args: { p_mission_id: string }
        Returns: {
          distance_km: number
          documents_valides: boolean
          nom_complet: string
          plafond_48h_ok: boolean
          profession: Database["public"]["Enums"]["type_profession"]
          rang_matching: number
          repos_11h_ok: boolean
          score_fiabilite: number
          soignant_id: string
        }[]
      }
      fn_mes_etablissements_soignant: {
        Args: never
        Returns: {
          adresse_code_postal: string
          adresse_departement: string
          adresse_lat: number
          adresse_lng: number
          adresse_rue: string
          adresse_ville: string
          finess: string
          id: string
          nom: string
          taux_majoration_dimanche_pourcent: number
          taux_majoration_ferie_pourcent: number
          taux_majoration_nuit_pourcent: number
          type: Database["public"]["Enums"]["type_etablissement"]
        }[]
      }
      fn_mes_evaluations_recues: {
        Args: never
        Returns: {
          commentaire: string
          cree_le: string
          mission_id: string
          mission_intitule: string
          note: number
          type_evaluateur: string
        }[]
      }
      fn_mes_exclusions_recues: { Args: never; Returns: Json }
      fn_mes_filleuls: { Args: never; Returns: Json }
      fn_mes_missions_soignant: {
        Args: never
        Returns: {
          debut_le: string
          description: string
          duree_heures: number
          est_urgente: boolean
          etablissement_nom: string
          etablissement_ville: string
          fin_le: string
          id: string
          intitule: string
          montant_icp: number
          montant_ifm: number
          montant_majoration_dimanche: number
          montant_majoration_ferie: number
          montant_majoration_nuit: number
          net_a_payer: number
          profession_requise: Database["public"]["Enums"]["type_profession"]
          service: string
          statut: Database["public"]["Enums"]["statut_mission"]
          taux_horaire_base: number
          total_brut: number
        }[]
      }
      fn_mes_revenus_connect: { Args: { p_mois_debut?: string }; Returns: Json }
      fn_mes_soignants_etablissement: {
        Args: never
        Returns: {
          id: string
          nom: string
          numero_rpps: string
          prenom: string
          profession: Database["public"]["Enums"]["type_profession"]
          rpps_verifie: boolean
          score_fiabilite: number
          telephone: string
          total_missions_terminees: number
          tous_documents_valides: boolean
        }[]
      }
      fn_messages_non_lus: { Args: never; Returns: number }
      fn_missions_publiques_etablissement: {
        Args: { p_etablissement_id: string }
        Returns: {
          debut_le: string
          fin_le: string
          id: string
          intitule: string
          nom_etablissement: string
          profession_requise: Database["public"]["Enums"]["type_profession"]
          service: string
          taux_horaire_base: number
          ville_etablissement: string
        }[]
      }
      fn_missions_publiques_recherche: {
        Args: { p_profession?: string; p_ville?: string }
        Returns: {
          code_postal: string
          debut_le: string
          est_urgente: boolean
          fin_le: string
          id: string
          intitule: string
          profession_requise: string
          taux_horaire_base: number
          total_count: number
          type_contrat_recherche: string
          ville: string
        }[]
      }
      fn_mode_paiement_mission: {
        Args: { p_mission_id: string }
        Returns: Json
      }
      fn_modifier_mission_etablissement: {
        Args: {
          p_description?: string
          p_intitule: string
          p_mission_id: string
          p_service?: string
        }
        Returns: Json
      }
      fn_modifier_mon_etablissement: {
        Args: {
          p_adresse_code_postal?: string
          p_adresse_departement?: string
          p_adresse_lat?: number
          p_adresse_lng?: number
          p_adresse_rue?: string
          p_adresse_ville?: string
          p_contrat_url?: string
          p_convention_collective?: string
          p_couleur_theme?: string
          p_email_contact?: string
          p_finess?: string
          p_logo_url?: string
          p_mode_paiement_commission?: string
          p_nom?: string
          p_taux_majoration_dimanche?: number
          p_taux_majoration_ferie?: number
          p_taux_majoration_nuit?: number
          p_telephone?: string
        }
        Returns: Json
      }
      fn_modifier_mon_profil: {
        Args: {
          p_adresse_code_postal?: string
          p_adresse_lat?: number
          p_adresse_lng?: number
          p_adresse_rue?: string
          p_adresse_ville?: string
          p_annees_experience?: number
          p_avatar_url?: string
          p_bio?: string
          p_date_naissance?: string
          p_nom?: string
          p_numero_adeli?: string
          p_numero_rpps?: string
          p_prenom?: string
          p_rayon_deplacement_km?: number
          p_specialites?: string[]
          p_taux_horaire_minimum?: number
          p_telephone?: string
          p_type_exercice?: string
          p_types_contrat?: string[]
          p_ville_recherche?: string
          p_ville_urgence?: string
        }
        Returns: Json
      }
      fn_modifier_tva_liberal: {
        Args: { p_assujetti_tva: boolean; p_numero_tva?: string }
        Returns: Json
      }
      fn_mon_token_calendrier: { Args: never; Returns: string }
      fn_nettoyer_missions_fantomes: { Args: never; Returns: number }
      fn_nettoyer_tokens_push: { Args: never; Returns: number }
      fn_note_moyenne: { Args: { p_user_id: string }; Returns: Json }
      fn_notifier_documents_expirants: { Args: never; Returns: number }
      fn_obtenir_conversation: {
        Args: { p_autre_id: string; p_mission_id?: string }
        Returns: string
      }
      fn_planning_etablissement: {
        Args: { p_debut?: string; p_fin?: string }
        Returns: Json
      }
      fn_planning_soignant: {
        Args: { p_debut?: string; p_fin?: string }
        Returns: Json
      }
      fn_pointer_arrivee: {
        Args: {
          p_code_arrivee?: string
          p_lat?: number
          p_lng?: number
          p_mission_id: string
          p_modele?: string
          p_precision?: number
          p_terminal_id?: string
        }
        Returns: Json
      }
      fn_pointer_arrivee_code: {
        Args: { p_code: string; p_mission_id: string }
        Returns: Json
      }
      fn_pointer_debut_pause: {
        Args: { p_motif?: string; p_presence_id: string }
        Returns: Json
      }
      fn_pointer_depart: {
        Args: {
          p_code_depart?: string
          p_lat?: number
          p_lng?: number
          p_modele?: string
          p_precision?: number
          p_presence_id: string
          p_terminal_id?: string
        }
        Returns: Json
      }
      fn_pointer_depart_code: {
        Args: { p_code: string; p_presence_id: string }
        Returns: Json
      }
      fn_pointer_fin_pause: { Args: { p_presence_id: string }; Returns: Json }
      fn_pool_urgence_etablissement: {
        Args: { p_etablissement_id: string }
        Returns: {
          avatar_url: string
          bio: string
          derniere_mission_chez_nous: string
          distance_km: number
          en_mission_maintenant: boolean
          est_favori: boolean
          missions_urgence_terminees: number
          nom: string
          pool_urgence_rayon_km: number
          prenom: string
          profession: string
          score_fiabilite: number
          soignant_id: string
        }[]
      }
      fn_postuler_mission: {
        Args: { p_message?: string; p_mission_id: string }
        Returns: Json
      }
      fn_presences_detail_mission: {
        Args: { p_mission_id: string }
        Returns: Json
      }
      fn_proposer_mission_soignant: {
        Args: { p_mission_id: string; p_soignant_id: string }
        Returns: Json
      }
      fn_purger_audit_ancien: { Args: never; Returns: number }
      fn_purger_demo: { Args: never; Returns: Json }
      fn_purger_gps_ancien: { Args: never; Returns: number }
      fn_recalculer_palier_commission: {
        Args: { p_etablissement_id: string }
        Returns: Json
      }
      fn_recalculer_tous_paliers: { Args: never; Returns: number }
      fn_rechercher_utilisateurs: { Args: { p_query: string }; Returns: Json }
      fn_recommander_soignants: {
        Args: { p_limit?: number; p_mission_id: string }
        Returns: {
          distance_km: number
          est_favori: boolean
          id: string
          missions_etab: number
          nom: string
          prenom: string
          profession: Database["public"]["Enums"]["type_profession"]
          score_fiabilite: number
          score_matching: number
        }[]
      }
      fn_rejeter_virement_admin: {
        Args: { p_facture_id: string }
        Returns: Json
      }
      fn_relancer_signatures_contrats: { Args: never; Returns: number }
      fn_repondre_litige: {
        Args: { p_litige_id: string; p_reponse: string }
        Returns: Json
      }
      fn_resoudre_litige: {
        Args: { p_litige_id: string; p_resolution: string; p_statut: string }
        Returns: Json
      }
      fn_retirer_exclusion: { Args: { p_exclu_id: string }; Returns: Json }
      fn_rgpd_exporter_donnees_soignant: {
        Args: { p_soignant_id: string }
        Returns: Json
      }
      fn_rgpd_purge_automatique_inactifs: {
        Args: never
        Returns: {
          action_effectuee: string
          derniere_activite: string
          soignant_purge_id: string
        }[]
      }
      fn_sanitiser_html: { Args: { p_html: string }; Returns: string }
      fn_set_user_role: {
        Args: { p_etablissement_id?: string; p_role: string; p_user_id: string }
        Returns: undefined
      }
      fn_signer_attestation_sante: { Args: never; Returns: Json }
      fn_signer_contrat_etablissement: {
        Args: { p_contrat_id: string; p_signature_image: string }
        Returns: Json
      }
      fn_signer_contrat_soignant: {
        Args: { p_contrat_id: string; p_signature_image: string }
        Returns: Json
      }
      fn_soignant_pour_etablissement: {
        Args: { p_soignant_id: string }
        Returns: Json
      }
      fn_soignant_stripe_connect_actif: {
        Args: { p_soignant_id: string }
        Returns: boolean
      }
      fn_soignants_urgence: {
        Args: { p_mission_id: string }
        Returns: {
          distance_km: number
          id: string
          nom: string
          prenom: string
          score_fiabilite: number
          telephone: string
          urgence_rayon_km: number
        }[]
      }
      fn_souscrire_prevoyance: {
        Args: { p_numero_contrat?: string; p_plan_id: string }
        Returns: Json
      }
      fn_supprimer_mon_compte: { Args: never; Returns: Json }
      fn_terminer_mission: { Args: { p_mission_id: string }; Returns: Json }
      fn_toggle_pool_urgence: {
        Args: { p_actif: boolean; p_creneaux?: Json; p_rayon_km?: number }
        Returns: Json
      }
      fn_top_soignants: {
        Args: { p_limit?: number; p_profession?: string }
        Returns: {
          id: string
          nb_evaluations: number
          nom: string
          note_moyenne: number
          prenom: string
          profession: string
          score_fiabilite: number
          total_missions_terminees: number
        }[]
      }
      fn_traiter_candidature: {
        Args: { p_candidature_id: string; p_decision: string; p_motif?: string }
        Returns: Json
      }
      fn_traiter_reclamation: {
        Args: {
          p_points_restaures?: number
          p_reclamation_id: string
          p_statut: string
        }
        Returns: Json
      }
      fn_update_document_verification: {
        Args: {
          p_document_id: string
          p_motif_rejet?: string
          p_statut_verification: string
          p_valide_depuis?: string
          p_valide_jusqua?: string
          p_verifie_le?: string
        }
        Returns: undefined
      }
      fn_upsert_token_push: {
        Args: { p_plateforme: string; p_token: string }
        Returns: undefined
      }
      fn_user_id_pour_etablissement: {
        Args: { p_etablissement_id: string }
        Returns: string
      }
      fn_valider_etablissement: {
        Args: { p_etablissement_id: string; p_motif?: string; p_statut: string }
        Returns: Json
      }
      fn_valider_presence: { Args: { p_presence_id: string }; Returns: Json }
      fn_valider_presences_lot: { Args: { p_ids: string[] }; Returns: Json }
      fn_verifier_coherence_identite: {
        Args: { p_soignant_id: string }
        Returns: Json
      }
      fn_verifier_documents_expirants: { Args: never; Returns: number }
      mon_etablissement_id: { Args: never; Returns: string }
      mon_role: { Args: never; Returns: string }
    }
    Enums: {
      statut_mission:
        | "OUVERTE"
        | "ASSIGNEE"
        | "EN_COURS"
        | "TERMINEE"
        | "ANNULEE_PAR_ETABLISSEMENT"
        | "ANNULEE_PAR_SOIGNANT"
        | "ABSENCE"
        | "LITIGE"
      statut_verification:
        | "EN_ATTENTE"
        | "VERIFIE"
        | "REJETE"
        | "EXPIRE"
        | "REVUE_MANUELLE_REQUISE"
        | "API_INDISPONIBLE"
      type_contrat: "CDDU" | "CDDU_USAGE" | "VACATION" | "LIBERAL" | "SALARIE"
      type_document:
        | "CARTE_IDENTITE"
        | "PASSEPORT"
        | "TITRE_SEJOUR"
        | "DIPLOME"
        | "RPPS_ADELI"
        | "RCP_ASSURANCE"
        | "VACCINATIONS"
        | "CASIER_JUDICIAIRE"
        | "RIB"
        | "KBIS"
        | "ATTESTATION_URSSAF"
        | "AUTORISATION_EXERCICE"
        | "MEDECINE_TRAVAIL"
        | "FORMATION_OBLIGATOIRE"
        | "AUTRE"
        | "CARTE_ORDRE"
        | "ATTESTATION_CPAM"
        | "NOTE_HONORAIRES"
        | "ATTESTATION_3200H"
      type_etablissement:
        | "HOPITAL_PUBLIC"
        | "CLINIQUE_PRIVEE"
        | "EHPAD"
        | "SSIAD"
        | "HAD"
        | "CENTRE_SANTE"
        | "LABO"
        | "IME"
        | "MAS"
        | "FAM"
        | "PHARMACIE_OFFICINE"
        | "ESPIC"
      type_profession:
        | "IDE"
        | "AS"
        | "AES"
        | "IBODE"
        | "IADE"
        | "SAGE_FEMME"
        | "KINE"
        | "MEDECIN"
        | "PHARMACIEN"
        | "MANIPULATEUR_RADIO"
        | "PREPARATEUR_PHARMA"
        | "DIETETICIEN"
        | "ERGOTHERAPEUTE"
        | "PSYCHOMOTRICIEN"
        | "ORTHOPHONISTE"
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
}

type DatabaseWithoutInternals = Omit<Database, "__InternalSupabase">

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, "public">]

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] &
        DefaultSchema["Views"])
    ? (DefaultSchema["Tables"] &
        DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
        Row: infer R
      }
      ? R
      : never
    : never

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Insert: infer I
      }
      ? I
      : never
    : never

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Update: infer U
      }
      ? U
      : never
    : never

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    | keyof DefaultSchema["Enums"]
    | { schema: keyof DatabaseWithoutInternals },
  EnumName extends DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never = never,
> = DefaultSchemaEnumNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema["Enums"]
    ? DefaultSchema["Enums"][DefaultSchemaEnumNameOrOptions]
    : never

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    | keyof DefaultSchema["CompositeTypes"]
    | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never = never,
> = PublicCompositeTypeNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
    ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
    : never

export const Constants = {
  public: {
    Enums: {
      statut_mission: [
        "OUVERTE",
        "ASSIGNEE",
        "EN_COURS",
        "TERMINEE",
        "ANNULEE_PAR_ETABLISSEMENT",
        "ANNULEE_PAR_SOIGNANT",
        "ABSENCE",
        "LITIGE",
      ],
      statut_verification: [
        "EN_ATTENTE",
        "VERIFIE",
        "REJETE",
        "EXPIRE",
        "REVUE_MANUELLE_REQUISE",
        "API_INDISPONIBLE",
      ],
      type_contrat: ["CDDU", "CDDU_USAGE", "VACATION", "LIBERAL", "SALARIE"],
      type_document: [
        "CARTE_IDENTITE",
        "PASSEPORT",
        "TITRE_SEJOUR",
        "DIPLOME",
        "RPPS_ADELI",
        "RCP_ASSURANCE",
        "VACCINATIONS",
        "CASIER_JUDICIAIRE",
        "RIB",
        "KBIS",
        "ATTESTATION_URSSAF",
        "AUTORISATION_EXERCICE",
        "MEDECINE_TRAVAIL",
        "FORMATION_OBLIGATOIRE",
        "AUTRE",
        "CARTE_ORDRE",
        "ATTESTATION_CPAM",
        "NOTE_HONORAIRES",
        "ATTESTATION_3200H",
      ],
      type_etablissement: [
        "HOPITAL_PUBLIC",
        "CLINIQUE_PRIVEE",
        "EHPAD",
        "SSIAD",
        "HAD",
        "CENTRE_SANTE",
        "LABO",
        "IME",
        "MAS",
        "FAM",
        "PHARMACIE_OFFICINE",
        "ESPIC",
      ],
      type_profession: [
        "IDE",
        "AS",
        "AES",
        "IBODE",
        "IADE",
        "SAGE_FEMME",
        "KINE",
        "MEDECIN",
        "PHARMACIEN",
        "MANIPULATEUR_RADIO",
        "PREPARATEUR_PHARMA",
        "DIETETICIEN",
        "ERGOTHERAPEUTE",
        "PSYCHOMOTRICIEN",
        "ORTHOPHONISTE",
      ],
    },
  },
} as const
