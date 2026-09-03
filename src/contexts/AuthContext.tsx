import React, { createContext, useContext, useState, useCallback, useEffect, ReactNode } from 'react';
import * as Sentry from '@sentry/react';
import { supabase, SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY } from '@/integrations/supabase/client';
import { Session, User } from '@supabase/supabase-js';
import { logger } from '@/lib/logger';
import { getAttribution } from '@/lib/attribution';
import { gererErreurSupabase } from '@/lib/supabaseErrorHandler';
import { viderCacheHorsLigne } from '@/lib/cacheHorsLigne';
import { estRefusInscriptionAttendu, extraireErreurEdgeFn } from '@/lib/erreurs';
import { useQueryClient } from '@tanstack/react-query';
import { ouvrirUrlPsc } from '@/lib/pscNavigation';

interface AppUser {
  id: string;
  email: string;
  prenom?: string;
  nom?: string;
}

interface AuthContextType {
  user: AppUser | null;
  session: Session | null;
  loading: boolean;
  connexion: (email: string, motDePasse: string) => Promise<void>;
  deconnexion: () => Promise<void>;
  inscriptionSoignant: (data: any) => Promise<void>;
  inscriptionEtablissement: (data: any) => Promise<void>;
}

const AuthContext = createContext<AuthContextType | null>(null);

function toAppUser(user: User): AppUser {
  return {
    id: user.id,
    email: user.email || '',
    prenom: user.user_metadata?.prenom,
    nom: user.user_metadata?.nom,
  };
}

function erreurConfirmationEmail(): Error {
  const erreur = new Error(
    'Un email de confirmation vient de vous être envoyé. Ouvrez-le, revenez ici, puis appuyez sur « J’ai confirmé mon email » pour terminer votre inscription.',
  );
  (erreur as Error & { code?: string }).code = 'EMAIL_CONFIRMATION_REQUIRED';
  return erreur;
}

/**
 * Supabase ne renvoie volontairement pas `USER_ALREADY_REGISTERED` quand la
 * confirmation email est active : un second signUp reçoit un faux utilisateur
 * sans identité. Sans ce rattrapage, un utilisateur ayant confirmé son email
 * ne pouvait jamais reprendre la création de son profil métier.
 */
async function resoudreSessionInscription(
  authData: { user: User | null; session: Session | null },
  email: string,
  password: string,
): Promise<{ user: User; session: Session }> {
  const emailNormalise = email.trim().toLowerCase();
  const appartientAuCompte = (session: Session | null) => (
    session?.user.email?.trim().toLowerCase() === emailNormalise
  );

  if (appartientAuCompte(authData.session)) {
    return { user: authData.session!.user, session: authData.session! };
  }

  const { data: sessionData } = await supabase.auth.getSession();
  if (appartientAuCompte(sessionData.session)) {
    // La session est la source d'identité. Le faux utilisateur que Supabase
    // renvoie sur un signUp dupliqué ne doit jamais fournir l'id métier.
    return { user: sessionData.session!.user, session: sessionData.session! };
  }

  const identities = authData.user?.identities;
  if (authData.user && Array.isArray(identities) && identities.length === 0) {
    const { data: signInData, error: signInError } = await supabase.auth.signInWithPassword({
      email,
      password,
    });
    if (signInData.user && signInData.session) {
      return { user: signInData.user, session: signInData.session };
    }
    if ((signInError as { code?: string } | null)?.code === 'email_not_confirmed'
      || /email not confirmed/i.test(signInError?.message || '')) {
      throw erreurConfirmationEmail();
    }
    const erreur = new Error('Ce compte existe déjà. Vérifiez votre mot de passe ou connectez-vous.');
    (erreur as Error & { code?: string }).code = 'USER_ALREADY_REGISTERED';
    throw erreur;
  }

  throw erreurConfirmationEmail();
}

export function AuthProvider({ children }: { children: ReactNode }) {
  const queryClient = useQueryClient();
  const [user, setUser] = useState<AppUser | null>(null);
  const [session, setSession] = useState<Session | null>(null);
  const [loading, setLoading] = useState(true);
  const userId = user?.id;

  useEffect(() => {
    const { data: { subscription } } = supabase.auth.onAuthStateChange((event, session) => {
      setSession(session);
      setUser(session?.user ? toAppUser(session.user) : null);
      setLoading(false);

      // Detect session expiry / sign out triggered by token refresh failure
      if (event === 'SIGNED_OUT' || (event === 'TOKEN_REFRESHED' && !session)) {
        Sentry.setUser(null);
        queryClient.clear();
      }
    });

    supabase.auth.getSession().then(({ data: { session } }) => {
      setSession(session);
      setUser(session?.user ? toAppUser(session.user) : null);
      setLoading(false);
    });

    return () => subscription.unsubscribe();
  }, [queryClient]);

  // Initialise aussi le push pour une session restaurée, PSC ou biométrique —
  // pas seulement après le formulaire de connexion. Le module est idempotent.
  useEffect(() => {
    if (loading) return;
    if (userId) {
      void import('@/lib/pushNative').then(({ initNativePush }) => initNativePush(userId));
    } else {
      void import('@/lib/pushNative').then(({ resetNativePushListeners }) => resetNativePushListeners());
    }
  }, [loading, userId]);

  const connexion = useCallback(async (email: string, motDePasse: string, captchaToken?: string) => {
    const { data, error } = await supabase.auth.signInWithPassword({
      email,
      password: motDePasse,
      ...(captchaToken ? { options: { captchaToken } } : {}),
    });
    if (error) throw error;

    const u = data.user;

    // Sentry user identification
    Sentry.setUser({ id: u.id });

    // Une connexion Auth réussie ne doit jamais être retransformée en échec
    // utilisateur parce qu'un audit ou une mise à jour d'activité est lent.
    // Ces écritures restent best-effort et les autorisations sont toujours
    // imposées côté serveur par les RLS/RPC.
    void supabase.rpc('fn_audit_connexion', {
      p_action: 'CONNEXION',
    }).then(({ error: auditError }) => {
      if (auditError) logger.warn('Audit connexion ignoré', auditError);
    }, (auditError) => {
      logger.warn('Audit connexion indisponible — connexion conservée', auditError);
    });

    if (u.app_metadata?.role === 'SOIGNANT') {
      void supabase.rpc('fn_maj_activite_soignant' as any).then(
        () => undefined,
        (activityError) => logger.warn('Mise à jour activité soignant ignorée', activityError),
      );
    }
  }, []);

  const deconnexion = useCallback(async () => {
    const currentUser = user;
    if (currentUser) {
      const { error: auditError } = await supabase.rpc('fn_audit_connexion', {
        p_action: 'DECONNEXION',
      });
      if (auditError) logger.error('Audit déconnexion échoué', auditError);
    }

    // Si l'utilisateur s'est connecté via PSC, on doit appeler end_session_endpoint
    // pour invalider la session ANS. Sinon il resterait connecté côté PSC et un
    // nouveau "Se connecter avec Pro Santé Connect" le re-loguerait silencieusement.
    let pscEndSessionUrl: string | null = null;
    if (currentUser) {
      try {
        const { data: soignant } = await supabase
          .from('soignants')
          .select('psc_sub')
          .eq('id', currentUser.id)
          .maybeSingle();
        const isPscUser = !!soignant?.psc_sub;
        if (isPscUser) {
          // supabase.functions.invoke transmet automatiquement le JWT de la session courante
          const { data: logoutData } = await supabase.functions.invoke('psc-logout', { body: {} });
          if (logoutData?.configured && typeof logoutData.end_session_url === 'string') {
            pscEndSessionUrl = logoutData.end_session_url;
          }
        }
      } catch (e) {
        logger.warn('[AuthContext] PSC logout lookup failed (fallback to local signOut)', e);
      }
    }

    if (pscEndSessionUrl) {
      // On ne fait PAS signOut() ici : c'est /connexion?logout=psc qui le fera après
      // que PSC ait redirigé le navigateur. Cela évite une race entre un signOut local
      // (qui invalide tout) et le redirect PSC qui pourrait être abandonné.
      viderCacheHorsLigne();
      queryClient.clear();
      // Retirer uniquement cette installation. Les autres appareils du compte
      // continuent a recevoir leurs notifications.
      try {
        const { desactiverPushAppareilCourant } = await import('@/lib/pushDeviceToken');
        await desactiverPushAppareilCourant();
      } catch (e) {
        logger.warn('[AuthContext] cleanup token push appareil avant PSC logout failed', e);
      } finally {
        try {
          const { resetNativePushListeners } = await import('@/lib/pushNative');
          await resetNativePushListeners();
        } catch { /* ne jamais bloquer le logout pour un cleanup local */ }
      }
      Sentry.setUser(null);
      if (await ouvrirUrlPsc(pscEndSessionUrl)) return;
      logger.warn('[AuthContext] URL de déconnexion PSC refusée ou navigateur indisponible');
    }

    // Retire seulement le token de l'appareil courant. Un logout sur mobile ne
    // doit jamais couper les notifications des autres appareils du compte.
    try {
      const { desactiverPushAppareilCourant } = await import('@/lib/pushDeviceToken');
      await desactiverPushAppareilCourant();
    } catch (e) {
      logger.warn('[AuthContext] cleanup token push appareil avant signOut failed', e);
    } finally {
      try {
        const { resetNativePushListeners } = await import('@/lib/pushNative');
        await resetNativePushListeners();
      } catch { /* ne jamais bloquer le logout pour un cleanup local */ }
    }

    await supabase.auth.signOut();
    viderCacheHorsLigne();
    queryClient.clear();
    Sentry.setUser(null);
  }, [user, queryClient]);

  const inscriptionSoignant = useCallback(async (data: any) => {
    logger.debug('[INSCRIPTION] 1. Début inscription soignant, données:', { email: data.email, prenom: data.prenom, nom: data.nom, profession: data.profession });

    // Étape 1 : signUp Supabase Auth (ou signIn si le user existe déjà
    // d'une tentative précédente avortée — le profil soignant n'existe
    // pas encore mais le compte auth oui).
    let authData: any;
    try {
      logger.debug('[INSCRIPTION] 2. Appel supabase.auth.signUp...');
      const { data: signUpData, error: authError } = await supabase.auth.signUp({
        email: data.email,
        password: data.motDePasse,
        options: {
          data: { role: 'SOIGNANT', prenom: data.prenom, nom: data.nom },
          ...(data.turnstileToken ? { captchaToken: data.turnstileToken } : {}),
        },
      });
      if (authError) {
        const msg = authError.message?.toLowerCase() || '';
        if (msg.includes('already') && msg.includes('registered')) {
          logger.debug('[INSCRIPTION] 2b. User déjà enregistré, tentative signIn...');
          const { data: signInData, error: signInError } = await supabase.auth.signInWithPassword({
            email: data.email,
            password: data.motDePasse,
          });
          if (signInError) {
            logger.error('[INSCRIPTION] ERREUR signIn fallback', signInError);
            throw new Error('Ce compte existe déjà. Vérifiez votre mot de passe ou connectez-vous.');
          }
          authData = signInData;
        } else {
          logger.error('[INSCRIPTION] ERREUR signUp', authError);
          throw authError;
        }
      } else {
        authData = signUpData;
      }
      logger.debug('[INSCRIPTION] 3. signUp/signIn OK, user id:', authData.user?.id, 'session:', !!authData.session);
    } catch (err) {
      logger.error('[INSCRIPTION] signUp EXCEPTION', err);
      throw err;
    }

    if (!authData.session) logger.warn('[INSCRIPTION] 3b. Aucun token dans signUp, résolution du parcours de confirmation...');
    const sessionInscription = await resoudreSessionInscription(authData, data.email, data.motDePasse);
    const userId = sessionInscription.user.id;
    const accessToken = sessionInscription.session.access_token;
    logger.debug('[INSCRIPTION] 3c. Session d’inscription résolue:', !!accessToken);
    const registerBody = {
      prenom: data.prenom,
      nom: data.nom,
      telephone: data.telephone || null,
      dateNaissance: data.dateNaissance || null,
      profession: data.profession,
      typesContrat: data.typesContrat || ['CDD'],
      rpps: data.rpps || null,
      rayon: data.rayon,
      lat: data.lat || null,
      lng: data.lng || null,
      est_etudiant: data.est_etudiant ?? false,
      etudiant_details: data.etudiant_details || null,
      navigateur: navigator.userAgent,
      turnstileToken: data.turnstileToken || null,
      attribution: getAttribution(),
    };

    try {
      logger.debug('[INSCRIPTION] 4. Appel fetch register-soignant');
      const headers: Record<string, string> = { 'Content-Type': 'application/json' };
      if (accessToken) {
        headers['Authorization'] = `Bearer ${accessToken}`;
      }
      headers['apikey'] = SUPABASE_PUBLISHABLE_KEY;

      const response = await fetch(
        `${SUPABASE_URL}/functions/v1/register-soignant`,
        { method: 'POST', headers, body: JSON.stringify(registerBody) }
      );

      logger.debug('[INSCRIPTION] 5. register-soignant HTTP status:', response.status);
      const result = await response.json();
      logger.debug('[INSCRIPTION] 6. register-soignant réponse:', result);

      if (!response.ok || result?.ok === false || result?.error) {
        // Refus métier attendu (RPPS introuvable, captcha, mot de passe faible…) :
        // l'utilisateur voit un message clair → on n'en fait PAS une issue Sentry.
        if (estRefusInscriptionAttendu(result?.code)) {
          logger.warn('[INSCRIPTION] register-soignant refus attendu', result?.code);
        } else {
          logger.error('[INSCRIPTION] ERREUR register-soignant', result);
        }
        try { await supabase.auth.signOut(); } catch { /* ignore */ }
        // [BUG 2 fix] Propage le code machine-readable + détails du backend
        // sur l'Error throwée, pour que mapperErreurInscription() côté
        // page puisse lire err.code au lieu de retomber sur le pattern
        // matching texte (qui ratait RPPS_NOT_FOUND, etc.).
        const erreur = new Error(result?.message || result?.error || 'Erreur lors de la création de votre profil. Veuillez réessayer.');
        (erreur as any).code = result?.code;
        (erreur as any).details = result?.details;
        (erreur as any).body = result;
        (erreur as any).httpStatus = response.status;
        throw erreur;
      }

      logger.debug('[INSCRIPTION] 7. register-soignant OK ✅');
    } catch (err) {
      // Idem côté catch : un refus métier attendu remonté via l'Error (err.code)
      // reste un breadcrumb, pas une issue Sentry.
      if (estRefusInscriptionAttendu((err as any)?.code)) {
        logger.warn('[INSCRIPTION] register-soignant refus attendu (catch)', (err as any)?.code);
      } else {
        logger.error('[INSCRIPTION] register-soignant EXCEPTION', err);
        Sentry.captureException(err, { tags: { composant: 'AuthContext', action: 'inscription_soignant' } });
      }
      try { await supabase.auth.signOut(); } catch { /* ignore */ }
      // Re-throw en préservant code/details si déjà attachés (vrai pour
      // notre Error construite ci-dessus, false pour les exceptions natives
      // comme TypeError "Failed to fetch" — qui n'ont pas de code).
      throw err instanceof Error ? err : new Error('Erreur lors de la création de votre profil. Veuillez réessayer.');
    }

    // L'email BIENVENUE_SOIGNANT est envoyé par register-soignant lui-même
    // (best-effort côté serveur) — pas de double-envoi côté client.
  }, []);

  const inscriptionEtablissement = useCallback(async (data: any) => {
    let authData: { user: User | null; session: Session | null };
    const { data: signUpData, error: authError } = await supabase.auth.signUp({
      email: data.email,
      password: data.motDePasse,
      options: {
        data: { role: 'ETABLISSEMENT', nom_etablissement: data.nom },
        ...(data.turnstileToken ? { captchaToken: data.turnstileToken } : {}),
      },
    });
    if (authError) {
      const dejaInscrit = /already.*registered|user.*registered/i.test(authError.message || '');
      if (dejaInscrit) {
        // Reprise d'une inscription interrompue après création Auth mais avant
        // le profil métier. Le backend décidera ensuite, via sa réservation
        // atomique, si ce compte peut réellement devenir établissement.
        const { data: signInData, error: signInError } = await supabase.auth.signInWithPassword({
          email: data.email,
          password: data.motDePasse,
        });
        if (signInError) {
          const erreur = new Error('Ce compte existe déjà. Vérifiez votre mot de passe ou connectez-vous.');
          (erreur as any).code = 'USER_ALREADY_REGISTERED';
          throw erreur;
        }
        authData = signInData;
      } else {
        logger.error('Inscription établissement auth échouée', authError);
        // Ne PAS masquer la cause réelle : on propage le message + code Supabase
        // pour que la page affiche un message précis (e-mail déjà utilisé, mot de
        // passe trop faible, captcha, rate-limit) via mapperErreurInscription.
        const erreur = new Error(authError.message || 'Erreur lors de la création du compte.');
        (erreur as any).code = (authError as any).code;
        (erreur as any).status = (authError as any).status;
        throw erreur;
      }
    } else {
      authData = signUpData;
    }

    const sessionInscription = await resoudreSessionInscription(authData, data.email, data.motDePasse);

    const { data: result, error: fnError } = await supabase.functions.invoke('register-etablissement', {
      body: {
        nom: data.nom,
        siret: data.siret,
        finess: data.finess || null,
        type: data.type,
        adresse_rue: data.rue || null,
        adresse_ville: data.ville,
        adresse_code_postal: data.codePostal || null,
        adresse_departement: data.departement || null,
        telephone_contact: data.telephoneContact || null,
        email_contact: data.emailContact || data.email,
        adresse_lat: data.lat || null,
        adresse_lng: data.lng || null,
        numero_licence: data.numeroLicence || null,
        navigateur: navigator.userAgent,
        turnstileToken: data.turnstileToken || null,
        attribution: getAttribution(),
      },
      headers: { Authorization: `Bearer ${sessionInscription.session.access_token}` },
    });

    // Quand l'edge function renvoie un status non-2xx, le SDK met data=null
    // et le body JSON réel est dans fnError.context. On l'extrait ici pour
    // propager code/message/details vers mapperErreurInscription côté page.
    const resolvedResult = result ?? (fnError ? await extraireErreurEdgeFn(null, fnError) : null);

    if (fnError || resolvedResult?.ok === false || resolvedResult?.error) {
      Sentry.captureException(fnError || new Error(resolvedResult?.message || resolvedResult?.error), { tags: { composant: 'AuthContext', action: 'inscription_etablissement' } });
      logger.error('register-etablissement échoué', fnError || resolvedResult);
      try {
        await supabase.auth.signOut();
      } catch { /* ignore */ }
      // [BUG 2 fix] Propage code/details du backend pour que mapperErreur
      // côté page puisse afficher un message précis (SIRET déjà enregistré,
      // SIRET checksum invalide, etc.).
      const erreur = new Error(resolvedResult?.message || resolvedResult?.error || 'Erreur lors de la création du profil établissement. Veuillez réessayer.');
      (erreur as any).code = resolvedResult?.code;
      (erreur as any).details = resolvedResult?.details;
      (erreur as any).body = resolvedResult;
      throw erreur;
    }

    // L'email BIENVENUE_ETABLISSEMENT est envoyé par register-etablissement lui-même
    // (best-effort côté serveur) — pas de double-envoi côté client.
  }, []);

  return (
    <AuthContext.Provider value={{ user, session, loading, connexion, deconnexion, inscriptionSoignant, inscriptionEtablissement }}>
      {children}
    </AuthContext.Provider>
  );
}

export function useAuth() {
  const ctx = useContext(AuthContext);
  if (!ctx) {
    return {
      user: null, session: null, loading: true,
      connexion: async () => {}, deconnexion: async () => {},
      inscriptionSoignant: async () => {}, inscriptionEtablissement: async () => {},
    } as any;
  }
  return ctx;
}
