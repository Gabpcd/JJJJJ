import { supabase } from '@/integrations/supabase/client';

export interface EtablissementSafe {
  id: string;
  nom: string;
  adresse_rue: string;
  adresse_code_postal: string;
  adresse_ville: string;
  adresse_departement: string | null;
  adresse_lat: number | null;
  adresse_lng: number | null;
  type: string;
  finess: string | null;
  taux_majoration_nuit_pourcent: number | null;
  taux_majoration_dimanche_pourcent: number | null;
  taux_majoration_ferie_pourcent: number | null;
  couleur_theme?: string | null;
  logo_url?: string | null;
  /** 7c — capacité « ⚡ Paiement rapide » de l'étab (feature flag + SEPA actif,
   *  calculée serveur). Le badge exige EN PLUS une mission LIBERAL. */
  paiement_rapide?: boolean;
  /** 7c — jour de paie habituel (1-31) pour la prévisibilité salariée. */
  jour_paie_habituel?: number | null;
}

/**
 * Fetches safe (non-sensitive) establishment data for a list of IDs
 * via the security-definer RPC fn_etablissements_safe.
 * Returns a map of id → establishment data.
 */
export async function fetchEtablissementsSafe(ids: string[]): Promise<Record<string, EtablissementSafe>> {
  if (!ids.length) return {};
  const uniqueIds = [...new Set(ids)];
  const { data } = await supabase.rpc('fn_etablissements_safe', { p_ids: uniqueIds });
  const map: Record<string, EtablissementSafe> = {};
  (data || []).forEach((e: any) => { map[e.id] = e; });
  return map;
}

/**
 * Enriches an array of missions (or any objects with etablissement_id)
 * by adding an `etablissements` property with safe data.
 */
export async function enrichirEtablissements<T extends { etablissement_id: string }>(
  items: T[]
): Promise<(T & { etablissements: EtablissementSafe | null })[]> {
  const ids = items.map(i => i.etablissement_id).filter(Boolean);
  const map = await fetchEtablissementsSafe(ids);
  return items.map(item => ({
    ...item,
    etablissements: map[item.etablissement_id] || null,
  }));
}
