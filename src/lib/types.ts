export interface Soignant {
  id: string;
  prenom: string;
  nom: string;
  email: string;
  telephone: string | null;
  date_naissance: string | null;
  profession: string;
  numero_rpps: string | null;
  numero_adeli: string | null;
  type_contrat: string;
  score_fiabilite: number;
  total_missions_terminees: number;
  total_missions_annulees: number;
  total_retards_pointage: number;
  total_absences: number;
  heures_cumulees: number;
  eligible_conversion_3200h: boolean;
  prevoyance_inscrit: boolean;
  prevoyance_fournisseur: string | null;
  adresse_lat: number | null;
  adresse_lng: number | null;
  rayon_deplacement_km: number;
  tous_documents_valides: boolean;
  identite_verifiee: boolean;
  diplome_verifie: boolean;
  rpps_verifie: boolean;
  statut_verification_aria: string;
  cree_le: string;
  modifie_le: string;
  derniere_activite_le: string | null;
}

export interface Etablissement {
  id: string;
  nom: string;
  siret: string;
  finess: string | null;
  type: string;
  groupe_sante_id: string | null;
  adresse_rue: string | null;
  adresse_ville: string | null;
  adresse_code_postal: string | null;
  adresse_departement: string | null;
  adresse_lat: number | null;
  adresse_lng: number | null;
  email_contact: string | null;
  telephone_contact: string | null;
  taux_majoration_nuit_pourcent: number | null;
  taux_majoration_dimanche_pourcent: number | null;
  taux_majoration_ferie_pourcent: number | null;
  groupes_sante?: { nom: string } | null;
  cree_le: string;
  modifie_le: string;
}

export interface Mission {
  id: string;
  etablissement_id: string;
  intitule: string;
  description: string | null;
  profession_requise: string;
  service: string | null;
  debut_le: string;
  fin_le: string;
  duree_heures: number | null;
  taux_horaire_base: number;
  est_urgente: boolean;
  niveau_urgence: number;
  statut: string;
  soignant_assigne_id: string | null;
  soignants?: { prenom: string; nom: string } | null;
  etablissements?: { nom: string; adresse_ville: string | null } | null;
  cree_le: string;
  modifie_le: string;
}

export type UserRole = 'SOIGNANT' | 'ADMIN_ETABLISSEMENT' | 'ADMIN_GROUPE' | 'ADMIN';
