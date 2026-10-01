import type { Database } from '@/integrations/supabase/types';

type SoignantRow = Database['public']['Tables']['soignants']['Row'];

/** Le RPC peut répondre HTTP 200 avec { error }. Ne jamais transformer cette
 * réponse, ni des champs incompatibles avec le formulaire, en profil vide. */
export function validerProfilSoignant(data: unknown, userId: string): SoignantRow & { specialites: string[] } {
  if (!data || typeof data !== 'object' || Array.isArray(data)) throw new Error('PROFIL_INVALIDE');
  const row = data as Record<string, unknown>;
  if (row.id !== userId || 'error' in row
    || ['prenom', 'nom', 'email', 'profession'].some(key => !Object.prototype.hasOwnProperty.call(row, key))) throw new Error('PROFIL_INVALIDE');
  const textes = ['email', 'prenom', 'nom', 'profession', 'specialite_medicale', 'specialite_medicale_declaree',
    'specialite_source', 'rpps_verifie_le', 'statut_liberal', 'type_exercice', 'telephone', 'date_naissance',
    'numero_rpps', 'bio', 'avatar_url', 'ville_recherche', 'types_contrat_acceptes', 'type_contrat'];
  const nombres = ['heures_cumulees', 'adresse_lat', 'adresse_lng', 'rayon_deplacement_km',
    'annees_experience', 'taux_horaire_minimum', 'urgence_rayon_km'];
  const booleens = ['specialite_verifiee', 'rpps_verifie', 'attestation_cumul_activite',
    'consentement_gps', 'disponible_urgence', 'tous_documents_valides'];
  if (textes.some(key => row[key] != null && typeof row[key] !== 'string')
    || nombres.some(key => row[key] != null && (typeof row[key] !== 'number' || !Number.isFinite(row[key])))
    || booleens.some(key => row[key] != null && typeof row[key] !== 'boolean')) throw new Error('PROFIL_INVALIDE');
  const brut = row.specialites;
  const specialites: unknown = brut == null || brut === '' ? [] : typeof brut === 'string' ? JSON.parse(brut) : brut;
  if (!Array.isArray(specialites) || specialites.some(value => typeof value !== 'string')) throw new Error('PROFIL_INVALIDE');
  return { ...row, specialites } as SoignantRow & { specialites: string[] };
}
