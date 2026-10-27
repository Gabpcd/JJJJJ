import { assertConsent, canOfferSignature, matchingRevision } from '../workflows/contracts/business';
import { ContractWorkflowError, type ContractContext, type ContractConsent, type ContractDetails, type ContractGateway,
  type ContractPage, type ContractSignResult, type OtpRequestResult, type SignContractInput } from '../workflows/contracts/types';
import { DEMO_CONTRACT_CODE, DEMO_CONTRACT_ID, demoContractHtml } from './demoFixture';

export interface DemoContractSession { context: ContractContext; epoch: number; canRead: boolean; canSign: boolean }
const clone = <T>(value: T): T => JSON.parse(JSON.stringify(value)) as T;
const key = (context: ContractContext) => `${context.kind}:${context.userId}:${context.kind === 'etablissement' ? context.etablissementId : ''}`;

/** Explicit local simulator. There is no API client, fetch, provider or storage port here. */
export class DemoContractGateway implements ContractGateway {
  readonly mode = 'demo' as const;
  private owner: string | null = null;
  private saved: ContractDetails | null = null;
  private busy = false;
  private otpRequested = false;
  private otpExpiry: number | null = null;
  constructor(private readonly options: { currentSession: () => DemoContractSession | null; digestUtf8: (value: string) => Promise<string>;
    uncertainSignature?: boolean; now?: () => number }) {}
  private now() { return (this.options.now ?? Date.now)(); }
  private identity(context: ContractContext, signal?: AbortSignal): DemoContractSession {
    if (signal?.aborted) throw Object.assign(new Error('Lecture fictive interrompue.'), { name: 'AbortError' });
    const current = this.options.currentSession();
    const allowed = context.kind === 'soignant' ? context.userId === 'demo-soignant'
      : context.userId === 'demo-etablissement-user' && context.etablissementId === 'demo-etablissement';
    if (!allowed || !current || key(current.context) !== key(context) || !current.canRead) {
      throw new ContractWorkflowError('INVALID_SCOPE', 'Ce compte ne correspond pas à la démonstration des contrats.');
    }
    return { ...current, context: { ...current.context } };
  }
  private same(identity: DemoContractSession, signal?: AbortSignal) {
    const current = this.identity(identity.context, signal);
    if (current.epoch !== identity.epoch || current.canSign !== identity.canSign) {
      throw new ContractWorkflowError('SESSION_CHANGED', 'La session fictive a changé. Rouvrez le contrat.');
    }
  }
  async read(context: ContractContext, id: string, signal?: AbortSignal): Promise<ContractDetails> {
    const identity = this.identity(context, signal);
    if (id !== DEMO_CONTRACT_ID) throw new ContractWorkflowError('INVALID_SCOPE', 'Contrat fictif introuvable.');
    const owner = `${key(identity.context)}:${identity.epoch}`;
    if (this.owner !== owner) { this.owner = owner; this.otpRequested = false; this.otpExpiry = null; }
    if (!this.saved) {
      const html = demoContractHtml(); const sha256 = await this.options.digestUtf8(html); this.same(identity, signal);
      const path = `${DEMO_CONTRACT_ID}/synthetic.html`;
      const renderedAt = '2026-10-27T10:00:00.000Z';
      if (!this.saved) this.saved = { userId: identity.context.userId, party: identity.context.kind, permissions: { read: true, sign: identity.canSign }, isTestAccount: true,
        record: { id, mission_id: '00000000-0000-4000-8000-000000000022', soignant_id: 'demo-soignant', etablissement_id: 'demo-etablissement',
          numero_contrat: 'DEMO-CONTRAT-001', type_contrat: 'CDD', statut: 'EN_ATTENTE_SIGNATURES', cree_le: renderedAt,
          signature_soignant: false, signature_soignant_le: null, signature_etablissement: false, signature_etablissement_le: null,
          contenu_html: html, hash_document: sha256, storage_path: path, contenu_html_rendu_le: renderedAt, mode_signature: 'OTP' },
        signatures: [], original: { contractId: id, html, sha256, storagePath: path, renderedAt, source: 'synthetic' }, originalIssue: null,
        otpAdmission: null };
    }
    this.same(identity, signal);
    // The synthetic contract is shared by its two parties. Session-specific OTP,
    // identity and permissions are projected afresh and never inherited across actors.
    const detail = clone(this.saved);
    detail.userId = identity.context.userId; detail.party = identity.context.kind;
    detail.permissions = { read: true, sign: identity.canSign };
    detail.otpAdmission = identity.canSign ? { expiresAt: this.now() + 3_600_000, canSend: true,
      canValidate: this.otpRequested && !!this.otpExpiry && this.otpExpiry > this.now(), otpExpiresAt: this.otpExpiry } : null;
    return detail;
  }
  async list(context: ContractContext, page = 0, signal?: AbortSignal): Promise<ContractPage> {
    if (!Number.isInteger(page) || page < 0) throw new ContractWorkflowError('INVALID_INPUT', 'Page fictive invalide.');
    const detail = await this.read(context, DEMO_CONTRACT_ID, signal);
    return { rows: page === 0 ? [detail.record] : [], page, nextPage: null, total: 1 };
  }
  private async admitted(context: ContractContext, input: ContractConsent, signal?: AbortSignal) {
    assertConsent(input); const identity = this.identity(context, signal);
    const detail = await this.read(context, input.revision.contractId, signal); this.same(identity, signal);
    if (!canOfferSignature(detail) || !matchingRevision(detail.original, input.revision)) {
      throw new ContractWorkflowError('SIGNATURE_UNAVAILABLE', 'La signature fictive est indisponible pour cet accès ou cette révision.');
    }
    return { identity, detail };
  }
  async requestOtp(context: ContractContext, input: ContractConsent, signal?: AbortSignal): Promise<OtpRequestResult> {
    if (this.busy) throw new ContractWorkflowError('BUSY', 'Une action fictive est déjà en cours.');
    this.busy = true;
    try {
      const { identity } = await this.admitted(context, input, signal); this.same(identity, signal); this.otpRequested = true; this.otpExpiry = this.now() + 600_000;
      const contract = await this.read(context, DEMO_CONTRACT_ID, signal);
      return { kind: 'queued', delivery: 'unverified', contract, phoneMasked: null, expiresAt: contract.otpAdmission!.otpExpiresAt,
        sendsRemaining: null, issue: null, message: `Simulation locale : code fictif ${DEMO_CONTRACT_CODE}. Aucun SMS n’a été envoyé.` };
    } finally { this.busy = false; }
  }
  async sign(context: ContractContext, input: SignContractInput, signal?: AbortSignal): Promise<ContractSignResult> {
    if (this.busy) throw new ContractWorkflowError('BUSY', 'Une action fictive est déjà en cours.');
    this.busy = true;
    try {
      const { identity, detail } = await this.admitted(context, input, signal); this.same(identity, signal);
      if (!this.otpRequested || !this.otpExpiry || this.otpExpiry <= this.now() || input.code !== DEMO_CONTRACT_CODE) return { kind: 'rejected', contract: detail,
        issue: { code: 'OTP_INCORRECT', message: 'Code fictif incorrect.', retryAt: null, attemptsRemaining: null }, message: 'Code fictif incorrect.' };
      const at = new Date(this.now()).toISOString();
      const record = this.saved!.record;
      if (identity.context.kind === 'soignant') { record.signature_soignant = true; record.signature_soignant_le = at; record.statut = 'SIGNE_SOIGNANT'; }
      else { record.signature_etablissement = true; record.signature_etablissement_le = at; record.statut = 'SIGNE_ETABLISSEMENT'; }
      if (record.signature_soignant && record.signature_etablissement) record.statut = 'SIGNE_COMPLET';
      this.saved!.signatures.push({ id: identity.context.kind === 'soignant' ? '00000000-0000-4000-8000-000000000023' : '00000000-0000-4000-8000-000000000024', contrat_id: record.id, signataire_user_id: identity.context.userId,
        signataire_role: identity.context.kind, statut_signature: 'signe', signe_a: at, otp_valide_a: at, hash_document: input.revision.sha256, cree_le: at });
      this.otpRequested = false; this.otpExpiry = null;
      if (this.options.uncertainSignature) return { kind: 'unconfirmed', contract: null, issue: null,
        message: 'Simulation : réponse interrompue après enregistrement fictif. Actualisez sans recommencer la signature.' };
      return { kind: 'confirmed', contract: await this.read(context, DEMO_CONTRACT_ID, signal), issue: null,
        message: 'Simulation : signature fictive retrouvée après relecture. Aucun contrat réel n’a été signé.' };
    } finally { this.busy = false; }
  }
}
