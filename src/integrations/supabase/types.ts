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
          {
            foreignKeyName: "conformite_travail_soignant_id_fkey"
            columns: ["soignant_id"]
            isOneToOne: false
            referencedRelation: "vm_fiabilite_soignants"
            referencedColumns: ["soignant_id"]
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
          est_critique: boolean | null
          id: string
          libelle: string | null
          modifie_le: string | null
          motif_rejet: string | null
          nom_fichier: string
          rappel_expire_envoye: boolean | null
          rappel_j30_envoye: boolean | null
          rappel_j7_envoye: boolean | null
          s3_bucket: string
          s3_cle: string
          s3_version_id: string | null
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
          est_critique?: boolean | null
          id?: string
          libelle?: string | null
          modifie_le?: string | null
          motif_rejet?: string | null
          nom_fichier: string
          rappel_expire_envoye?: boolean | null
          rappel_j30_envoye?: boolean | null
          rappel_j7_envoye?: boolean | null
          s3_bucket?: string
          s3_cle: string
          s3_version_id?: string | null
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
          est_critique?: boolean | null
          id?: string
          libelle?: string | null
          modifie_le?: string | null
          motif_rejet?: string | null
          nom_fichier?: string
          rappel_expire_envoye?: boolean | null
          rappel_j30_envoye?: boolean | null
          rappel_j7_envoye?: boolean | null
          s3_bucket?: string
          s3_cle?: string
          s3_version_id?: string | null
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
          {
            foreignKeyName: "documents_soignants_soignant_id_fkey"
            columns: ["soignant_id"]
            isOneToOne: false
            referencedRelation: "vm_fiabilite_soignants"
            referencedColumns: ["soignant_id"]
          },
        ]
      }
      etablissements: {
        Row: {
          adresse_code_postal: string
          adresse_departement: string | null
          adresse_lat: number | null
          adresse_lng: number | null
          adresse_rue: string
          adresse_ville: string
          cree_le: string | null
          email_contact: string
          finess: string | null
          formule_abonnement: string | null
          groupe_sante_id: string | null
          id: string
          modifie_le: string | null
          nom: string
          rist_plafond_actif: boolean | null
          rist_taux_base_horaire: number | null
          siret: string
          supprime_le: string | null
          taux_majoration_dimanche_pourcent: number | null
          taux_majoration_ferie_pourcent: number | null
          taux_majoration_nuit_pourcent: number | null
          telephone_contact: string | null
          type: Database["public"]["Enums"]["type_etablissement"]
        }
        Insert: {
          adresse_code_postal: string
          adresse_departement?: string | null
          adresse_lat?: number | null
          adresse_lng?: number | null
          adresse_rue: string
          adresse_ville: string
          cree_le?: string | null
          email_contact: string
          finess?: string | null
          formule_abonnement?: string | null
          groupe_sante_id?: string | null
          id?: string
          modifie_le?: string | null
          nom: string
          rist_plafond_actif?: boolean | null
          rist_taux_base_horaire?: number | null
          siret: string
          supprime_le?: string | null
          taux_majoration_dimanche_pourcent?: number | null
          taux_majoration_ferie_pourcent?: number | null
          taux_majoration_nuit_pourcent?: number | null
          telephone_contact?: string | null
          type: Database["public"]["Enums"]["type_etablissement"]
        }
        Update: {
          adresse_code_postal?: string
          adresse_departement?: string | null
          adresse_lat?: number | null
          adresse_lng?: number | null
          adresse_rue?: string
          adresse_ville?: string
          cree_le?: string | null
          email_contact?: string
          finess?: string | null
          formule_abonnement?: string | null
          groupe_sante_id?: string | null
          id?: string
          modifie_le?: string | null
          nom?: string
          rist_plafond_actif?: boolean | null
          rist_taux_base_horaire?: number | null
          siret?: string
          supprime_le?: string | null
          taux_majoration_dimanche_pourcent?: number | null
          taux_majoration_ferie_pourcent?: number | null
          taux_majoration_nuit_pourcent?: number | null
          telephone_contact?: string | null
          type?: Database["public"]["Enums"]["type_etablissement"]
        }
        Relationships: [
          {
            foreignKeyName: "etablissements_groupe_sante_id_fkey"
            columns: ["groupe_sante_id"]
            isOneToOne: false
            referencedRelation: "groupes_sante"
            referencedColumns: ["id"]
          },
        ]
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
          cree_le: string | null
          email_admin: string | null
          formule_abonnement: string | null
          groupe_parent_id: string | null
          id: string
          modifie_le: string | null
          nom: string
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
          cree_le?: string | null
          email_admin?: string | null
          formule_abonnement?: string | null
          groupe_parent_id?: string | null
          id?: string
          modifie_le?: string | null
          nom: string
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
          cree_le?: string | null
          email_admin?: string | null
          formule_abonnement?: string | null
          groupe_parent_id?: string | null
          id?: string
          modifie_le?: string | null
          nom?: string
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
      missions: {
        Row: {
          cree_le: string | null
          debut_le: string
          description: string | null
          duree_heures: number | null
          est_urgente: boolean | null
          etablissement_id: string
          fin_le: string
          heures_dimanche: number | null
          heures_ferie: number | null
          heures_nuit: number | null
          id: string
          intitule: string
          modifie_le: string | null
          montant_icp: number | null
          montant_ifm: number | null
          montant_majoration_dimanche: number | null
          montant_majoration_ferie: number | null
          montant_majoration_nuit: number | null
          net_a_payer: number | null
          niveau_urgence: number | null
          profession_requise: Database["public"]["Enums"]["type_profession"]
          rist_plafond_applique: boolean | null
          service: string | null
          soignant_assigne_id: string | null
          statut: Database["public"]["Enums"]["statut_mission"] | null
          taux_horaire_base: number
          taux_icp: number | null
          taux_ifm: number | null
          taux_rist_plafonne: number | null
          total_brut: number | null
          yousign_id_procedure: string | null
          yousign_statut: string | null
        }
        Insert: {
          cree_le?: string | null
          debut_le: string
          description?: string | null
          duree_heures?: number | null
          est_urgente?: boolean | null
          etablissement_id: string
          fin_le: string
          heures_dimanche?: number | null
          heures_ferie?: number | null
          heures_nuit?: number | null
          id?: string
          intitule: string
          modifie_le?: string | null
          montant_icp?: number | null
          montant_ifm?: number | null
          montant_majoration_dimanche?: number | null
          montant_majoration_ferie?: number | null
          montant_majoration_nuit?: number | null
          net_a_payer?: number | null
          niveau_urgence?: number | null
          profession_requise: Database["public"]["Enums"]["type_profession"]
          rist_plafond_applique?: boolean | null
          service?: string | null
          soignant_assigne_id?: string | null
          statut?: Database["public"]["Enums"]["statut_mission"] | null
          taux_horaire_base: number
          taux_icp?: number | null
          taux_ifm?: number | null
          taux_rist_plafonne?: number | null
          total_brut?: number | null
          yousign_id_procedure?: string | null
          yousign_statut?: string | null
        }
        Update: {
          cree_le?: string | null
          debut_le?: string
          description?: string | null
          duree_heures?: number | null
          est_urgente?: boolean | null
          etablissement_id?: string
          fin_le?: string
          heures_dimanche?: number | null
          heures_ferie?: number | null
          heures_nuit?: number | null
          id?: string
          intitule?: string
          modifie_le?: string | null
          montant_icp?: number | null
          montant_ifm?: number | null
          montant_majoration_dimanche?: number | null
          montant_majoration_ferie?: number | null
          montant_majoration_nuit?: number | null
          net_a_payer?: number | null
          niveau_urgence?: number | null
          profession_requise?: Database["public"]["Enums"]["type_profession"]
          rist_plafond_applique?: boolean | null
          service?: string | null
          soignant_assigne_id?: string | null
          statut?: Database["public"]["Enums"]["statut_mission"] | null
          taux_horaire_base?: number
          taux_icp?: number | null
          taux_ifm?: number | null
          taux_rist_plafonne?: number | null
          total_brut?: number | null
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
          {
            foreignKeyName: "missions_soignant_assigne_id_fkey"
            columns: ["soignant_assigne_id"]
            isOneToOne: false
            referencedRelation: "vm_fiabilite_soignants"
            referencedColumns: ["soignant_id"]
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
          depart_id_terminal: string | null
          depart_ip: unknown
          depart_lat: number | null
          depart_lng: number | null
          depart_precision_gps_m: number | null
          distance_etablissement_m: number | null
          id: string
          mission_id: string
          modifie_le: string | null
          motif_litige: string | null
          perimetre_gps_valide: boolean | null
          pointage_arrivee_le: string | null
          pointage_depart_le: string | null
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
          depart_id_terminal?: string | null
          depart_ip?: unknown
          depart_lat?: number | null
          depart_lng?: number | null
          depart_precision_gps_m?: number | null
          distance_etablissement_m?: number | null
          id?: string
          mission_id: string
          modifie_le?: string | null
          motif_litige?: string | null
          perimetre_gps_valide?: boolean | null
          pointage_arrivee_le?: string | null
          pointage_depart_le?: string | null
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
          depart_id_terminal?: string | null
          depart_ip?: unknown
          depart_lat?: number | null
          depart_lng?: number | null
          depart_precision_gps_m?: number | null
          distance_etablissement_m?: number | null
          id?: string
          mission_id?: string
          modifie_le?: string | null
          motif_litige?: string | null
          perimetre_gps_valide?: boolean | null
          pointage_arrivee_le?: string | null
          pointage_depart_le?: string | null
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
          {
            foreignKeyName: "presences_soignant_id_fkey"
            columns: ["soignant_id"]
            isOneToOne: false
            referencedRelation: "vm_fiabilite_soignants"
            referencedColumns: ["soignant_id"]
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
      soignants: {
        Row: {
          adresse_lat: number | null
          adresse_lng: number | null
          cree_le: string | null
          date_naissance: string | null
          derniere_activite_le: string | null
          diplome_verifie: boolean | null
          eligible_conversion_3200h: boolean | null
          email: string
          heures_cumulees: number | null
          id: string
          identite_verifiee: boolean | null
          modifie_le: string | null
          nom: string
          numero_adeli: string | null
          numero_rpps: string | null
          prenom: string
          prevoyance_fournisseur: string | null
          prevoyance_inscrit: boolean | null
          prevoyance_numero_contrat: string | null
          profession: Database["public"]["Enums"]["type_profession"]
          rayon_deplacement_km: number | null
          rpps_verifie: boolean | null
          score_fiabilite: number | null
          statut_verification_aria:
            | Database["public"]["Enums"]["statut_verification"]
            | null
          supprime_le: string | null
          telephone: string | null
          total_absences: number | null
          total_missions_annulees: number | null
          total_missions_terminees: number | null
          total_retards_pointage: number | null
          tous_documents_valides: boolean | null
          type_contrat: Database["public"]["Enums"]["type_contrat"] | null
        }
        Insert: {
          adresse_lat?: number | null
          adresse_lng?: number | null
          cree_le?: string | null
          date_naissance?: string | null
          derniere_activite_le?: string | null
          diplome_verifie?: boolean | null
          eligible_conversion_3200h?: boolean | null
          email: string
          heures_cumulees?: number | null
          id?: string
          identite_verifiee?: boolean | null
          modifie_le?: string | null
          nom: string
          numero_adeli?: string | null
          numero_rpps?: string | null
          prenom: string
          prevoyance_fournisseur?: string | null
          prevoyance_inscrit?: boolean | null
          prevoyance_numero_contrat?: string | null
          profession: Database["public"]["Enums"]["type_profession"]
          rayon_deplacement_km?: number | null
          rpps_verifie?: boolean | null
          score_fiabilite?: number | null
          statut_verification_aria?:
            | Database["public"]["Enums"]["statut_verification"]
            | null
          supprime_le?: string | null
          telephone?: string | null
          total_absences?: number | null
          total_missions_annulees?: number | null
          total_missions_terminees?: number | null
          total_retards_pointage?: number | null
          tous_documents_valides?: boolean | null
          type_contrat?: Database["public"]["Enums"]["type_contrat"] | null
        }
        Update: {
          adresse_lat?: number | null
          adresse_lng?: number | null
          cree_le?: string | null
          date_naissance?: string | null
          derniere_activite_le?: string | null
          diplome_verifie?: boolean | null
          eligible_conversion_3200h?: boolean | null
          email?: string
          heures_cumulees?: number | null
          id?: string
          identite_verifiee?: boolean | null
          modifie_le?: string | null
          nom?: string
          numero_adeli?: string | null
          numero_rpps?: string | null
          prenom?: string
          prevoyance_fournisseur?: string | null
          prevoyance_inscrit?: boolean | null
          prevoyance_numero_contrat?: string | null
          profession?: Database["public"]["Enums"]["type_profession"]
          rayon_deplacement_km?: number | null
          rpps_verifie?: boolean | null
          score_fiabilite?: number | null
          statut_verification_aria?:
            | Database["public"]["Enums"]["statut_verification"]
            | null
          supprime_le?: string | null
          telephone?: string | null
          total_absences?: number | null
          total_missions_annulees?: number | null
          total_missions_terminees?: number | null
          total_retards_pointage?: number | null
          tous_documents_valides?: boolean | null
          type_contrat?: Database["public"]["Enums"]["type_contrat"] | null
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
          {
            foreignKeyName: "souscriptions_prevoyance_soignant_id_fkey"
            columns: ["soignant_id"]
            isOneToOne: false
            referencedRelation: "vm_fiabilite_soignants"
            referencedColumns: ["soignant_id"]
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
          {
            foreignKeyName: "suivi_conversion_3200h_soignant_id_fkey"
            columns: ["soignant_id"]
            isOneToOne: true
            referencedRelation: "vm_fiabilite_soignants"
            referencedColumns: ["soignant_id"]
          },
        ]
      }
    }
    Views: {
      vm_fiabilite_soignants: {
        Row: {
          categorie_soignant: string | null
          derniere_activite_le: string | null
          nom: string | null
          prenom: string | null
          profession: Database["public"]["Enums"]["type_profession"] | null
          score_calcule: number | null
          soignant_id: string | null
          total_absences: number | null
          total_missions_annulees: number | null
          total_missions_terminees: number | null
          total_retards_pointage: number | null
          tous_documents_valides: boolean | null
        }
        Relationships: []
      }
    }
    Functions: {
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
      fn_est_jour_ferie: { Args: { p_date: string }; Returns: boolean }
      fn_generer_jours_feries: { Args: { p_annee: number }; Returns: undefined }
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
      type_contrat: "CDDU" | "INTERIM" | "VACATION" | "LIBERAL" | "SALARIE"
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
      type_contrat: ["CDDU", "INTERIM", "VACATION", "LIBERAL", "SALARIE"],
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
