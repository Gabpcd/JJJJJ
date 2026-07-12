import { isNative } from './platform';
import { supabase } from '@/integrations/supabase/client';
import { logger } from './logger';
import { normaliserLienJolene } from './nativeLinks';
import { memoriserTokenPushAppareil } from './pushDeviceToken';

type RoleApp = 'SOIGNANT' | 'ADMIN_ETABLISSEMENT' | 'ETABLISSEMENT' | 'ADMIN_PLATEFORME' | 'ADMIN' | 'ADMIN_GROUPE' | null;

let userInitialise: string | null = null;
let initialisationEnCours: Promise<void> | null = null;
let userInitialisationEnCours: string | null = null;
let generationPush = 0;

function valeurTexte(value: unknown): string | null {
  return typeof value === 'string' && value.trim() ? value.trim() : null;
}

function segment(value: unknown): string | null {
  const text = valeurTexte(value);
  return text ? encodeURIComponent(text) : null;
}

async function enregistrerToken(token: string, userIdAttendu: string): Promise<void> {
  const { data } = await supabase.auth.getSession();
  if (data.session?.user.id !== userIdAttendu) {
    throw new Error('Session changée pendant l’enregistrement du token push');
  }
  const { Capacitor } = await import('@capacitor/core');
  const plateforme = Capacitor.getPlatform() === 'ios' ? 'IOS' : 'ANDROID';
  const { error } = await supabase.rpc('fn_upsert_token_push' as any, {
    p_token: token,
    p_plateforme: plateforme,
  });
  if (error) throw error;
  memoriserTokenPushAppareil(token);
}

async function roleCourant(): Promise<RoleApp> {
  let delai: number | undefined;
  try {
    const resultat = await Promise.race([
      supabase.rpc('fn_get_my_role' as any),
      new Promise<null>((resolve) => {
        delai = window.setTimeout(() => resolve(null), 1_200);
      }),
    ]);
    const data = resultat?.data;
    const role = typeof data === 'string' ? data : (data as { role?: string } | null)?.role;
    return valeurTexte(role) as RoleApp;
  } catch {
    return null;
  } finally {
    if (delai !== undefined) window.clearTimeout(delai);
  }
}

function lienExplicite(data: Record<string, unknown>): string | null {
  const type = valeurTexte(data.type_evenement);
  const lien = valeurTexte(data.lien) ?? valeurTexte(data.link) ?? valeurTexte(data.url);
  const normalise = lien ? normaliserLienJolene(lien) : null;
  // Les anciennes versions du dispatcher injectaient « / » quand aucun lien
  // n'était fourni. Avec un type connu, laisser le fallback métier décider.
  return normalise && (normalise !== '/' || !type) ? normalise : null;
}

/**
 * Initialise le push pour toute session, y compris restaurée, biométrique ou
 * PSC. Le plugin Capacitor retourne le token attendu par chaque transport du
 * backend Jolene : APNs brut sur iOS, FCM sur Android.
 */
export async function initNativePush(userId: string): Promise<void> {
  if (!isNative() || !userId) return;
  if (userInitialise === userId) return;
  if (initialisationEnCours && userInitialisationEnCours === userId) return initialisationEnCours;

  // Un changement de compte invalide immédiatement les callbacks de l'ancien
  // cycle, même si un prompt système ou un appel réseau était encore ouvert.
  const generation = ++generationPush;
  userInitialisationEnCours = userId;

  initialisationEnCours = (async () => {
    const { PushNotifications } = await import('@capacitor/push-notifications');
    if (generation !== generationPush) return;

    // Un seul jeu de listeners par compte/appareil. Ils sont installés avant
    // register() afin de ne pas rater le token initial ou une rotation.
    await PushNotifications.removeAllListeners();
    if (generation !== generationPush) return;

    let permission = await PushNotifications.checkPermissions();
    if (permission.receive === 'prompt') {
      permission = await PushNotifications.requestPermissions();
    }
    if (permission.receive !== 'granted') {
      logger.debug('[PUSH] Permission non accordée');
      userInitialise = userId;
      return;
    }

    let confirmerToken!: () => void;
    let refuserToken!: (error: Error) => void;
    const tokenEnregistre = new Promise<void>((resolve, reject) => {
      confirmerToken = resolve;
      refuserToken = reject;
    });

    await PushNotifications.addListener('registration', ({ value }) => {
      if (generation !== generationPush) return;
      if (!value) {
        refuserToken(new Error('Le service push n’a retourné aucun token'));
        return;
      }
      void enregistrerToken(value, userId).then(confirmerToken).catch(refuserToken);
    });

    await PushNotifications.addListener('registrationError', (error) => {
      if (generation !== generationPush) return;
      const detail = valeurTexte((error as { error?: unknown }).error) ?? 'erreur native';
      refuserToken(new Error(`Échec enregistrement push : ${detail}`));
    });

    await PushNotifications.addListener('pushNotificationReceived', (notification) => {
      if (generation !== generationPush) return;
      window.dispatchEvent(new CustomEvent('jolene:push-foreground', {
        detail: {
          title: notification.title,
          body: notification.body,
          data: notification.data,
        },
      }));
    });

    await PushNotifications.addListener('pushNotificationActionPerformed', async ({ notification }) => {
      if (generation !== generationPush) return;
      const data = (notification.data ?? {}) as Record<string, unknown>;
      // Un lien explicite n'a besoin d'aucun appel réseau : il doit fonctionner
      // immédiatement, y compris quand l'app est lancée hors-ligne.
      const path = lienExplicite(data) ?? navigationPathForEvent(data, await roleCourant());
      if (!path) return;
      window.history.pushState(null, '', path);
      window.dispatchEvent(new PopStateEvent('popstate'));
    });

    await PushNotifications.register();
    let delaiToken: number | undefined;
    try {
      await Promise.race([
        tokenEnregistre,
        new Promise<never>((_, reject) => {
          delaiToken = window.setTimeout(
            () => reject(new Error('Délai dépassé lors de l’enregistrement push')),
            15_000,
          );
        }),
      ]);
    } finally {
      if (delaiToken !== undefined) window.clearTimeout(delaiToken);
    }
    if (generation !== generationPush) return;
    userInitialise = userId;
    logger.debug('[PUSH] Token natif enregistré');
  })().catch((error) => {
    if (generation !== generationPush) return;
    userInitialise = null;
    logger.error('[PUSH] Initialisation native échouée', error);
  }).finally(() => {
    if (generation === generationPush) {
      initialisationEnCours = null;
      userInitialisationEnCours = null;
    }
  });

  return initialisationEnCours;
}

/** Nettoie uniquement les listeners locaux ; le logout supprime le token côté DB. */
export async function resetNativePushListeners(): Promise<void> {
  const generation = ++generationPush;
  userInitialise = null;
  initialisationEnCours = null;
  userInitialisationEnCours = null;
  if (!isNative()) return;
  try {
    const { PushNotifications } = await import('@capacitor/push-notifications');
    if (generation !== generationPush) return;
    await PushNotifications.removeAllListeners();
  } catch { /* plugin absent au tout premier lancement — sans effet */ }
}

/**
 * Route un payload push vers une route réellement déclarée dans App.tsx.
 * Un lien explicite n'est accepté que s'il est interne ou HTTPS Jolene.
 */
export function navigationPathForEvent(data: Record<string, unknown>, role: RoleApp = null): string | null {
  const type = valeurTexte(data.type_evenement);
  const lienNormalise = lienExplicite(data);
  if (lienNormalise) return lienNormalise;

  const missionId = segment(data.mission_id);
  const contratId = segment(data.contrat_id);
  const factureId = segment(data.facture_id);
  const litigeId = segment(data.litige_id);
  const estEtab = role === 'ADMIN_ETABLISSEMENT' || role === 'ETABLISSEMENT';
  const estAdmin = role === 'ADMIN_PLATEFORME' || role === 'ADMIN';

  switch (type) {
    case 'CONTRAT_A_SIGNER':
    case 'CONTRAT_SIGNE':
    case 'CONTRAT_REJETE':
      if (contratId) return `/contrat/${contratId}`;
      return estEtab ? '/etablissement/contrats' : '/soignant/mes-documents?tab=contrats';
    case 'CANDIDATURE_RECUE':
    case 'CANDIDATURE_ANNULEE_SOIGNANT':
      return missionId ? `/etablissement/missions/${missionId}` : '/etablissement/missions';
    case 'CANDIDATURE_ACCEPTEE':
    case 'CANDIDATURE_REFUSEE':
    case 'MISSION_ANNULEE_ETAB':
      return missionId ? `/soignant/missions/${missionId}` : '/soignant/missions';
    case 'MISSION_ASSIGNEE':
    case 'MISSION_URGENTE':
    case 'MISSION_RAPPEL':
    case 'RAPPEL_MISSION':
    case 'RAPPEL_MISSION_J1':
    case 'MISSION_RAPPEL_J1':
    case 'POINTAGE_MANQUANT':
    case 'POOL_URGENCE_NOTIFICATIONS_ENVOYEES':
    case 'URGENCE':
    case 'POOL_URGENCE':
      return missionId ? `/soignant/missions/${missionId}` : '/soignant/missions';
    case 'MISSION_A_POURVOIR':
    case 'NOUVELLE_MISSION_MATCHANT_FILTRE':
    case 'FAVORI_NOUVELLE_MISSION':
      return missionId ? `/soignant/missions/${missionId}` : '/soignant/recherche-missions';
    case 'FACTURE_EMISE':
      if (estEtab) return factureId ? `/etablissement/facturation/${factureId}` : '/etablissement/facturation';
      return '/soignant/mes-gains?tab=factures';
    case 'PAIEMENT_RECU':
    case 'PAIEMENT_RECLAME':
      return estEtab ? '/etablissement/facturation' : '/soignant/mes-gains?tab=paiements';
    case 'LITIGE_OUVERT':
    case 'LITIGE_RESOLU':
    case 'NOUVEAU_MESSAGE_LITIGE': {
      const base = estAdmin ? '/admin/litiges' : estEtab ? '/etablissement/litiges' : '/soignant/litiges';
      return litigeId ? `${base}#${litigeId}` : base;
    }
    case 'DPAE_RAPPEL':
    case 'DPAE_ANNULATION_RAPPEL':
    case 'DPAE_NON_REGULARISEE_POINTAGE':
      if (contratId) return `/contrat/${contratId}`;
      return estEtab ? '/etablissement/contrats' : '/soignant/mes-documents?tab=dpae';
    case 'RECLAMATION_SCORE_DECISION':
      return estEtab ? '/etablissement/mes-reclamations' : '/soignant/litiges?tab=reclamations';
    case 'ALERTE_ADMIN':
      return '/admin/reclamations?tab=score';
    default:
      return null;
  }
}
