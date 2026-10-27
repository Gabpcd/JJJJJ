import type { MissionRecord, MissionSlot } from '../data/types';
import { ESTABLISHMENT_PERMISSION_KEYS, type EstablishmentContext, type EstablishmentPermissions, type EstablishmentProfile } from './types';

export const DEMO_ESTABLISHMENT_CONTEXT: EstablishmentContext = {
  userId: 'demo-etablissement-user', email: 'etablissement@demo.invalid', etablissementId: 'demo-etablissement',
  membershipRole: 'PROPRIETAIRE',
  permissions: Object.fromEntries(ESTABLISHMENT_PERMISSION_KEYS.map(key => [key, true])) as EstablishmentPermissions,
};
export const DEMO_ESTABLISHMENT_PROFILE: EstablishmentProfile = {
  id: 'demo-etablissement', nom: 'Clinique des Lilas · Démo', type: 'CLINIQUE', siret: null, finess: null,
  adresse_rue: null, adresse_ville: 'Paris', adresse_code_postal: '75011',
  email_contact: 'etablissement@demo.invalid', telephone_contact: null,
  statut_verification: 'VERIFIE', contrat_service_signe: true, peut_publier_missions: true,
};

/** Explicit synthetic fixtures only. No provider/client is referenced in this module. */
export function demonstrationMissions(now: Date): { records: MissionRecord[]; slots: MissionSlot[] } {
  const date = new Date(now);
  date.setUTCHours(8, 0, 0, 0);
  const records: MissionRecord[] = [];
  const slots: MissionSlot[] = [];
  const states = ['OUVERTE', 'ASSIGNEE', 'EN_COURS', 'TERMINEE', 'ANNULEE_PAR_ETABLISSEMENT', 'EXPIREE'];
  for (let index = 0; index < 12; index += 1) {
    const id = `demo-etab-mission-${String(index + 1).padStart(3, '0')}`;
    const begin = new Date(date.getTime() + (index + 1) * 86_400_000);
    const end = new Date(begin.getTime() + 8 * 3_600_000);
    const multiple = index === 0;
    const lastEnd = multiple ? new Date(end.getTime() + 2 * 86_400_000) : end;
    records.push({ id, etablissement_id: DEMO_ESTABLISHMENT_CONTEXT.etablissementId,
      intitule: `${index % 2 ? 'Soins de suite' : 'Médecine'} — mission fictive ${index + 1}`,
      description: 'Mission de démonstration. Aucune candidature, aucun contrat et aucun paiement réels.',
      service: index % 2 ? 'Soins de suite' : 'Médecine', profession_requise: 'IDE',
      specialite_medicale_requise: null, accepte_non_specialises: null,
      debut_le: begin.toISOString(), fin_le: lastEnd.toISOString(), duree_heures: multiple ? 16 : 8,
      nb_creneaux: multiple ? 2 : 1, taux_horaire_base: index % 2 ? 30 : 28,
      taux_rist_plafonne: null, rist_plafond_applique: false,
      total_brut: null, net_a_payer: null, est_urgente: index === 0, niveau_urgence: index === 0 ? 1 : 0,
      statut: states[index % states.length], type_contrat_recherche: index % 2 ? 'LIBERAL' : 'SALARIE',
      boostee_le: null, mode_remuneration: 'HORAIRE', retrocession_pct: null,
    });
    slots.push({ id: `${id}-slot-1`, mission_id: id, debut: begin.toISOString(), fin: end.toISOString(), est_pause: false, type_creneau: 'PREVISIONNEL' });
    if (multiple) slots.push({ id: `${id}-slot-2`, mission_id: id,
      debut: new Date(begin.getTime() + 2 * 86_400_000).toISOString(), fin: lastEnd.toISOString(), est_pause: false, type_creneau: 'PREVISIONNEL' });
  }
  return { records, slots };
}
