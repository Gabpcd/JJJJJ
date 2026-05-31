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
      admin_invocations: {
        Row: {
          admin_user_id: string
          completed_at: string | null
          dry_run: boolean
          duration_ms: number | null
          id: string
          internal_status: string
          invoked_at: string
          is_test: boolean
          reason: string
          request_id: string | null
          response_excerpt: string | null
          status_returned: number | null
          target_function: string
          target_payload: Json | null
        }
        Insert: {
          admin_user_id: string
          completed_at?: string | null
          dry_run?: boolean
          duration_ms?: number | null
          id?: string
          internal_status?: string
          invoked_at?: string
          is_test?: boolean
          reason: string
          request_id?: string | null
          response_excerpt?: string | null
          status_returned?: number | null
          target_function: string
          target_payload?: Json | null
        }
        Update: {
          admin_user_id?: string
          completed_at?: string | null
          dry_run?: boolean
          duration_ms?: number | null
          id?: string
          internal_status?: string
          invoked_at?: string
          is_test?: boolean
          reason?: string
          request_id?: string | null
          response_excerpt?: string | null
          status_returned?: number | null
          target_function?: string
          target_payload?: Json | null
        }
        Relationships: []
      }
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
      alertes_systeme: {
        Row: {
          cree_le: string
          details: Json | null
          email_envoye_le: string | null
          id: string
          message: string
          resolu_le: string | null
          severite: string
          source: string
          type_alerte: string
        }
        Insert: {
          cree_le?: string
          details?: Json | null
          email_envoye_le?: string | null
          id?: string
          message: string
          resolu_le?: string | null
          severite: string
          source: string
          type_alerte: string
        }
        Update: {
          cree_le?: string
          details?: Json | null
          email_envoye_le?: string | null
          id?: string
          message?: string
          resolu_le?: string | null
          severite?: string
          source?: string
          type_alerte?: string
        }
        Relationships: []
      }
      api_keys: {
        Row: {
          actif: boolean | null
          cle_api: string
          cle_secret: string | null
          cle_secret_hash: string | null
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
          cle_secret?: string | null
          cle_secret_hash?: string | null
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
          cle_secret?: string | null
          cle_secret_hash?: string | null
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
      articles_aide: {
        Row: {
          audience: string
          categorie: string
          contenu: string
          cree_le: string
          id: string
          mis_a_jour_le: string
          ordre_affichage: number
          publie: boolean
          slug: string
          titre: string
        }
        Insert: {
          audience: string
          categorie: string
          contenu: string
          cree_le?: string
          id?: string
          mis_a_jour_le?: string
          ordre_affichage?: number
          publie?: boolean
          slug: string
          titre: string
        }
        Update: {
          audience?: string
          categorie?: string
          contenu?: string
          cree_le?: string
          id?: string
          mis_a_jour_le?: string
          ordre_affichage?: number
          publie?: boolean
          slug?: string
          titre?: string
        }
        Relationships: []
      }
      assurance_config: {
        Row: {
          actif: boolean | null
          assurance_auto: boolean | null
          cree_le: string | null
          etablissement_id: string
          id: string
          montant_couverture_eur: number | null
          part_soignant_pourcent: number | null
          prise_en_charge: string | null
          provider: string | null
          provider_contrat_cadre: string | null
          type_couverture: string | null
        }
        Insert: {
          actif?: boolean | null
          assurance_auto?: boolean | null
          cree_le?: string | null
          etablissement_id: string
          id?: string
          montant_couverture_eur?: number | null
          part_soignant_pourcent?: number | null
          prise_en_charge?: string | null
          provider?: string | null
          provider_contrat_cadre?: string | null
          type_couverture?: string | null
        }
        Update: {
          actif?: boolean | null
          assurance_auto?: boolean | null
          cree_le?: string | null
          etablissement_id?: string
          id?: string
          montant_couverture_eur?: number | null
          part_soignant_pourcent?: number | null
          prise_en_charge?: string | null
          provider?: string | null
          provider_contrat_cadre?: string | null
          type_couverture?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "assurance_config_etablissement_id_fkey"
            columns: ["etablissement_id"]
            isOneToOne: true
            referencedRelation: "etablissements"
            referencedColumns: ["id"]
          },
        ]
      }
      assurances_mission: {
        Row: {
          accepte_conditions: boolean | null
          accepte_le: string | null
          cree_le: string | null
          debut_couverture: string
          etablissement_id: string
          fin_couverture: string
          franchise_eur: number | null
          id: string
          mission_id: string
          modifie_le: string | null
          montant_couverture_eur: number
          prime_ht_eur: number
          prime_ttc_eur: number
          provider: string | null
          provider_police_id: string | null
          provider_reference: string | null
          provider_sinistre_id: string | null
          sinistre_declare_le: string | null
          sinistre_description: string | null
          sinistre_montant_estime: number | null
          sinistre_statut: string | null
          soignant_id: string
          souscrit_par: string | null
          statut: string
          taux_tva: number | null
          type: string
        }
        Insert: {
          accepte_conditions?: boolean | null
          accepte_le?: string | null
          cree_le?: string | null
          debut_couverture: string
          etablissement_id: string
          fin_couverture: string
          franchise_eur?: number | null
          id?: string
          mission_id: string
          modifie_le?: string | null
          montant_couverture_eur?: number
          prime_ht_eur: number
          prime_ttc_eur: number
          provider?: string | null
          provider_police_id?: string | null
          provider_reference?: string | null
          provider_sinistre_id?: string | null
          sinistre_declare_le?: string | null
          sinistre_description?: string | null
          sinistre_montant_estime?: number | null
          sinistre_statut?: string | null
          soignant_id: string
          souscrit_par?: string | null
          statut?: string
          taux_tva?: number | null
          type?: string
        }
        Update: {
          accepte_conditions?: boolean | null
          accepte_le?: string | null
          cree_le?: string | null
          debut_couverture?: string
          etablissement_id?: string
          fin_couverture?: string
          franchise_eur?: number | null
          id?: string
          mission_id?: string
          modifie_le?: string | null
          montant_couverture_eur?: number
          prime_ht_eur?: number
          prime_ttc_eur?: number
          provider?: string | null
          provider_police_id?: string | null
          provider_reference?: string | null
          provider_sinistre_id?: string | null
          sinistre_declare_le?: string | null
          sinistre_description?: string | null
          sinistre_montant_estime?: number | null
          sinistre_statut?: string | null
          soignant_id?: string
          souscrit_par?: string | null
          statut?: string
          taux_tva?: number | null
          type?: string
        }
        Relationships: [
          {
            foreignKeyName: "assurances_mission_etablissement_id_fkey"
            columns: ["etablissement_id"]
            isOneToOne: false
            referencedRelation: "etablissements"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "assurances_mission_mission_id_fkey"
            columns: ["mission_id"]
            isOneToOne: false
            referencedRelation: "missions"
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
      bulletins_paie: {
        Row: {
          cree_le: string
          date_emission: string
          date_paiement: string | null
          etablissement_id: string
          icp: number
          id: string
          ifm: number
          mission_id: string
          modifie_le: string
          net_avant_impot: number
          numero_bulletin: string
          pdf_s3_key: string | null
          periode_debut: string
          periode_fin: string
          salaire_brut: number
          soignant_id: string
          statut: string
          total_cotisations_patronales: number
          total_cotisations_salariales: number
        }
        Insert: {
          cree_le?: string
          date_emission?: string
          date_paiement?: string | null
          etablissement_id: string
          icp?: number
          id?: string
          ifm?: number
          mission_id: string
          modifie_le?: string
          net_avant_impot: number
          numero_bulletin: string
          pdf_s3_key?: string | null
          periode_debut: string
          periode_fin: string
          salaire_brut: number
          soignant_id: string
          statut?: string
          total_cotisations_patronales?: number
          total_cotisations_salariales?: number
        }
        Update: {
          cree_le?: string
          date_emission?: string
          date_paiement?: string | null
          etablissement_id?: string
          icp?: number
          id?: string
          ifm?: number
          mission_id?: string
          modifie_le?: string
          net_avant_impot?: number
          numero_bulletin?: string
          pdf_s3_key?: string | null
          periode_debut?: string
          periode_fin?: string
          salaire_brut?: number
          soignant_id?: string
          statut?: string
          total_cotisations_patronales?: number
          total_cotisations_salariales?: number
        }
        Relationships: [
          {
            foreignKeyName: "bulletins_paie_etablissement_id_fkey"
            columns: ["etablissement_id"]
            isOneToOne: false
            referencedRelation: "etablissements"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "bulletins_paie_mission_id_fkey"
            columns: ["mission_id"]
            isOneToOne: true
            referencedRelation: "missions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "bulletins_paie_soignant_id_fkey"
            columns: ["soignant_id"]
            isOneToOne: false
            referencedRelation: "soignants"
            referencedColumns: ["id"]
          },
        ]
      }
      calendar_connections: {
        Row: {
          access_token: string | null
          calendar_id: string | null
          cree_le: string | null
          id: string
          last_sync_at: string | null
          last_sync_error: string | null
          modifie_le: string | null
          provider: string
          refresh_token: string | null
          sync_enabled: boolean | null
          token_expires_at: string | null
          utilisateur_id: string
        }
        Insert: {
          access_token?: string | null
          calendar_id?: string | null
          cree_le?: string | null
          id?: string
          last_sync_at?: string | null
          last_sync_error?: string | null
          modifie_le?: string | null
          provider: string
          refresh_token?: string | null
          sync_enabled?: boolean | null
          token_expires_at?: string | null
          utilisateur_id: string
        }
        Update: {
          access_token?: string | null
          calendar_id?: string | null
          cree_le?: string | null
          id?: string
          last_sync_at?: string | null
          last_sync_error?: string | null
          modifie_le?: string | null
          provider?: string
          refresh_token?: string | null
          sync_enabled?: boolean | null
          token_expires_at?: string | null
          utilisateur_id?: string
        }
        Relationships: []
      }
      calendar_events_sync: {
        Row: {
          connection_id: string
          cree_le: string | null
          external_event_id: string | null
          id: string
          last_synced_at: string | null
          mission_id: string
          sync_direction: string | null
        }
        Insert: {
          connection_id: string
          cree_le?: string | null
          external_event_id?: string | null
          id?: string
          last_synced_at?: string | null
          mission_id: string
          sync_direction?: string | null
        }
        Update: {
          connection_id?: string
          cree_le?: string | null
          external_event_id?: string | null
          id?: string
          last_synced_at?: string | null
          mission_id?: string
          sync_direction?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "calendar_events_sync_connection_id_fkey"
            columns: ["connection_id"]
            isOneToOne: false
            referencedRelation: "calendar_connections"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "calendar_events_sync_mission_id_fkey"
            columns: ["mission_id"]
            isOneToOne: false
            referencedRelation: "missions"
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
          type_contrat_choisi: string | null
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
          type_contrat_choisi?: string | null
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
          type_contrat_choisi?: string | null
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
      cessions_creance: {
        Row: {
          contenu_hash: string | null
          cree_le: string
          facture_honoraire_id: string
          id: string
          ip_address: string | null
          montant: number
          signed_at: string
          soignant_id: string
          user_agent: string | null
          version_texte: string
        }
        Insert: {
          contenu_hash?: string | null
          cree_le?: string
          facture_honoraire_id: string
          id?: string
          ip_address?: string | null
          montant: number
          signed_at?: string
          soignant_id: string
          user_agent?: string | null
          version_texte: string
        }
        Update: {
          contenu_hash?: string | null
          cree_le?: string
          facture_honoraire_id?: string
          id?: string
          ip_address?: string | null
          montant?: number
          signed_at?: string
          soignant_id?: string
          user_agent?: string | null
          version_texte?: string
        }
        Relationships: [
          {
            foreignKeyName: "cessions_creance_facture_honoraire_id_fkey"
            columns: ["facture_honoraire_id"]
            isOneToOne: false
            referencedRelation: "factures_honoraires"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "cessions_creance_soignant_id_fkey"
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
      chorus_submissions: {
        Row: {
          avoir_reference_invoice: string | null
          created_at: string
          error_code: string | null
          error_message: string | null
          id: string
          invoice_id: string
          last_checked_at: string | null
          payload_xml: string | null
          piste_request_id: string | null
          response_raw: Json | null
          status: string
          submission_type: string
          submitted_at: string | null
          type_document: string
        }
        Insert: {
          avoir_reference_invoice?: string | null
          created_at?: string
          error_code?: string | null
          error_message?: string | null
          id?: string
          invoice_id: string
          last_checked_at?: string | null
          payload_xml?: string | null
          piste_request_id?: string | null
          response_raw?: Json | null
          status?: string
          submission_type?: string
          submitted_at?: string | null
          type_document?: string
        }
        Update: {
          avoir_reference_invoice?: string | null
          created_at?: string
          error_code?: string | null
          error_message?: string | null
          id?: string
          invoice_id?: string
          last_checked_at?: string | null
          payload_xml?: string | null
          piste_request_id?: string | null
          response_raw?: Json | null
          status?: string
          submission_type?: string
          submitted_at?: string | null
          type_document?: string
        }
        Relationships: [
          {
            foreignKeyName: "chorus_submissions_invoice_id_fkey"
            columns: ["invoice_id"]
            isOneToOne: false
            referencedRelation: "factures_honoraires"
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
          contenu_html_rendu_le: string | null
          cree_le: string | null
          dpae_effectuee: boolean | null
          dpae_effectuee_le: string | null
          dpae_numero: string | null
          etablissement_id: string
          hash_document: string | null
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
          storage_path: string | null
          template_slug: string | null
          type_contrat: string
          yousign_document_id: string | null
          yousign_procedure_id: string | null
        }
        Insert: {
          contenu_html?: string | null
          contenu_html_rendu_le?: string | null
          cree_le?: string | null
          dpae_effectuee?: boolean | null
          dpae_effectuee_le?: string | null
          dpae_numero?: string | null
          etablissement_id: string
          hash_document?: string | null
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
          storage_path?: string | null
          template_slug?: string | null
          type_contrat: string
          yousign_document_id?: string | null
          yousign_procedure_id?: string | null
        }
        Update: {
          contenu_html?: string | null
          contenu_html_rendu_le?: string | null
          cree_le?: string | null
          dpae_effectuee?: boolean | null
          dpae_effectuee_le?: string | null
          dpae_numero?: string | null
          etablissement_id?: string
          hash_document?: string | null
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
          storage_path?: string | null
          template_slug?: string | null
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
      contrats_service_signatures: {
        Row: {
          contenu_hash: string | null
          cree_le: string
          etablissement_id: string
          id: string
          ip_address: string | null
          motif_revocation: string | null
          pdf_url: string | null
          revoked_at: string | null
          signature_s3_key: string | null
          signed_at: string
          user_agent: string | null
          version: string
        }
        Insert: {
          contenu_hash?: string | null
          cree_le?: string
          etablissement_id: string
          id?: string
          ip_address?: string | null
          motif_revocation?: string | null
          pdf_url?: string | null
          revoked_at?: string | null
          signature_s3_key?: string | null
          signed_at?: string
          user_agent?: string | null
          version?: string
        }
        Update: {
          contenu_hash?: string | null
          cree_le?: string
          etablissement_id?: string
          id?: string
          ip_address?: string | null
          motif_revocation?: string | null
          pdf_url?: string | null
          revoked_at?: string | null
          signature_s3_key?: string | null
          signed_at?: string
          user_agent?: string | null
          version?: string
        }
        Relationships: [
          {
            foreignKeyName: "contrats_service_signatures_etablissement_id_fkey"
            columns: ["etablissement_id"]
            isOneToOne: false
            referencedRelation: "etablissements"
            referencedColumns: ["id"]
          },
        ]
      }
      contrats_travail_missions: {
        Row: {
          cree_le: string
          etablissement_id: string
          id: string
          mission_id: string
          nom_fichier: string | null
          pdf_s3_key: string
          soignant_id: string | null
          taille_octets: number | null
          uploaded_at: string
          uploaded_by: string
        }
        Insert: {
          cree_le?: string
          etablissement_id: string
          id?: string
          mission_id: string
          nom_fichier?: string | null
          pdf_s3_key: string
          soignant_id?: string | null
          taille_octets?: number | null
          uploaded_at?: string
          uploaded_by: string
        }
        Update: {
          cree_le?: string
          etablissement_id?: string
          id?: string
          mission_id?: string
          nom_fichier?: string | null
          pdf_s3_key?: string
          soignant_id?: string | null
          taille_octets?: number | null
          uploaded_at?: string
          uploaded_by?: string
        }
        Relationships: [
          {
            foreignKeyName: "contrats_travail_missions_etablissement_id_fkey"
            columns: ["etablissement_id"]
            isOneToOne: false
            referencedRelation: "etablissements"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "contrats_travail_missions_mission_id_fkey"
            columns: ["mission_id"]
            isOneToOne: true
            referencedRelation: "missions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "contrats_travail_missions_soignant_id_fkey"
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
      credits_etablissement: {
        Row: {
          applique_le: string | null
          cree_le: string
          etablissement_id: string
          facture_id: string | null
          id: string
          montant_eur: number
          motif: Database["public"]["Enums"]["credit_etab_motif"]
          parrainage_id: string | null
        }
        Insert: {
          applique_le?: string | null
          cree_le?: string
          etablissement_id: string
          facture_id?: string | null
          id?: string
          montant_eur: number
          motif: Database["public"]["Enums"]["credit_etab_motif"]
          parrainage_id?: string | null
        }
        Update: {
          applique_le?: string | null
          cree_le?: string
          etablissement_id?: string
          facture_id?: string | null
          id?: string
          montant_eur?: number
          motif?: Database["public"]["Enums"]["credit_etab_motif"]
          parrainage_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "credits_etablissement_etablissement_id_fkey"
            columns: ["etablissement_id"]
            isOneToOne: false
            referencedRelation: "etablissements"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "credits_etablissement_facture_id_fkey"
            columns: ["facture_id"]
            isOneToOne: false
            referencedRelation: "factures"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "credits_etablissement_parrainage_id_fkey"
            columns: ["parrainage_id"]
            isOneToOne: false
            referencedRelation: "parrainages_etablissements"
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
      email_queue: {
        Row: {
          cree_le: string
          data: Json | null
          destinataire_email: string | null
          destinataire_id: string | null
          envoye: boolean | null
          envoye_le: string | null
          erreur: string | null
          id: string
          statut: string
          type: string
        }
        Insert: {
          cree_le?: string
          data?: Json | null
          destinataire_email?: string | null
          destinataire_id?: string | null
          envoye?: boolean | null
          envoye_le?: string | null
          erreur?: string | null
          id?: string
          statut?: string
          type: string
        }
        Update: {
          cree_le?: string
          data?: Json | null
          destinataire_email?: string | null
          destinataire_id?: string | null
          envoye?: boolean | null
          envoye_le?: string | null
          erreur?: string | null
          id?: string
          statut?: string
          type?: string
        }
        Relationships: []
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
      equipe_membres: {
        Row: {
          depuis_le: string | null
          equipe_id: string
          id: string
          role_equipe: string | null
          soignant_id: string
        }
        Insert: {
          depuis_le?: string | null
          equipe_id: string
          id?: string
          role_equipe?: string | null
          soignant_id: string
        }
        Update: {
          depuis_le?: string | null
          equipe_id?: string
          id?: string
          role_equipe?: string | null
          soignant_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "equipe_membres_equipe_id_fkey"
            columns: ["equipe_id"]
            isOneToOne: false
            referencedRelation: "equipes"
            referencedColumns: ["id"]
          },
        ]
      }
      equipes: {
        Row: {
          couleur: string | null
          cree_le: string | null
          etablissement_id: string
          id: string
          nom: string
          service: string | null
          supprime_le: string | null
        }
        Insert: {
          couleur?: string | null
          cree_le?: string | null
          etablissement_id: string
          id?: string
          nom: string
          service?: string | null
          supprime_le?: string | null
        }
        Update: {
          couleur?: string | null
          cree_le?: string | null
          etablissement_id?: string
          id?: string
          nom?: string
          service?: string | null
          supprime_le?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "equipes_etablissement_id_fkey"
            columns: ["etablissement_id"]
            isOneToOne: false
            referencedRelation: "etablissements"
            referencedColumns: ["id"]
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
          bloque_auto_le: string | null
          bloque_auto_raisons: Json | null
          chorus_pro_actif: boolean | null
          chorus_pro_identifiant: string | null
          code_parrainage: string | null
          contrat_service_signe: boolean
          contrat_service_signe_le: string | null
          contrat_uploade_le: string | null
          contrat_url: string | null
          contrat_valide: boolean | null
          convention_collective: string | null
          couleur_theme: string | null
          cree_le: string | null
          delai_paiement_jours: number | null
          description: string | null
          email_contact: string
          est_secteur_public: boolean | null
          finess: string | null
          finess_verifie: boolean | null
          finess_verifie_le: string | null
          formule_abonnement: string | null
          groupe_sante_id: string | null
          heure_debut_nuit: string | null
          heure_fin_nuit: string | null
          horaires_ouverture: Json | null
          id: string
          logo_url: string | null
          missions_mois_precedent: number | null
          mode_facturation: string | null
          mode_paiement_commission: string | null
          modifie_le: string | null
          motif_rejet: string | null
          nb_evaluations: number | null
          niveau: Database["public"]["Enums"]["niveau_qualitatif"] | null
          nom: string
          note_moyenne: number | null
          palier_commission_id: string | null
          palier_recalcule_le: string | null
          parraine_par_id: string | null
          peut_publier_missions: boolean | null
          rib_s3_key: string | null
          rist_plafond_actif: boolean | null
          rist_taux_base_horaire: number | null
          score_qualite: number | null
          siret: string
          siret_categorie_juridique: string | null
          siret_code_naf: string | null
          siret_est_actif: boolean | null
          siret_raison_sociale: string | null
          siret_verifie: boolean | null
          siret_verifie_le: string | null
          sms_actif: boolean | null
          sms_consent_le: string | null
          statut_verification: string | null
          stripe_account_id: string | null
          stripe_customer_id: string | null
          stripe_sepa_payment_method_id: string | null
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
          bloque_auto_le?: string | null
          bloque_auto_raisons?: Json | null
          chorus_pro_actif?: boolean | null
          chorus_pro_identifiant?: string | null
          code_parrainage?: string | null
          contrat_service_signe?: boolean
          contrat_service_signe_le?: string | null
          contrat_uploade_le?: string | null
          contrat_url?: string | null
          contrat_valide?: boolean | null
          convention_collective?: string | null
          couleur_theme?: string | null
          cree_le?: string | null
          delai_paiement_jours?: number | null
          description?: string | null
          email_contact: string
          est_secteur_public?: boolean | null
          finess?: string | null
          finess_verifie?: boolean | null
          finess_verifie_le?: string | null
          formule_abonnement?: string | null
          groupe_sante_id?: string | null
          heure_debut_nuit?: string | null
          heure_fin_nuit?: string | null
          horaires_ouverture?: Json | null
          id?: string
          logo_url?: string | null
          missions_mois_precedent?: number | null
          mode_facturation?: string | null
          mode_paiement_commission?: string | null
          modifie_le?: string | null
          motif_rejet?: string | null
          nb_evaluations?: number | null
          niveau?: Database["public"]["Enums"]["niveau_qualitatif"] | null
          nom: string
          note_moyenne?: number | null
          palier_commission_id?: string | null
          palier_recalcule_le?: string | null
          parraine_par_id?: string | null
          peut_publier_missions?: boolean | null
          rib_s3_key?: string | null
          rist_plafond_actif?: boolean | null
          rist_taux_base_horaire?: number | null
          score_qualite?: number | null
          siret: string
          siret_categorie_juridique?: string | null
          siret_code_naf?: string | null
          siret_est_actif?: boolean | null
          siret_raison_sociale?: string | null
          siret_verifie?: boolean | null
          siret_verifie_le?: string | null
          sms_actif?: boolean | null
          sms_consent_le?: string | null
          statut_verification?: string | null
          stripe_account_id?: string | null
          stripe_customer_id?: string | null
          stripe_sepa_payment_method_id?: string | null
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
          bloque_auto_le?: string | null
          bloque_auto_raisons?: Json | null
          chorus_pro_actif?: boolean | null
          chorus_pro_identifiant?: string | null
          code_parrainage?: string | null
          contrat_service_signe?: boolean
          contrat_service_signe_le?: string | null
          contrat_uploade_le?: string | null
          contrat_url?: string | null
          contrat_valide?: boolean | null
          convention_collective?: string | null
          couleur_theme?: string | null
          cree_le?: string | null
          delai_paiement_jours?: number | null
          description?: string | null
          email_contact?: string
          est_secteur_public?: boolean | null
          finess?: string | null
          finess_verifie?: boolean | null
          finess_verifie_le?: string | null
          formule_abonnement?: string | null
          groupe_sante_id?: string | null
          heure_debut_nuit?: string | null
          heure_fin_nuit?: string | null
          horaires_ouverture?: Json | null
          id?: string
          logo_url?: string | null
          missions_mois_precedent?: number | null
          mode_facturation?: string | null
          mode_paiement_commission?: string | null
          modifie_le?: string | null
          motif_rejet?: string | null
          nb_evaluations?: number | null
          niveau?: Database["public"]["Enums"]["niveau_qualitatif"] | null
          nom?: string
          note_moyenne?: number | null
          palier_commission_id?: string | null
          palier_recalcule_le?: string | null
          parraine_par_id?: string | null
          peut_publier_missions?: boolean | null
          rib_s3_key?: string | null
          rist_plafond_actif?: boolean | null
          rist_taux_base_horaire?: number | null
          score_qualite?: number | null
          siret?: string
          siret_categorie_juridique?: string | null
          siret_code_naf?: string | null
          siret_est_actif?: boolean | null
          siret_raison_sociale?: string | null
          siret_verifie?: boolean | null
          siret_verifie_le?: string | null
          sms_actif?: boolean | null
          sms_consent_le?: string | null
          statut_verification?: string | null
          stripe_account_id?: string | null
          stripe_customer_id?: string | null
          stripe_sepa_payment_method_id?: string | null
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
          {
            foreignKeyName: "etablissements_parraine_par_id_fkey"
            columns: ["parraine_par_id"]
            isOneToOne: false
            referencedRelation: "etablissements"
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
      factor_advances: {
        Row: {
          approuvee_le: string | null
          cree_le: string
          etablissement_id: string
          facture_honoraire_id: string
          financee_le: string | null
          frais_factor: number | null
          frais_jolene: number | null
          id: string
          mission_id: string | null
          modifie_le: string
          montant_facture_ttc: number
          montant_net_soignant: number | null
          motif_rejet: string | null
          provider: string
          provider_advance_id: string | null
          provider_invoice_id: string | null
          raw_response: Json | null
          recouvree_le: string | null
          soignant_id: string
          statut: string
        }
        Insert: {
          approuvee_le?: string | null
          cree_le?: string
          etablissement_id: string
          facture_honoraire_id: string
          financee_le?: string | null
          frais_factor?: number | null
          frais_jolene?: number | null
          id?: string
          mission_id?: string | null
          modifie_le?: string
          montant_facture_ttc: number
          montant_net_soignant?: number | null
          motif_rejet?: string | null
          provider?: string
          provider_advance_id?: string | null
          provider_invoice_id?: string | null
          raw_response?: Json | null
          recouvree_le?: string | null
          soignant_id: string
          statut?: string
        }
        Update: {
          approuvee_le?: string | null
          cree_le?: string
          etablissement_id?: string
          facture_honoraire_id?: string
          financee_le?: string | null
          frais_factor?: number | null
          frais_jolene?: number | null
          id?: string
          mission_id?: string | null
          modifie_le?: string
          montant_facture_ttc?: number
          montant_net_soignant?: number | null
          motif_rejet?: string | null
          provider?: string
          provider_advance_id?: string | null
          provider_invoice_id?: string | null
          raw_response?: Json | null
          recouvree_le?: string | null
          soignant_id?: string
          statut?: string
        }
        Relationships: [
          {
            foreignKeyName: "factor_advances_etablissement_id_fkey"
            columns: ["etablissement_id"]
            isOneToOne: false
            referencedRelation: "etablissements"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "factor_advances_facture_honoraire_id_fkey"
            columns: ["facture_honoraire_id"]
            isOneToOne: false
            referencedRelation: "factures_honoraires"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "factor_advances_mission_id_fkey"
            columns: ["mission_id"]
            isOneToOne: false
            referencedRelation: "missions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "factor_advances_soignant_id_fkey"
            columns: ["soignant_id"]
            isOneToOne: false
            referencedRelation: "soignants"
            referencedColumns: ["id"]
          },
        ]
      }
      factoring_partners: {
        Row: {
          active: boolean
          address: string | null
          api_credentials: Json | null
          bic: string | null
          contact_email: string | null
          created_at: string
          iban: string
          id: string
          legal_name: string
          siret: string
          subrogation_template: string | null
          updated_at: string | null
          webhook_url: string | null
        }
        Insert: {
          active?: boolean
          address?: string | null
          api_credentials?: Json | null
          bic?: string | null
          contact_email?: string | null
          created_at?: string
          iban: string
          id?: string
          legal_name: string
          siret: string
          subrogation_template?: string | null
          updated_at?: string | null
          webhook_url?: string | null
        }
        Update: {
          active?: boolean
          address?: string | null
          api_credentials?: Json | null
          bic?: string | null
          contact_email?: string | null
          created_at?: string
          iban?: string
          id?: string
          legal_name?: string
          siret?: string
          subrogation_template?: string | null
          updated_at?: string | null
          webhook_url?: string | null
        }
        Relationships: []
      }
      factures: {
        Row: {
          bloque_le: string | null
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
          facture_precedente_id: string | null
          id: string
          mission_id: string | null
          mode_paiement: string | null
          modifie_le: string | null
          montant_ht: number
          montant_signe: number | null
          montant_ttc: number
          montant_tva: number
          nombre_missions: number | null
          numero_facture: string
          periode_debut: string | null
          periode_fin: string | null
          relance_1_le: string | null
          relance_2_le: string | null
          statut: string | null
          stripe_hosted_url: string | null
          stripe_invoice_id: string | null
          stripe_payment_intent_id: string | null
          taux_tva: number | null
          type_document: string
          virement_confirme_le: string | null
          virement_confirme_par: string | null
          virement_reference: string | null
        }
        Insert: {
          bloque_le?: string | null
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
          facture_precedente_id?: string | null
          id?: string
          mission_id?: string | null
          mode_paiement?: string | null
          modifie_le?: string | null
          montant_ht: number
          montant_signe?: number | null
          montant_ttc: number
          montant_tva: number
          nombre_missions?: number | null
          numero_facture: string
          periode_debut?: string | null
          periode_fin?: string | null
          relance_1_le?: string | null
          relance_2_le?: string | null
          statut?: string | null
          stripe_hosted_url?: string | null
          stripe_invoice_id?: string | null
          stripe_payment_intent_id?: string | null
          taux_tva?: number | null
          type_document?: string
          virement_confirme_le?: string | null
          virement_confirme_par?: string | null
          virement_reference?: string | null
        }
        Update: {
          bloque_le?: string | null
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
          facture_precedente_id?: string | null
          id?: string
          mission_id?: string | null
          mode_paiement?: string | null
          modifie_le?: string | null
          montant_ht?: number
          montant_signe?: number | null
          montant_ttc?: number
          montant_tva?: number
          nombre_missions?: number | null
          numero_facture?: string
          periode_debut?: string | null
          periode_fin?: string | null
          relance_1_le?: string | null
          relance_2_le?: string | null
          statut?: string | null
          stripe_hosted_url?: string | null
          stripe_invoice_id?: string | null
          stripe_payment_intent_id?: string | null
          taux_tva?: number | null
          type_document?: string
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
            foreignKeyName: "factures_facture_precedente_id_fkey"
            columns: ["facture_precedente_id"]
            isOneToOne: false
            referencedRelation: "factures"
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
      factures_honoraires: {
        Row: {
          admin_notes: string | null
          annee_iso: number | null
          chorus_avoir_reference_invoice: string | null
          chorus_last_sync_at: string | null
          chorus_submission_id: string | null
          chorus_submission_status: string | null
          cree_le: string
          date_echeance: string | null
          date_emission: string
          date_paiement: string | null
          date_remboursement: string | null
          engagement_juridique: string | null
          est_facture_finale_mission: boolean
          etablissement_id: string
          exoneration_tva: boolean | null
          factor_assigned: boolean
          factor_id: string | null
          facture_precedente_id: string | null
          facturx_xml_url: string | null
          id: string
          is_public_sector: boolean
          litige_id: string | null
          mandat_version: string | null
          mission_id: string | null
          mode_remboursement: Database["public"]["Enums"]["mode_remboursement_avoir"]
          modifie_le: string
          montant_ht: number
          montant_signe: number | null
          montant_ttc: number
          montant_tva: number
          numero_facture: string
          numero_semaine_iso: number | null
          pdf_a_regenerer: boolean
          pdf_s3_key: string | null
          periode_debut: string
          periode_fin: string
          reference_remboursement: string | null
          service_code_chorus: string | null
          siret_client: string | null
          soignant_id: string
          statut: string
          statut_litige: Database["public"]["Enums"]["statut_litige_facture"]
          stripe_payment_intent_id: string | null
          subrogation_mention: string | null
          taux_tva: number | null
          template_version: string
          type_document: Database["public"]["Enums"]["type_document_facture"]
          updated_at: string | null
        }
        Insert: {
          admin_notes?: string | null
          annee_iso?: number | null
          chorus_avoir_reference_invoice?: string | null
          chorus_last_sync_at?: string | null
          chorus_submission_id?: string | null
          chorus_submission_status?: string | null
          cree_le?: string
          date_echeance?: string | null
          date_emission?: string
          date_paiement?: string | null
          date_remboursement?: string | null
          engagement_juridique?: string | null
          est_facture_finale_mission?: boolean
          etablissement_id: string
          exoneration_tva?: boolean | null
          factor_assigned?: boolean
          factor_id?: string | null
          facture_precedente_id?: string | null
          facturx_xml_url?: string | null
          id?: string
          is_public_sector?: boolean
          litige_id?: string | null
          mandat_version?: string | null
          mission_id?: string | null
          mode_remboursement?: Database["public"]["Enums"]["mode_remboursement_avoir"]
          modifie_le?: string
          montant_ht: number
          montant_signe?: number | null
          montant_ttc: number
          montant_tva?: number
          numero_facture: string
          numero_semaine_iso?: number | null
          pdf_a_regenerer?: boolean
          pdf_s3_key?: string | null
          periode_debut: string
          periode_fin: string
          reference_remboursement?: string | null
          service_code_chorus?: string | null
          siret_client?: string | null
          soignant_id: string
          statut?: string
          statut_litige?: Database["public"]["Enums"]["statut_litige_facture"]
          stripe_payment_intent_id?: string | null
          subrogation_mention?: string | null
          taux_tva?: number | null
          template_version?: string
          type_document?: Database["public"]["Enums"]["type_document_facture"]
          updated_at?: string | null
        }
        Update: {
          admin_notes?: string | null
          annee_iso?: number | null
          chorus_avoir_reference_invoice?: string | null
          chorus_last_sync_at?: string | null
          chorus_submission_id?: string | null
          chorus_submission_status?: string | null
          cree_le?: string
          date_echeance?: string | null
          date_emission?: string
          date_paiement?: string | null
          date_remboursement?: string | null
          engagement_juridique?: string | null
          est_facture_finale_mission?: boolean
          etablissement_id?: string
          exoneration_tva?: boolean | null
          factor_assigned?: boolean
          factor_id?: string | null
          facture_precedente_id?: string | null
          facturx_xml_url?: string | null
          id?: string
          is_public_sector?: boolean
          litige_id?: string | null
          mandat_version?: string | null
          mission_id?: string | null
          mode_remboursement?: Database["public"]["Enums"]["mode_remboursement_avoir"]
          modifie_le?: string
          montant_ht?: number
          montant_signe?: number | null
          montant_ttc?: number
          montant_tva?: number
          numero_facture?: string
          numero_semaine_iso?: number | null
          pdf_a_regenerer?: boolean
          pdf_s3_key?: string | null
          periode_debut?: string
          periode_fin?: string
          reference_remboursement?: string | null
          service_code_chorus?: string | null
          siret_client?: string | null
          soignant_id?: string
          statut?: string
          statut_litige?: Database["public"]["Enums"]["statut_litige_facture"]
          stripe_payment_intent_id?: string | null
          subrogation_mention?: string | null
          taux_tva?: number | null
          template_version?: string
          type_document?: Database["public"]["Enums"]["type_document_facture"]
          updated_at?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "factures_honoraires_etablissement_id_fkey"
            columns: ["etablissement_id"]
            isOneToOne: false
            referencedRelation: "etablissements"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "factures_honoraires_facture_precedente_id_fkey"
            columns: ["facture_precedente_id"]
            isOneToOne: false
            referencedRelation: "factures_honoraires"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "factures_honoraires_litige_id_fkey"
            columns: ["litige_id"]
            isOneToOne: false
            referencedRelation: "litiges"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "factures_honoraires_mission_id_fkey"
            columns: ["mission_id"]
            isOneToOne: false
            referencedRelation: "missions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "factures_honoraires_soignant_id_fkey"
            columns: ["soignant_id"]
            isOneToOne: false
            referencedRelation: "soignants"
            referencedColumns: ["id"]
          },
        ]
      }
      favoris_etab_soignant: {
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
      favoris_soignant_etab: {
        Row: {
          cree_le: string
          etablissement_id: string
          id: string
          soignant_id: string
        }
        Insert: {
          cree_le?: string
          etablissement_id: string
          id?: string
          soignant_id: string
        }
        Update: {
          cree_le?: string
          etablissement_id?: string
          id?: string
          soignant_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "favoris_soignant_etab_etablissement_id_fkey"
            columns: ["etablissement_id"]
            isOneToOne: false
            referencedRelation: "etablissements"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "favoris_soignant_etab_soignant_id_fkey"
            columns: ["soignant_id"]
            isOneToOne: false
            referencedRelation: "soignants"
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
      filtres_sauvegardes: {
        Row: {
          alerte_active: boolean
          audience: Database["public"]["Enums"]["filtre_audience"]
          cree_le: string
          dernier_check_le: string
          filtres: Json
          frequence_alerte: Database["public"]["Enums"]["filtre_frequence_alerte"]
          id: string
          mis_a_jour_le: string
          nb_resultats_dernier_check: number
          nom: string
          utilisateur_id: string
        }
        Insert: {
          alerte_active?: boolean
          audience: Database["public"]["Enums"]["filtre_audience"]
          cree_le?: string
          dernier_check_le?: string
          filtres?: Json
          frequence_alerte?: Database["public"]["Enums"]["filtre_frequence_alerte"]
          id?: string
          mis_a_jour_le?: string
          nb_resultats_dernier_check?: number
          nom: string
          utilisateur_id: string
        }
        Update: {
          alerte_active?: boolean
          audience?: Database["public"]["Enums"]["filtre_audience"]
          cree_le?: string
          dernier_check_le?: string
          filtres?: Json
          frequence_alerte?: Database["public"]["Enums"]["filtre_frequence_alerte"]
          id?: string
          mis_a_jour_le?: string
          nb_resultats_dernier_check?: number
          nom?: string
          utilisateur_id?: string
        }
        Relationships: []
      }
      groupes_sante: {
        Row: {
          adresse_facturation: string | null
          bfa_contrat_signe_le: string | null
          bfa_eligible: boolean | null
          contrat_debut: string | null
          contrat_fin: string | null
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
          taux_commission_negocie: number | null
          telephone_admin: string | null
        }
        Insert: {
          adresse_facturation?: string | null
          bfa_contrat_signe_le?: string | null
          bfa_eligible?: boolean | null
          contrat_debut?: string | null
          contrat_fin?: string | null
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
          taux_commission_negocie?: number | null
          telephone_admin?: string | null
        }
        Update: {
          adresse_facturation?: string | null
          bfa_contrat_signe_le?: string | null
          bfa_eligible?: boolean | null
          contrat_debut?: string | null
          contrat_fin?: string | null
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
          taux_commission_negocie?: number | null
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
      heures_externes_soignants: {
        Row: {
          attestation_nom_fichier: string | null
          attestation_url: string | null
          commentaire_validation: string | null
          cree_le: string | null
          date_debut: string
          date_fin: string
          etablissement_nom: string
          etablissement_type: string | null
          heures_declarees: number
          id: string
          mis_a_jour_le: string | null
          soignant_id: string
          statut_validation: string | null
          valide_le: string | null
          valide_par: string | null
        }
        Insert: {
          attestation_nom_fichier?: string | null
          attestation_url?: string | null
          commentaire_validation?: string | null
          cree_le?: string | null
          date_debut: string
          date_fin: string
          etablissement_nom: string
          etablissement_type?: string | null
          heures_declarees: number
          id?: string
          mis_a_jour_le?: string | null
          soignant_id: string
          statut_validation?: string | null
          valide_le?: string | null
          valide_par?: string | null
        }
        Update: {
          attestation_nom_fichier?: string | null
          attestation_url?: string | null
          commentaire_validation?: string | null
          cree_le?: string | null
          date_debut?: string
          date_fin?: string
          etablissement_nom?: string
          etablissement_type?: string | null
          heures_declarees?: number
          id?: string
          mis_a_jour_le?: string | null
          soignant_id?: string
          statut_validation?: string | null
          valide_le?: string | null
          valide_par?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "heures_externes_soignants_soignant_id_fkey"
            columns: ["soignant_id"]
            isOneToOne: false
            referencedRelation: "soignants"
            referencedColumns: ["id"]
          },
        ]
      }
      historique_blocages_etablissements: {
        Row: {
          action: string
          cree_le: string
          etablissement_id: string
          id: string
          raisons: Json | null
        }
        Insert: {
          action: string
          cree_le?: string
          etablissement_id: string
          id?: string
          raisons?: Json | null
        }
        Update: {
          action?: string
          cree_le?: string
          etablissement_id?: string
          id?: string
          raisons?: Json | null
        }
        Relationships: [
          {
            foreignKeyName: "historique_blocages_etablissements_etablissement_id_fkey"
            columns: ["etablissement_id"]
            isOneToOne: false
            referencedRelation: "etablissements"
            referencedColumns: ["id"]
          },
        ]
      }
      invoice_audit_log: {
        Row: {
          action: string
          actor_id: string | null
          created_at: string
          id: string
          invoice_id: string
          payload_after: Json | null
          payload_before: Json | null
        }
        Insert: {
          action: string
          actor_id?: string | null
          created_at?: string
          id?: string
          invoice_id: string
          payload_after?: Json | null
          payload_before?: Json | null
        }
        Update: {
          action?: string
          actor_id?: string | null
          created_at?: string
          id?: string
          invoice_id?: string
          payload_after?: Json | null
          payload_before?: Json | null
        }
        Relationships: [
          {
            foreignKeyName: "invoice_audit_log_invoice_id_fkey"
            columns: ["invoice_id"]
            isOneToOne: false
            referencedRelation: "factures_honoraires"
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
          accord_etablissement: boolean | null
          accord_etablissement_le: string | null
          accord_soignant: boolean | null
          accord_soignant_le: string | null
          categorie_litige: Database["public"]["Enums"]["categorie_litige"]
          cree_le: string | null
          derniers_rappels_envoyes: Json
          escalade_auto_le: string | null
          escalade_auto_motif: string | null
          est_informatif: boolean
          etablissement_id: string
          facture_id: string | null
          gel_facture_scope: string
          id: string
          initie_par: string
          mission_id: string
          montant_tresorerie_bloquee: number | null
          motif: string
          paiement_soignant_id: string | null
          periode_debut: string | null
          periode_fin: string | null
          presence_id: string | null
          reponse: string | null
          resolu_le: string | null
          resolu_par: string | null
          resolution: string | null
          soignant_id: string
          statut: string | null
          type_legacy: boolean
          type_litige: Database["public"]["Enums"]["type_litige"]
        }
        Insert: {
          accord_etablissement?: boolean | null
          accord_etablissement_le?: string | null
          accord_soignant?: boolean | null
          accord_soignant_le?: string | null
          categorie_litige?: Database["public"]["Enums"]["categorie_litige"]
          cree_le?: string | null
          derniers_rappels_envoyes?: Json
          escalade_auto_le?: string | null
          escalade_auto_motif?: string | null
          est_informatif?: boolean
          etablissement_id: string
          facture_id?: string | null
          gel_facture_scope?: string
          id?: string
          initie_par: string
          mission_id: string
          montant_tresorerie_bloquee?: number | null
          motif: string
          paiement_soignant_id?: string | null
          periode_debut?: string | null
          periode_fin?: string | null
          presence_id?: string | null
          reponse?: string | null
          resolu_le?: string | null
          resolu_par?: string | null
          resolution?: string | null
          soignant_id: string
          statut?: string | null
          type_legacy?: boolean
          type_litige?: Database["public"]["Enums"]["type_litige"]
        }
        Update: {
          accord_etablissement?: boolean | null
          accord_etablissement_le?: string | null
          accord_soignant?: boolean | null
          accord_soignant_le?: string | null
          categorie_litige?: Database["public"]["Enums"]["categorie_litige"]
          cree_le?: string | null
          derniers_rappels_envoyes?: Json
          escalade_auto_le?: string | null
          escalade_auto_motif?: string | null
          est_informatif?: boolean
          etablissement_id?: string
          facture_id?: string | null
          gel_facture_scope?: string
          id?: string
          initie_par?: string
          mission_id?: string
          montant_tresorerie_bloquee?: number | null
          motif?: string
          paiement_soignant_id?: string | null
          periode_debut?: string | null
          periode_fin?: string | null
          presence_id?: string | null
          reponse?: string | null
          resolu_le?: string | null
          resolu_par?: string | null
          resolution?: string | null
          soignant_id?: string
          statut?: string | null
          type_legacy?: boolean
          type_litige?: Database["public"]["Enums"]["type_litige"]
        }
        Relationships: [
          {
            foreignKeyName: "litiges_facture_id_fkey"
            columns: ["facture_id"]
            isOneToOne: false
            referencedRelation: "factures_honoraires"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "litiges_mission_id_fkey"
            columns: ["mission_id"]
            isOneToOne: false
            referencedRelation: "missions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "litiges_paiement_soignant_id_fkey"
            columns: ["paiement_soignant_id"]
            isOneToOne: false
            referencedRelation: "paiements_soignant"
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
      mandats_facturation_signatures: {
        Row: {
          contenu_hash: string | null
          cree_le: string
          id: string
          ip_address: string | null
          pdf_url: string | null
          revoked_at: string | null
          signed_at: string
          soignant_id: string
          user_agent: string | null
          version: string
        }
        Insert: {
          contenu_hash?: string | null
          cree_le?: string
          id?: string
          ip_address?: string | null
          pdf_url?: string | null
          revoked_at?: string | null
          signed_at?: string
          soignant_id: string
          user_agent?: string | null
          version: string
        }
        Update: {
          contenu_hash?: string | null
          cree_le?: string
          id?: string
          ip_address?: string | null
          pdf_url?: string | null
          revoked_at?: string | null
          signed_at?: string
          soignant_id?: string
          user_agent?: string | null
          version?: string
        }
        Relationships: [
          {
            foreignKeyName: "mandats_facturation_signatures_soignant_id_fkey"
            columns: ["soignant_id"]
            isOneToOne: false
            referencedRelation: "soignants"
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
      messages_litige: {
        Row: {
          auteur_id: string
          contenu: string
          cree_le: string | null
          id: string
          litige_id: string
          type_auteur: string
        }
        Insert: {
          auteur_id: string
          contenu: string
          cree_le?: string | null
          id?: string
          litige_id: string
          type_auteur: string
        }
        Update: {
          auteur_id?: string
          contenu?: string
          cree_le?: string | null
          id?: string
          litige_id?: string
          type_auteur?: string
        }
        Relationships: [
          {
            foreignKeyName: "messages_litige_litige_id_fkey"
            columns: ["litige_id"]
            isOneToOne: false
            referencedRelation: "litiges"
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
      mission_creneaux: {
        Row: {
          cree_le: string
          debut: string
          est_pause: boolean
          fin: string | null
          id: string
          mission_id: string
          modifie_le: string
          ordre: number
          type_creneau: string
          type_pause: string | null
        }
        Insert: {
          cree_le?: string
          debut: string
          est_pause?: boolean
          fin?: string | null
          id?: string
          mission_id: string
          modifie_le?: string
          ordre?: number
          type_creneau?: string
          type_pause?: string | null
        }
        Update: {
          cree_le?: string
          debut?: string
          est_pause?: boolean
          fin?: string | null
          id?: string
          mission_id?: string
          modifie_le?: string
          ordre?: number
          type_creneau?: string
          type_pause?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "mission_creneaux_mission_id_fkey"
            columns: ["mission_id"]
            isOneToOne: false
            referencedRelation: "missions"
            referencedColumns: ["id"]
          },
        ]
      }
      mission_series: {
        Row: {
          cree_le: string
          cree_par: string | null
          etablissement_id: string
          id: string
          modifie_le: string
          motif: string | null
          nb_missions_prevues: number
        }
        Insert: {
          cree_le?: string
          cree_par?: string | null
          etablissement_id: string
          id?: string
          modifie_le?: string
          motif?: string | null
          nb_missions_prevues?: number
        }
        Update: {
          cree_le?: string
          cree_par?: string | null
          etablissement_id?: string
          id?: string
          modifie_le?: string
          motif?: string | null
          nb_missions_prevues?: number
        }
        Relationships: [
          {
            foreignKeyName: "mission_series_etablissement_id_fkey"
            columns: ["etablissement_id"]
            isOneToOne: false
            referencedRelation: "etablissements"
            referencedColumns: ["id"]
          },
        ]
      }
      missions: {
        Row: {
          absence_sans_prevenir: boolean
          accepte_non_specialises: boolean | null
          annulee_le: string | null
          annulee_par: string | null
          choix_contrat_soignant: string | null
          code_arrivee: string | null
          code_depart: string | null
          code_pointage_actif: string | null
          code_pointage_hmac: string | null
          commission_a_recalculer: boolean
          commission_facturee: boolean | null
          cree_le: string | null
          debut_effectif: string | null
          debut_le: string
          description: string | null
          duree_heures: number | null
          duree_heures_effective: number | null
          est_urgente: boolean | null
          etablissement_id: string
          facture_id: string | null
          fige_le: string | null
          fin_effective: string | null
          fin_le: string
          heure_debut_nuit_fige: string | null
          heure_fin_nuit_fige: string | null
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
          nb_creneaux: number
          nb_scans: number | null
          net_a_payer: number | null
          net_estime: number | null
          niveau_urgence: number | null
          numero_note_honoraires: string | null
          prochain_type_scan: string | null
          profession_requise: Database["public"]["Enums"]["type_profession"]
          regularisation_sociale_requise: boolean
          relance_paiement_1_le: string | null
          relance_paiement_2_le: string | null
          rist_plafond_applique: boolean | null
          serie_id: string | null
          service: string | null
          soignant_assigne_id: string | null
          specialite_medicale_requise: string | null
          statut: Database["public"]["Enums"]["statut_mission"] | null
          strategie_facturation: Database["public"]["Enums"]["strategie_facturation"]
          stripe_payment_intent_id: string | null
          stripe_transfer_id: string | null
          taux_commission: number | null
          taux_commission_fige: number | null
          taux_horaire_base: number
          taux_horaire_base_fige: number | null
          taux_icp: number | null
          taux_ifm: number | null
          taux_majoration_dimanche_fige: number | null
          taux_majoration_ferie_fige: number | null
          taux_majoration_nuit_fige: number | null
          taux_rist_plafonne: number | null
          terminee_le: string | null
          total_brut: number | null
          type_contrat_applique:
            | Database["public"]["Enums"]["type_contrat_applique_enum"]
            | null
          type_contrat_recherche: string
          type_paiement_soignant: string | null
          yousign_id_procedure: string | null
          yousign_statut: string | null
        }
        Insert: {
          absence_sans_prevenir?: boolean
          accepte_non_specialises?: boolean | null
          annulee_le?: string | null
          annulee_par?: string | null
          choix_contrat_soignant?: string | null
          code_arrivee?: string | null
          code_depart?: string | null
          code_pointage_actif?: string | null
          code_pointage_hmac?: string | null
          commission_a_recalculer?: boolean
          commission_facturee?: boolean | null
          cree_le?: string | null
          debut_effectif?: string | null
          debut_le: string
          description?: string | null
          duree_heures?: number | null
          duree_heures_effective?: number | null
          est_urgente?: boolean | null
          etablissement_id: string
          facture_id?: string | null
          fige_le?: string | null
          fin_effective?: string | null
          fin_le: string
          heure_debut_nuit_fige?: string | null
          heure_fin_nuit_fige?: string | null
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
          nb_creneaux?: number
          nb_scans?: number | null
          net_a_payer?: number | null
          net_estime?: number | null
          niveau_urgence?: number | null
          numero_note_honoraires?: string | null
          prochain_type_scan?: string | null
          profession_requise: Database["public"]["Enums"]["type_profession"]
          regularisation_sociale_requise?: boolean
          relance_paiement_1_le?: string | null
          relance_paiement_2_le?: string | null
          rist_plafond_applique?: boolean | null
          serie_id?: string | null
          service?: string | null
          soignant_assigne_id?: string | null
          specialite_medicale_requise?: string | null
          statut?: Database["public"]["Enums"]["statut_mission"] | null
          strategie_facturation?: Database["public"]["Enums"]["strategie_facturation"]
          stripe_payment_intent_id?: string | null
          stripe_transfer_id?: string | null
          taux_commission?: number | null
          taux_commission_fige?: number | null
          taux_horaire_base: number
          taux_horaire_base_fige?: number | null
          taux_icp?: number | null
          taux_ifm?: number | null
          taux_majoration_dimanche_fige?: number | null
          taux_majoration_ferie_fige?: number | null
          taux_majoration_nuit_fige?: number | null
          taux_rist_plafonne?: number | null
          terminee_le?: string | null
          total_brut?: number | null
          type_contrat_applique?:
            | Database["public"]["Enums"]["type_contrat_applique_enum"]
            | null
          type_contrat_recherche?: string
          type_paiement_soignant?: string | null
          yousign_id_procedure?: string | null
          yousign_statut?: string | null
        }
        Update: {
          absence_sans_prevenir?: boolean
          accepte_non_specialises?: boolean | null
          annulee_le?: string | null
          annulee_par?: string | null
          choix_contrat_soignant?: string | null
          code_arrivee?: string | null
          code_depart?: string | null
          code_pointage_actif?: string | null
          code_pointage_hmac?: string | null
          commission_a_recalculer?: boolean
          commission_facturee?: boolean | null
          cree_le?: string | null
          debut_effectif?: string | null
          debut_le?: string
          description?: string | null
          duree_heures?: number | null
          duree_heures_effective?: number | null
          est_urgente?: boolean | null
          etablissement_id?: string
          facture_id?: string | null
          fige_le?: string | null
          fin_effective?: string | null
          fin_le?: string
          heure_debut_nuit_fige?: string | null
          heure_fin_nuit_fige?: string | null
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
          nb_creneaux?: number
          nb_scans?: number | null
          net_a_payer?: number | null
          net_estime?: number | null
          niveau_urgence?: number | null
          numero_note_honoraires?: string | null
          prochain_type_scan?: string | null
          profession_requise?: Database["public"]["Enums"]["type_profession"]
          regularisation_sociale_requise?: boolean
          relance_paiement_1_le?: string | null
          relance_paiement_2_le?: string | null
          rist_plafond_applique?: boolean | null
          serie_id?: string | null
          service?: string | null
          soignant_assigne_id?: string | null
          specialite_medicale_requise?: string | null
          statut?: Database["public"]["Enums"]["statut_mission"] | null
          strategie_facturation?: Database["public"]["Enums"]["strategie_facturation"]
          stripe_payment_intent_id?: string | null
          stripe_transfer_id?: string | null
          taux_commission?: number | null
          taux_commission_fige?: number | null
          taux_horaire_base?: number
          taux_horaire_base_fige?: number | null
          taux_icp?: number | null
          taux_ifm?: number | null
          taux_majoration_dimanche_fige?: number | null
          taux_majoration_ferie_fige?: number | null
          taux_majoration_nuit_fige?: number | null
          taux_rist_plafonne?: number | null
          terminee_le?: string | null
          total_brut?: number | null
          type_contrat_applique?:
            | Database["public"]["Enums"]["type_contrat_applique_enum"]
            | null
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
            foreignKeyName: "missions_serie_id_fkey"
            columns: ["serie_id"]
            isOneToOne: false
            referencedRelation: "mission_series"
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
            foreignKeyName: "missions_specialite_medicale_requise_fkey"
            columns: ["specialite_medicale_requise"]
            isOneToOne: false
            referencedRelation: "specialites_medicales"
            referencedColumns: ["code"]
          },
        ]
      }
      notations_missions: {
        Row: {
          commentaire: string | null
          cree_le: string
          critere_1: number
          critere_2: number
          critere_3: number
          critere_4: number
          id: string
          masque: boolean
          masque_le: string | null
          masque_par: string | null
          mis_a_jour_le: string
          mission_id: string
          notateur_anonymise: boolean
          notateur_id: string
          note_id: string
          sens: Database["public"]["Enums"]["sens_notation"]
          signale: boolean
        }
        Insert: {
          commentaire?: string | null
          cree_le?: string
          critere_1: number
          critere_2: number
          critere_3: number
          critere_4: number
          id?: string
          masque?: boolean
          masque_le?: string | null
          masque_par?: string | null
          mis_a_jour_le?: string
          mission_id: string
          notateur_anonymise?: boolean
          notateur_id: string
          note_id: string
          sens: Database["public"]["Enums"]["sens_notation"]
          signale?: boolean
        }
        Update: {
          commentaire?: string | null
          cree_le?: string
          critere_1?: number
          critere_2?: number
          critere_3?: number
          critere_4?: number
          id?: string
          masque?: boolean
          masque_le?: string | null
          masque_par?: string | null
          mis_a_jour_le?: string
          mission_id?: string
          notateur_anonymise?: boolean
          notateur_id?: string
          note_id?: string
          sens?: Database["public"]["Enums"]["sens_notation"]
          signale?: boolean
        }
        Relationships: [
          {
            foreignKeyName: "notations_missions_mission_id_fkey"
            columns: ["mission_id"]
            isOneToOne: false
            referencedRelation: "missions"
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
      notifications_notation_j1: {
        Row: {
          destinataire_id: string
          envoye_le: string
          id: string
          mission_id: string
          sens: Database["public"]["Enums"]["sens_notation"]
        }
        Insert: {
          destinataire_id: string
          envoye_le?: string
          id?: string
          mission_id: string
          sens: Database["public"]["Enums"]["sens_notation"]
        }
        Update: {
          destinataire_id?: string
          envoye_le?: string
          id?: string
          mission_id?: string
          sens?: Database["public"]["Enums"]["sens_notation"]
        }
        Relationships: [
          {
            foreignKeyName: "notifications_notation_j1_mission_id_fkey"
            columns: ["mission_id"]
            isOneToOne: false
            referencedRelation: "missions"
            referencedColumns: ["id"]
          },
        ]
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
            isOneToOne: true
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
          echeance_le: string | null
          etablissement_id: string
          id: string
          methode: string
          mission_id: string
          modifie_le: string | null
          montant_net: number
          motif_contestation: string | null
          reference_virement: string | null
          relance_1_le: string | null
          relance_2_le: string | null
          soignant_id: string
          statut: string
          stripe_transfer_id: string | null
        }
        Insert: {
          confirme_par_etablissement?: boolean | null
          confirme_par_etablissement_le?: string | null
          confirme_par_soignant?: boolean | null
          confirme_par_soignant_le?: string | null
          conteste?: boolean | null
          cree_le?: string | null
          date_paiement?: string | null
          echeance_le?: string | null
          etablissement_id: string
          id?: string
          methode: string
          mission_id: string
          modifie_le?: string | null
          montant_net: number
          motif_contestation?: string | null
          reference_virement?: string | null
          relance_1_le?: string | null
          relance_2_le?: string | null
          soignant_id: string
          statut?: string
          stripe_transfer_id?: string | null
        }
        Update: {
          confirme_par_etablissement?: boolean | null
          confirme_par_etablissement_le?: string | null
          confirme_par_soignant?: boolean | null
          confirme_par_soignant_le?: string | null
          conteste?: boolean | null
          cree_le?: string | null
          date_paiement?: string | null
          echeance_le?: string | null
          etablissement_id?: string
          id?: string
          methode?: string
          mission_id?: string
          modifie_le?: string | null
          montant_net?: number
          motif_contestation?: string | null
          reference_virement?: string | null
          relance_1_le?: string | null
          relance_2_le?: string | null
          soignant_id?: string
          statut?: string
          stripe_transfer_id?: string | null
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
      parametres_litiges: {
        Row: {
          cle: string
          description: string
          modifie_le: string
          modifie_par: string | null
          valeur: string
        }
        Insert: {
          cle: string
          description: string
          modifie_le?: string
          modifie_par?: string | null
          valeur: string
        }
        Update: {
          cle?: string
          description?: string
          modifie_le?: string
          modifie_par?: string | null
          valeur?: string
        }
        Relationships: []
      }
      parcours_liberal_soignants: {
        Row: {
          cree_le: string | null
          demarre_le: string | null
          etapes: Json | null
          id: string
          mis_a_jour_le: string | null
          parcours_kine: string | null
          soignant_id: string
          termine_le: string | null
        }
        Insert: {
          cree_le?: string | null
          demarre_le?: string | null
          etapes?: Json | null
          id?: string
          mis_a_jour_le?: string | null
          parcours_kine?: string | null
          soignant_id: string
          termine_le?: string | null
        }
        Update: {
          cree_le?: string | null
          demarre_le?: string | null
          etapes?: Json | null
          id?: string
          mis_a_jour_le?: string | null
          parcours_kine?: string | null
          soignant_id?: string
          termine_le?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "parcours_liberal_soignants_soignant_id_fkey"
            columns: ["soignant_id"]
            isOneToOne: true
            referencedRelation: "soignants"
            referencedColumns: ["id"]
          },
        ]
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
      parrainages_etablissements: {
        Row: {
          code_parrainage: string
          cree_le: string
          filleul_etab_id: string
          id: string
          mis_a_jour_le: string
          parrain_etab_id: string
          statut: Database["public"]["Enums"]["parrainage_etab_statut"]
          valide_le: string | null
        }
        Insert: {
          code_parrainage: string
          cree_le?: string
          filleul_etab_id: string
          id?: string
          mis_a_jour_le?: string
          parrain_etab_id: string
          statut?: Database["public"]["Enums"]["parrainage_etab_statut"]
          valide_le?: string | null
        }
        Update: {
          code_parrainage?: string
          cree_le?: string
          filleul_etab_id?: string
          id?: string
          mis_a_jour_le?: string
          parrain_etab_id?: string
          statut?: Database["public"]["Enums"]["parrainage_etab_statut"]
          valide_le?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "parrainages_etablissements_filleul_etab_id_fkey"
            columns: ["filleul_etab_id"]
            isOneToOne: true
            referencedRelation: "etablissements"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "parrainages_etablissements_parrain_etab_id_fkey"
            columns: ["parrain_etab_id"]
            isOneToOne: false
            referencedRelation: "etablissements"
            referencedColumns: ["id"]
          },
        ]
      }
      partages_rib: {
        Row: {
          actif: boolean | null
          consulte_le: string | null
          consulte_par: string | null
          contrat_id: string
          document_rib_id: string | null
          etablissement_id: string
          expire_le: string | null
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
          expire_le?: string | null
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
          expire_le?: string | null
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
      preferences_notifications: {
        Row: {
          canal_email: boolean
          canal_in_app: boolean
          canal_push: boolean
          canal_sms: boolean
          cree_le: string
          mis_a_jour_le: string
          utilisateur_id: string
        }
        Insert: {
          canal_email?: boolean
          canal_in_app?: boolean
          canal_push?: boolean
          canal_sms?: boolean
          cree_le?: string
          mis_a_jour_le?: string
          utilisateur_id: string
        }
        Update: {
          canal_email?: boolean
          canal_in_app?: boolean
          canal_push?: boolean
          canal_sms?: boolean
          cree_le?: string
          mis_a_jour_le?: string
          utilisateur_id?: string
        }
        Relationships: []
      }
      preferences_notifications_par_evenement: {
        Row: {
          actif: boolean
          canal: Database["public"]["Enums"]["canal_notification"]
          cree_le: string
          id: string
          mis_a_jour_le: string
          type_evenement: Database["public"]["Enums"]["type_evenement_notification"]
          utilisateur_id: string
        }
        Insert: {
          actif?: boolean
          canal: Database["public"]["Enums"]["canal_notification"]
          cree_le?: string
          id?: string
          mis_a_jour_le?: string
          type_evenement: Database["public"]["Enums"]["type_evenement_notification"]
          utilisateur_id: string
        }
        Update: {
          actif?: boolean
          canal?: Database["public"]["Enums"]["canal_notification"]
          cree_le?: string
          id?: string
          mis_a_jour_le?: string
          type_evenement?: Database["public"]["Enums"]["type_evenement_notification"]
          utilisateur_id?: string
        }
        Relationships: []
      }
      presences: {
        Row: {
          ajustement_litige_id: string | null
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
          depart_modele_terminal: string | null
          depart_precision_gps_m: number | null
          distance_etablissement_m: number | null
          duree_brute_min: number | null
          duree_nette_min: number | null
          duree_pause_min: number | null
          heures_ajustees_litige: number | null
          heures_reelles: number | null
          id: string
          litige_auto_cree_le: string | null
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
          ajustement_litige_id?: string | null
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
          depart_modele_terminal?: string | null
          depart_precision_gps_m?: number | null
          distance_etablissement_m?: number | null
          duree_brute_min?: number | null
          duree_nette_min?: number | null
          duree_pause_min?: number | null
          heures_ajustees_litige?: number | null
          heures_reelles?: number | null
          id?: string
          litige_auto_cree_le?: string | null
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
          ajustement_litige_id?: string | null
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
          depart_modele_terminal?: string | null
          depart_precision_gps_m?: number | null
          distance_etablissement_m?: number | null
          duree_brute_min?: number | null
          duree_nette_min?: number | null
          duree_pause_min?: number | null
          heures_ajustees_litige?: number | null
          heures_reelles?: number | null
          id?: string
          litige_auto_cree_le?: string | null
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
            foreignKeyName: "presences_ajustement_litige_id_fkey"
            columns: ["ajustement_litige_id"]
            isOneToOne: false
            referencedRelation: "litiges"
            referencedColumns: ["id"]
          },
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
      prevoyance_liste_attente: {
        Row: {
          cree_le: string
          email: string
          id: string
          mis_a_jour_le: string
          niveau_souhaite: Database["public"]["Enums"]["niveau_prevoyance_souhaite"]
          soignant_id: string | null
        }
        Insert: {
          cree_le?: string
          email: string
          id?: string
          mis_a_jour_le?: string
          niveau_souhaite?: Database["public"]["Enums"]["niveau_prevoyance_souhaite"]
          soignant_id?: string | null
        }
        Update: {
          cree_le?: string
          email?: string
          id?: string
          mis_a_jour_le?: string
          niveau_souhaite?: Database["public"]["Enums"]["niveau_prevoyance_souhaite"]
          soignant_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "prevoyance_liste_attente_soignant_id_fkey"
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
      psc_auth_sessions: {
        Row: {
          code_verifier: string
          cree_le: string
          expire_le: string
          intention: string
          nonce: string
          state: string
        }
        Insert: {
          code_verifier: string
          cree_le?: string
          expire_le?: string
          intention?: string
          nonce: string
          state: string
        }
        Update: {
          code_verifier?: string
          cree_le?: string
          expire_le?: string
          intention?: string
          nonce?: string
          state?: string
        }
        Relationships: []
      }
      rappels_contrat_travail: {
        Row: {
          cible_etab: boolean
          cible_soignant: boolean
          cree_le: string
          envoye_le: string
          id: string
          mission_id: string
        }
        Insert: {
          cible_etab?: boolean
          cible_soignant?: boolean
          cree_le?: string
          envoye_le?: string
          id?: string
          mission_id: string
        }
        Update: {
          cible_etab?: boolean
          cible_soignant?: boolean
          cree_le?: string
          envoye_le?: string
          id?: string
          mission_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "rappels_contrat_travail_mission_id_fkey"
            columns: ["mission_id"]
            isOneToOne: false
            referencedRelation: "missions"
            referencedColumns: ["id"]
          },
        ]
      }
      rate_limits: {
        Row: {
          action: string
          cle: string
          derniere_tentative: string | null
          id: string
          premiere_tentative: string | null
          tentatives: number | null
        }
        Insert: {
          action: string
          cle: string
          derniere_tentative?: string | null
          id?: string
          premiere_tentative?: string | null
          tentatives?: number | null
        }
        Update: {
          action?: string
          cle?: string
          derniere_tentative?: string | null
          id?: string
          premiere_tentative?: string | null
          tentatives?: number | null
        }
        Relationships: []
      }
      reclamations: {
        Row: {
          categorie: string
          cree_le: string
          details: string
          id: string
          mission_id: string | null
          priorite: string
          reponse_admin: string | null
          statut: string
          sujet: string
          traite_le: string | null
          traite_par: string | null
          type_utilisateur: string
          utilisateur_id: string
        }
        Insert: {
          categorie: string
          cree_le?: string
          details: string
          id?: string
          mission_id?: string | null
          priorite?: string
          reponse_admin?: string | null
          statut?: string
          sujet: string
          traite_le?: string | null
          traite_par?: string | null
          type_utilisateur: string
          utilisateur_id: string
        }
        Update: {
          categorie?: string
          cree_le?: string
          details?: string
          id?: string
          mission_id?: string | null
          priorite?: string
          reponse_admin?: string | null
          statut?: string
          sujet?: string
          traite_le?: string | null
          traite_par?: string | null
          type_utilisateur?: string
          utilisateur_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "reclamations_mission_id_fkey"
            columns: ["mission_id"]
            isOneToOne: false
            referencedRelation: "missions"
            referencedColumns: ["id"]
          },
        ]
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
      regles_exercice_profession: {
        Row: {
          description: string | null
          profession: Database["public"]["Enums"]["type_profession"]
          types_exercice_autorises: string[]
        }
        Insert: {
          description?: string | null
          profession: Database["public"]["Enums"]["type_profession"]
          types_exercice_autorises: string[]
        }
        Update: {
          description?: string | null
          profession?: Database["public"]["Enums"]["type_profession"]
          types_exercice_autorises?: string[]
        }
        Relationships: []
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
          cree_le: string
          date_naissance: string | null
          nom: string
          prenom: string
          profession: string
          rpps: string
          specialite_medicale: string | null
        }
        Insert: {
          cree_le?: string
          date_naissance?: string | null
          nom: string
          prenom: string
          profession: string
          rpps: string
          specialite_medicale?: string | null
        }
        Update: {
          cree_le?: string
          date_naissance?: string | null
          nom?: string
          prenom?: string
          profession?: string
          rpps?: string
          specialite_medicale?: string | null
        }
        Relationships: []
      }
      scans_pointage: {
        Row: {
          code_saisi: string
          cree_le: string
          creneau_effectif_id: string | null
          distance_etablissement_m: number | null
          est_en_avance: boolean
          horodatage_arrondi: string
          id: string
          id_terminal: string | null
          ip_address: unknown
          latitude: number | null
          longitude: number | null
          mission_id: string
          numero_scan: number
          precision_gps_m: number | null
          scanne_le: string
          soignant_id: string
          type_scan: string
          validation_etab_requise: boolean
          valide_le: string | null
          valide_par: string | null
          valide_par_etab: boolean
        }
        Insert: {
          code_saisi: string
          cree_le?: string
          creneau_effectif_id?: string | null
          distance_etablissement_m?: number | null
          est_en_avance?: boolean
          horodatage_arrondi: string
          id?: string
          id_terminal?: string | null
          ip_address?: unknown
          latitude?: number | null
          longitude?: number | null
          mission_id: string
          numero_scan: number
          precision_gps_m?: number | null
          scanne_le?: string
          soignant_id: string
          type_scan: string
          validation_etab_requise?: boolean
          valide_le?: string | null
          valide_par?: string | null
          valide_par_etab?: boolean
        }
        Update: {
          code_saisi?: string
          cree_le?: string
          creneau_effectif_id?: string | null
          distance_etablissement_m?: number | null
          est_en_avance?: boolean
          horodatage_arrondi?: string
          id?: string
          id_terminal?: string | null
          ip_address?: unknown
          latitude?: number | null
          longitude?: number | null
          mission_id?: string
          numero_scan?: number
          precision_gps_m?: number | null
          scanne_le?: string
          soignant_id?: string
          type_scan?: string
          validation_etab_requise?: boolean
          valide_le?: string | null
          valide_par?: string | null
          valide_par_etab?: boolean
        }
        Relationships: [
          {
            foreignKeyName: "scans_pointage_creneau_effectif_id_fkey"
            columns: ["creneau_effectif_id"]
            isOneToOne: false
            referencedRelation: "mission_creneaux"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "scans_pointage_mission_id_fkey"
            columns: ["mission_id"]
            isOneToOne: false
            referencedRelation: "missions"
            referencedColumns: ["id"]
          },
        ]
      }
      scoring_breakdown: {
        Row: {
          absence_sans_prevenir_malus: number
          anciennete_volume_pct: number | null
          anciennete_volume_poids: number | null
          bonus_super_actif: number
          composantes_actives_count: number
          composantes_inactives_json: Json | null
          cree_le: string
          en_periode_probatoire: boolean
          id: string
          litiges_malus: number
          niveau: Database["public"]["Enums"]["niveau_qualitatif"]
          notation_etab_soignant_pct: number | null
          notation_etab_soignant_poids: number | null
          notation_soignant_etab_pct: number | null
          notation_soignant_etab_poids: number | null
          ponctualite_pct: number | null
          ponctualite_poids: number | null
          presentisme_pct: number | null
          presentisme_poids: number | null
          raison_recalcul: string | null
          reactivite_pct: number | null
          reactivite_poids: number | null
          redistribution_json: Json | null
          score_total: number
          soignant_id: string
        }
        Insert: {
          absence_sans_prevenir_malus?: number
          anciennete_volume_pct?: number | null
          anciennete_volume_poids?: number | null
          bonus_super_actif?: number
          composantes_actives_count: number
          composantes_inactives_json?: Json | null
          cree_le?: string
          en_periode_probatoire?: boolean
          id?: string
          litiges_malus?: number
          niveau: Database["public"]["Enums"]["niveau_qualitatif"]
          notation_etab_soignant_pct?: number | null
          notation_etab_soignant_poids?: number | null
          notation_soignant_etab_pct?: number | null
          notation_soignant_etab_poids?: number | null
          ponctualite_pct?: number | null
          ponctualite_poids?: number | null
          presentisme_pct?: number | null
          presentisme_poids?: number | null
          raison_recalcul?: string | null
          reactivite_pct?: number | null
          reactivite_poids?: number | null
          redistribution_json?: Json | null
          score_total: number
          soignant_id: string
        }
        Update: {
          absence_sans_prevenir_malus?: number
          anciennete_volume_pct?: number | null
          anciennete_volume_poids?: number | null
          bonus_super_actif?: number
          composantes_actives_count?: number
          composantes_inactives_json?: Json | null
          cree_le?: string
          en_periode_probatoire?: boolean
          id?: string
          litiges_malus?: number
          niveau?: Database["public"]["Enums"]["niveau_qualitatif"]
          notation_etab_soignant_pct?: number | null
          notation_etab_soignant_poids?: number | null
          notation_soignant_etab_pct?: number | null
          notation_soignant_etab_poids?: number | null
          ponctualite_pct?: number | null
          ponctualite_poids?: number | null
          presentisme_pct?: number | null
          presentisme_poids?: number | null
          raison_recalcul?: string | null
          reactivite_pct?: number | null
          reactivite_poids?: number | null
          redistribution_json?: Json | null
          score_total?: number
          soignant_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "scoring_breakdown_soignant_id_fkey"
            columns: ["soignant_id"]
            isOneToOne: false
            referencedRelation: "soignants"
            referencedColumns: ["id"]
          },
        ]
      }
      serie_email_envois: {
        Row: {
          cree_le: string
          envoye_le: string | null
          erreur_message: string | null
          etape: Database["public"]["Enums"]["serie_onboarding_etape"]
          id: string
          mis_a_jour_le: string
          planifie_le: string
          serie: Database["public"]["Enums"]["serie_onboarding_type"]
          skip_raison: string | null
          statut: Database["public"]["Enums"]["serie_email_statut"]
          tentatives: number
          utilisateur_id: string
        }
        Insert: {
          cree_le?: string
          envoye_le?: string | null
          erreur_message?: string | null
          etape: Database["public"]["Enums"]["serie_onboarding_etape"]
          id?: string
          mis_a_jour_le?: string
          planifie_le: string
          serie: Database["public"]["Enums"]["serie_onboarding_type"]
          skip_raison?: string | null
          statut?: Database["public"]["Enums"]["serie_email_statut"]
          tentatives?: number
          utilisateur_id: string
        }
        Update: {
          cree_le?: string
          envoye_le?: string | null
          erreur_message?: string | null
          etape?: Database["public"]["Enums"]["serie_onboarding_etape"]
          id?: string
          mis_a_jour_le?: string
          planifie_le?: string
          serie?: Database["public"]["Enums"]["serie_onboarding_type"]
          skip_raison?: string | null
          statut?: Database["public"]["Enums"]["serie_email_statut"]
          tentatives?: number
          utilisateur_id?: string
        }
        Relationships: []
      }
      shift_affectations: {
        Row: {
          cree_le: string | null
          id: string
          mission_id: string | null
          shift_id: string
          soignant_id: string
          statut: string | null
        }
        Insert: {
          cree_le?: string | null
          id?: string
          mission_id?: string | null
          shift_id: string
          soignant_id: string
          statut?: string | null
        }
        Update: {
          cree_le?: string | null
          id?: string
          mission_id?: string | null
          shift_id?: string
          soignant_id?: string
          statut?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "shift_affectations_mission_id_fkey"
            columns: ["mission_id"]
            isOneToOne: false
            referencedRelation: "missions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "shift_affectations_shift_id_fkey"
            columns: ["shift_id"]
            isOneToOne: false
            referencedRelation: "shifts"
            referencedColumns: ["id"]
          },
        ]
      }
      shifts: {
        Row: {
          cree_le: string | null
          equipe_id: string | null
          etablissement_id: string
          heure_debut: string
          heure_fin: string
          id: string
          intitule: string
          jour: string
          modifie_le: string | null
          nb_postes: number | null
          nb_pourvus: number | null
          notes: string | null
          profession_requise: string | null
          recurrence: string | null
          service: string | null
        }
        Insert: {
          cree_le?: string | null
          equipe_id?: string | null
          etablissement_id: string
          heure_debut: string
          heure_fin: string
          id?: string
          intitule: string
          jour: string
          modifie_le?: string | null
          nb_postes?: number | null
          nb_pourvus?: number | null
          notes?: string | null
          profession_requise?: string | null
          recurrence?: string | null
          service?: string | null
        }
        Update: {
          cree_le?: string | null
          equipe_id?: string | null
          etablissement_id?: string
          heure_debut?: string
          heure_fin?: string
          id?: string
          intitule?: string
          jour?: string
          modifie_le?: string | null
          nb_postes?: number | null
          nb_pourvus?: number | null
          notes?: string | null
          profession_requise?: string | null
          recurrence?: string | null
          service?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "shifts_equipe_id_fkey"
            columns: ["equipe_id"]
            isOneToOne: false
            referencedRelation: "equipes"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "shifts_etablissement_id_fkey"
            columns: ["etablissement_id"]
            isOneToOne: false
            referencedRelation: "etablissements"
            referencedColumns: ["id"]
          },
        ]
      }
      signatures_contrats: {
        Row: {
          audit_trail: Json | null
          contrat_id: string
          cree_le: string | null
          hash_document: string | null
          id: string
          ip_signature: unknown
          modifie_le: string | null
          otp_code_hash: string | null
          otp_envoye_a: string | null
          otp_tentatives: number | null
          otp_valide_a: string | null
          psc_session_active: boolean | null
          rpps_verifie: boolean | null
          signataire_role: string
          signataire_user_id: string
          signature_image_base64: string | null
          signe_a: string | null
          sms_envoyes_count: number | null
          sms_premier_envoi_a: string | null
          statut_signature: string
          traits_identite_verifies: boolean | null
          user_agent: string | null
        }
        Insert: {
          audit_trail?: Json | null
          contrat_id: string
          cree_le?: string | null
          hash_document?: string | null
          id?: string
          ip_signature?: unknown
          modifie_le?: string | null
          otp_code_hash?: string | null
          otp_envoye_a?: string | null
          otp_tentatives?: number | null
          otp_valide_a?: string | null
          psc_session_active?: boolean | null
          rpps_verifie?: boolean | null
          signataire_role: string
          signataire_user_id: string
          signature_image_base64?: string | null
          signe_a?: string | null
          sms_envoyes_count?: number | null
          sms_premier_envoi_a?: string | null
          statut_signature?: string
          traits_identite_verifies?: boolean | null
          user_agent?: string | null
        }
        Update: {
          audit_trail?: Json | null
          contrat_id?: string
          cree_le?: string | null
          hash_document?: string | null
          id?: string
          ip_signature?: unknown
          modifie_le?: string | null
          otp_code_hash?: string | null
          otp_envoye_a?: string | null
          otp_tentatives?: number | null
          otp_valide_a?: string | null
          psc_session_active?: boolean | null
          rpps_verifie?: boolean | null
          signataire_role?: string
          signataire_user_id?: string
          signature_image_base64?: string | null
          signe_a?: string | null
          sms_envoyes_count?: number | null
          sms_premier_envoi_a?: string | null
          statut_signature?: string
          traits_identite_verifies?: boolean | null
          user_agent?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "signatures_contrats_contrat_id_fkey"
            columns: ["contrat_id"]
            isOneToOne: false
            referencedRelation: "contrats_mission"
            referencedColumns: ["id"]
          },
        ]
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
      sms_envoyes: {
        Row: {
          contenu: string
          cout_eur: number | null
          cree_le: string
          destinataire_id: string | null
          erreur: string | null
          id: string
          idempotency_key: string | null
          provider_id: string | null
          statut: string | null
          telephone: string
          type: string
        }
        Insert: {
          contenu: string
          cout_eur?: number | null
          cree_le?: string
          destinataire_id?: string | null
          erreur?: string | null
          id?: string
          idempotency_key?: string | null
          provider_id?: string | null
          statut?: string | null
          telephone: string
          type: string
        }
        Update: {
          contenu?: string
          cout_eur?: number | null
          cree_le?: string
          destinataire_id?: string | null
          erreur?: string | null
          id?: string
          idempotency_key?: string | null
          provider_id?: string | null
          statut?: string | null
          telephone?: string
          type?: string
        }
        Relationships: []
      }
      soignants: {
        Row: {
          accepte_missions_generalistes: boolean | null
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
          defacto_opt_in: boolean
          derniere_activite_le: string | null
          diplome_verifie: boolean | null
          disponible_urgence: boolean | null
          eligible_conversion_3200h: boolean | null
          email: string
          en_periode_probatoire: boolean
          est_cumul_activite: boolean | null
          est_salarie_etablissement: boolean | null
          heures_cumulees: number | null
          heures_plateforme: number | null
          iban_last4: string | null
          id: string
          identite_verifiee: boolean | null
          lieu_naissance_commune: string | null
          lieu_naissance_departement: string | null
          mandat_facturation_signe: boolean | null
          mandat_facturation_signe_le: string | null
          mandat_facturation_version: string | null
          modifie_le: string | null
          nationalite: string | null
          nb_absences_sans_prevenir_6_mois: number
          nb_evaluations: number | null
          niveau: Database["public"]["Enums"]["niveau_qualitatif"] | null
          nom: string
          note_moyenne: number | null
          numero_adeli: string | null
          numero_rpps: string | null
          numero_secu: string | null
          numero_securite_sociale: string | null
          numero_tva: string | null
          parraine_par: string | null
          pays_naissance: string | null
          pool_urgence_sms_opt_in: boolean
          premiere_mission_le: string | null
          prenom: string
          prevoyance_fournisseur: string | null
          prevoyance_inscrit: boolean | null
          prevoyance_numero_contrat: string | null
          priorite_missions_urgentes: boolean
          profession: Database["public"]["Enums"]["type_profession"] | null
          psc_last_login: string | null
          psc_linked_le: string | null
          psc_sub: string | null
          rayon_deplacement_km: number | null
          rib_partage_le: string | null
          rpps_nom_api: string | null
          rpps_prenom_api: string | null
          rpps_profession_api: string | null
          rpps_verifie: boolean | null
          rpps_verifie_le: string | null
          score_breakdown_id: string | null
          score_fiabilite: number | null
          sexe: string | null
          siret_liberal: string | null
          sms_actif: boolean | null
          sms_alertes_actives: boolean | null
          sms_consent_le: string | null
          specialite_code: string | null
          specialite_medicale: string | null
          specialite_source: string | null
          specialite_verifiee: boolean | null
          specialite_verifiee_le: string | null
          specialites: string[] | null
          statut_compte: Database["public"]["Enums"]["statut_compte_soignant"]
          statut_liberal: string | null
          statut_verification_aria:
            | Database["public"]["Enums"]["statut_verification"]
            | null
          stripe_account_id: string | null
          supprime_le: string | null
          suspension_le: string | null
          suspension_raison: string | null
          taux_horaire_minimum: number | null
          telephone: string | null
          total_absences: number | null
          total_litiges_perdus: number
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
          accepte_missions_generalistes?: boolean | null
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
          defacto_opt_in?: boolean
          derniere_activite_le?: string | null
          diplome_verifie?: boolean | null
          disponible_urgence?: boolean | null
          eligible_conversion_3200h?: boolean | null
          email: string
          en_periode_probatoire?: boolean
          est_cumul_activite?: boolean | null
          est_salarie_etablissement?: boolean | null
          heures_cumulees?: number | null
          heures_plateforme?: number | null
          iban_last4?: string | null
          id?: string
          identite_verifiee?: boolean | null
          lieu_naissance_commune?: string | null
          lieu_naissance_departement?: string | null
          mandat_facturation_signe?: boolean | null
          mandat_facturation_signe_le?: string | null
          mandat_facturation_version?: string | null
          modifie_le?: string | null
          nationalite?: string | null
          nb_absences_sans_prevenir_6_mois?: number
          nb_evaluations?: number | null
          niveau?: Database["public"]["Enums"]["niveau_qualitatif"] | null
          nom: string
          note_moyenne?: number | null
          numero_adeli?: string | null
          numero_rpps?: string | null
          numero_secu?: string | null
          numero_securite_sociale?: string | null
          numero_tva?: string | null
          parraine_par?: string | null
          pays_naissance?: string | null
          pool_urgence_sms_opt_in?: boolean
          premiere_mission_le?: string | null
          prenom: string
          prevoyance_fournisseur?: string | null
          prevoyance_inscrit?: boolean | null
          prevoyance_numero_contrat?: string | null
          priorite_missions_urgentes?: boolean
          profession?: Database["public"]["Enums"]["type_profession"] | null
          psc_last_login?: string | null
          psc_linked_le?: string | null
          psc_sub?: string | null
          rayon_deplacement_km?: number | null
          rib_partage_le?: string | null
          rpps_nom_api?: string | null
          rpps_prenom_api?: string | null
          rpps_profession_api?: string | null
          rpps_verifie?: boolean | null
          rpps_verifie_le?: string | null
          score_breakdown_id?: string | null
          score_fiabilite?: number | null
          sexe?: string | null
          siret_liberal?: string | null
          sms_actif?: boolean | null
          sms_alertes_actives?: boolean | null
          sms_consent_le?: string | null
          specialite_code?: string | null
          specialite_medicale?: string | null
          specialite_source?: string | null
          specialite_verifiee?: boolean | null
          specialite_verifiee_le?: string | null
          specialites?: string[] | null
          statut_compte?: Database["public"]["Enums"]["statut_compte_soignant"]
          statut_liberal?: string | null
          statut_verification_aria?:
            | Database["public"]["Enums"]["statut_verification"]
            | null
          stripe_account_id?: string | null
          supprime_le?: string | null
          suspension_le?: string | null
          suspension_raison?: string | null
          taux_horaire_minimum?: number | null
          telephone?: string | null
          total_absences?: number | null
          total_litiges_perdus?: number
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
          accepte_missions_generalistes?: boolean | null
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
          defacto_opt_in?: boolean
          derniere_activite_le?: string | null
          diplome_verifie?: boolean | null
          disponible_urgence?: boolean | null
          eligible_conversion_3200h?: boolean | null
          email?: string
          en_periode_probatoire?: boolean
          est_cumul_activite?: boolean | null
          est_salarie_etablissement?: boolean | null
          heures_cumulees?: number | null
          heures_plateforme?: number | null
          iban_last4?: string | null
          id?: string
          identite_verifiee?: boolean | null
          lieu_naissance_commune?: string | null
          lieu_naissance_departement?: string | null
          mandat_facturation_signe?: boolean | null
          mandat_facturation_signe_le?: string | null
          mandat_facturation_version?: string | null
          modifie_le?: string | null
          nationalite?: string | null
          nb_absences_sans_prevenir_6_mois?: number
          nb_evaluations?: number | null
          niveau?: Database["public"]["Enums"]["niveau_qualitatif"] | null
          nom?: string
          note_moyenne?: number | null
          numero_adeli?: string | null
          numero_rpps?: string | null
          numero_secu?: string | null
          numero_securite_sociale?: string | null
          numero_tva?: string | null
          parraine_par?: string | null
          pays_naissance?: string | null
          pool_urgence_sms_opt_in?: boolean
          premiere_mission_le?: string | null
          prenom?: string
          prevoyance_fournisseur?: string | null
          prevoyance_inscrit?: boolean | null
          prevoyance_numero_contrat?: string | null
          priorite_missions_urgentes?: boolean
          profession?: Database["public"]["Enums"]["type_profession"] | null
          psc_last_login?: string | null
          psc_linked_le?: string | null
          psc_sub?: string | null
          rayon_deplacement_km?: number | null
          rib_partage_le?: string | null
          rpps_nom_api?: string | null
          rpps_prenom_api?: string | null
          rpps_profession_api?: string | null
          rpps_verifie?: boolean | null
          rpps_verifie_le?: string | null
          score_breakdown_id?: string | null
          score_fiabilite?: number | null
          sexe?: string | null
          siret_liberal?: string | null
          sms_actif?: boolean | null
          sms_alertes_actives?: boolean | null
          sms_consent_le?: string | null
          specialite_code?: string | null
          specialite_medicale?: string | null
          specialite_source?: string | null
          specialite_verifiee?: boolean | null
          specialite_verifiee_le?: string | null
          specialites?: string[] | null
          statut_compte?: Database["public"]["Enums"]["statut_compte_soignant"]
          statut_liberal?: string | null
          statut_verification_aria?:
            | Database["public"]["Enums"]["statut_verification"]
            | null
          stripe_account_id?: string | null
          supprime_le?: string | null
          suspension_le?: string | null
          suspension_raison?: string | null
          taux_horaire_minimum?: number | null
          telephone?: string | null
          total_absences?: number | null
          total_litiges_perdus?: number
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
        Relationships: [
          {
            foreignKeyName: "fk_soignants_score_breakdown"
            columns: ["score_breakdown_id"]
            isOneToOne: false
            referencedRelation: "scoring_breakdown"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "soignants_specialite_medicale_fkey"
            columns: ["specialite_medicale"]
            isOneToOne: false
            referencedRelation: "specialites_medicales"
            referencedColumns: ["code"]
          },
        ]
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
      specialites_medicales: {
        Row: {
          actif: boolean | null
          code: string
          cree_le: string | null
          label: string
          profession_parent: string
        }
        Insert: {
          actif?: boolean | null
          code: string
          cree_le?: string | null
          label: string
          profession_parent: string
        }
        Update: {
          actif?: boolean | null
          code?: string
          cree_le?: string | null
          label?: string
          profession_parent?: string
        }
        Relationships: []
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
      stripe_refunds_queue: {
        Row: {
          avoir_id: string
          cree_le: string
          dernier_essai_le: string | null
          erreur: string | null
          facture_origine_id: string
          id: string
          montant_cts: number
          statut: string
          stripe_payment_intent_id: string
          stripe_refund_id: string | null
          tentatives: number
          traite_le: string | null
        }
        Insert: {
          avoir_id: string
          cree_le?: string
          dernier_essai_le?: string | null
          erreur?: string | null
          facture_origine_id: string
          id?: string
          montant_cts: number
          statut?: string
          stripe_payment_intent_id: string
          stripe_refund_id?: string | null
          tentatives?: number
          traite_le?: string | null
        }
        Update: {
          avoir_id?: string
          cree_le?: string
          dernier_essai_le?: string | null
          erreur?: string | null
          facture_origine_id?: string
          id?: string
          montant_cts?: number
          statut?: string
          stripe_payment_intent_id?: string
          stripe_refund_id?: string | null
          tentatives?: number
          traite_le?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "stripe_refunds_queue_avoir_id_fkey"
            columns: ["avoir_id"]
            isOneToOne: false
            referencedRelation: "factures_honoraires"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "stripe_refunds_queue_facture_origine_id_fkey"
            columns: ["facture_origine_id"]
            isOneToOne: false
            referencedRelation: "factures_honoraires"
            referencedColumns: ["id"]
          },
        ]
      }
      stripe_transfers: {
        Row: {
          charge_le: string | null
          cree_le: string | null
          dispute_cree_le: string | null
          dispute_id: string | null
          dispute_reason: string | null
          dispute_statut: string | null
          erreur: string | null
          etablissement_id: string
          facture_id: string | null
          id: string
          mission_id: string
          montant_commission: number
          montant_soignant: number
          montant_total: number
          paye_le: string | null
          reversed_le: string | null
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
          dispute_cree_le?: string | null
          dispute_id?: string | null
          dispute_reason?: string | null
          dispute_statut?: string | null
          erreur?: string | null
          etablissement_id: string
          facture_id?: string | null
          id?: string
          mission_id: string
          montant_commission: number
          montant_soignant: number
          montant_total: number
          paye_le?: string | null
          reversed_le?: string | null
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
          dispute_cree_le?: string | null
          dispute_id?: string | null
          dispute_reason?: string | null
          dispute_statut?: string | null
          erreur?: string | null
          etablissement_id?: string
          facture_id?: string | null
          id?: string
          mission_id?: string
          montant_commission?: number
          montant_soignant?: number
          montant_total?: number
          paye_le?: string | null
          reversed_le?: string | null
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
      stripe_webhook_events: {
        Row: {
          erreur: string | null
          event_id: string
          event_type: string
          payload: Json | null
          recu_le: string
          traite_le: string | null
        }
        Insert: {
          erreur?: string | null
          event_id: string
          event_type: string
          payload?: Json | null
          recu_le?: string
          traite_le?: string | null
        }
        Update: {
          erreur?: string | null
          event_id?: string
          event_type?: string
          payload?: Json | null
          recu_le?: string
          traite_le?: string | null
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
          auth_key: string | null
          cree_le: string | null
          derniere_utilisation: string | null
          endpoint: string | null
          id: string
          p256dh: string | null
          plateforme: string | null
          token: string
          utilisateur_id: string
        }
        Insert: {
          actif?: boolean | null
          auth_key?: string | null
          cree_le?: string | null
          derniere_utilisation?: string | null
          endpoint?: string | null
          id?: string
          p256dh?: string | null
          plateforme?: string | null
          token: string
          utilisateur_id: string
        }
        Update: {
          actif?: boolean | null
          auth_key?: string | null
          cree_le?: string | null
          derniere_utilisation?: string | null
          endpoint?: string | null
          id?: string
          p256dh?: string | null
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
      _sha256_hex: { Args: { p_input: string }; Returns: string }
      est_admin: { Args: never; Returns: boolean }
      est_admin_etablissement: { Args: never; Returns: boolean }
      est_admin_valide: { Args: never; Returns: boolean }
      est_soignant: { Args: never; Returns: boolean }
      fn_accepter_mission: {
        Args: { p_choix_contrat?: string; p_mission_id: string }
        Returns: Json
      }
      fn_accepter_mission_urgence: {
        Args: { p_mission_id: string }
        Returns: Json
      }
      fn_activer_liberal: { Args: never; Returns: Json }
      fn_admin_chorus_config_toggle: {
        Args: {
          p_actif: boolean
          p_code_service?: string
          p_etablissement_id: string
          p_identifiant_cpro?: string
          p_numero_structure?: string
        }
        Returns: Json
      }
      fn_admin_chorus_stats: { Args: never; Returns: Json }
      fn_admin_chorus_submission_reset: {
        Args: { p_facture_honoraire_id: string }
        Returns: Json
      }
      fn_admin_cleanup_test_accounts: { Args: never; Returns: Json }
      fn_admin_cohort_economics: { Args: { p_mois?: number }; Returns: Json }
      fn_admin_conformite: { Args: never; Returns: Json }
      fn_admin_conformite_detail: { Args: { p_type: string }; Returns: Json }
      fn_admin_creer_litige_force: {
        Args: {
          p_mission_id: string
          p_motif: string
          p_raison_bypass: string
          p_type_litige: Database["public"]["Enums"]["type_litige"]
        }
        Returns: Json
      }
      fn_admin_factor_stats: { Args: never; Returns: Json }
      fn_admin_finances: { Args: never; Returns: Json }
      fn_admin_finances_par_etablissement: { Args: never; Returns: Json }
      fn_admin_forcer_reupload_rib: {
        Args: { p_etablissement_id: string; p_raison: string }
        Returns: Json
      }
      fn_admin_get_user_id_by_email: {
        Args: { p_email: string }
        Returns: string
      }
      fn_admin_graphiques: { Args: never; Returns: Json }
      fn_admin_health_check: { Args: never; Returns: Json }
      fn_admin_incoherences_identite: {
        Args: never
        Returns: {
          coherence_details: Json
          coherence_identite: string
          identite_verifiee: boolean
          nom: string
          nom_cni: string
          nom_profil: string
          nom_rpps: string
          prenom: string
          prenom_profil: string
          rpps_verifie: boolean
          soignant_id: string
        }[]
      }
      fn_admin_invocations_purge: { Args: never; Returns: number }
      fn_admin_kpi: { Args: never; Returns: Json }
      fn_admin_lever_suspension: {
        Args: { p_raison: string; p_soignant_id: string }
        Returns: Json
      }
      fn_admin_lister_taux_commission: { Args: never; Returns: Json }
      fn_admin_mandats_stats: { Args: never; Returns: Json }
      fn_admin_marquer_absence_sans_prevenir: {
        Args: { p_mission_id: string; p_motif?: string }
        Returns: Json
      }
      fn_admin_marquer_facture_en_retard: {
        Args: { p_facture_id: string }
        Returns: Json
      }
      fn_admin_masquer_notation: {
        Args: { p_notation_id: string; p_raison: string }
        Returns: Json
      }
      fn_admin_moderer_document: {
        Args: { p_action: string; p_document_id: string; p_motif?: string }
        Returns: Json
      }
      fn_admin_moderer_evaluation: {
        Args: { p_action: string; p_evaluation_id: string }
        Returns: Json
      }
      fn_admin_modifier_gel_scope_litige: {
        Args: { p_litige_id: string; p_nouveau_scope: string; p_raison: string }
        Returns: Json
      }
      fn_admin_modifier_taux_commission: {
        Args: {
          p_etablissement_id?: string
          p_groupe_id?: string
          p_nouveau_taux?: number
          p_raison?: string
        }
        Returns: Json
      }
      fn_admin_planning_global: {
        Args: { p_debut?: string; p_fin?: string }
        Returns: Json
      }
      fn_admin_recategoriser_litige_legacy: {
        Args: {
          p_litige_id: string
          p_nouveau_type: Database["public"]["Enums"]["type_litige"]
        }
        Returns: Json
      }
      fn_admin_rejeter_etablissement: {
        Args: { p_etablissement_id: string; p_motif?: string }
        Returns: Json
      }
      fn_admin_reset_test_account: { Args: { p_role: string }; Returns: Json }
      fn_admin_resoudre_alerte: { Args: { p_alerte_id: string }; Returns: Json }
      fn_admin_resoudre_litige:
        | {
            Args: {
              p_ajuster_heures?: number
              p_ajuster_taux?: number
              p_en_faveur_de?: string
              p_litige_id: string
              p_resolution: string
            }
            Returns: Json
          }
        | {
            Args: {
              p_action_financiere?: string
              p_ajuster_heures?: number
              p_ajuster_taux?: number
              p_en_faveur_de?: string
              p_litige_id: string
              p_resolution: string
            }
            Returns: Json
          }
      fn_admin_stripe_connect_stats: { Args: never; Returns: Json }
      fn_admin_suspendre_utilisateur: {
        Args: { p_id: string; p_suspendre?: boolean; p_table: string }
        Returns: Json
      }
      fn_admin_trancher_litige: {
        Args: { p_decision: string; p_litige_id: string; p_motif?: string }
        Returns: Json
      }
      fn_admin_valider_contrat_etablissement: {
        Args: { p_etablissement_id: string; p_valider?: boolean }
        Returns: Json
      }
      fn_admin_valider_etablissement: {
        Args: { p_etablissement_id: string }
        Returns: Json
      }
      fn_ajouter_jours_ouvres: {
        Args: { p_date: string; p_nb_jours: number }
        Returns: string
      }
      fn_ajouter_message_litige: {
        Args: { p_contenu: string; p_litige_id: string }
        Returns: Json
      }
      fn_alerte_cddu_repetitif: {
        Args: { p_etablissement_id: string; p_soignant_id: string }
        Returns: Json
      }
      fn_alerter_mediation_prioritaire: { Args: never; Returns: Json }
      fn_alerter_paiements_retard: { Args: never; Returns: Json }
      fn_alertes_dashboard_etab: { Args: never; Returns: Json }
      fn_analytics_etablissement: {
        Args: { p_etablissement_id: string; p_mois?: number }
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
      fn_appliquer_credits_disponibles_etab: {
        Args: { p_facture_id: string }
        Returns: Json
      }
      fn_appliquer_parrainage: { Args: { p_code: string }; Returns: Json }
      fn_appliquer_parrainage_etab: { Args: { p_code: string }; Returns: Json }
      fn_appliquer_remise_groupe: { Args: never; Returns: Json }
      fn_arrondir_quart_heure: { Args: { p_ts: string }; Returns: string }
      fn_assigner_mission_admin: {
        Args: {
          p_choix_contrat?: string
          p_mission_id: string
          p_soignant_id: string
        }
        Returns: Json
      }
      fn_audit_connexion: { Args: { p_action: string }; Returns: Json }
      fn_auto_creation_litiges_presence: { Args: never; Returns: Json }
      fn_auto_facturation_mensuelle: { Args: never; Returns: Json }
      fn_auto_terminer_missions: { Args: never; Returns: Json }
      fn_auto_transitions_missions: { Args: never; Returns: Json }
      fn_auto_valider_presences_72h: { Args: never; Returns: number }
      fn_badge_stats: { Args: never; Returns: Json }
      fn_basculer_litiges_revue_admin_timeout: { Args: never; Returns: Json }
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
      fn_calculer_heures_majorees: {
        Args: { p_debut: string; p_fin: string }
        Returns: {
          heures_dimanche: number
          heures_ferie: number
          heures_nuit: number
        }[]
      }
      fn_calculer_heures_totales: {
        Args: { p_soignant_id: string }
        Returns: Json
      }
      fn_calculer_montant_periode: {
        Args: {
          p_mission_id: string
          p_periode_debut?: string
          p_periode_fin?: string
        }
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
      fn_calculer_score_etablissement: {
        Args: { p_etab_id: string }
        Returns: Json
      }
      fn_calculer_score_fiabilite_v2: {
        Args: { p_raison?: string; p_soignant_id: string }
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
      fn_cession_existe: {
        Args: { p_facture_honoraire_id: string }
        Returns: boolean
      }
      fn_charger_demo_investisseur: { Args: never; Returns: Json }
      fn_check_crons_health: { Args: never; Returns: Json }
      fn_check_rate_limit: {
        Args: { p_action: string; p_max_per_minute?: number }
        Returns: boolean
      }
      fn_check_stripe_webhook_health: { Args: never; Returns: Json }
      fn_choisir_parcours_kine: {
        Args: { p_parcours: string }
        Returns: {
          cree_le: string | null
          demarre_le: string | null
          etapes: Json | null
          id: string
          mis_a_jour_le: string | null
          parcours_kine: string | null
          soignant_id: string
          termine_le: string | null
        }
        SetofOptions: {
          from: "*"
          to: "parcours_liberal_soignants"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      fn_cloturer_litige: {
        Args: { p_litige_id: string; p_resolution?: string }
        Returns: Json
      }
      fn_cloturer_litige_mutuel: {
        Args: { p_litige_id: string }
        Returns: Json
      }
      fn_codes_pointage_mission: {
        Args: { p_mission_id: string }
        Returns: Json
      }
      fn_commission_info_etablissement: { Args: never; Returns: Json }
      fn_compter_missions_sans_notation: {
        Args: { p_role?: string }
        Returns: Json
      }
      fn_compter_nouveaux_pour_filtre: {
        Args: { p_filtre_id: string; p_since: string }
        Returns: number
      }
      fn_compteur_heures_soignant: {
        Args: { p_soignant_id: string }
        Returns: {
          eligible_free_transition: boolean
          heures_externes_en_attente: number
          heures_externes_validees: number
          heures_jolene: number
          heures_totales: number
        }[]
      }
      fn_compteur_soignants_disponibles: {
        Args: { p_etablissement_id: string }
        Returns: Json
      }
      fn_confirmer_accord_partie: {
        Args: { p_litige_id: string }
        Returns: Json
      }
      fn_confirmer_paiement_soignant: {
        Args: { p_paiement_id: string }
        Returns: Json
      }
      fn_confirmer_reception_paiement: {
        Args: { p_paiement_id: string }
        Returns: Json
      }
      fn_confirmer_remboursement_avoir: {
        Args: { p_avoir_id: string; p_reference_virement: string }
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
      fn_contrat_storage_path: { Args: { p_contrat_id: string }; Returns: Json }
      fn_creer_api_key: {
        Args: {
          p_etablissement_id?: string
          p_nom: string
          p_permissions: string[]
        }
        Returns: Json
      }
      fn_creer_bulletin_paie: { Args: { p_mission_id: string }; Returns: Json }
      fn_creer_filtre_sauvegarde: {
        Args: {
          p_alerte_active?: boolean
          p_audience: Database["public"]["Enums"]["filtre_audience"]
          p_filtres: Json
          p_frequence_alerte?: Database["public"]["Enums"]["filtre_frequence_alerte"]
          p_nom: string
        }
        Returns: Json
      }
      fn_creer_litige: {
        Args: { p_mission_id: string; p_motif?: string; p_presence_id?: string }
        Returns: Json
      }
      fn_creer_mission: {
        Args: {
          p_accepte_non_specialises?: boolean
          p_debut_le?: string
          p_description?: string
          p_est_urgente?: boolean
          p_fin_le?: string
          p_intitule: string
          p_mode_attribution?: string
          p_niveau_urgence?: number
          p_profession_requise?: Database["public"]["Enums"]["type_profession"]
          p_service?: string
          p_specialite_medicale_requise?: string
          p_taux_horaire_base?: number
        }
        Returns: Json
      }
      fn_creer_notation_mission: {
        Args: {
          p_commentaire?: string
          p_critere_1: number
          p_critere_2: number
          p_critere_3: number
          p_critere_4: number
          p_mission_id: string
          p_sens: string
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
      fn_cumul_annuel_paie: {
        Args: { p_annee?: number; p_jusqu_au?: string; p_soignant_id: string }
        Returns: Json
      }
      fn_cumul_factures_mission: {
        Args: { p_jusqu_au?: string; p_mission_id: string }
        Returns: Json
      }
      fn_dashboard_soignant_complet: { Args: never; Returns: Json }
      fn_declarer_fin_retroactive: {
        Args: { p_heure_fin: string; p_mission_id: string; p_raison?: string }
        Returns: Json
      }
      fn_declarer_paiement_soignant:
        | {
            Args: {
              p_date_paiement?: string
              p_methode?: string
              p_mission_id: string
              p_montant: number
              p_reference?: string
            }
            Returns: Json
          }
        | {
            Args: {
              p_attestation_sur_l_honneur?: boolean
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
      fn_demander_mediation_admin: {
        Args: { p_litige_id: string; p_message?: string }
        Returns: Json
      }
      fn_demander_mediation_litige: {
        Args: { p_litige_id: string }
        Returns: Json
      }
      fn_deposer_chorus: {
        Args: { p_chorus_id?: string; p_facture_id: string }
        Returns: Json
      }
      fn_detail_facture: { Args: { p_facture_id: string }; Returns: Json }
      fn_detecter_teleportation: {
        Args: {
          p_horodatage: string
          p_lat: number
          p_lng: number
          p_soignant_id: string
        }
        Returns: Json
      }
      fn_diagnostic_coherence_financiere: { Args: never; Returns: Json }
      fn_doit_notifier: {
        Args: {
          p_canal: Database["public"]["Enums"]["canal_notification"]
          p_type_evenement: Database["public"]["Enums"]["type_evenement_notification"]
          p_utilisateur_id: string
        }
        Returns: boolean
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
      fn_emettre_alerte_monitoring: {
        Args: {
          p_details?: Json
          p_message: string
          p_severite: string
          p_source: string
          p_type: string
        }
        Returns: string
      }
      fn_enregistrer_numero_dpae: {
        Args: { p_contrat_id: string; p_dpae_numero: string }
        Returns: Json
      }
      fn_enregistrer_siret_liberal: { Args: { p_siret: string }; Returns: Json }
      fn_envoyer_message: {
        Args: { p_contenu: string; p_conversation_id: string }
        Returns: Json
      }
      fn_envoyer_otp_signature: {
        Args: { p_contrat_id: string }
        Returns: Json
      }
      fn_envoyer_rappels_litiges: { Args: never; Returns: Json }
      fn_envoyer_rappels_notation_j1: { Args: never; Returns: Json }
      fn_est_exclu: {
        Args: { p_etablissement_id: string; p_soignant_id: string }
        Returns: boolean
      }
      fn_est_exclu_par_etablissement: {
        Args: { p_etablissement_id: string }
        Returns: boolean
      }
      fn_est_jour_ferie: { Args: { p_date: string }; Returns: boolean }
      fn_etab_valider_acceptation_urgence: {
        Args: {
          p_action: string
          p_candidature_id: string
          p_motif_refus?: string
        }
        Returns: Json
      }
      fn_etablissement_pour_mission: {
        Args: { p_etablissement_id: string }
        Returns: Json
      }
      fn_etablissement_pour_soignant: {
        Args: { p_etablissement_id: string }
        Returns: Json
      }
      fn_etablissement_public: {
        Args: { p_etablissement_id: string }
        Returns: Json
      }
      fn_etablissements_avec_missions_ouvertes: { Args: never; Returns: Json }
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
          type: string
        }[]
      }
      fn_evaluer_alertes_filtres: {
        Args: { p_frequence?: string }
        Returns: {
          audience: Database["public"]["Enums"]["filtre_audience"]
          filtre_id: string
          nb_nouveaux: number
          nom: string
          utilisateur_id: string
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
      fn_evolution_missions_etab: { Args: never; Returns: Json }
      fn_evolution_score_soignant: { Args: { p_limit?: number }; Returns: Json }
      fn_exclure_utilisateur: {
        Args: { p_exclu_id: string; p_motif?: string; p_type: string }
        Returns: Json
      }
      fn_expirer_parrainages_inactifs: { Args: never; Returns: Json }
      fn_export_fec: {
        Args: { p_annee: number }
        Returns: {
          comp_aux_libelle: string
          comp_aux_num: string
          compte_libelle: string
          compte_num: string
          credit: number
          debit: number
          devise: string
          ecriture_date: string
          ecriture_libelle: string
          ecriture_num: string
          journal_code: string
          journal_libelle: string
          montant: number
          piece_date: string
          piece_ref: string
        }[]
      }
      fn_exporter_mes_donnees: { Args: never; Returns: Json }
      fn_exporter_rgpd_etablissement: { Args: never; Returns: Json }
      fn_fenetre_contestation_ouverte: {
        Args: {
          p_facture_id?: string
          p_mission_id: string
          p_type_litige: Database["public"]["Enums"]["type_litige"]
        }
        Returns: boolean
      }
      fn_generer_code_parrainage: { Args: never; Returns: string }
      fn_generer_code_parrainage_etab: { Args: never; Returns: string }
      fn_generer_donnees_dpae: { Args: { p_contrat_id: string }; Returns: Json }
      fn_generer_facture: { Args: { p_mission_id: string }; Returns: Json }
      fn_generer_facture_honoraires_mission: {
        Args: { p_mission_id: string }
        Returns: Json
      }
      fn_generer_facture_mensuelle: {
        Args: { p_etablissement_id: string }
        Returns: Json
      }
      fn_generer_facture_rate_limited: { Args: never; Returns: Json }
      fn_generer_jours_feries: { Args: { p_annee: number }; Returns: undefined }
      fn_generer_numero_contrat: { Args: { p_type: string }; Returns: string }
      fn_generer_numero_contrat_safe: {
        Args: { p_type: string }
        Returns: string
      }
      fn_generer_numero_facture: { Args: never; Returns: string }
      fn_generer_numero_note_honoraires: { Args: never; Returns: string }
      fn_gerer_blocage_etabs: { Args: never; Returns: Json }
      fn_get_my_role: { Args: never; Returns: Json }
      fn_get_or_create_parcours_liberal: {
        Args: { p_soignant_id?: string }
        Returns: {
          cree_le: string | null
          demarre_le: string | null
          etapes: Json | null
          id: string
          mis_a_jour_le: string | null
          parcours_kine: string | null
          soignant_id: string
          termine_le: string | null
        }
        SetofOptions: {
          from: "*"
          to: "parcours_liberal_soignants"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      fn_get_stripe_account_soignant: {
        Args: { p_soignant_id: string }
        Returns: string
      }
      fn_health_check: { Args: never; Returns: Json }
      fn_html_escape: { Args: { p_text: string }; Returns: string }
      fn_inscrire_liste_attente_prevoyance: {
        Args: { p_email: string; p_niveau?: string }
        Returns: Json
      }
      fn_is_valid_uuid: { Args: { p_text: string }; Returns: boolean }
      fn_lire_secret_cron: { Args: never; Returns: string }
      fn_list_admin_user_ids: { Args: never; Returns: string[] }
      fn_lister_factures_a_regenerer: {
        Args: { p_limit?: number }
        Returns: {
          cree_le: string
          id: string
          numero_facture: string
          soignant_id: string
          type_document: Database["public"]["Enums"]["type_document_facture"]
        }[]
      }
      fn_lister_mes_filtres_sauvegardes: {
        Args: { p_audience?: Database["public"]["Enums"]["filtre_audience"] }
        Returns: Json
      }
      fn_lister_missions_a_facturer: {
        Args: { p_today?: string }
        Returns: Json
      }
      fn_lister_missions_contrat_travail_manquant: {
        Args: never
        Returns: Json
      }
      fn_lister_notations_recues: { Args: { p_limit?: number }; Returns: Json }
      fn_litige_pour_mission: { Args: { p_mission_id: string }; Returns: Json }
      fn_litige_preuves_agregees: {
        Args: { p_litige_id: string }
        Returns: Json
      }
      fn_litige_push_notification: {
        Args: {
          p_corps: string
          p_destinataire_id: string
          p_email_data?: Json
          p_litige_id: string
          p_titre: string
          p_type_destinataire: string
          p_type_notif: string
        }
        Returns: undefined
      }
      fn_litiges_escalader_auto: { Args: never; Returns: Json }
      fn_litiges_etablissement: { Args: never; Returns: Json }
      fn_litiges_historique_similaires: {
        Args: { p_limit?: number; p_litige_id: string }
        Returns: {
          cree_le: string
          en_faveur_de: string
          id: string
          mission_id: string
          montant_tresorerie_bloquee: number
          motif: string
          resolu_le: string
          resolution: string
          statut: string
          type_litige: Database["public"]["Enums"]["type_litige"]
        }[]
      }
      fn_maj_activite_soignant: { Args: never; Returns: Json }
      fn_maj_etape_parcours: {
        Args: { p_etape_cle: string; p_valeur: boolean }
        Returns: {
          cree_le: string | null
          demarre_le: string | null
          etapes: Json | null
          id: string
          mis_a_jour_le: string | null
          parcours_kine: string | null
          soignant_id: string
          termine_le: string | null
        }
        SetofOptions: {
          from: "*"
          to: "parcours_liberal_soignants"
          isOneToOne: true
          isSetofReturn: false
        }
      }
      fn_maj_infos_dpae: {
        Args: {
          p_lieu_naissance_commune: string
          p_lieu_naissance_departement: string
          p_nationalite: string
          p_pays_naissance: string
          p_sexe: string
        }
        Returns: Json
      }
      fn_marquer_messages_lus: {
        Args: { p_conversation_id: string }
        Returns: undefined
      }
      fn_marquer_rappel_contrat_travail_envoye: {
        Args: {
          p_cible_etab: boolean
          p_cible_soignant: boolean
          p_mission_id: string
        }
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
      fn_matching_soignants: {
        Args: { p_mission_id: string }
        Returns: {
          deja_travaille: boolean
          disponible: boolean
          distance_km: number
          nom: string
          note_moyenne: number
          prenom: string
          profession: string
          score_fiabilite: number
          score_matching: number
          soignant_id: string
        }[]
      }
      fn_mes_avances_factor: {
        Args: never
        Returns: {
          cree_le: string
          etablissement_nom: string
          financee_le: string
          frais_factor: number
          frais_jolene: number
          id: string
          mission_intitule: string
          montant_facture_ttc: number
          montant_net_soignant: number
          numero_facture: string
          statut: string
        }[]
      }
      fn_mes_bulletins_paie: {
        Args: never
        Returns: {
          cree_le: string
          date_emission: string
          date_paiement: string
          etablissement_id: string
          etablissement_nom: string
          icp: number
          id: string
          ifm: number
          mission_id: string
          mission_intitule: string
          net_avant_impot: number
          numero_bulletin: string
          pdf_s3_key: string
          periode_debut: string
          periode_fin: string
          salaire_brut: number
          statut: string
          total_cotisations_salariales: number
        }[]
      }
      fn_mes_credits_etab: { Args: never; Returns: Json }
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
      fn_mes_factures: { Args: never; Returns: Json }
      fn_mes_factures_honoraires: {
        Args: never
        Returns: {
          date_echeance: string
          date_emission: string
          date_paiement: string
          etablissement_nom: string
          id: string
          mission_intitule: string
          montant_ttc: number
          numero_facture: string
          statut: string
        }[]
      }
      fn_mes_favoris_etablissements: { Args: never; Returns: Json }
      fn_mes_favoris_soignants: { Args: never; Returns: Json }
      fn_mes_filleuls: { Args: never; Returns: Json }
      fn_mes_filleuls_etab: { Args: never; Returns: Json }
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
          profession: string
          rpps_verifie: boolean
          score_fiabilite: number
          telephone: string
          total_missions_terminees: number
          tous_documents_valides: boolean
        }[]
      }
      fn_messages_non_lus: { Args: never; Returns: number }
      fn_mission_est_de_nuit: {
        Args: { p_debut: string; p_fin: string }
        Returns: boolean
      }
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
      fn_modifier_filtre_sauvegarde: {
        Args: {
          p_alerte_active?: boolean
          p_frequence_alerte?: Database["public"]["Enums"]["filtre_frequence_alerte"]
          p_id: string
          p_nom?: string
        }
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
      fn_modifier_mon_nir: { Args: { p_nir: string }; Returns: Json }
      fn_modifier_mon_profil: {
        Args: {
          p_adresse_code_postal?: string
          p_adresse_lat?: number
          p_adresse_lng?: number
          p_adresse_rue?: string
          p_adresse_ville?: string
          p_annees_experience?: number
          p_attestation_cumul_activite?: boolean
          p_avatar_url?: string
          p_bio?: string
          p_consentement_gps?: boolean
          p_date_naissance?: string
          p_disponible_urgence?: boolean
          p_est_cumul_activite?: boolean
          p_est_salarie_etablissement?: boolean
          p_nom?: string
          p_numero_adeli?: string
          p_numero_rpps?: string
          p_prenom?: string
          p_profession?: string
          p_rayon_deplacement_km?: number
          p_specialites?: string[]
          p_taux_horaire_minimum?: number
          p_telephone?: string
          p_type_exercice?: string
          p_types_contrat?: string[]
          p_types_contrat_acceptes?: string
          p_urgence_rayon_km?: number
          p_ville_recherche?: string
          p_ville_urgence?: string
        }
        Returns: Json
      }
      fn_modifier_mon_profil_extra: {
        Args: {
          p_adresse_lat?: number
          p_adresse_lng?: number
          p_disponible_urgence?: boolean
          p_rayon_deplacement_km?: number
          p_type_exercice?: string
          p_urgence_rayon_km?: number
        }
        Returns: Json
      }
      fn_modifier_notation_mission: {
        Args: {
          p_commentaire?: string
          p_critere_1: number
          p_critere_2: number
          p_critere_3: number
          p_critere_4: number
          p_notation_id: string
        }
        Returns: Json
      }
      fn_modifier_preferences_notifications: {
        Args: {
          p_canal_email?: boolean
          p_canal_in_app?: boolean
          p_canal_push?: boolean
          p_canal_sms?: boolean
          p_par_evenement?: Json
        }
        Returns: Json
      }
      fn_modifier_profil_etablissement: {
        Args: {
          p_adresse_code_postal?: string
          p_adresse_departement?: string
          p_adresse_lat?: number
          p_adresse_lng?: number
          p_adresse_rue?: string
          p_adresse_ville?: string
          p_couleur_theme?: string
          p_description?: string
          p_email_contact?: string
          p_finess?: string
          p_horaires_ouverture?: Json
          p_mode_paiement_commission?: string
          p_nom?: string
          p_telephone_contact?: string
        }
        Returns: Json
      }
      fn_modifier_reference_paiement: {
        Args: { p_nouvelle_reference: string; p_paiement_id: string }
        Returns: Json
      }
      fn_modifier_tva_liberal: {
        Args: { p_assujetti_tva: boolean; p_numero_tva?: string }
        Returns: Json
      }
      fn_modifier_type_contrat_mission: {
        Args: { p_mission_id: string; p_type_contrat: string }
        Returns: Json
      }
      fn_mon_bfa: { Args: never; Returns: Json }
      fn_mon_breakdown_actuel: { Args: never; Returns: Json }
      fn_mon_contrat_plateforme: { Args: never; Returns: Json }
      fn_mon_etab_alerte_cddu: {
        Args: { p_etablissement_id: string; p_soignant_id: string }
        Returns: Json
      }
      fn_mon_etablissement_complet: { Args: never; Returns: Json }
      fn_mon_profil_soignant_complet: { Args: never; Returns: Json }
      fn_mon_score_etab: { Args: never; Returns: Json }
      fn_mon_token_calendrier: { Args: never; Returns: string }
      fn_nettoyer_missions_fantomes: { Args: never; Returns: number }
      fn_nettoyer_partages_rib_expires: { Args: never; Returns: undefined }
      fn_nettoyer_psc_sessions_expirees: { Args: never; Returns: undefined }
      fn_nettoyer_tokens_push: { Args: never; Returns: number }
      fn_next_bulletin_paie_number: {
        Args: { p_soignant_id: string }
        Returns: string
      }
      fn_note_moyenne: { Args: { p_user_id: string }; Returns: Json }
      fn_notifier_documents_expirants: { Args: never; Returns: number }
      fn_obligations_financieres: { Args: never; Returns: Json }
      fn_obtenir_apercu_filtre: {
        Args: { p_filtre_id: string; p_limit?: number; p_since: string }
        Returns: Json
      }
      fn_obtenir_conversation: {
        Args: { p_autre_id: string; p_mission_id?: string }
        Returns: string
      }
      fn_obtenir_donnees_template_serie: {
        Args: { p_envoi_id: string }
        Returns: Json
      }
      fn_obtenir_mes_preferences_notifications: { Args: never; Returns: Json }
      fn_ouvrir_litige_rate_limited:
        | { Args: { p_mission_id: string; p_motif: string }; Returns: Json }
        | {
            Args: {
              p_mission_id: string
              p_motif: string
              p_type_litige: Database["public"]["Enums"]["type_litige"]
            }
            Returns: Json
          }
      fn_paiements_etablissement: { Args: never; Returns: Json }
      fn_planifier_serie_onboarding: {
        Args: {
          p_serie: Database["public"]["Enums"]["serie_onboarding_type"]
          p_utilisateur_id: string
        }
        Returns: Json
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
      fn_pool_urgence_missions_pour_soignant: { Args: never; Returns: Json }
      fn_postuler_mission: {
        Args: {
          p_choix_contrat?: string
          p_message?: string
          p_mission_id: string
        }
        Returns: Json
      }
      fn_postuler_mission_rate_limited: {
        Args: { p_mission_id: string }
        Returns: Json
      }
      fn_presences_detail_mission: {
        Args: { p_mission_id: string }
        Returns: Json
      }
      fn_profession_peut_etre_liberal: {
        Args: { p_profession: string }
        Returns: boolean
      }
      fn_professions_liberales: { Args: never; Returns: Json }
      fn_proposer_accord_partie: {
        Args: { p_litige_id: string }
        Returns: Json
      }
      fn_proposer_cloture_litige: {
        Args: { p_litige_id: string }
        Returns: Json
      }
      fn_proposer_mission_soignant: {
        Args: {
          p_choix_contrat?: string
          p_mission_id: string
          p_soignant_id: string
        }
        Returns: Json
      }
      fn_purger_audit_ancien: { Args: never; Returns: number }
      fn_purger_demo: { Args: never; Returns: Json }
      fn_purger_gps_ancien: { Args: never; Returns: number }
      fn_recalculer_commissions_post_litige: { Args: never; Returns: Json }
      fn_recalculer_palier_commission: {
        Args: { p_etablissement_id: string }
        Returns: Json
      }
      fn_recalculer_score_fiabilite_soignant: {
        Args: { p_soignant_id: string }
        Returns: number
      }
      fn_recalculer_tous_paliers: { Args: never; Returns: number }
      fn_recalculer_tresorerie_bloquee: {
        Args: { p_litige_id: string }
        Returns: undefined
      }
      fn_rechercher_aide: {
        Args: { p_audience?: string; p_query?: string }
        Returns: Json
      }
      fn_rechercher_soignants_etab: {
        Args: {
          p_disponible_urgence?: boolean
          p_distance_max_km?: number
          p_documents_valides?: boolean
          p_experience_min?: number
          p_limit?: number
          p_note_min?: number
          p_offset?: number
          p_profession?: string
          p_recherche_texte?: string
          p_score_min?: number
          p_specialites?: string[]
          p_type_exercice?: string
          p_ville?: string
        }
        Returns: Json
      }
      fn_rechercher_utilisateurs: { Args: { p_query: string }; Returns: Json }
      fn_recommander_soignants: {
        Args: { p_limit?: number; p_mission_id: string }
        Returns: {
          distance_km: number
          est_favori: boolean
          id: string
          missions_etab: number
          missions_etablissement: number
          nb_evaluations: number
          nom: string
          note_moyenne: number
          prenom: string
          profession: Database["public"]["Enums"]["type_profession"]
          score_fiabilite: number
          score_matching: number
          tous_documents_valides: boolean
          type_exercice: string
        }[]
      }
      fn_rejeter_virement_admin: {
        Args: { p_facture_id: string }
        Returns: Json
      }
      fn_relancer_signatures_contrats: { Args: never; Returns: number }
      fn_repartition_heures_soignant: {
        Args: { p_periode_jours?: number }
        Returns: Json
      }
      fn_repondre_contestation_paiement: {
        Args: {
          p_action: string
          p_nouvelle_reference?: string
          p_paiement_id: string
          p_reponse?: string
        }
        Returns: Json
      }
      fn_repondre_litige: {
        Args: { p_litige_id: string; p_reponse: string }
        Returns: Json
      }
      fn_repondre_proposition: {
        Args: { p_accepter: boolean; p_candidature_id: string }
        Returns: Json
      }
      fn_resolve_template_contrat: {
        Args: {
          p_profession: string
          p_type_contrat: string
          p_type_etab: string
        }
        Returns: Json
      }
      fn_resoudre_litige: {
        Args: { p_litige_id: string; p_resolution: string; p_statut: string }
        Returns: Json
      }
      fn_retirer_exclusion: { Args: { p_exclu_id: string }; Returns: Json }
      fn_revoquer_api_key: { Args: { p_id: string }; Returns: Json }
      fn_revoquer_contrat_service: { Args: { p_motif: string }; Returns: Json }
      fn_revoquer_mandat_facturation: {
        Args: { p_motif?: string }
        Returns: Json
      }
      fn_rgpd_exporter_donnees_soignant: {
        Args: { p_soignant_id: string }
        Returns: Json
      }
      fn_rgpd_exporter_rate_limited: { Args: never; Returns: Json }
      fn_rgpd_purge_automatique_inactifs: {
        Args: never
        Returns: {
          action_effectuee: string
          derniere_activite: string
          soignant_purge_id: string
        }[]
      }
      fn_sanitiser_html: { Args: { p_html: string }; Returns: string }
      fn_sauvegarder_profil: { Args: { p_data: Json }; Returns: Json }
      fn_scanner_code_pointage: {
        Args: { p_code: string; p_metadata?: Json }
        Returns: Json
      }
      fn_score_etab_public: { Args: { p_etab_id: string }; Returns: Json }
      fn_set_user_role: {
        Args: { p_etablissement_id?: string; p_role: string; p_user_id: string }
        Returns: undefined
      }
      fn_signaler_notation: {
        Args: { p_motif?: string; p_notation_id: string }
        Returns: Json
      }
      fn_signer_attestation_sante: { Args: never; Returns: Json }
      fn_signer_cession_creance: {
        Args: {
          p_contenu_hash?: string
          p_facture_honoraire_id: string
          p_ip?: string
          p_user_agent?: string
          p_version: string
        }
        Returns: Json
      }
      fn_signer_contrat_etablissement: {
        Args: { p_contrat_id: string; p_signature_image: string }
        Returns: Json
      }
      fn_signer_contrat_otp: {
        Args: {
          p_contrat_id: string
          p_hash_document?: string
          p_otp_code: string
          p_signature_image?: string
        }
        Returns: Json
      }
      fn_signer_contrat_service: {
        Args: {
          p_contenu_hash: string
          p_ip: string
          p_signature_s3_key?: string
          p_user_agent: string
          p_version: string
        }
        Returns: Json
      }
      fn_signer_contrat_soignant: {
        Args: { p_contrat_id: string; p_signature_image: string }
        Returns: Json
      }
      fn_signer_mandat_facturation: {
        Args: {
          p_contenu_hash?: string
          p_ip?: string
          p_user_agent?: string
          p_version: string
        }
        Returns: Json
      }
      fn_sms_doit_envoyer: {
        Args: {
          p_destinataire_id: string
          p_fenetre_minutes?: number
          p_type: string
        }
        Returns: boolean
      }
      fn_soignant_compatible_mission: {
        Args: {
          p_accepte_non_specialises: boolean
          p_mission_profession: Database["public"]["Enums"]["type_profession"]
          p_mission_specialite: string
          p_soignant_profession: Database["public"]["Enums"]["type_profession"]
          p_soignant_specialite: string
        }
        Returns: boolean
      }
      fn_soignant_dpae_complet: {
        Args: { p_soignant_id: string }
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
          soignant_id: string
          telephone: string
          urgence_rayon_km: number
        }[]
      }
      fn_soumettre_reclamation: {
        Args: {
          p_categorie: string
          p_details: string
          p_mission_id?: string
          p_sujet: string
        }
        Returns: Json
      }
      fn_souscrire_prevoyance: {
        Args: { p_numero_contrat?: string; p_plan_id: string }
        Returns: Json
      }
      fn_stats_dashboard_etablissement: { Args: never; Returns: Json }
      fn_stats_etab_complements: { Args: never; Returns: Json }
      fn_stats_rh_etablissement: { Args: never; Returns: Json }
      fn_stripe_webhook_event_is_new: {
        Args: { p_event_id: string; p_event_type: string; p_payload?: Json }
        Returns: boolean
      }
      fn_suggestions_missions_pour_soignant: {
        Args: { p_limit?: number }
        Returns: Json
      }
      fn_supprimer_api_key: { Args: { p_id: string }; Returns: Json }
      fn_supprimer_compte_etablissement_rate_limited: {
        Args: never
        Returns: Json
      }
      fn_supprimer_compte_rate_limited: { Args: never; Returns: Json }
      fn_supprimer_filtre_sauvegarde: { Args: { p_id: string }; Returns: Json }
      fn_supprimer_mon_compte: { Args: never; Returns: Json }
      fn_supprimer_mon_compte_etablissement: { Args: never; Returns: Json }
      fn_terminer_mission: { Args: { p_mission_id: string }; Returns: Json }
      fn_toggle_favori_etablissement: {
        Args: { p_actif: boolean; p_etablissement_id: string }
        Returns: Json
      }
      fn_toggle_pool_urgence: {
        Args: { p_actif: boolean; p_creneaux?: Json; p_rayon_km?: number }
        Returns: Json
      }
      fn_toggle_pool_urgence_sms: { Args: { p_actif: boolean }; Returns: Json }
      fn_top_etablissements_soignant: {
        Args: { p_limit?: number }
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
      fn_traiter_reclamation_generale: {
        Args: { p_reclamation_id: string; p_reponse?: string; p_statut: string }
        Returns: Json
      }
      fn_trigger_regen_pdf_immediate: {
        Args: { p_facture_id: string }
        Returns: number
      }
      fn_types_exercice_autorises: {
        Args: { p_profession: string }
        Returns: string[]
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
      fn_uploader_contrat_plateforme: {
        Args: { p_contrat_url: string }
        Returns: Json
      }
      fn_uploader_contrat_travail_mission: {
        Args: {
          p_mission_id: string
          p_nom_fichier: string
          p_pdf_s3_key: string
          p_taille_octets: number
        }
        Returns: Json
      }
      fn_upsert_token_push: {
        Args: { p_plateforme?: string; p_token: string }
        Returns: undefined
      }
      fn_user_id_pour_etablissement: {
        Args: { p_etablissement_id: string }
        Returns: string
      }
      fn_valider_alerte_presence: {
        Args: { p_presence_id: string }
        Returns: Json
      }
      fn_valider_etablissement: {
        Args: { p_etablissement_id: string; p_motif?: string; p_statut: string }
        Returns: Json
      }
      fn_valider_presence: { Args: { p_presence_id: string }; Returns: Json }
      fn_valider_presences_lot: { Args: { p_ids: string[] }; Returns: Json }
      fn_verifier_api_key: {
        Args: { p_cle_api: string; p_cle_secret: string }
        Returns: Json
      }
      fn_verifier_coherence_documents: {
        Args: { p_soignant_id?: string }
        Returns: Json
      }
      fn_verifier_coherence_identite: {
        Args: { p_soignant_id: string }
        Returns: Json
      }
      fn_verifier_documents_expirants: { Args: never; Returns: number }
      fn_verifier_pre_facturation: {
        Args: {
          p_mission_id: string
          p_periode_debut?: string
          p_periode_fin?: string
        }
        Returns: Json
      }
      fn_verifier_rate_limit: {
        Args: {
          p_action: string
          p_cle: string
          p_fenetre_secondes?: number
          p_max_tentatives?: number
        }
        Returns: boolean
      }
      fn_verifier_skip_serie_onboarding: {
        Args: { p_envoi_id: string }
        Returns: Json
      }
      mon_etablissement_id: { Args: never; Returns: string }
      mon_role: { Args: never; Returns: string }
      next_avoir_commission_number: {
        Args: { p_etablissement_id: string }
        Returns: string
      }
      next_avoir_number: { Args: { p_soignant_id: string }; Returns: string }
      next_facture_complementaire_number: {
        Args: { p_etablissement_id: string }
        Returns: string
      }
      next_invoice_number: { Args: { p_soignant_id: string }; Returns: string }
      peut_exercer: {
        Args: {
          p_profession: string
          p_type_etablissement: string
          p_type_exercice: string
        }
        Returns: boolean
      }
      peut_exercer_liberal: {
        Args: { p_profession: string; p_type_etablissement: string }
        Returns: boolean
      }
    }
    Enums: {
      canal_notification: "EMAIL" | "SMS" | "PUSH" | "IN_APP"
      categorie_litige:
        | "PRESENCE"
        | "FINANCIER"
        | "CONDITIONS"
        | "COMPORTEMENT"
        | "AUTRE"
      credit_etab_motif: "PARRAINAGE"
      filtre_audience:
        | "SOIGNANT_RECHERCHE_MISSIONS"
        | "ETAB_RECHERCHE_SOIGNANTS"
      filtre_frequence_alerte: "IMMEDIATE" | "QUOTIDIENNE" | "HEBDOMADAIRE"
      mode_remboursement_avoir: "N_A" | "AUTO_STRIPE" | "VIREMENT_MANUEL"
      niveau_prevoyance_souhaite: "BRONZE" | "ARGENT" | "OR" | "INDIFFERENT"
      niveau_qualitatif: "BRONZE" | "ARGENT" | "OR" | "PLATINE"
      parrainage_etab_statut: "PENDING" | "VALIDATED" | "EXPIRED"
      sens_notation: "ETAB_VERS_SOIGNANT" | "SOIGNANT_VERS_ETAB"
      serie_email_statut: "PLANIFIE" | "ENVOYE" | "SKIPPED" | "ERREUR"
      serie_onboarding_etape: "J0" | "J1" | "J3" | "J7"
      serie_onboarding_type: "SOIGNANT_ONBOARDING" | "ETAB_ONBOARDING"
      statut_compte_soignant:
        | "ACTIF"
        | "SUSPENDU"
        | "SUPPRIME"
        | "EN_REVISION_ADMIN"
      statut_litige_facture:
        | "NORMAL"
        | "EN_ATTENTE_LITIGE"
        | "LITIGE_RESOLU_AJUSTE"
        | "LITIGE_RESOLU_CONFIRME"
      statut_mission:
        | "OUVERTE"
        | "ASSIGNEE"
        | "EN_COURS"
        | "TERMINEE"
        | "ANNULEE_PAR_ETABLISSEMENT"
        | "ANNULEE_PAR_SOIGNANT"
        | "ABSENCE"
        | "LITIGE"
        | "EXPIREE"
      statut_verification:
        | "EN_ATTENTE"
        | "VERIFIE"
        | "REJETE"
        | "EXPIRE"
        | "REVUE_MANUELLE_REQUISE"
        | "API_INDISPONIBLE"
      strategie_facturation: "FINALE_UNIQUE" | "HEBDO_ET_FINALE"
      type_contrat: "CDD" | "VACATION" | "LIBERAL" | "SALARIE"
      type_contrat_applique_enum: "LIBERAL" | "SALARIE"
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
      type_document_facture: "FACTURE" | "AVOIR"
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
        | "CABINET_MEDICAL"
        | "CABINET_DENTAIRE"
        | "CABINET_IDEL"
        | "CABINET_SAGE_FEMME"
        | "CABINET_KINE"
        | "CABINET_ORTHO"
        | "CABINET_ERGO"
        | "CABINET_PSYCHOMOT"
      type_evenement_notification:
        | "NOUVELLE_MISSION_MATCHANT_FILTRE"
        | "CANDIDATURE_RECUE"
        | "CANDIDATURE_ACCEPTEE"
        | "MISSION_ASSIGNEE"
        | "RAPPEL_J1_MISSION"
        | "POINTAGE_MANQUANT"
        | "FACTURE_EMISE"
        | "PAIEMENT_RECU"
        | "CONTRAT_TRAVAIL_DEPOSE"
        | "LITIGE_OUVERT"
        | "LITIGE_RESOLU"
        | "DOCUMENT_EXPIRANT"
        | "MANDAT_RE_SIGNATURE"
        | "SERIE_ONBOARDING"
        | "URGENCE"
        | "NOUVEAU_SOIGNANT_MATCHANT_FILTRE"
        | "FAVORI_NOUVELLE_MISSION"
        | "NOTATION_RAPPEL"
      type_litige:
        | "ABSENCE_SOIGNANT"
        | "DEPART_ANTICIPE"
        | "RETARD_IMPORTANT"
        | "DESACCORD_MONTANT_FACTURE"
        | "DESACCORD_HEURES_POINTAGE"
        | "NON_PAIEMENT"
        | "FRAIS_COMPLEMENTAIRES"
        | "CONDITIONS_MISSION_NON_RESPECTEES"
        | "SECURITE_DANGER"
        | "COMPORTEMENT_SOIGNANT"
        | "COMPORTEMENT_ETABLISSEMENT"
        | "AUTRE"
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
        | "DENTISTE"
        | "AUXILIAIRE_PUERICULTURE"
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
      canal_notification: ["EMAIL", "SMS", "PUSH", "IN_APP"],
      categorie_litige: [
        "PRESENCE",
        "FINANCIER",
        "CONDITIONS",
        "COMPORTEMENT",
        "AUTRE",
      ],
      credit_etab_motif: ["PARRAINAGE"],
      filtre_audience: [
        "SOIGNANT_RECHERCHE_MISSIONS",
        "ETAB_RECHERCHE_SOIGNANTS",
      ],
      filtre_frequence_alerte: ["IMMEDIATE", "QUOTIDIENNE", "HEBDOMADAIRE"],
      mode_remboursement_avoir: ["N_A", "AUTO_STRIPE", "VIREMENT_MANUEL"],
      niveau_prevoyance_souhaite: ["BRONZE", "ARGENT", "OR", "INDIFFERENT"],
      niveau_qualitatif: ["BRONZE", "ARGENT", "OR", "PLATINE"],
      parrainage_etab_statut: ["PENDING", "VALIDATED", "EXPIRED"],
      sens_notation: ["ETAB_VERS_SOIGNANT", "SOIGNANT_VERS_ETAB"],
      serie_email_statut: ["PLANIFIE", "ENVOYE", "SKIPPED", "ERREUR"],
      serie_onboarding_etape: ["J0", "J1", "J3", "J7"],
      serie_onboarding_type: ["SOIGNANT_ONBOARDING", "ETAB_ONBOARDING"],
      statut_compte_soignant: [
        "ACTIF",
        "SUSPENDU",
        "SUPPRIME",
        "EN_REVISION_ADMIN",
      ],
      statut_litige_facture: [
        "NORMAL",
        "EN_ATTENTE_LITIGE",
        "LITIGE_RESOLU_AJUSTE",
        "LITIGE_RESOLU_CONFIRME",
      ],
      statut_mission: [
        "OUVERTE",
        "ASSIGNEE",
        "EN_COURS",
        "TERMINEE",
        "ANNULEE_PAR_ETABLISSEMENT",
        "ANNULEE_PAR_SOIGNANT",
        "ABSENCE",
        "LITIGE",
        "EXPIREE",
      ],
      statut_verification: [
        "EN_ATTENTE",
        "VERIFIE",
        "REJETE",
        "EXPIRE",
        "REVUE_MANUELLE_REQUISE",
        "API_INDISPONIBLE",
      ],
      strategie_facturation: ["FINALE_UNIQUE", "HEBDO_ET_FINALE"],
      type_contrat: ["CDD", "VACATION", "LIBERAL", "SALARIE"],
      type_contrat_applique_enum: ["LIBERAL", "SALARIE"],
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
      type_document_facture: ["FACTURE", "AVOIR"],
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
        "CABINET_MEDICAL",
        "CABINET_DENTAIRE",
        "CABINET_IDEL",
        "CABINET_SAGE_FEMME",
        "CABINET_KINE",
        "CABINET_ORTHO",
        "CABINET_ERGO",
        "CABINET_PSYCHOMOT",
      ],
      type_evenement_notification: [
        "NOUVELLE_MISSION_MATCHANT_FILTRE",
        "CANDIDATURE_RECUE",
        "CANDIDATURE_ACCEPTEE",
        "MISSION_ASSIGNEE",
        "RAPPEL_J1_MISSION",
        "POINTAGE_MANQUANT",
        "FACTURE_EMISE",
        "PAIEMENT_RECU",
        "CONTRAT_TRAVAIL_DEPOSE",
        "LITIGE_OUVERT",
        "LITIGE_RESOLU",
        "DOCUMENT_EXPIRANT",
        "MANDAT_RE_SIGNATURE",
        "SERIE_ONBOARDING",
        "URGENCE",
        "NOUVEAU_SOIGNANT_MATCHANT_FILTRE",
        "FAVORI_NOUVELLE_MISSION",
        "NOTATION_RAPPEL",
      ],
      type_litige: [
        "ABSENCE_SOIGNANT",
        "DEPART_ANTICIPE",
        "RETARD_IMPORTANT",
        "DESACCORD_MONTANT_FACTURE",
        "DESACCORD_HEURES_POINTAGE",
        "NON_PAIEMENT",
        "FRAIS_COMPLEMENTAIRES",
        "CONDITIONS_MISSION_NON_RESPECTEES",
        "SECURITE_DANGER",
        "COMPORTEMENT_SOIGNANT",
        "COMPORTEMENT_ETABLISSEMENT",
        "AUTRE",
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
        "DENTISTE",
        "AUXILIAIRE_PUERICULTURE",
      ],
    },
  },
} as const
