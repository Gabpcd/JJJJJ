// Reverse-geocoding : convertir des coordonnées GPS en adresse lisible.
// Utilise l'API Adresse de l'État (data.gouv.fr), gratuite et sans clé, pour la
// France. Permet d'afficher « 12 rue de la Paix, 75002 Paris » au lieu de
// « 48.8698, 2.3311 » quand l'utilisateur autorise sa géolocalisation.

export interface AdresseGeocodee {
  label: string;        // adresse complète lisible
  rue: string | null;   // numéro + voie
  ville: string | null;
  codePostal: string | null;
}

/**
 * Convertit lat/lng en adresse lisible. Retourne null si introuvable / réseau KO.
 */
export async function reverseGeocode(lat: number, lng: number): Promise<AdresseGeocodee | null> {
  try {
    const url = `https://api-adresse.data.gouv.fr/reverse/?lon=${encodeURIComponent(lng)}&lat=${encodeURIComponent(lat)}`;
    const res = await fetch(url, { headers: { Accept: 'application/json' } });
    if (!res.ok) return null;
    const data = await res.json();
    const f = data?.features?.[0];
    if (!f) return null;
    const p = f.properties || {};
    return {
      label: p.label || '',
      rue: p.name || null,
      ville: p.city || null,
      codePostal: p.postcode || null,
    };
  } catch {
    return null;
  }
}
