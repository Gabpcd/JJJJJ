import type { Database } from '@/integrations/supabase/types';

type Soignant = Database['public']['Tables']['soignants']['Row'];

export interface ItemCompletion {
  cle: string;
  label: string;
  rempli: boolean;
  obligatoire: boolean;
  ordre: number;
  action_label?: string;
  action_route?: string;
}

export interface ResumeCompletion {
  pourcentage: number;
  total_items: number;
  items_remplis: number;
  items_obligatoires_manquants: ItemCompletion[];
  items: ItemCompletion[];
  est_complet: boolean;
  peut_candidater: boolean;
}

export function calculerCompletionProfil(
  soignant: Soignant | null,
  options?: {
    documents_ok?: boolean;
    identite_verifiee?: boolean;
  }
): ResumeCompletion {
  if (!soignant) {
    return {
      pourcentage: 0,
      total_items: 9,
      items_remplis: 0,
      items_obligatoires_manquants: [],
      items: [],
      est_complet: false,
      peut_candidater: false,
    };
  }

  const items: ItemCompletion[] = [
    {
      cle: 'prenom',
      label: 'Prénom',
      rempli: !!soignant.prenom,
      obligatoire: true,
      ordre: 1,
      action_route: '/soignant/profil',
    },
    {
      cle: 'nom',
      label: 'Nom',
      rempli: !!soignant.nom,
      obligatoire: true,
      ordre: 2,
      action_route: '/soignant/profil',
    },
    {
      cle: 'date_naissance',
      label: 'Date de naissance',
      rempli: !!soignant.date_naissance,
      obligatoire: true,
      ordre: 3,
      action_route: '/soignant/profil',
    },
    {
      cle: 'telephone',
      label: 'Téléphone',
      rempli: !!soignant.telephone,
      obligatoire: true,
      ordre: 4,
      action_route: '/soignant/profil',
    },
    {
      cle: 'rpps',
      label: 'RPPS vérifié',
      rempli: !!soignant.rpps_verifie,
      obligatoire: false,
      ordre: 5,
      action_label: 'Vérifier mon RPPS',
      action_route: '/soignant/profil',
    },
    {
      cle: 'profession',
      label: 'Profession',
      rempli: !!soignant.profession,
      obligatoire: false,
      ordre: 6,
      action_route: '/soignant/profil',
    },
    {
      cle: 'adresse',
      label: 'Adresse géolocalisée',
      rempli: !!soignant.adresse_lat && !!soignant.adresse_lng,
      obligatoire: true,
      ordre: 7,
      action_route: '/soignant/profil',
    },
    {
      cle: 'documents',
      label: 'Documents validés',
      rempli: options?.documents_ok ?? !!soignant.tous_documents_valides,
      obligatoire: false,
      ordre: 8,
      action_label: 'Téléverser mes documents',
      action_route: '/soignant/mes-documents',
    },
    {
      cle: 'identite',
      label: 'Identité vérifiée',
      rempli: options?.identite_verifiee ?? !!soignant.identite_verifiee,
      obligatoire: false,
      ordre: 9,
      action_label: 'Compléter mon identité',
      action_route: '/soignant/profil',
    },
  ];

  const items_remplis = items.filter((i) => i.rempli).length;
  const total_items = items.length;
  const items_obligatoires_manquants = items.filter(
    (i) => i.obligatoire && !i.rempli,
  );
  const pourcentage = Math.round((items_remplis / total_items) * 100);

  return {
    pourcentage,
    total_items,
    items_remplis,
    items_obligatoires_manquants,
    items: items.sort((a, b) => a.ordre - b.ordre),
    est_complet: pourcentage === 100,
    peut_candidater: items_obligatoires_manquants.length === 0,
  };
}

export function getMotifProfilIncomplet(
  resume: ResumeCompletion,
): string | null {
  if (resume.est_complet) return null;
  if (resume.items_obligatoires_manquants.length > 0) {
    return `${resume.items_obligatoires_manquants.length} information(s) obligatoire(s) manquante(s).`;
  }
  if (!resume.peut_candidater) {
    return 'Vous pouvez voir les missions mais pas encore candidater.';
  }
  return 'Profil partiellement complété.';
}
