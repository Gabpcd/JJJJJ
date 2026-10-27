import { enrichMission, filterMissions, throwIfAborted, validateContext } from './business';
import type { EtablissementSummary, Mission, MissionFilters, MissionGateway, MissionReadContext, MissionRecord, MissionSlot, RoleResult, SoignantProfile } from './types';

export const DEMO_CONTEXT: MissionReadContext = {
  userId: 'demo-soignant',
  email: 'demonstration@example.invalid',
  profile: {
    id: 'demo-soignant', profession: 'IDE', adresse_lat: 48.8566, adresse_lng: 2.3522,
    rayon_deplacement_km: 50, tous_documents_valides: false, type_contrat: 'CDD',
    types_contrat_acceptes: '["CDD","LIBERAL"]', type_exercice: 'MIXTE', taux_horaire_minimum: 0,
  },
};

const ESTABLISHMENTS: EtablissementSummary[] = [
  { id: 'demo-etab-1', nom: 'Établissement fictif République', adresse_ville: 'Paris', adresse_code_postal: '75011', adresse_lat: 48.867, adresse_lng: 2.363, type: 'CLINIQUE' },
  { id: 'demo-etab-2', nom: 'Établissement fictif des Lilas', adresse_ville: 'Les Lilas', adresse_code_postal: '93260', adresse_lat: 48.879, adresse_lng: 2.421, type: 'EHPAD' },
  { id: 'demo-etab-3', nom: 'Cabinet fictif du Parc', adresse_ville: 'Vincennes', adresse_code_postal: '94300', adresse_lat: 48.848, adresse_lng: 2.439, type: 'CABINET' },
];

/** Local synthetic data only. Never used as a fallback for an API failure. */
export class DemoGateway implements MissionGateway {
  readonly mode = 'demo' as const;
  private readonly records: MissionRecord[] = [];
  private readonly slots: MissionSlot[] = [];

  constructor(now: () => Date = () => new Date()) {
    const base = now();
    for (let index = 0; index < 30; index += 1) {
      const day = new Date(base);
      day.setUTCDate(day.getUTCDate() + index + 1);
      day.setUTCHours(index % 4 === 3 ? 20 : 7, 0, 0, 0);
      const start = day.toISOString();
      const finish = new Date(day.getTime() + 8 * 3_600_000).toISOString();
      const id = `demo-mission-${String(index + 1).padStart(3, '0')}`;
      const multi = index % 6 === 5;
      const laterStart = new Date(day.getTime() + 2 * 86_400_000).toISOString();
      const laterFinish = new Date(day.getTime() + 2 * 86_400_000 + 8 * 3_600_000).toISOString();
      const hourly = 23 + index % 8;
      this.records.push({
        id, intitule: `Démonstration · ${index % 2 ? 'Soins de suite' : 'Médecine polyvalente'} ${index + 1}`,
        description: 'Mission entièrement fictive pour découvrir la navigation native. Aucun remplacement, contrat ou paiement ne peut être engagé dans ce pilote.',
        service: index % 2 ? 'Soins de suite' : 'Médecine polyvalente', profession_requise: 'IDE',
        specialite_medicale_requise: null, accepte_non_specialises: null,
        debut_le: start, fin_le: multi ? laterFinish : finish, duree_heures: multi ? 16 : 8,
        nb_creneaux: multi ? 2 : 1, taux_horaire_base: hourly,
        taux_rist_plafonne: index === 0 ? hourly : null, rist_plafond_applique: index === 0,
        total_brut: null, net_a_payer: null, est_urgente: index % 5 === 0,
        niveau_urgence: index % 5 === 0 ? 1 : 0, statut: 'OUVERTE',
        etablissement_id: ESTABLISHMENTS[index % ESTABLISHMENTS.length].id,
        type_contrat_recherche: index % 3 === 2 ? 'LIBERAL' : 'SALARIE',
        boostee_le: null, mode_remuneration: 'HORAIRE', retrocession_pct: null,
      });
      this.slots.push({ id: `${id}-slot-1`, mission_id: id, debut: start, fin: finish, est_pause: false, type_creneau: 'PREVISIONNEL' });
      if (multi) this.slots.push({ id: `${id}-slot-2`, mission_id: id, debut: laterStart, fin: laterFinish, est_pause: false, type_creneau: 'PREVISIONNEL' });
    }
  }

  async getRole(signal?: AbortSignal): Promise<RoleResult> {
    throwIfAborted(signal);
    return { role: 'SOIGNANT', etablissement_id: null };
  }

  async getProfile(userId: string, signal?: AbortSignal): Promise<SoignantProfile | null> {
    throwIfAborted(signal);
    return userId === DEMO_CONTEXT.userId ? { ...DEMO_CONTEXT.profile } : null;
  }

  async listMissions(context: MissionReadContext, filters: MissionFilters = {}, signal?: AbortSignal): Promise<Mission[]> {
    this.check(context, signal);
    return filterMissions(this.records.map(record => this.enrich(record, context)), context, filters);
  }

  async getMission(id: string, context: MissionReadContext, signal?: AbortSignal): Promise<Mission | null> {
    this.check(context, signal);
    const record = this.records.find(mission => mission.id === id);
    return record ? this.enrich(record, context) : null;
  }

  private check(context: MissionReadContext, signal?: AbortSignal): void {
    throwIfAborted(signal);
    validateContext(context);
    if (context.userId !== DEMO_CONTEXT.userId) throw new Error('Le mode démonstration utilise uniquement son profil fictif.');
  }

  private enrich(record: MissionRecord, context: MissionReadContext): Mission {
    const establishment = ESTABLISHMENTS.find(item => item.id === record.etablissement_id);
    return enrichMission({ ...record }, context, establishment ? { ...establishment } : null,
      this.slots.filter(slot => slot.mission_id === record.id).map(slot => ({ ...slot })));
  }
}
