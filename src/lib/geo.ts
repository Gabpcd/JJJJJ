/**
 * Calcule la distance en km entre deux points GPS (formule de Haversine).
 * Retourne null si des coordonnées sont manquantes.
 */
export function calculerDistanceKm(
  lat1: number | null, lng1: number | null,
  lat2: number | null, lng2: number | null
): number | null {
  if (lat1 == null || lng1 == null || lat2 == null || lng2 == null) return null;

  const R = 6371;
  const dLat = (lat2 - lat1) * Math.PI / 180;
  const dLng = (lng2 - lng1) * Math.PI / 180;
  const a =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos(lat1 * Math.PI / 180) * Math.cos(lat2 * Math.PI / 180) *
    Math.sin(dLng / 2) * Math.sin(dLng / 2);
  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
  return Math.round(R * c * 10) / 10;
}

/**
 * Formate une distance pour l'affichage.
 */
export function formaterDistance(km: number | null): string {
  if (km === null) return 'Distance inconnue';
  if (km < 1) return `${Math.round(km * 1000)}m`;
  return `${km} km`;
}
