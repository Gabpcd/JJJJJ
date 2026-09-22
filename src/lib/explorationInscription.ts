import { getMissionMatchInfo } from '@/lib/profession-hierarchy';
import { supabase } from '@/integrations/supabase/client';
import { associerCreneauxAuxMissions } from '@/components/planning/planning-candidat';
import { enregistrerParcours } from '@/lib/inscriptionProgressive';

/** Même offre et même planning dans Liste, Swipe et Détail, sans profil métier. */
export async function chargerMissionsInscription(missionId?: string, signal?: AbortSignal) {
  const offres: any[] = [];
  const taillePage = 100;
  // La pagination précède les filtres de l'interface : aucune profession ne
  // disparaît parce que les premières offres concernent d'autres métiers.
  for (let offset = 0; ; offset += taillePage) {
    let query = supabase.rpc('fn_explorer_missions_inscription' as any, {
      p_mission_id: missionId ?? null, p_offset: offset, p_limit: taillePage,
    });
    if (signal) query = query.abortSignal(signal);
    const { data, error } = await query;
    if (error) throw error;
    const page = (data ?? []) as any[];
    offres.push(...page);
    if (missionId || page.length < taillePage) break;
  }
  return associerCreneauxAuxMissions(offres, offres.flatMap(m => m.creneaux ?? []), false)
    .map(m => ({ ...m, mission_id: m.id, etablissement_nom: m.etablissements?.nom,
      etablissement_ville: m.etablissements?.adresse_ville,
      etablissement_code_postal: m.etablissements?.adresse_code_postal,
      etablissement_logo_url: m.etablissements?.logo_url,
      distance_km: null, score: 0, breakdown: {} }));
}

/** Mémorise l'intention sans envoyer de candidature avant confirmation finale. */
export async function preparerCandidatureInscription(missionId: string) {
  await enregistrerParcours({ missionChoisie: missionId });
  return '/inscription/completer';
}

export async function chargerFavorisInscription() {
  const { chargerParcours } = await import('@/lib/inscriptionProgressive');
  const parcours = await chargerParcours();
  return Array.isArray(parcours?.donnees.missionsSauvegardees)
    ? parcours.donnees.missionsSauvegardees.filter((id): id is string => typeof id === 'string') : [];
}

export async function sauvegarderFavoriInscription(missionId: string, actif: boolean) {
  const { error } = await supabase.rpc('fn_modifier_favori_inscription' as any, {
    p_mission_id: missionId, p_actif: actif,
  });
  if (error) throw error;
}

export async function chargerOffresSauvegardeesInscription() {
  const ids = new Set(await chargerFavorisInscription());
  if (ids.size === 0) return [];
  return (await chargerMissionsInscription()).filter(m => ids.has(m.id));
}

export function missionCorrespondProfessionInscription(requise: string, selection: string, compte: string) {
  if (selection) return requise === selection;
  return !compte || requise === compte
    || getMissionMatchInfo(compte, null, requise, null, true)?.type === 'HIERARCHIE_NATURELLE';
}
