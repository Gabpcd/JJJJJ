import { supabase } from '@/integrations/supabase/client';

export interface CreneauMissionCharge {
  id: string;
  mission_id: string;
  debut: string;
  fin: string | null;
  est_pause: boolean;
  type_creneau: string;
}

interface ChargerCreneauxOptions {
  typeCreneau?: 'PREVISIONNEL' | 'EFFECTIF';
  exclurePauses?: boolean;
  signal?: AbortSignal;
  tailleLotIds?: number;
  taillePage?: number;
}

const TAILLE_LOT_IDS = 50;
const TAILLE_PAGE = 500;

function lots<T>(valeurs: T[], taille: number): T[][] {
  return Array.from(
    { length: Math.ceil(valeurs.length / taille) },
    (_, index) => valeurs.slice(index * taille, (index + 1) * taille),
  );
}

/**
 * Charge tous les créneaux des missions demandées, même lorsque la limite
 * PostgREST est inférieure à la plage demandée. Le `count: exact` permet de
 * détecter une réponse tronquée : toute page absente ou incohérente échoue
 * fermé au lieu de transformer un planning partiel en planning contractuel.
 */
export async function chargerCreneauxMissionsPagines(
  missionIds: Array<string | null | undefined>,
  options: ChargerCreneauxOptions = {},
): Promise<CreneauMissionCharge[]> {
  const ids = [...new Set(missionIds.filter((id): id is string => Boolean(id)))];
  if (ids.length === 0) return [];

  const tailleLotIds = Math.max(1, options.tailleLotIds ?? TAILLE_LOT_IDS);
  const taillePage = Math.max(1, options.taillePage ?? TAILLE_PAGE);
  const resultat = new Map<string, CreneauMissionCharge>();

  for (const lotIds of lots(ids, tailleLotIds)) {
    const resultatLot = new Map<string, CreneauMissionCharge>();
    let offset = 0;
    let totalAttendu: number | null = null;

    while (totalAttendu === null || offset < totalAttendu) {
      if (options.signal?.aborted) throw new DOMException('Chargement annulé', 'AbortError');

      let requete = supabase
        .from('mission_creneaux')
        .select('id, mission_id, debut, fin, est_pause, type_creneau', { count: 'exact' })
        .in('mission_id', lotIds);

      if (options.typeCreneau) {
        requete = requete.eq('type_creneau', options.typeCreneau);
      }
      if (options.exclurePauses) {
        requete = requete.eq('est_pause', false);
      }

      requete = requete
        .order('mission_id', { ascending: true })
        .order('debut', { ascending: true })
        .order('id', { ascending: true })
        .range(offset, offset + taillePage - 1);

      if (options.signal) requete = requete.abortSignal(options.signal);

      const { data, error, count } = await requete;
      if (error) throw error;
      if (count === null) {
        throw new Error('Le nombre total de créneaux n’a pas pu être vérifié.');
      }
      if (totalAttendu !== null && count !== totalAttendu) {
        throw new Error('Le planning a changé pendant son chargement. Rechargez la page.');
      }
      totalAttendu = count;

      const page = (data ?? []) as CreneauMissionCharge[];
      if (page.length === 0 && offset < totalAttendu) {
        throw new Error('Le planning détaillé est incomplet. Rechargez la page.');
      }

      const avant = resultatLot.size;
      for (const creneau of page) resultatLot.set(creneau.id, creneau);
      if (page.length > 0 && resultatLot.size === avant && offset < totalAttendu) {
        throw new Error('Le planning détaillé contient des pages dupliquées.');
      }
      offset += page.length;
    }

    if (resultatLot.size !== totalAttendu) {
      throw new Error('Le planning détaillé contient des créneaux manquants ou dupliqués.');
    }
    for (const [id, creneau] of resultatLot) resultat.set(id, creneau);
  }

  return [...resultat.values()];
}
