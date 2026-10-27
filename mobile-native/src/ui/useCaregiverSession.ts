import { useSession } from '../session/SessionProvider';

/** Only mounted inside the authenticated caregiver navigator. */
export function useCaregiverSession() {
  const session = useSession();
  if (session.snapshot.context?.kind !== 'soignant') throw new Error('Écran réservé au compte soignant connecté.');
  return { ...session, context: session.snapshot.context };
}
