import type { CreneauPointage } from '@/lib/disponibilite-pointage';

type MissionHistorique = {
  id: string;
  etablissement_id?: string | null;
  debut_le?: string | null;
  fin_le?: string | null;
  [cle: string]: unknown;
};

/**
 * Construit une ligne d'historique depuis les segments EFFECTIF canoniques
 * lorsqu'une ancienne mission ne possède pas de ligne `presences` legacy.
 * Cette ligne est uniquement un modèle d'affichage : elle ne prétend pas être
 * une présence validable et ne fournit donc jamais un faux identifiant métier.
 */
export function construireHistoriqueEffectifsSansPresence({
  missions,
  presences,
  creneauxParMission,
  etablissements,
  soignantId,
}: {
  missions: MissionHistorique[];
  presences: Array<{ mission_id?: string | null }>;
  creneauxParMission: Record<string, CreneauPointage[]>;
  etablissements: Record<string, unknown>;
  soignantId: string;
}) {
  const missionsAvecPresence = new Set(
    presences.map((presence) => presence.mission_id).filter(Boolean),
  );

  return missions.flatMap((mission) => {
    if (missionsAvecPresence.has(mission.id)) return [];
    const creneaux = creneauxParMission[mission.id] ?? [];
    const effectifs = creneaux
      .filter((creneau) => (
        creneau.type_creneau === 'EFFECTIF'
        && !creneau.est_pause
        && Boolean(creneau.fin)
      ))
      .sort((a, b) => new Date(a.debut).getTime() - new Date(b.debut).getTime());
    if (effectifs.length === 0) return [];

    return [{
      id: `effectifs-mission-${mission.id}`,
      mission_id: mission.id,
      soignant_id: soignantId,
      pointage_arrivee_le: effectifs[0].debut,
      pointage_depart_le: effectifs.at(-1)?.fin ?? null,
      valide_par_etablissement: false,
      valide_le: null,
      methode_pointage_arrivee: null,
      methode_pointage_depart: null,
      origine_effectifs_sans_presence: true,
      missions: {
        ...mission,
        etablissements: mission.etablissement_id
          ? etablissements[mission.etablissement_id] ?? null
          : null,
        creneaux,
      },
    }];
  });
}
