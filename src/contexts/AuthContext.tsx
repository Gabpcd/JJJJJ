import React, { createContext, useContext, useState, useCallback, useEffect, ReactNode } from 'react';
import * as Sentry from '@sentry/react';
import { supabase, SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY } from '@/integrations/supabase/client';
import { Session, User } from '@supabase/supabase-js';
import { logger } from '@/lib/logger';
import { gererErreurSupabase } from '@/lib/supabaseErrorHandler';
import { viderCacheHorsLigne } from '@/lib/cacheHorsLigne';

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

export function AuthProvider({ children }: { children: ReactNode }) {
  const [user, setUser] = useState<AppUser | null>(null);
  const [session, setSession] = useState<Session | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    const { data: { subscription } } = supabase.auth.onAuthStateChange((event, session) => {
      setSession(session);
      setUser(session?.user ? toAppUser(session.user) : null);
      setLoading(false);

      // Detect session expiry / sign out triggered by token refresh failure
      if (event === 'SIGNED_OUT' || (event === 'TOKEN_REFRESHED' && !session)) {
        Sentry.setUser(null);
      }
    });

    supabase.auth.getSession().then(({ data: { session } }) => {
      setSession(session);
      setUser(session?.user ? toAppUser(session.user) : null);
      setLoading(false);
    });

    return () => subscription.unsubscribe();
  }, []);

  const connexion = useCallback(async (email: string, motDePasse: string) => {
    const { data, error } = await supabase.auth.signInWithPassword({ email, password: motDePasse });
    if (error) throw error;

    const u = data.user;

    // Get verified role from server — never trust client metadata
    let verifiedRole = 'INCONNU';
    try {
      const { data: roleData } = await supabase.rpc('fn_get_my_role');
      if (roleData && (roleData as any).role) {
        verifiedRole = (roleData as any).role;
      }
    } catch { /* fallback */ }

    const { error: auditError } = await supabase.rpc('fn_audit_connexion', {
      p_action: 'CONNEXION',
    });
    if (auditError) logger.error('Audit connexion échoué', auditError);

    // Sentry user identification
    Sentry.setUser({ id: u.id, email: u.email || undefined });

    if (verifiedRole === 'SOIGNANT') {
      supabase.rpc('fn_maj_activite_soignant' as any).then(() => {});
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
    await supabase.auth.signOut();
    viderCacheHorsLigne();
    Sentry.setUser(null);
  }, [user]);

  const inscriptionSoignant = useCallback(async (data: any) => {
    logger.debug('[INSCRIPTION] 1. Début inscription soignant, données:', { email: data.email, prenom: data.prenom, nom: data.nom, profession: data.profession });

    // Étape 1 : signUp Supabase Auth
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
        logger.error('[INSCRIPTION] ERREUR signUp', authError);
        throw authError;
      }
      authData = signUpData;
      logger.debug('[INSCRIPTION] 3. signUp OK, user id:', authData.user?.id, 'session:', !!authData.session);
    } catch (err) {
      logger.error('[INSCRIPTION] signUp EXCEPTION', err);
      throw err;
    }

    const userId = authData.user!.id;
    let accessToken = authData.session?.access_token;
    if (!accessToken) {
      logger.warn('[INSCRIPTION] 3b. Aucun token dans signUp, tentative via getSession...');
      const { data: sessionData } = await supabase.auth.getSession();
      accessToken = sessionData.session?.access_token;
      logger.debug('[INSCRIPTION] 3c. Token via getSession:', !!accessToken);
    }
    if (!accessToken) {
      throw new Error('Session introuvable après inscription. Veuillez réessayer.');
    }
    const registerBody = {
      prenom: data.prenom,
      nom: data.nom,
      telephone: data.telephone || null,
      dateNaissance: data.dateNaissance || null,
      profession: data.profession,
      typesContrat: data.typesContrat || ['CDDU'],
      rpps: data.rpps || null,
      rayon: data.rayon,
      lat: data.lat || null,
      lng: data.lng || null,
      navigateur: navigator.userAgent,
      turnstileToken: data.turnstileToken || null,
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

      if (!response.ok || result?.error) {
        logger.error('[INSCRIPTION] ERREUR register-soignant', result);
        try { await supabase.auth.signOut(); } catch { /* ignore */ }
        throw new Error(result?.error || 'Erreur lors de la création de votre profil. Veuillez réessayer.');
      }

      logger.debug('[INSCRIPTION] 7. register-soignant OK ✅');
    } catch (err) {
      logger.error('[INSCRIPTION] register-soignant EXCEPTION', err);
      Sentry.captureException(err, { tags: { composant: 'AuthContext', action: 'inscription_soignant' } });
      try { await supabase.auth.signOut(); } catch { /* ignore */ }
      throw err instanceof Error ? err : new Error('Erreur lors de la création de votre profil. Veuillez réessayer.');
    }

    // L'email BIENVENUE_SOIGNANT est envoyé par register-soignant lui-même
    // (best-effort côté serveur) — pas de double-envoi côté client.
  }, []);

  const inscriptionEtablissement = useCallback(async (data: any) => {
    const { data: authData, error: authError } = await supabase.auth.signUp({
      email: data.email,
      password: data.motDePasse,
      options: {
        data: { role: 'ETABLISSEMENT', nom_etablissement: data.nom },
        ...(data.turnstileToken ? { captchaToken: data.turnstileToken } : {}),
      },
    });
    if (authError) {
      logger.error('Inscription établissement auth échouée', authError);
      throw new Error('Erreur lors de la création du compte.');
    }

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
      },
    });

    if (fnError || result?.error) {
      Sentry.captureException(fnError || new Error(result?.error), { tags: { composant: 'AuthContext', action: 'inscription_etablissement' } });
      logger.error('register-etablissement échoué', fnError || result?.error);
      try {
        await supabase.auth.signOut();
      } catch { /* ignore */ }
      throw new Error('Erreur lors de la création du profil établissement. Veuillez réessayer.');
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
