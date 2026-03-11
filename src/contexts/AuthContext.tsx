import React, { createContext, useContext, useState, useCallback, ReactNode } from 'react';
import { useNavigate } from 'react-router-dom';
import { UserRole, Soignant, Etablissement } from '@/lib/types';
import { MOCK_SOIGNANT, MOCK_ETABLISSEMENT } from '@/lib/mock-data';

interface User {
  id: string;
  email: string;
  role: UserRole;
  prenom?: string;
  nom?: string;
}

interface AuthContextType {
  user: User | null;
  loading: boolean;
  connexion: (email: string, motDePasse: string) => Promise<void>;
  deconnexion: () => void;
  inscriptionSoignant: (data: any) => Promise<void>;
  inscriptionEtablissement: (data: any) => Promise<void>;
}

const AuthContext = createContext<AuthContextType | null>(null);

export function AuthProvider({ children }: { children: ReactNode }) {
  const [user, setUser] = useState<User | null>(null);
  const [loading, setLoading] = useState(false);

  const connexion = useCallback(async (email: string, _motDePasse: string) => {
    setLoading(true);
    // Simulate API call
    await new Promise(r => setTimeout(r, 800));

    // Demo: determine role from email
    let role: UserRole = 'SOIGNANT';
    if (email.includes('etab') || email.includes('hopital') || email.includes('chu')) {
      role = 'ETABLISSEMENT';
    } else if (email.includes('groupe') || email.includes('admin')) {
      role = 'ADMIN_GROUPE';
    }

    setUser({
      id: role === 'SOIGNANT' ? MOCK_SOIGNANT.id : MOCK_ETABLISSEMENT.id,
      email,
      role,
      prenom: role === 'SOIGNANT' ? MOCK_SOIGNANT.prenom : undefined,
      nom: role === 'SOIGNANT' ? MOCK_SOIGNANT.nom : MOCK_ETABLISSEMENT.nom,
    });
    setLoading(false);
  }, []);

  const deconnexion = useCallback(() => {
    setUser(null);
  }, []);

  const inscriptionSoignant = useCallback(async (data: any) => {
    setLoading(true);
    await new Promise(r => setTimeout(r, 1000));
    setUser({
      id: 'new-soignant-' + Date.now(),
      email: data.email,
      role: 'SOIGNANT',
      prenom: data.prenom,
      nom: data.nom,
    });
    setLoading(false);
  }, []);

  const inscriptionEtablissement = useCallback(async (data: any) => {
    setLoading(true);
    await new Promise(r => setTimeout(r, 1000));
    setUser({
      id: 'new-etab-' + Date.now(),
      email: data.email,
      role: 'ETABLISSEMENT',
      nom: data.nom,
    });
    setLoading(false);
  }, []);

  return (
    <AuthContext.Provider value={{ user, loading, connexion, deconnexion, inscriptionSoignant, inscriptionEtablissement }}>
      {children}
    </AuthContext.Provider>
  );
}

export function useAuth() {
  const ctx = useContext(AuthContext);
  if (!ctx) throw new Error('useAuth must be used within AuthProvider');
  return ctx;
}
