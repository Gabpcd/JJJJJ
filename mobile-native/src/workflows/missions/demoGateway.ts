import { DemoGateway } from '../../data/demoGateway';
import { throwIfAborted, validateContext } from '../../data/business';
import type { MissionGateway, MissionReadContext } from '../../data/types';
import { alreadyApplied, applicationAction, hasActiveAssignment, isTerminalMission, type ApplicationSnapshot, type ApplyInput, type ApplyResult,
  type MissionWorkflowGateway, type MyMissionsPage, type MyMissionsTab } from './types';

/** In-memory rehearsal only. This class never receives a Supabase client or calls a provider. */
export class DemoMissionWorkflowGateway implements MissionWorkflowGateway {
  readonly mode = 'demo' as const;
  private readonly results = new Map<string, ApplicationSnapshot>();
  constructor(private readonly source: MissionGateway = new DemoGateway()) {
    if (source.mode !== 'demo') throw new Error('La démonstration nécessite une source de données fictives.');
  }

  async readApplication(context: MissionReadContext, id: string, signal?: AbortSignal): Promise<ApplicationSnapshot | null> {
    validateContext(context); throwIfAborted(signal);
    const historical = id === 'demo-history-cancelled';
    const mission = await this.source.getMission(historical ? 'demo-mission-016' : id, context, signal); throwIfAborted(signal);
    if (!mission) return null;
    const key = `${context.userId}:${id}`;
    const stored = this.results.get(key);
    if (stored) return JSON.parse(JSON.stringify(stored)) as ApplicationSnapshot;
    if (historical) {
      const old = new Date(mission.debut_le).getTime();
      const shift = Date.now() - 7 * 24 * 3600_000 - old;
      const past = (value: string) => new Date(new Date(value).getTime() + shift).toISOString();
      const cancelled: ApplicationSnapshot = { userId: context.userId,
        mission: { ...mission, id, intitule: 'Démonstration · Mission annulée', statut: 'ANNULEE_PAR_ETABLISSEMENT',
          debut_le: past(mission.debut_le), fin_le: past(mission.fin_le),
          creneaux_planifies: mission.creneaux_planifies.map(slot => ({ ...slot, debut: past(slot.debut), fin: slot.fin ? past(slot.fin) : slot.fin })) },
        attribution: 'CANDIDATURE', assignedTo: context.userId, appliedContract: 'SALARIE',
        application: { id: 'demo-history-application', statut: 'ACCEPTEE', type_contrat_choisi: 'SALARIE' },
        canApply: true, missingProfile: [], documentsComplete: false, exactPersistedPlanning: true,
        caregiver: { firstName: 'Camille', lastName: 'Démonstration', profession: context.profile.profession },
        acceptanceEmails: [{ recipient: 'soignant', state: 'failed' }] };
      this.results.set(key, cancelled);
      return JSON.parse(JSON.stringify(cancelled)) as ApplicationSnapshot;
    }
    return { userId: context.userId, mission, attribution: Number(id.slice(-3)) % 3 === 0 ? 'PREMIER_ARRIVE' : 'CANDIDATURE',
      assignedTo: null, appliedContract: null, application: null, canApply: true,
      missingProfile: [], documentsComplete: false, exactPersistedPlanning: mission.planning_exact,
      caregiver: { firstName: 'Camille', lastName: 'Démonstration', profession: context.profile.profession } };
  }

  async listMine(context: MissionReadContext, tab: MyMissionsTab, page = 0, signal?: AbortSignal): Promise<MyMissionsPage> {
    // Check the explicit demo identity even when no local application exists.
    await this.source.getProfile(context.userId, signal).then(profile => {
      if (!profile) throw new Error('Ce compte ne correspond pas à la démonstration.');
    });
    validateContext(context); throwIfAborted(signal);
    if (tab === 'passees') await this.readApplication(context, 'demo-history-cancelled', signal);
    const matching = [...this.results.values()].filter(row => row.userId === context.userId
      && (tab === 'candidatures' ? Boolean(row.application) : tab === 'actives' ? hasActiveAssignment(row) : row.assignedTo === context.userId && isTerminalMission(row)));
    return { rows: matching.slice(0, (page + 1) * 20).map(({ mission, application, appliedContract }) => ({
      id: mission.id, title: mission.intitule, startsAt: mission.debut_le, endsAt: mission.fin_le, status: mission.statut,
      establishment: mission.etablissements?.nom ?? 'Établissement fictif', city: mission.etablissements?.adresse_ville ?? null,
      contract: appliedContract ?? application?.type_contrat_choisi ?? mission.type_contrat_recherche,
      applicationId: application?.id ?? null, applicationStatus: application?.statut ?? null,
    })), page, hasMore: matching.length > (page + 1) * 20 };
  }

  async apply(context: MissionReadContext, snapshot: ApplicationSnapshot, input: ApplyInput, signal?: AbortSignal): Promise<ApplyResult> {
    throwIfAborted(signal);
    const fresh = await this.readApplication(context, snapshot.mission.id, signal);
    if (!fresh || snapshot.userId !== context.userId) throw new Error('Mission fictive introuvable.');
    if (isTerminalMission(fresh)) return { kind: 'rejected', snapshot: fresh, message: 'Cette mission fictive est clôturée.' };
    if (alreadyApplied(fresh)) return { kind: 'confirmed', snapshot: fresh, documentsToComplete: !fresh.documentsComplete };
    const action = applicationAction(fresh);
    if (!action) return { kind: 'rejected', snapshot: fresh, message: 'Cette mission fictive ne peut pas être confirmée.' };
    if (fresh.mission.type_contrat_recherche === 'TOUS' && !input.contractChoice) return { kind: 'choice', snapshot: fresh,
      options: [{ value: 'SALARIE', label: 'Salarié' }, { value: 'LIBERAL', label: 'Libéral' }] };
    if (action === 'POSTULER') fresh.application = { id: `demo-application-${fresh.mission.id}`, statut: 'EN_ATTENTE',
      type_contrat_choisi: input.contractChoice ?? fresh.mission.type_contrat_recherche };
    else {
      fresh.assignedTo = context.userId; fresh.appliedContract = input.contractChoice ?? fresh.mission.type_contrat_recherche;
      fresh.mission = { ...fresh.mission, statut: 'ASSIGNEE' };
    }
    throwIfAborted(signal);
    this.results.set(`${context.userId}:${snapshot.mission.id}`, JSON.parse(JSON.stringify(fresh)) as ApplicationSnapshot);
    return { kind: 'confirmed', snapshot: fresh, documentsToComplete: !fresh.documentsComplete };
  }

  async retryAcceptanceEmails(context: MissionReadContext, missionId: string, signal?: AbortSignal) {
    const snapshot = await this.readApplication(context, missionId, signal);
    if (!snapshot || !hasActiveAssignment(snapshot)) throw new Error('Aucune attribution fictive active.');
    return [];
  }
}
