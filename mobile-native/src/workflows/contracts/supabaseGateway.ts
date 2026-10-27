import type { SupabaseClient } from '@supabase/supabase-js';
import { readSignatureSmsStagingAdmission } from '../../../../src/lib/signatureSmsStagingAdmission';
import { assertConsent, canOfferSignature, CONTRACT_ID, CONTRACTS_STAGING_ORIGIN, hasPartySignature,
  inspectOriginal, matchingRevision, serverIssue, validContractStoragePath } from './business';
import { ContractWorkflowError, type ContractConsent, type ContractContext, type ContractDetails, type ContractGateway,
  type ContractOriginalTransport, type ContractPage, type ContractParty, type ContractRecord, type ContractSignature,
  type ContractSignResult, type OtpRequestResult, type SignContractInput, type StoredContractRecord } from './types';

const SUMMARY = 'id,mission_id,numero_contrat,type_contrat,statut,soignant_id,etablissement_id,signature_soignant,signature_soignant_le,signature_etablissement,signature_etablissement_le,cree_le';
const ORIGINAL = `${SUMMARY},contenu_html,hash_document,storage_path,contenu_html_rendu_le,mode_signature`;
// Column grants intentionally exclude OTP hash, delivery timestamps and counters.
const SIGNATURE = 'id,contrat_id,signataire_user_id,signataire_role,statut_signature,signe_a,otp_valide_a,hash_document,cree_le';
const PAGE_SIZE = 20;
type Reply = { data: any; error: unknown; count?: number | null };
type Identity = { userId: string; authorization: string; party: ContractParty; establishmentId: string | null;
  canSign: boolean; isTestAccount: boolean };
function abort(signal?: AbortSignal): void {
  if (signal?.aborted) throw Object.assign(new Error('Opération interrompue.'), { name: 'AbortError' });
}
function scope(): never { throw new ContractWorkflowError('INVALID_SCOPE', 'Ce contrat ou ce droit ne correspond pas à votre compte.'); }
function unavailable(): never { throw new ContractWorkflowError('UNAVAILABLE', 'Les contrats ne peuvent pas être chargés. Réessayez.'); }
const nullableString = (value: unknown) => value === null || typeof value === 'string';
const nullableDate = (value: unknown) => value === null || typeof value === 'string' && Number.isFinite(Date.parse(value));
const nullableBoolean = (value: unknown) => value === null || typeof value === 'boolean';
function checkedRecord(value: unknown, identity: Identity, full: boolean, requestedId?: string): StoredContractRecord {
  if (!value || typeof value !== 'object' || Array.isArray(value)) scope();
  const row = value as StoredContractRecord;
  if ([row.id, row.mission_id, row.soignant_id, row.etablissement_id].some(id => !CONTRACT_ID.test(id))
    || requestedId && row.id !== requestedId || typeof row.numero_contrat !== 'string' || typeof row.type_contrat !== 'string'
    || !nullableString(row.statut) || !nullableDate(row.cree_le)
    || !nullableBoolean(row.signature_soignant) || !nullableBoolean(row.signature_etablissement)
    || !nullableDate(row.signature_soignant_le) || !nullableDate(row.signature_etablissement_le)
    || (identity.party === 'soignant' ? row.soignant_id !== identity.userId : row.etablissement_id !== identity.establishmentId)) scope();
  if (full && (!nullableString(row.contenu_html) || !nullableString(row.hash_document) || !nullableString(row.storage_path)
    || !nullableDate(row.contenu_html_rendu_le) || !nullableString(row.mode_signature))) scope();
  return row;
}
function checkedSignature(value: unknown, contractId: string): ContractSignature {
  if (!value || typeof value !== 'object' || Array.isArray(value)) scope();
  const row = value as ContractSignature;
  if (!CONTRACT_ID.test(row.id) || !CONTRACT_ID.test(row.signataire_user_id) || row.contrat_id !== contractId
    || !['soignant', 'etablissement'].includes(row.signataire_role) || typeof row.statut_signature !== 'string'
    || !nullableString(row.hash_document)
    || ['signe_a', 'otp_valide_a', 'cree_le'].some(key => !nullableDate(row[key as keyof ContractSignature]))) scope();
  return row;
}
function signatureConfirmed(details: ContractDetails, userId: string, hash: string): boolean {
  const contract = details.record;
  const flag = details.party === 'soignant' ? contract.signature_soignant : contract.signature_etablissement;
  const date = details.party === 'soignant' ? contract.signature_soignant_le : contract.signature_etablissement_le;
  return flag === true && !!date && details.original?.sha256 === hash && details.signatures.some(signature =>
    signature.signataire_user_id === userId && signature.signataire_role === details.party
    && signature.statut_signature === 'signe' && !!signature.signe_a && !!signature.otp_valide_a && signature.hash_document === hash);
}

/** STAGING ordinary-user transport. No generator, direct UPDATE, canvas fallback, provider or admin API. */
export class SupabaseContractGateway implements ContractGateway {
  readonly mode = 'supabase' as const;
  private readonly inFlight = new Set<string>();
  constructor(private readonly client: SupabaseClient, private readonly originals: ContractOriginalTransport,
    private readonly digestUtf8: (html: string) => Promise<string>, private readonly now: () => number = Date.now) {
    const sentinel = new URL(client.storage.from('contrats-signes').getPublicUrl('native-origin-check').data.publicUrl);
    if (sentinel.origin !== CONTRACTS_STAGING_ORIGIN || sentinel.pathname !== '/storage/v1/object/public/contrats-signes/native-origin-check'
      || sentinel.username || sentinel.password || sentinel.search || sentinel.hash) scope();
  }
  private async current(identity: Pick<Identity, 'userId'>, signal?: AbortSignal): Promise<void> {
    abort(signal); const session = await this.client.auth.getSession(); abort(signal);
    if (session.error || !session.data.session?.access_token || session.data.session.user.id !== identity.userId) {
      throw new ContractWorkflowError('SESSION_CHANGED', 'Votre session a changé. Revenez à votre espace avant de continuer.');
    }
  }
  private async rpc(identity: Identity, name: string, args: Record<string, unknown>, signal?: AbortSignal): Promise<Reply> {
    await this.current(identity, signal); let result: Reply;
    try {
      let request = this.client.rpc(name, args).setHeader('Authorization', identity.authorization);
      if (signal) request = request.abortSignal(signal);
      abort(signal); result = await request;
    } catch { result = { data: null, error: true }; }
    await this.current(identity, signal); return result;
  }
  private async identity(context: ContractContext, signal?: AbortSignal): Promise<Identity> {
    if (!context || !CONTRACT_ID.test(context.userId) || !['soignant', 'etablissement'].includes(context.kind)
      || context.kind === 'etablissement' && !CONTRACT_ID.test(context.etablissementId)) scope();
    const frozen = { ...context }; abort(signal);
    const session = await this.client.auth.getSession(); abort(signal);
    const token = session.data.session?.access_token;
    if (session.error || !token || session.data.session?.user.id !== frozen.userId) {
      throw new ContractWorkflowError('SESSION_CHANGED', 'Reconnectez-vous pour consulter vos contrats.');
    }
    const auth = await this.client.auth.getUser(token); abort(signal);
    if (auth.error || auth.data.user?.id !== frozen.userId || !auth.data.user.email_confirmed_at) scope();
    const identity: Identity = { userId: frozen.userId, authorization: `Bearer ${token}`, party: frozen.kind,
      establishmentId: frozen.kind === 'etablissement' ? frozen.etablissementId : null, canSign: false, isTestAccount: false };
    const role = await this.rpc(identity, 'fn_get_my_role', {}, signal);
    if (role.error || !role.data || role.data.parcours_incomplet === true
      || role.data.user_id && role.data.user_id !== identity.userId) scope();
    if (frozen.kind === 'soignant') {
      if (role.data.role !== 'SOIGNANT') scope(); identity.canSign = true;
    } else {
      if (!['ADMIN_ETABLISSEMENT', 'ETABLISSEMENT'].includes(role.data.role)
        || role.data.etablissement_id && role.data.etablissement_id !== frozen.etablissementId) scope();
      const resolved = await this.rpc(identity, 'fn_mes_permissions_etab', { p_etablissement_id: frozen.etablissementId }, signal);
      if (resolved.error || resolved.data?.success !== true || resolved.data.etablissement_id !== frozen.etablissementId
        || typeof resolved.data.role !== 'string' || !resolved.data.role) scope();
      // General lecture and the permissions JSON do not establish lecture_contrats.
      const lecture = await this.rpc(identity, 'fn_a_permission_etablissement', {
        p_permission: 'lecture_contrats', p_etablissement_id: frozen.etablissementId,
      }, signal);
      if (lecture.error || lecture.data !== true) scope();
      const signature = await this.rpc(identity, 'fn_a_permission_etablissement', {
        p_permission: 'contrats', p_etablissement_id: frozen.etablissementId,
      }, signal);
      if (signature.error || typeof signature.data !== 'boolean') unavailable(); identity.canSign = signature.data;
    }
    let profile = this.client.from(identity.party === 'soignant' ? 'soignants' : 'etablissements')
      .select('id,est_compte_test').eq('id', identity.establishmentId ?? identity.userId).setHeader('Authorization', identity.authorization);
    if (signal) profile = profile.abortSignal(signal);
    const result = await profile.maybeSingle(); await this.current(identity, signal);
    if (result.error || result.data?.id !== (identity.establishmentId ?? identity.userId)) scope();
    identity.isTestAccount = result.data.est_compte_test === true;
    return identity;
  }
  private scopedQuery(identity: Identity, projection: string) {
    return this.client.from('contrats_mission').select(projection)
      .eq(identity.party === 'soignant' ? 'soignant_id' : 'etablissement_id', identity.establishmentId ?? identity.userId)
      .setHeader('Authorization', identity.authorization);
  }
  private async record(identity: Identity, id: string, signal?: AbortSignal): Promise<StoredContractRecord> {
    if (!CONTRACT_ID.test(id)) scope(); await this.current(identity, signal);
    let query = this.scopedQuery(identity, ORIGINAL).eq('id', id); if (signal) query = query.abortSignal(signal);
    const response = await query.maybeSingle(); await this.current(identity, signal);
    if (response.error || !response.data) unavailable(); return checkedRecord(response.data, identity, true, id);
  }
  async list(context: ContractContext, page = 0, signal?: AbortSignal): Promise<ContractPage> {
    context = { ...context };
    if (!Number.isSafeInteger(page) || page < 0 || page > 100_000) throw new ContractWorkflowError('INVALID_INPUT', 'Page de contrats invalide.');
    const identity = await this.identity(context, signal);
    let query = this.client.from('contrats_mission').select(SUMMARY, { count: 'exact' })
      .eq(identity.party === 'soignant' ? 'soignant_id' : 'etablissement_id', identity.establishmentId ?? identity.userId)
      .order('cree_le', { ascending: false, nullsFirst: false }).order('id', { ascending: false })
      .range(page * PAGE_SIZE, (page + 1) * PAGE_SIZE - 1).setHeader('Authorization', identity.authorization);
    if (signal) query = query.abortSignal(signal);
    const response = await query; await this.current(identity, signal);
    if (response.error || !Array.isArray(response.data) || !Number.isSafeInteger(response.count) || response.count! < 0
      || response.data.length !== Math.min(PAGE_SIZE, Math.max(0, response.count! - page * PAGE_SIZE))) unavailable();
    const rows: ContractRecord[] = response.data.map(row => checkedRecord(row, identity, false));
    if (new Set(rows.map(row => row.id)).size !== rows.length) scope();
    return { rows, page, total: response.count!, nextPage: (page + 1) * PAGE_SIZE < response.count! ? page + 1 : null };
  }
  private async readWithIdentity(identity: Identity, id: string, signal?: AbortSignal): Promise<ContractDetails> {
    const record = await this.record(identity, id, signal);
    let proof = this.client.from('signatures_contrats').select(SIGNATURE, { count: 'exact' }).eq('contrat_id', id)
      .order('cree_le', { ascending: true }).order('id', { ascending: true }).range(0, 99).setHeader('Authorization', identity.authorization);
    if (signal) proof = proof.abortSignal(signal);
    const proofs = await proof; await this.current(identity, signal);
    if (proofs.error || !Array.isArray(proofs.data) || proofs.count !== proofs.data.length) unavailable();
    const signatures = proofs.data.map(row => checkedSignature(row, id));
    if (new Set(signatures.map(row => row.id)).size !== signatures.length) scope();
    const before = await this.rpc(identity, 'fn_contrat_storage_path', { p_contrat_id: id }, signal);
    if (before.error || before.data?.success !== true) scope();
    if (before.data.storage_path !== record.storage_path || before.data.hash_document !== record.hash_document
      || before.data.rendu_le !== record.contenu_html_rendu_le) throw new ContractWorkflowError('DOCUMENT_CHANGED', 'Le contrat a changé. Rechargez son original.');
    let inspected: Pick<ContractDetails, 'original' | 'originalIssue'> = { original: null, originalIssue: 'unprepared' };
    if (record.storage_path && record.contenu_html && record.hash_document && record.contenu_html_rendu_le) {
      if (!validContractStoragePath(record.storage_path, id)) inspected = { original: null, originalIssue: 'unavailable' };
      else {
        let bytes: Uint8Array | undefined;
        try {
          bytes = await this.originals.read({ contractId: id, storagePath: record.storage_path, authorization: identity.authorization, signal });
          await this.current(identity, signal);
          inspected = await inspectOriginal(record, signatures, this.digestUtf8, bytes); await this.current(identity, signal);
        } catch (error) {
          await this.current(identity, signal);
          inspected = { original: null, originalIssue: 'unavailable' };
        } finally { bytes?.fill(0); }
      }
    }
    // Re-authorize under the captured JWT and compare the immutable revision after Storage GET.
    const after = await this.rpc(identity, 'fn_contrat_storage_path', { p_contrat_id: id }, signal);
    if (after.error || after.data?.success !== true) scope();
    const reread = await this.record(identity, id, signal);
    if (after.data.storage_path !== record.storage_path || after.data.hash_document !== record.hash_document
      || after.data.rendu_le !== record.contenu_html_rendu_le || reread.contenu_html !== record.contenu_html
      || reread.hash_document !== record.hash_document || reread.storage_path !== record.storage_path
      || reread.contenu_html_rendu_le !== record.contenu_html_rendu_le) {
      throw new ContractWorkflowError('DOCUMENT_CHANGED', 'Le contrat a changé. Rechargez son original.');
    }
    const otpAdmission = identity.isTestAccount && inspected.original ? await readSignatureSmsStagingAdmission({
      rpc: (name, args) => this.rpc(identity, name, args, signal),
    }, CONTRACTS_STAGING_ORIGIN, id, this.now()) : null;
    await this.current(identity, signal);
    return { userId: identity.userId, party: identity.party, record: reread, signatures, ...inspected,
      permissions: { read: true, sign: identity.canSign }, isTestAccount: identity.isTestAccount, otpAdmission };
  }
  async read(context: ContractContext, contractId: string, signal?: AbortSignal): Promise<ContractDetails> {
    context = { ...context };
    return this.readWithIdentity(await this.identity(context, signal), contractId, signal);
  }
  private async exclusive<T>(context: ContractContext, id: string, operation: () => Promise<T>): Promise<T> {
    const key = `${context.userId}:${id}`;
    if (this.inFlight.has(key)) throw new ContractWorkflowError('BUSY', 'Une demande est déjà en cours. Patientez puis rechargez le contrat.');
    this.inFlight.add(key); try { return await operation(); } finally { this.inFlight.delete(key); }
  }
  private assertAction(details: ContractDetails, input: ContractConsent, action: 'send' | 'sign'): void {
    if (!matchingRevision(details.original, input.revision)) throw new ContractWorkflowError('ORIGINAL_UNAVAILABLE', 'L’original affiché doit être rechargé avant de signer.');
    if (!canOfferSignature(details)) throw new ContractWorkflowError('SIGNATURE_UNAVAILABLE', 'La signature n’est pas disponible pour ce contrat et ce compte.');
    const admission = details.otpAdmission;
    if (!admission || admission.expiresAt <= this.now() || (action === 'send' ? !admission.canSend
      : !admission.canValidate || !admission.otpExpiresAt || admission.otpExpiresAt <= this.now())) {
      throw new ContractWorkflowError('TEST_NOT_ADMITTED', 'Cette demande de signature n’est pas autorisée par la recette TEST actuelle.');
    }
  }
  private async fresh(context: ContractContext, id: string, identity: Identity, signal?: AbortSignal): Promise<ContractDetails | null> {
    try { return await this.read(context, id, signal); }
    catch { await this.current(identity, signal); return null; }
  }
  async requestOtp(context: ContractContext, input: ContractConsent, signal?: AbortSignal): Promise<OtpRequestResult> {
    assertConsent(input); abort(signal);
    context = { ...context }; input = { accepted: true, revision: { ...input.revision } };
    return this.exclusive(context, input.revision.contractId, async () => {
      const identity = await this.identity(context, signal);
      const before = await this.readWithIdentity(identity, input.revision.contractId, signal);
      this.assertAction(before, input, 'send');
      const response = await this.rpc(identity, 'fn_envoyer_otp_signature', { p_contrat_id: input.revision.contractId }, signal);
      const contract = await this.fresh(context, input.revision.contractId, identity, signal);
      const issue = serverIssue(response.data);
      const own = contract?.signatures.find(row => row.signataire_user_id === identity.userId && row.signataire_role === identity.party);
      const queued = !response.error && response.data?.success === true && response.data.role === identity.party
        && !!contract && matchingRevision(contract.original, input.revision) && !!contract.otpAdmission?.canValidate
        && own?.statut_signature === 'otp_envoye'
        && Number.isInteger(response.data.sms_envoyes) && response.data.sms_envoyes > 0 && response.data.sms_envoyes <= 3;
      const phone = response.data?.telephone_masked;
      return { kind: queued ? 'queued' : issue ? 'rejected' : 'unconfirmed', delivery: 'unverified', contract, issue,
        phoneMasked: queued && typeof phone === 'string' && phone.length <= 80 && phone.includes('*')
          && (phone.match(/\d/g)?.length ?? 0) <= 4 ? phone : null,
        expiresAt: queued ? contract!.otpAdmission!.otpExpiresAt : null,
        sendsRemaining: queued && Number.isInteger(response.data.sms_restants) && response.data.sms_restants >= 0
          && response.data.sms_restants <= 3 ? response.data.sms_restants : null,
        message: queued ? 'La demande de code est enregistrée. Attendez le SMS avant de saisir le code ; sa réception n’est pas encore confirmée.'
          : issue?.message ?? 'La demande de code ne peut pas être confirmée. Relisez l’état du contrat avant tout nouvel envoi.' };
    });
  }
  async sign(context: ContractContext, input: SignContractInput, signal?: AbortSignal): Promise<ContractSignResult> {
    assertConsent(input); abort(signal);
    if (!/^[0-9]{6}$/.test(input.code)) throw new ContractWorkflowError('INVALID_INPUT', 'Saisissez le code SMS à six chiffres.');
    context = { ...context }; input = { accepted: true, revision: { ...input.revision }, code: input.code };
    return this.exclusive(context, input.revision.contractId, async () => {
      const identity = await this.identity(context, signal);
      const before = await this.readWithIdentity(identity, input.revision.contractId, signal);
      if (hasPartySignature(before.record, before.party)) return { kind: 'already_signed', contract: before, issue: null,
        message: 'Votre signature est déjà enregistrée. Aucun nouvel acte de signature n’a été envoyé.' };
      this.assertAction(before, input, 'sign');
      const response = await this.rpc(identity, 'fn_signer_contrat_otp', {
        p_contrat_id: input.revision.contractId, p_otp_code: input.code,
        p_hash_document: input.revision.sha256, p_signature_image: null,
      }, signal);
      const contract = await this.fresh(context, input.revision.contractId, identity, signal);
      const issue = serverIssue(response.data);
      const confirmed = !!contract && matchingRevision(contract.original, input.revision)
        && signatureConfirmed(contract, identity.userId, input.revision.sha256);
      return { kind: confirmed ? 'confirmed' : issue ? 'rejected' : 'unconfirmed', contract, issue: confirmed ? null : issue,
        message: confirmed ? 'Votre signature est enregistrée et sa preuve a été relue.'
          : issue?.message ?? 'La signature ne peut pas être confirmée. Rechargez son état ; ne renvoyez pas automatiquement le code.' };
    });
  }
}
