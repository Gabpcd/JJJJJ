import React, { createContext, useContext, useState, useCallback, useEffect, ReactNode } from 'react';
import { supabase } from '@/integrations/supabase/client';
import { UserRole } from '@/lib/types';

import { Session, User } from '@supabase/supabase-js';
import { logger } from '@/lib/logger';

interface AppUser {
  id: string;
  email: string;
  role: UserRole;
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

function extractRole(user: User): UserRole {
  // Le rôle affiché ici est provisoire (affichage uniquement).
  // La vérification d'accès réelle se fait via useRole() + fn_get_my_role côté serveur.
  const metaRole = user.user_metadata?.role;
  if (metaRole === 'ADMIN_ETABLISSEMENT' || metaRole === 'ETABLISSEMENT') return 'ADMIN_ETABLISSEMENT';
  if (metaRole === 'ADMIN_GROUPE') return 'ADMIN_GROUPE';
  if (metaRole === 'ADMIN') return 'ADMIN';
  return 'SOIGNANT';
}

function toAppUser(user: User): AppUser {
  return {
    id: user.id,
    email: user.email || '',
    role: extractRole(user),
    prenom: user.user_metadata?.prenom,
    nom: user.user_metadata?.nom,
  };
}

export function AuthProvider({ children }: { children: ReactNode }) {
  const [user, setUser] = useState<AppUser | null>(null);
  const [session, setSession] = useState<Session | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    const { data: { subscription } } = supabase.auth.onAuthStateChange((_event, session) => {
      setSession(session);
      setUser(session?.user ? toAppUser(session.user) : null);
      setLoading(false);
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

    // C3: Resolve role server-side to prevent identity spoofing in audit logs
    let verifiedRole: string = extractRole(u);
    try {
      const { data: roleData } = await supabase.rpc('fn_get_my_role');
      if (roleData && (roleData as any).role) {
        verifiedRole = (roleData as any).role;
      }
    } catch { /* fallback to extractRole */ }

    // Audit HDS with server-verified role
    const { error: auditError } = await supabase.rpc('fn_ecrire_audit_safe', {
      p_acteur_id: u.id,
      p_type_acteur: verifiedRole,
      p_action: 'CONNEXION',
      p_type_ressource: verifiedRole === 'SOIGNANT' ? 'soignant' : 'etablissement',
      p_id_ressource: u.id,
      p_cle_s3: null,
      p_details: { methode: 'email_password', horodatage: new Date().toISOString() },
      p_ip: null,
      p_navigateur: navigator.userAgent,
    });
    if (auditError) logger.error('Audit connexion échoué', auditError);

    // Update derniere_activite_le for soignants via RPC
    if (role === 'SOIGNANT') {
      supabase.rpc('fn_maj_activite_soignant' as any).then(() => {});
    }
  }, []);

  const deconnexion = useCallback(async () => {
    const currentUser = user;
    // Audit AVANT signOut (sinon la session est invalidée)
    if (currentUser) {
      const { error: auditError } = await supabase.rpc('fn_ecrire_audit_safe', {
        p_acteur_id: currentUser.id,
        p_type_acteur: currentUser.role,
        p_action: 'DECONNEXION',
        p_type_ressource: currentUser.role === 'SOIGNANT' ? 'soignant' : 'etablissement',
        p_id_ressource: currentUser.id,
        p_cle_s3: null,
        p_details: { horodatage: new Date().toISOString() },
        p_ip: null,
        p_navigateur: navigator.userAgent,
      });
      if (auditError) logger.error('Audit déconnexion échoué', auditError);
    }
    await supabase.auth.signOut();
  }, [user]);

  const inscriptionSoignant = useCallback(async (data: any) => {
    // 1. Create auth account
    const { data: authData, error: authError } = await supabase.auth.signUp({
      email: data.email,
      password: data.motDePasse,
      options: { data: { role: 'SOIGNANT', prenom: data.prenom, nom: data.nom } },
    });
    if (authError) {
      logger.error('Inscription soignant auth échouée', authError);
      throw authError;
    }

    // 2. Create profile + assign role via secure Edge Function (no client-side INSERT)
    const { data: result, error: fnError } = await supabase.functions.invoke('register-soignant', {
      body: {
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
      },
    });

    if (fnError) {
      logger.error('register-soignant échoué', fnError);
      throw new Error('Erreur lors de la création du profil soignant.');
    }

    if (result?.error) {
      throw new Error(result.error);
    }

    // 3. Email de bienvenue (fire-and-forget)
    const userId = authData.user!.id;
    supabase.functions.invoke('send-email', {
      body: {
        type: 'BIENVENUE_SOIGNANT',
        data: { prenom: data.prenom },
        destinataire_id: userId,
      },
    }).catch(() => {});
  }, []);

  const inscriptionEtablissement = useCallback(async (data: any) => {
    // 1. Create auth account
    const { data: authData, error: authError } = await supabase.auth.signUp({
      email: data.email,
      password: data.motDePasse,
      options: { data: { role: 'ETABLISSEMENT', nom_etablissement: data.nom } },
    });
    if (authError) {
      logger.error('Inscription établissement auth échouée', authError);
      throw new Error('Erreur lors de la création du compte.');
    }

    // 2. Server-side: create établissement + assign role via Edge Function
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
      },
    });

    if (fnError) {
      logger.error('register-etablissement échoué', fnError);
      throw new Error('Erreur lors de la création du profil établissement.');
    }

    // Check for error in response body
    if (result?.error) {
      throw new Error(result.error);
    }

    // 3. Email de bienvenue établissement (fire-and-forget)
    supabase.functions.invoke('send-email', {
      body: {
        type: 'BIENVENUE_ETABLISSEMENT',
        data: { nom: data.nom },
        destinataire_id: authData.user!.id,
      },
    }).catch(() => {});
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
    // During HMR, context can temporarily be null — return safe defaults
    return {
      user: null, session: null, loading: true,
      connexion: async () => {}, deconnexion: async () => {},
      inscriptionSoignant: async () => {}, inscriptionEtablissement: async () => {},
    } as any;
  }
  return ctx;
}
