import { Smartphone, MapPin, Clock, Plane } from 'lucide-react';

interface Props {
  arrivee_mock_detected?: boolean | null;
  depart_mock_detected?: boolean | null;
  alerte_teleportation?: boolean | null;
  perimetre_gps_valide?: boolean | null;
  coherence_incidents?: Array<string> | Record<string, any> | null;
}

const CODES_COHERENCE: Record<string, string> = {
  ARRIVEE_TROP_PRECOCE: 'Arrivée >30 min avant début',
  ARRIVEE_APRES_FIN: 'Arrivée après fin prévue',
  DEPART_AVANT_ARRIVEE: 'Départ avant arrivée',
  DEPART_TROP_PRECOCE: 'Départ très tôt vs fin prévue',
  DUREE_TROP_COURTE: 'Durée pointée < 30 min',
  DUREE_TROP_LONGUE: 'Durée pointée > 24h',
  ARRIVEE_SANS_DEPART_24H: 'Arrivée sans départ depuis 24h',
};

/**
 * Badges visuels anti-triche Sprint 4.5 affichés à côté d'une présence.
 *
 * Sprint 6 PR 7 — Fix P1-7 audit Sprint 5.
 *
 * 4 types de signaux :
 * - Mock GPS détecté (arrivée OU départ)
 * - Téléportation détectée (cron toutes les 15 min, Haversine > 200 km/h)
 * - Périmètre GPS invalide (scan loin de l'étab)
 * - Cohérence temporelle (7 codes incidents jsonb)
 */
export function BadgesAntiTrichePresence({
  arrivee_mock_detected,
  depart_mock_detected,
  alerte_teleportation,
  perimetre_gps_valide,
  coherence_incidents,
}: Props) {
  const mockGps = arrivee_mock_detected || depart_mock_detected;
  const incidentsArray = Array.isArray(coherence_incidents)
    ? (coherence_incidents as string[])
    : coherence_incidents && typeof coherence_incidents === 'object'
      ? Object.keys(coherence_incidents)
      : [];

  const aucunSignal =
    !mockGps && !alerte_teleportation && perimetre_gps_valide !== false && incidentsArray.length === 0;
  if (aucunSignal) return null;

  return (
    <div className="flex items-center gap-1.5 flex-wrap" aria-label="Alertes anti-triche">
      {mockGps && (
        <span
          className="inline-flex items-center gap-1 text-[10px] px-1.5 py-0.5 rounded-full bg-destructive/15 text-destructive font-medium"
          title="GPS suspect (accuracy=0, coords rondes, vitesse aberrante)"
        >
          <Smartphone className="h-2.5 w-2.5" /> Mock GPS
        </span>
      )}
      {alerte_teleportation && (
        <span
          className="inline-flex items-center gap-1 text-[10px] px-1.5 py-0.5 rounded-full bg-destructive/15 text-destructive font-medium"
          title="Déplacement > 200 km/h entre deux pointages"
        >
          <Plane className="h-2.5 w-2.5" /> Téléportation
        </span>
      )}
      {perimetre_gps_valide === false && (
        <span
          className="inline-flex items-center gap-1 text-[10px] px-1.5 py-0.5 rounded-full bg-warning/15 text-warning font-medium"
          title="Pointage hors périmètre GPS configuré"
        >
          <MapPin className="h-2.5 w-2.5" /> GPS hors zone
        </span>
      )}
      {incidentsArray.map((code) => (
        <span
          key={code}
          className="inline-flex items-center gap-1 text-[10px] px-1.5 py-0.5 rounded-full bg-warning/15 text-warning font-medium"
          title={CODES_COHERENCE[code] || code}
        >
          <Clock className="h-2.5 w-2.5" /> {CODES_COHERENCE[code] || code}
        </span>
      ))}
    </div>
  );
}
