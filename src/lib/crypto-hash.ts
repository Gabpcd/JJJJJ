/**
 * Calcule le hash SHA-256 hexadécimal d'une chaîne UTF-8 via Web Crypto API.
 *
 * Utilisé pour générer une empreinte du contrat affiché à l'utilisateur au
 * moment de la signature OTP (preuve d'intégrité art. 1366 Code civil) :
 * si le document change entre l'affichage et la signature, le hash diffère
 * et la signature peut être contestée.
 *
 * Web Crypto API est disponible nativement dans tous les navigateurs modernes
 * et n'ajoute aucune dépendance.
 */
export async function sha256Hex(input: string): Promise<string> {
  const data = new TextEncoder().encode(input);
  const buffer = await crypto.subtle.digest('SHA-256', data);
  return Array.from(new Uint8Array(buffer))
    .map(b => b.toString(16).padStart(2, '0'))
    .join('');
}
