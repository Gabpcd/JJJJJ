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

function extractRole(user: User): UserRole {
  return (user.app_metadata?.role || user.user_metadata?.role || 'SOIGNANT') as UserRole;
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
    const { error: auditError } = await supabase.rpc('fn_ecrire_audit', {
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
    if (auditError) console.error('Audit failed:', auditError);

    // Update derniere_activite_le for soignants
    if (role === 'SOIGNANT') {
      supabase.from('soignants').update({ derniere_activite_le: new Date().toISOString() } as any).eq('id', u.id).then(() => {});
    }
  }, []);

  const deconnexion = useCallback(async () => {
    const currentUser = user;
    // Audit AVANT signOut (sinon la session est invalidée)
    if (currentUser) {
      const { error: auditError } = await supabase.rpc('fn_ecrire_audit', {
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
      if (auditError) console.error('Audit failed:', auditError);
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
      console.error('AUTH SIGNUP ERROR (soignant):', { message: authError.message, status: authError.status, name: authError.name });
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
      throw new Error(`[INSERT soignants] ${insertError.message} | details: ${insertError.details} | hint: ${insertError.hint} | code: ${insertError.code}`);
    }

    // 3. Set app_metadata for RLS
    await supabase.functions.invoke('set-user-claims', {
      body: { userId, role: 'SOIGNANT' },
    });

    // 4. Audit inscription + CGU consent
    await supabase.rpc('fn_ecrire_audit', {
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

    await supabase.rpc('fn_ecrire_audit', {
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
        subject: 'Bienvenue sur Soin Direct ! 🎉',
        html: emailBienvenueSoignant(data.prenom),
        type: 'BIENVENUE_SOIGNANT',
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
      console.error('AUTH SIGNUP ERROR (etablissement):', { message: authError.message, status: authError.status, name: authError.name });
      throw authError;
    }

    const userId = authData.user!.id;

    // 2. Insert into etablissements table
    const insertPayload = {
      id: userId,
      nom: data.nom,
      siret: data.siret,
      finess: data.finess || null,
      type: data.type,
      adresse_rue: data.rue || 'Non renseigné',
      adresse_ville: data.ville,
      adresse_code_postal: data.codePostal || '00000',
      adresse_departement: data.departement || null,
      email_contact: data.emailContact || data.email,
      telephone_contact: data.telephoneContact || null,
      adresse_lat: data.lat || null,
      adresse_lng: data.lng || null,
    };
    logger.debug('INSERT etablissements pour userId:', userId);
    const { error: insertError } = await supabase.from('etablissements').insert(insertPayload as any);
    if (insertError) {
      logger.error('INSERT etablissements échoué', insertError);
      throw new Error(`[INSERT etablissements] ${insertError.message} | details: ${insertError.details} | hint: ${insertError.hint} | code: ${insertError.code}`);
    }

    // 3. Set app_metadata for RLS
    await supabase.functions.invoke('set-user-claims', {
      body: { userId, role: 'ETABLISSEMENT', etablissementId: userId },
    });

    // 4. Audit inscription + CGU consent
    await supabase.rpc('fn_ecrire_audit', {
      p_acteur_id: userId,
      p_type_acteur: 'ADMIN_ETABLISSEMENT',
      p_action: 'CONNEXION',
      p_type_ressource: 'etablissement',
      p_id_ressource: userId,
      p_cle_s3: null,
      p_details: { evenement: 'inscription', type: data.type },
      p_ip: null,
      p_navigateur: navigator.userAgent,
    });

    await supabase.rpc('fn_ecrire_audit', {
      p_acteur_id: userId,
      p_type_acteur: 'ADMIN_ETABLISSEMENT',
      p_action: 'RGPD_CONSENTEMENT_DONNE',
      p_type_ressource: 'etablissement',
      p_id_ressource: userId,
      p_cle_s3: null,
      p_details: { type: 'inscription', cgu: true, confidentialite: true },
      p_ip: null,
      p_navigateur: navigator.userAgent,
    });

    // 5. Email de bienvenue établissement
    supabase.functions.invoke('send-email', {
      body: {
        to: data.email,
        subject: 'Bienvenue sur Soin Direct !',
        html: emailBienvenueEtablissement(data.nom),
        type: 'BIENVENUE_ETABLISSEMENT',
        destinataire_id: userId,
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
