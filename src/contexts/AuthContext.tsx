import React, { createContext, useContext, useState, useCallback, useEffect, ReactNode } from 'react';
import { supabase } from '@/integrations/supabase/client';
import { UserRole } from '@/lib/types';
import { emailBienvenueSoignant, emailBienvenueEtablissement } from '@/lib/emailTemplates';
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

function extractRole(_user: User): UserRole {
  // Le rôle affiché ici est provisoire (affichage uniquement).
  // La vérification d'accès réelle se fait via useRole() + fn_get_my_role côté serveur.
  return 'SOIGNANT' as UserRole;
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
    const role = extractRole(u);

    // Audit HDS
    const { error: auditError } = await supabase.rpc('fn_ecrire_audit_safe', {
      p_acteur_id: u.id,
      p_type_acteur: role === 'SOIGNANT' ? 'SOIGNANT' : 'ADMIN_ETABLISSEMENT',
      p_action: 'CONNEXION',
      p_type_ressource: role === 'SOIGNANT' ? 'soignant' : 'etablissement',
      p_id_ressource: u.id,
      p_cle_s3: null,
      p_details: { methode: 'email_password', horodatage: new Date().toISOString() },
      p_ip: null,
      p_navigateur: navigator.userAgent,
    });
    if (auditError) logger.error('Audit connexion échoué', auditError);

    // Update derniere_activite_le for soignants
    if (role === 'SOIGNANT') {
      supabase.from('soignants').update({ derniere_activite_le: new Date().toISOString() } as any).eq('id', u.id).then(() => {});
    }
  }, []);

  const deconnexion = useCallback(async () => {
    const currentUser = user;
    // Audit AVANT signOut (sinon la session est invalidée)
    if (currentUser) {
      const { error: auditError } = await supabase.rpc('fn_ecrire_audit_safe', {
        p_acteur_id: currentUser.id,
        p_type_acteur: currentUser.role === 'SOIGNANT' ? 'SOIGNANT' : 'ADMIN_ETABLISSEMENT',
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

    const userId = authData.user!.id;

    // 2. Insert into soignants table
    const typesContrat: string[] = data.typesContrat || (data.typeContrat ? [data.typeContrat] : ['CDDU']);
    const insertPayload = {
      id: userId,
      prenom: data.prenom,
      nom: data.nom,
      email: data.email,
      telephone: data.telephone || null,
      date_naissance: data.dateNaissance || null,
      profession: data.profession,
      type_contrat: typesContrat[0],
      types_contrat_acceptes: JSON.stringify(typesContrat),
      numero_rpps: data.rpps || null,
      rayon_deplacement_km: data.rayon,
      adresse_lat: data.lat || null,
      adresse_lng: data.lng || null,
    };
    logger.debug('INSERT soignants pour userId:', userId);
    const { error: insertError } = await supabase.from('soignants').insert(insertPayload as any);
    if (insertError) {
      logger.error('INSERT soignants échoué', insertError);
      throw new Error('Erreur lors de la création du profil soignant.');
    }

    // 3. Set app_metadata for RLS
    await supabase.functions.invoke('set-user-claims', {
      body: { userId, role: 'SOIGNANT' },
    });

    // 4. Audit inscription + CGU consent
    await supabase.rpc('fn_ecrire_audit_safe', {
      p_acteur_id: userId,
      p_type_acteur: 'SOIGNANT',
      p_action: 'CONNEXION',
      p_type_ressource: 'soignant',
      p_id_ressource: userId,
      p_cle_s3: null,
      p_details: { evenement: 'inscription', profession: data.profession },
      p_ip: null,
      p_navigateur: navigator.userAgent,
    });

    await supabase.rpc('fn_ecrire_audit_safe', {
      p_acteur_id: userId,
      p_type_acteur: 'SOIGNANT',
      p_action: 'RGPD_CONSENTEMENT_DONNE',
      p_type_ressource: 'soignant',
      p_id_ressource: userId,
      p_cle_s3: null,
      p_details: { type: 'inscription', cgu: true, confidentialite: true },
      p_ip: null,
      p_navigateur: navigator.userAgent,
    });

    // 5. Email de bienvenue
    supabase.functions.invoke('send-email', {
      body: {
        to: data.email,
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
        to: data.email,
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
