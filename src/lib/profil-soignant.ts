import type { Database } from '@/integrations/supabase/types';
import { PROFESSIONS_SANS_RPPS } from '@/lib/constantes';

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
  /** Progression des items REQUIS pour candidater (distincte du % global). */
  pourcentage_obligatoire: number;
  obligatoires_total: number;
  obligatoires_remplis: number;
  /** Items RECOMMANDÉS (non bloquants) non remplis. */
  items_recommandes_manquants: ItemCompletion[];
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
      pourcentage_obligatoire: 0,
      obligatoires_total: 0,
      obligatoires_remplis: 0,
      items_recommandes_manquants: [],
    };
  }

  const sansRPPS = !!soignant.profession && PROFESSIONS_SANS_RPPS.includes(soignant.profession);

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
    // RPPS uniquement pour les professions concernées (AS/AES en sont exemptés —
    // identification par diplôme + CNI). ADELI obsolète depuis 2024, plus utilisé.
    // Quand applicable, RPPS est OBLIGATOIRE car requis pour toute candidature
    // (les missions filtrent strictement par profession_requise renseignée par
    // l'API ANS lors de la vérification RPPS).
    ...(sansRPPS ? [] : [{
      cle: 'rpps',
      label: 'RPPS vérifié',
      rempli: !!soignant.rpps_verifie,
      obligatoire: true,
      ordre: 5,
      action_label: 'Vérifier mon RPPS',
      action_route: '/soignant/profil',
    }]),
    {
      cle: 'profession',
      label: 'Profession',
      rempli: !!soignant.profession,
      obligatoire: false,
      ordre: 6,
      action_route: '/soignant/profil',
    },
    {
      // L'adresse sert au matching/distance, PAS à candidater : le backend
      // (fn_postuler_mission) ne l'exige jamais. On la sort donc du gate
      // `peut_candidater` (recommandée, pas obligatoire) → nudge post-inscription
      // « ajoute ton adresse pour voir les missions près de chez toi ».
      cle: 'adresse',
      label: 'Adresse géolocalisée',
      rempli: !!soignant.adresse_lat && !!soignant.adresse_lng,
      obligatoire: false,
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
  const items_recommandes_manquants = items.filter(
    (i) => !i.obligatoire && !i.rempli,
  );
  const pourcentage = Math.round((items_remplis / total_items) * 100);

  const obligatoires = items.filter((i) => i.obligatoire);
  const obligatoires_total = obligatoires.length;
  const obligatoires_remplis = obligatoires.filter((i) => i.rempli).length;
  const pourcentage_obligatoire =
    obligatoires_total === 0
      ? 100
      : Math.round((obligatoires_remplis / obligatoires_total) * 100);

  return {
    pourcentage,
    total_items,
    items_remplis,
    items_obligatoires_manquants,
    items: items.sort((a, b) => a.ordre - b.ordre),
    est_complet: pourcentage === 100,
    peut_candidater: items_obligatoires_manquants.length === 0,
    pourcentage_obligatoire,
    obligatoires_total,
    obligatoires_remplis,
    items_recommandes_manquants,
  };
}

export function getMotifProfilIncomplet(
  resume: ResumeCompletion,
): string | null {
  if (resume.est_complet) return null;
  if (resume.items_obligatoires_manquants.length > 0) {
    // On NOMME explicitement les champs manquants (au lieu d'un simple comptage)
    // pour que le soignant sache exactement quoi compléter.
    const noms = resume.items_obligatoires_manquants.map((i) => i.label).join(', ');
    return `À compléter : ${noms}.`;
  }
  if (!resume.peut_candidater) {
    return 'Vous pouvez voir les missions mais pas encore candidater.';
  }
  return 'Profil partiellement complété.';
}

/** Liste courte des labels des champs obligatoires manquants (pour affichage en rouge). */
export function getChampsObligatoiresManquants(resume: ResumeCompletion): string[] {
  return resume.items_obligatoires_manquants.map((i) => i.label);
}
