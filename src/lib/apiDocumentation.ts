import { SUPABASE_URL } from '@/integrations/supabase/client';

export interface ApiKeySafe {
  id: string;
  nom: string;
  cle_api: string;
  permissions: string[];
  etablissement_id: string;
  groupe_sante_id: string | null;
  actif: boolean;
  derniere_utilisation: string | null;
  cree_le: string;
  expire_le: string | null;
  secret_configure: boolean;
}

export const API_BASE_URL = `${SUPABASE_URL}/functions/v1/api-v1`;

export const API_ENDPOINTS = [
  { method: 'GET', path: '/missions', desc: 'Lister les missions de l’établissement', example: '{ "missions": [{ "id": "uuid", "intitule": "IDE Nuit", "statut": "OUVERTE" }], "count": 1 }' },
  { method: 'POST', path: '/missions', desc: 'Créer une mission (permission missions:write)', example: '{ "mission": { "id": "uuid", "intitule": "IDE Jour", "statut": "OUVERTE" } }' },
  { method: 'GET', path: '/presences', desc: 'Lister les pointages (permission presences:read)', example: '{ "presences": [{ "id": "uuid", "mission_id": "uuid", "validee_par_etablissement": true }], "count": 1 }' },
  { method: 'GET', path: '/factures', desc: 'Lister les factures (permission factures:read)', example: '{ "factures": [{ "id": "uuid", "numero_facture": "SD-2026-001", "montant_ttc": 150.00 }], "count": 1 }' },
] as const;

export const API_PERMISSIONS = [
  { value: 'missions:read', label: 'Lire les missions' },
  { value: 'missions:write', label: 'Créer des missions' },
  { value: 'presences:read', label: 'Lire les pointages' },
  { value: 'factures:read', label: 'Lire les factures' },
] as const;

export const API_METHOD_COLORS: Record<string, string> = {
  GET: 'bg-success/10 text-success',
  POST: 'bg-primary/10 text-primary',
};
