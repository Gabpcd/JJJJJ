import { TYPES_DOCUMENTS_EXCLUS_UPLOAD } from '../../../../src/lib/documents';
import { validateDocumentBytes, type ValidatedDocumentBytes } from './bytes';
import { createDemoDocumentFile } from './demoFixture';
import { assertDemoDocumentUser } from './demoJournal';
import { visibleDocumentRequirements } from './requirements';
import { DocumentWorkflowError, type CaregiverDocument, type DocumentContext, type DocumentDossier, type DocumentGateway,
  type DocumentMutationResult, type DocumentOriginal, type DocumentProfile, type DocumentRequirement,
  type NativeDocumentFile, type UploadDocumentInput } from './types';

export interface DemoDocumentSession {
  userId: string; epoch: number;
  /** Preserve the profession chosen in onboarding, even when its demo user ID is reused. */
  profile?: { profession?: string | null; type_exercice?: string | null };
}
export interface DemoDocumentOutcome {
  userId: 'demo-soignant' | 'demo-inscription'; typeDocument: string;
  /** A committed synthetic upload whose first response is deliberately unconfirmed. */
  kind: 'confirmed' | 'uncertain_committed';
}
export interface DemoDocumentOptions {
  currentSession: () => DemoDocumentSession | null;
  initialFile?: NativeDocumentFile;
  /** Explicit scenario injection. Never populated as a fallback from a TEST/provider error. */
  outcomes?: readonly DemoDocumentOutcome[];
  now?: () => Date;
}

type Identity = DemoDocumentSession;
type DemoAccount = { profile: DocumentProfile; records: CaregiverDocument[]; originals: Map<string, Uint8Array>; sequence: number };
const clone = <T,>(value: T): T => JSON.parse(JSON.stringify(value)) as T;
function abort(signal?: AbortSignal) {
  if (signal?.aborted) { const error = new Error('Opération fictive annulée.'); error.name = 'AbortError'; throw error; }
}
function scope(): never { throw new DocumentWorkflowError('INVALID_SCOPE', 'Ce document ne fait pas partie de ton dossier de démonstration.'); }

/**
 * Entirely synthetic memory. No Supabase client, provider, filesystem, URL or transport.
 * The same binary validators and requirement presentation filters as TEST are used.
 * Demo verification never updates a professional profile or grants eligibility.
 */
export class DemoDocumentGateway implements Omit<DocumentGateway, 'mode'> {
  readonly mode = 'demo' as const;
  private readonly initial: Promise<ValidatedDocumentBytes>;
  private readonly accounts = new Map<string, DemoAccount>();
  private readonly busy = new Set<string>();
  private readonly outcomes: DemoDocumentOutcome[];
  private readonly now: () => Date;
  private readonly currentSession: DemoDocumentOptions['currentSession'];

  constructor(options: DemoDocumentOptions) {
    this.currentSession = options.currentSession;
    this.now = options.now ?? (() => new Date());
    this.outcomes = (options.outcomes ?? []).map(outcome => {
      assertDemoDocumentUser(outcome.userId);
      if (!['confirmed', 'uncertain_committed'].includes(outcome.kind) || TYPES_DOCUMENTS_EXCLUS_UPLOAD.includes(outcome.typeDocument)) {
        throw new Error('Scénario documentaire fictif invalide.');
      }
      return { ...outcome };
    });
    const source = options.initialFile ?? createDemoDocumentFile();
    this.initial = validateDocumentBytes({ ...source, bytes: new Uint8Array(source.bytes) });
    // A rejected injected fixture is reported on readDossier; do not emit an unhandled rejection.
    void this.initial.catch(() => undefined);
  }

  private identity(context: DocumentContext, signal?: AbortSignal): Identity {
    assertDemoDocumentUser(context.userId); abort(signal);
    const session = this.currentSession();
    if (!session || session.userId !== context.userId || !Number.isSafeInteger(session.epoch)) {
      throw new DocumentWorkflowError('SESSION_CHANGED', 'Rouvre le compte de démonstration concerné.');
    }
    return { ...session, profile: session.profile ? { ...session.profile } : undefined };
  }
  private current(identity: Identity, signal?: AbortSignal): void {
    abort(signal);
    const session = this.currentSession();
    if (!session || session.userId !== identity.userId || session.epoch !== identity.epoch) {
      throw new DocumentWorkflowError('SESSION_CHANGED', 'Le compte de démonstration a changé.');
    }
  }
  private rules(profile: DocumentProfile): DocumentRequirement[] {
    if (!profile.profession || !['IDE', 'MEDECIN'].includes(profile.profession)) return [];
    const definitions: Array<[string, boolean, string]> = profile.profession === 'MEDECIN'
      ? [['CARTE_IDENTITE', true, 'Identité fictive — aucun contrôle professionnel réel.'], ['ATTESTATION_SCOLARITE', false, 'Pièce de scolarité fictive.'], ['LICENCE_REMPLACEMENT', false, 'Pièce fictive ; aucun droit au remplacement n’est accordé.']]
      : [['DIPLOME', true, 'Diplôme fictif pour la démonstration.'], ['CARTE_IDENTITE', true, 'Pièce d’identité fictive pour la démonstration.'], ['RCP_ASSURANCE', false, 'Assurance fictive pour la démonstration.'], ['RIB', false, 'Justificatif fictif sans coordonnées bancaires.']];
    return visibleDocumentRequirements(profile, definitions.map(([type, critical, description]) => ({
      id: `demo-rule-${profile.profession}-${type}`, profession: profile.profession!, type_document: type, description,
      a_expiration: type !== 'DIPLOME', duree_validite_mois: null, est_critique: critical, type_exercice_requis: 'TOUS',
    })));
  }
  private async account(identity: Identity, signal?: AbortSignal): Promise<DemoAccount> {
    const initial = await this.initial; this.current(identity, signal);
    let account = this.accounts.get(identity.userId);
    if (account) {
      if (identity.profile) {
        account.profile.profession = identity.profile.profession ?? null;
        account.profile.type_exercice = identity.profile.type_exercice ?? null;
      }
      return account;
    }
    const doctor = identity.userId === 'demo-inscription';
    const profile: DocumentProfile = { id: identity.userId, profession: doctor ? 'MEDECIN' : 'IDE',
      prenom: 'Camille', nom: 'Démonstration', type_exercice: doctor ? 'SALARIE' : 'MIXTE',
      rpps_verifie: false, adeli_verifie: false, attestation_sante_signee_le: null };
    if (identity.profile) {
      profile.profession = identity.profile.profession ?? null;
      profile.type_exercice = identity.profile.type_exercice ?? null;
    }
    account = { profile, records: [], originals: new Map(), sequence: 0 };
    this.accounts.set(identity.userId, account);
    if (profile.profession === 'IDE') {
      for (const [type, status] of [['DIPLOME', 'VERIFIE'], ['CARTE_IDENTITE', 'REJETE'], ['RIB', 'EN_ATTENTE']] as const) {
        const row = this.makeDocument(identity, account, type, initial, `Simulation — ${type}`);
        row.statut_verification = status;
        row.motif_rejet = status === 'REJETE' ? 'Rejet fictif : image de démonstration volontairement considérée illisible.' : null;
        row.profession_certifiee = status === 'VERIFIE' ? profile.profession : null;
        account.records.push(row);
      }
    }
    return account;
  }
  private makeDocument(identity: Identity, account: DemoAccount, type: string, file: ValidatedDocumentBytes, label: string,
    preparedPath?: string): CaregiverDocument {
    const ordinal = String(++account.sequence).padStart(3, '0');
    const id = `demo-document-${identity.userId}-${ordinal}`;
    const path = preparedPath ?? `${identity.userId}/documents/${type}/demo-original-${ordinal}-${file.safeName}`;
    // Original bytes are copied once and never changed by verification, replacement or withdrawal.
    account.originals.set(id, new Uint8Array(file.bytes.slice(0)));
    return { id, soignant_id: identity.userId, type_document: type, nom_fichier: file.originalName,
      statut_verification: 'EN_ATTENTE', valide_depuis: null, valide_jusqua: null, televerse_le: this.now().toISOString(),
      motif_rejet: null, est_critique: this.rules(account.profile).find(rule => rule.type_document === type)?.est_critique ?? false,
      libelle: label, s3_cle: path, s3_bucket: 'jolene-documents', type_mime: file.mime, taille_octets: file.size,
      profession_certifiee: null, supprime_le: null, revoque_le: null };
  }
  private snapshot(identity: Identity, account: DemoAccount): DocumentDossier {
    return clone({ userId: identity.userId, profile: account.profile,
      documents: account.records.filter(row => !row.supprime_le && !row.revoque_le).slice().reverse(),
      requirements: this.rules(account.profile) });
  }
  private active(account: DemoAccount, documentId: string): CaregiverDocument {
    const document = account.records.find(row => row.id === documentId && !row.supprime_le && !row.revoque_le);
    if (!document) scope();
    return document;
  }
  private async exclusive<T>(identity: Identity, action: () => Promise<T>): Promise<T> {
    if (this.busy.has(identity.userId)) throw new DocumentWorkflowError('BUSY', 'Une simulation documentaire est déjà en cours.');
    this.busy.add(identity.userId);
    try { return await action(); } finally { this.busy.delete(identity.userId); }
  }

  async readDossier(context: DocumentContext, signal?: AbortSignal): Promise<DocumentDossier> {
    const identity = this.identity(context, signal);
    const account = await this.account(identity, signal);
    return this.snapshot(identity, account);
  }
  async getOriginal(context: DocumentContext, documentId: string, signal?: AbortSignal): Promise<DocumentOriginal> {
    const identity = this.identity(context, signal);
    const account = await this.account(identity, signal); this.active(account, documentId);
    throw new DocumentWorkflowError('UNAVAILABLE', 'L’ouverture d’un original fictif n’est pas fournie par cette démonstration.');
  }
  async upload(context: DocumentContext, input: UploadDocumentInput, signal?: AbortSignal): Promise<DocumentMutationResult> {
    const identity = this.identity(context, signal);
    return this.exclusive(identity, async () => {
      const file = await validateDocumentBytes(input.file); this.current(identity, signal);
      const account = await this.account(identity, signal);
      if (TYPES_DOCUMENTS_EXCLUS_UPLOAD.includes(input.typeDocument)
        || !this.rules(account.profile).some(rule => rule.type_document === input.typeDocument)
        || (input.label?.length ?? 0) > 500) throw new DocumentWorkflowError('INVALID_INPUT', 'Pièce non proposée dans ce dossier fictif.');
      const original = input.replacesDocumentId ? this.active(account, input.replacesDocumentId) : null;
      if (original && original.type_document !== input.typeDocument) scope();
      if (!original && account.records.some(row => row.type_document === input.typeDocument && !row.supprime_le && !row.revoque_le)) {
        throw new DocumentWorkflowError('INVALID_INPUT', 'Utilise Remplacer pour le justificatif fictif déjà présent.');
      }
      const path = `${identity.userId}/documents/${input.typeDocument}/demo-upload-${account.sequence + 1}-${file.safeName}`;
      try { await input.onPrepared?.({ storageKey: path }); this.current(identity, signal); }
      catch (error) {
        // Same safe boundary as TEST: no synthetic commit has started yet.
        if (input.onPrepared && input.onNotStarted) await input.onNotStarted({ storageKey: path });
        throw error;
      }
      const freshOriginal = input.replacesDocumentId ? this.active(account, input.replacesDocumentId) : null;
      const document = this.makeDocument(identity, account, input.typeDocument, file, input.label?.trim() || 'Simulation — document ajouté', path);
      if (freshOriginal) freshOriginal.revoque_le = this.now().toISOString();
      account.records.push(document);
      const index = this.outcomes.findIndex(item => item.userId === identity.userId && item.typeDocument === input.typeDocument);
      const outcome = index < 0 ? null : this.outcomes.splice(index, 1)[0];
      if (outcome?.kind === 'uncertain_committed') return { kind: 'unconfirmed', dossier: null, document: null,
        message: 'Simulation : réponse interrompue après l’enregistrement fictif. Vérifie l’envoi précédent.', reconciliation: { storageKey: path } };
      return { kind: 'confirmed', dossier: this.snapshot(identity, account), document: clone(document),
        message: 'Simulation : fichier enregistré en mémoire, sans envoi réel. Sa vérification reste une étape distincte.' };
    });
  }
  async reconcileUpload(context: DocumentContext, storageKey: string, signal?: AbortSignal): Promise<DocumentMutationResult> {
    const identity = this.identity(context, signal);
    if (!storageKey.startsWith(`${identity.userId}/documents/`) || storageKey.includes('..')) scope();
    const account = await this.account(identity, signal);
    const document = account.records.find(row => row.s3_cle === storageKey && !row.supprime_le && !row.revoque_le);
    return { kind: document ? 'confirmed' : 'unconfirmed', dossier: this.snapshot(identity, account), document: document ? clone(document) : null,
      message: document ? 'Simulation : enregistrement fictif retrouvé, sans renvoi du fichier.' : 'Simulation : cet envoi fictif reste non confirmé.',
      ...(document ? {} : { reconciliation: { storageKey } }) };
  }
  async verify(context: DocumentContext, documentId: string, signal?: AbortSignal): Promise<DocumentMutationResult> {
    const identity = this.identity(context, signal);
    return this.exclusive(identity, async () => {
      const account = await this.account(identity, signal); const document = this.active(account, documentId);
      document.statut_verification = 'VERIFIE'; document.motif_rejet = null;
      document.profession_certifiee = document.type_document === 'DIPLOME' ? account.profile.profession : null;
      return { kind: 'confirmed', dossier: this.snapshot(identity, account), document: clone(document),
        message: 'Simulation : statut fictif Vérifié. Aucun contrôle d’identité ou de qualification réel n’a été effectué.' };
    });
  }
  async requestReview(context: DocumentContext, documentId: string, motif: string, signal?: AbortSignal): Promise<DocumentMutationResult> {
    const identity = this.identity(context, signal);
    return this.exclusive(identity, async () => {
      if (motif.trim().length < 10 || motif.length > 1000) throw new DocumentWorkflowError('INVALID_INPUT', 'Le motif fictif doit contenir entre 10 et 1 000 caractères.');
      const account = await this.account(identity, signal); const document = this.active(account, documentId);
      if (!['REJETE', 'EN_ATTENTE', 'API_INDISPONIBLE'].includes(document.statut_verification ?? '')) {
        throw new DocumentWorkflowError('INVALID_INPUT', 'Cette pièce fictive ne nécessite pas cette demande de revue.');
      }
      document.statut_verification = 'REVUE_MANUELLE_REQUISE';
      return { kind: 'confirmed', dossier: this.snapshot(identity, account), document: clone(document),
        message: 'Simulation : demande fictive enregistrée. Aucune demande n’a été transmise à une équipe réelle.' };
    });
  }
  async logicalDelete(context: DocumentContext, documentId: string, signal?: AbortSignal): Promise<DocumentMutationResult> {
    const identity = this.identity(context, signal);
    return this.exclusive(identity, async () => {
      const account = await this.account(identity, signal); const document = this.active(account, documentId);
      document.supprime_le = this.now().toISOString();
      return { kind: 'confirmed', dossier: this.snapshot(identity, account), document: null,
        message: 'Simulation : pièce retirée du dossier actif. Son original fictif reste conservé en mémoire.' };
    });
  }
}
