/** Only the existing mission detail route may survive an unauthenticated visit.
 * Query strings, fragments, external origins and other actions are excluded.
 * The route and database still decide which mission this account can read.
 */
export function retourMissionNotification(lien: unknown): string | null {
  return typeof lien === 'string'
    && lien === lien.trim()
    && /^\/etablissement\/missions\/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(lien)
    ? lien : null;
}

export const OUVERTURE_NOTIFICATION = 'jolene:notification-opened';
