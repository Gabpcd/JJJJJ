/** Destination de navigation seulement ; aucun rôle, jeton Auth ou droit métier. */
const UUID = '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}';
const MISSION = new RegExp(`^/etablissement/missions/(${UUID})$`, 'i');
const LEGACY_STATE = /^[A-Za-z0-9_-]{43}$/;
const SIGNED_STATE = new RegExp(`^v1\\.([A-Za-z0-9_-]{43})\\.(${UUID})\\.([0-9]{10})\\.([A-Za-z0-9_-]{43})$`);
const PURPOSE = 'jolene.psc.navigation.v1\n';

export function retourMissionPsc(value: unknown): string | null {
  return typeof value === 'string' && MISSION.test(value) ? value.toLowerCase() : null;
}

function base64url(bytes: Uint8Array): string {
  return btoa(String.fromCharCode(...bytes)).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

async function cleEtat(secret: string): Promise<CryptoKey> {
  return await crypto.subtle.importKey('raw', new TextEncoder().encode(secret),
    { name: 'HMAC', hash: 'SHA-256' }, false, ['sign', 'verify']);
}

export async function signerEtatPsc(
  alea: string, retour: string, secret: string, maintenant = Math.floor(Date.now() / 1000),
): Promise<string> {
  const destination = retourMissionPsc(retour);
  if (!LEGACY_STATE.test(alea) || !destination || !secret || !Number.isSafeInteger(maintenant)) {
    throw new Error('PSC_RETURN_STATE_INVALID');
  }
  // Même durée maximale que la session PSC existante : quinze minutes.
  const expire = maintenant + 15 * 60;
  const mission = destination.slice('/etablissement/missions/'.length);
  const contenu = `v1.${alea}.${mission}.${expire}`;
  const signature = await crypto.subtle.sign('HMAC', await cleEtat(secret), new TextEncoder().encode(PURPOSE + contenu));
  return `${contenu}.${base64url(new Uint8Array(signature))}`;
}

export async function verifierEtatPsc(
  state: unknown, secret: string | undefined, maintenant = Math.floor(Date.now() / 1000),
): Promise<{ state: string; retour: string | null } | null> {
  if (typeof state !== 'string' || state.length > 180) return null;
  // Les sessions déjà ouvertes gardent le comportement historique, sans retour.
  if (LEGACY_STATE.test(state)) return { state, retour: null };
  const match = SIGNED_STATE.exec(state);
  if (!match || !secret || !Number.isSafeInteger(maintenant) || Number(match[3]) <= maintenant) return null;
  const contenu = state.slice(0, state.lastIndexOf('.'));
  try {
    const signature = Uint8Array.from(atob(match[4].replace(/-/g, '+').replace(/_/g, '/') + '='), c => c.charCodeAt(0));
    if (base64url(signature) !== match[4]) return null;
    const valide = await crypto.subtle.verify('HMAC', await cleEtat(secret), signature, new TextEncoder().encode(PURPOSE + contenu));
    if (!valide) return null;
    return { state, retour: `/etablissement/missions/${match[2]}` };
  } catch { return null; }
}
