import { useQuery } from '@tanstack/react-query';
import { supabase } from '@/integrations/supabase/client';
import { chargerMissionsInscription, missionCorrespondProfessionInscription } from '@/lib/explorationInscription';
import { enrichirEtablissements } from '@/lib/etablissements';
import { getMissionsCompatiblesFilter } from '@/lib/profession-hierarchy';
import { filtrerMissionsPlaywright } from '@/lib/donnees-test';
import { chargerCreneauxMissionsPagines } from '@/lib/mission-creneaux-pagines';
import { associerCreneauxAuxMissions } from '@/components/planning/planning-candidat';
import type { ParcoursInscription } from '@/lib/inscriptionProgressive';

export interface ProfilExploration {
  profession: string;
  adresse_lat: number | null;
  adresse_lng: number | null;
  rayon_deplacement_km: number;
  tous_documents_valides: boolean;
  type_contrat: string | null;
  types_contrat_acceptes: string | null;
  type_exercice?: string | null;
  taux_horaire_minimum?: number | null;
}

interface Options {
  userId?: string;
  email?: string;
  parcours?: ParcoursInscription | null;
  roleResolved: boolean;
  enabled: boolean;
  preferencesInitialisees: boolean;
  profession: string;
  tauxMin: number;
  urgentesOnly: boolean;
  etablissementId: string | null;
}

const MISSIONS_VIDES: any[] = [];

export async function chargerMissionsExploration(
  options: Options,
  soignant: ProfilExploration | null,
  signal: AbortSignal,
) {
  const { parcours, profession, tauxMin, urgentesOnly, etablissementId } = options;
  if (parcours) {
    const offres = await chargerMissionsInscription(undefined, signal);
    const professionCompte = String(parcours.donnees.profession || '');
    return offres.filter(m => missionCorrespondProfessionInscription(m.profession_requise, profession, professionCompte)
      && (!tauxMin || Number(m.taux_horaire_base) >= tauxMin)
      && (!urgentesOnly || m.est_urgente)
      && (!etablissementId || m.etablissement_id === etablissementId));
  }

  let query = supabase.from('missions').select(`
    id, intitule, description, service, profession_requise,
    specialite_medicale_requise, accepte_non_specialises,
    debut_le, fin_le, duree_heures, nb_creneaux, taux_horaire_base, taux_rist_plafonne, rist_plafond_applique,
    total_brut, net_a_payer, est_urgente, niveau_urgence, statut,
    soignant_assigne_id, cree_le, etablissement_id, type_contrat_recherche, boostee_le, mode_remuneration, retrocession_pct
  `)
    .eq('statut', 'OUVERTE')
    .gte('debut_le', new Date().toISOString())
    .order('boostee_le', { ascending: false, nullsFirst: false })
    .order('est_urgente', { ascending: false })
    .order('debut_le', { ascending: true })
    .limit(500);

  const professionFiltre = profession || soignant?.profession;
  if (professionFiltre) {
    const orFiltre = !profession ? getMissionsCompatiblesFilter(professionFiltre) : null;
    query = orFiltre ? query.or(orFiltre) : query.eq('profession_requise', professionFiltre as any);
  }
  if (tauxMin > 0) query = query.gte('taux_horaire_base', tauxMin);
  if (urgentesOnly) query = query.eq('est_urgente', true);
  if (etablissementId) query = query.eq('etablissement_id', etablissementId);

  const { data, error } = await query.abortSignal(signal);
  if (error) throw error;
  const missions = filtrerMissionsPlaywright(data ?? [], options.email);
  // Ces deux enrichissements dépendent de la liste, mais pas l'un de l'autre.
  const [creneaux, enriched] = await Promise.all([
    chargerCreneauxMissionsPagines(missions.map(m => m.id), {
      typeCreneau: 'PREVISIONNEL', exclurePauses: true, signal,
    }),
    enrichirEtablissements(missions),
  ]);
  return associerCreneauxAuxMissions(enriched, creneaux, false);
}

export function useExplorationMissions(options: Options) {
  const { userId, parcours, roleResolved, enabled, profession, tauxMin, urgentesOnly, etablissementId } = options;
  const profilQuery = useQuery({
    queryKey: ['explorer-profil', userId],
    enabled: !!userId && roleResolved && !parcours,
    staleTime: 60_000,
    queryFn: async ({ signal }) => {
      const { data, error } = await supabase.from('soignants')
        .select('profession, adresse_lat, adresse_lng, rayon_deplacement_km, tous_documents_valides, type_contrat, types_contrat_acceptes, type_exercice, taux_horaire_minimum')
        .eq('id', userId!).abortSignal(signal).maybeSingle();
      if (error) throw error;
      return data as ProfilExploration | null;
    },
  });
  const soignant = parcours ? null : profilQuery.data ?? null;
  const profilPret = !!parcours || profilQuery.isSuccess;
  const missionsQuery = useQuery({
    queryKey: [
      'explorer-missions', userId, parcours ? 'inscription' : 'profil',
      String(parcours?.donnees.profession || ''), soignant?.profession ?? '',
      profession, tauxMin, urgentesOnly, etablissementId,
    ],
    enabled: !!userId && roleResolved && profilPret && enabled
      && (!!parcours || !soignant || options.preferencesInitialisees),
    staleTime: 30_000,
    queryFn: ({ signal }) => chargerMissionsExploration(options, soignant, signal),
  });
  const liberal = soignant?.type_exercice === 'LIBERAL' || soignant?.type_exercice === 'MIXTE';
  const rcpQuery = useQuery({
    queryKey: ['explorer-rcp', userId],
    enabled: !!userId && roleResolved && !parcours && liberal,
    staleTime: 60_000,
    queryFn: async ({ signal }) => {
      const { data, error } = await supabase.from('documents_soignants')
        .select('statut_verification, valide_jusqua').eq('soignant_id', userId!)
        .eq('type_document', 'RCP_ASSURANCE').is('supprime_le', null)
        .order('televerse_le', { ascending: false })
        .limit(1).abortSignal(signal);
      if (error) throw error;
      return data?.[0] ?? null;
    },
  });
  const rcp = rcpQuery.data;
  const rcpExpiree = liberal && rcpQuery.isSuccess && (!rcp
    || rcp.statut_verification === 'REJETE' || rcp.statut_verification === 'EXPIRE'
    || !!(rcp.valide_jusqua && new Date(rcp.valide_jusqua) < new Date()));
  const rcpExpireLe = liberal && !rcpExpiree && rcp?.valide_jusqua
    && (new Date(rcp.valide_jusqua).getTime() - Date.now()) / 86_400_000 <= 30
    ? rcp.valide_jusqua : null;

  return {
    soignant, profilPret,
    missions: missionsQuery.data ?? MISSIONS_VIDES,
    loading: !roleResolved || (!profilPret && !profilQuery.isError) || (missionsQuery.isPending && !profilQuery.isError),
    actualisation: missionsQuery.isFetching && !missionsQuery.isPending,
    erreurChargement: profilQuery.isError || missionsQuery.isError,
    rcpExpiree, rcpExpireLe,
    recharger: async () => {
      if (profilQuery.isError) return profilQuery.refetch();
      return missionsQuery.refetch();
    },
  };
}
