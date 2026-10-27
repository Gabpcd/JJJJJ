import type { SupabaseClient } from '@supabase/supabase-js';
import { TYPES_DOCUMENTS, TYPES_DOCUMENTS_EXCLUS_UPLOAD } from '../../../../src/lib/documents';
import { validateDocumentBytes } from './bytes';
import { visibleDocumentRequirements } from './requirements';
import { DocumentWorkflowError, type CaregiverDocument, type DocumentContext, type DocumentDossier,
  type DocumentGateway, type DocumentMutationResult, type DocumentOriginal, type DocumentProfile,
  type DocumentRequirement, type OriginalSigningTransport, type UploadDocumentInput } from './types';

const BUCKET = 'jolene-documents';
const ALLOWED_ORIGIN = 'https://mejpriaetwgtcstbgfid.supabase.co';
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const PROFILE = 'id,profession,prenom,nom,type_exercice,rpps_verifie,adeli_verifie,attestation_sante_signee_le';
// As in the web client, an explicit runtime string avoids pathological recursive PostgREST projection types.
const DOCUMENT: string = 'id,soignant_id,type_document,nom_fichier,statut_verification,valide_depuis,valide_jusqua,televerse_le,motif_rejet,est_critique,s3_cle,s3_bucket,type_mime,taille_octets,libelle,profession_certifiee:resultat_ia->>profession_certifiee,supprime_le,revoque_le';
const REQUIREMENT = 'id,profession,type_document,description,a_expiration,duree_validite_mois,est_critique,type_exercice_requis';
const UNCONFIRMED = 'Le résultat ne peut pas être confirmé. Rechargez les documents avant de réessayer.';
type Identity = { userId: string; authorization: string };
type Response = { data: any; error: unknown };

function abort(signal?: AbortSignal): void {
  if (signal?.aborted) { const error = new Error('Opération interrompue.'); error.name = 'AbortError'; throw error; }
}
function scope(message = 'Le document ne correspond pas à votre compte.'): never {
  throw new DocumentWorkflowError('INVALID_SCOPE', message);
}
function unavailable(): never { throw new DocumentWorkflowError('UNAVAILABLE', 'Vos documents sont temporairement indisponibles. Réessayez.'); }
function checkedId(value: string): void { if (!UUID.test(value)) scope(); }
function checkedPath(path: string, userId: string, type?: string): void {
  const parts = path.split('/');
  if (path.length > 512 || parts.length !== 4 || parts[0] !== userId || parts[1] !== 'documents'
    || !/^[A-Z][A-Z0-9_]*$/.test(parts[2] ?? '') || (type && parts[2] !== type)
    || !/^[A-Za-z0-9._-]+$/.test(parts[3] ?? '') || path.includes('..')) scope();
}
function checkedDocument(value: unknown, userId: string): CaregiverDocument {
  if (!value || typeof value !== 'object') scope();
  const row = value as CaregiverDocument;
  if (!UUID.test(row.id) || row.soignant_id !== userId || row.s3_bucket !== BUCKET
    || typeof row.s3_cle !== 'string' || typeof row.type_document !== 'string'
    || typeof row.nom_fichier !== 'string' || (row.statut_verification !== null && typeof row.statut_verification !== 'string')
    || (row.televerse_le !== null && typeof row.televerse_le !== 'string')
    || (row.taille_octets !== null && typeof row.taille_octets !== 'number')
    || (row.type_mime !== null && typeof row.type_mime !== 'string')) scope();
  checkedPath(row.s3_cle, userId, row.type_document);
  return row;
}
function rejected(response: Response): boolean {
  return !response.error && (response.data?.success === false || !!response.data?.error_code || !!response.data?.error);
}

/** Ordinary authenticated client from nativeRuntime. No privileged keys, metadata grants or production fallback. */
export class SupabaseDocumentGateway implements DocumentGateway {
  readonly mode = 'supabase' as const;
  private readonly inFlight = new Set<string>();
  constructor(private readonly client: SupabaseClient, private readonly newId: () => string,
    private readonly originalSigner: OriginalSigningTransport,
    private readonly now: () => Date = () => new Date()) {
    // This SDK method only formats a URL locally. The sentinel is never requested or used as a document URL.
    // Check the actual injected Storage target rather than trusting a caller-supplied "staging" flag.
    const sentinel = client.storage.from(BUCKET).getPublicUrl('native-origin-check').data.publicUrl;
    const url = new URL(sentinel);
    if (url.origin !== ALLOWED_ORIGIN || url.pathname !== `/storage/v1/object/public/${BUCKET}/native-origin-check`
      || url.username || url.password || url.search || url.hash) scope('Ce serveur n’est pas autorisé pour la recette native.');
  }

  private async current(identity: Pick<Identity, 'userId'>, signal?: AbortSignal): Promise<void> {
    abort(signal);
    const session = await this.client.auth.getSession(); abort(signal);
    if (session.error || !session.data.session?.access_token || session.data.session.user.id !== identity.userId) {
      throw new DocumentWorkflowError('SESSION_CHANGED', 'Votre session a changé. Revenez à votre espace avant de continuer.');
    }
  }

  private async identity(context: DocumentContext, signal?: AbortSignal): Promise<Identity> {
    checkedId(context.userId); abort(signal);
    const session = await this.client.auth.getSession(); abort(signal);
    const token = session.data.session?.access_token;
    if (session.error || !token || session.data.session?.user.id !== context.userId) {
      throw new DocumentWorkflowError('SESSION_CHANGED', 'Reconnectez-vous pour accéder à vos documents.');
    }
    const user = await this.client.auth.getUser(token); abort(signal);
    if (user.error || user.data.user?.id !== context.userId) scope('L’identité de la session ne peut pas être vérifiée.');
    const identity = { userId: context.userId, authorization: `Bearer ${token}` };
    await this.current(identity, signal);
    let query = this.client.rpc('fn_get_my_role').setHeader('Authorization', identity.authorization);
    if (signal) query = query.abortSignal(signal);
    const role = await query;
    await this.current(identity, signal);
    if (role.error || role.data?.role !== 'SOIGNANT' || (role.data.user_id && role.data.user_id !== context.userId)) scope();
    return identity;
  }

  private async dossier(identity: Identity, signal?: AbortSignal): Promise<DocumentDossier> {
    await this.current(identity, signal);
    let profileQuery = this.client.from('soignants').select(PROFILE).eq('id', identity.userId)
      .setHeader('Authorization', identity.authorization);
    if (signal) profileQuery = profileQuery.abortSignal(signal);
    const profileResponse = await profileQuery.maybeSingle();
    await this.current(identity, signal);
    if (profileResponse.error) unavailable();
    if (!profileResponse.data) return { userId: identity.userId, profile: null, documents: [], requirements: [] };
    const profile = profileResponse.data as DocumentProfile;
    if (profile.id !== identity.userId) scope();
    const documents: CaregiverDocument[] = [];
    let expectedCount: number | null = null;
    for (let page = 0; page < 100; page++) {
      let query = this.client.from('documents_soignants').select(DOCUMENT, { count: 'exact' })
        .eq('soignant_id', identity.userId).is('supprime_le', null).is('revoque_le', null)
        .order('televerse_le', { ascending: false }).order('id', { ascending: false }).range(page * 100, page * 100 + 99)
        .setHeader('Authorization', identity.authorization);
      if (signal) query = query.abortSignal(signal);
      const result = await query;
      await this.current(identity, signal);
      if (result.error || !Array.isArray(result.data) || typeof result.count !== 'number'
        || (expectedCount !== null && result.count !== expectedCount)) unavailable();
      expectedCount = result.count;
      for (const item of result.data) {
        const row = checkedDocument(item, identity.userId);
        if (row.supprime_le !== null || row.revoque_le !== null || documents.some(existing => existing.id === row.id)) unavailable();
        documents.push(row);
      }
      if (documents.length === expectedCount) break;
      if (!result.data.length || documents.length > expectedCount) unavailable();
    }
    if (documents.length !== expectedCount) unavailable();
    let requirements: DocumentRequirement[] = [];
    if (profile.profession) {
      let query = this.client.from('documents_requis_par_profession').select(REQUIREMENT, { count: 'exact' })
        .eq('profession', profile.profession).order('id', { ascending: true }).range(0, 999)
        .setHeader('Authorization', identity.authorization);
      if (signal) query = query.abortSignal(signal);
      const result = await query;
      await this.current(identity, signal);
      if (result.error || !Array.isArray(result.data) || result.count !== result.data.length
        || result.data.some(row => row.profession !== profile.profession)) unavailable();
      requirements = visibleDocumentRequirements(profile, result.data as DocumentRequirement[]);
    }
    return { userId: identity.userId, profile, documents, requirements };
  }

  async readDossier(context: DocumentContext, signal?: AbortSignal): Promise<DocumentDossier> {
    return this.dossier(await this.identity(context, signal), signal);
  }

  async getOriginal(context: DocumentContext, documentId: string, signal?: AbortSignal): Promise<DocumentOriginal> {
    const identity = await this.identity(context, signal);
    const document = await this.active(identity, documentId, signal);
    const started = this.now().getTime();
    const expiresIn = 3600; // Existing web consultation TTL; never cache beyond this local deadline.
    const uri = await this.originalSigner.sign({ storageKey: document.s3_cle,
      authorization: identity.authorization, expiresIn, signal });
    await this.current(identity, signal);
    let url: URL;
    try { url = new URL(uri); } catch { unavailable(); }
    let decodedPath: string;
    try { decodedPath = decodeURIComponent(url.pathname); } catch { unavailable(); }
    if (url.origin !== ALLOWED_ORIGIN || url.username || url.password || url.hash
      || decodedPath !== `/storage/v1/object/sign/${BUCKET}/${document.s3_cle}`
      || !url.searchParams.get('token') || [...url.searchParams.keys()].some(key => key !== 'token')) scope();
    const fresh = await this.active(identity, documentId, signal);
    if (fresh.s3_cle !== document.s3_cle || fresh.s3_bucket !== document.s3_bucket) scope();
    const audit = await this.rpc(identity, 'fn_ecrire_audit_safe', {
      p_acteur_id: identity.userId, p_type_acteur: 'SOIGNANT', p_action: 'DOCUMENT_CONSULTATION',
      p_type_ressource: 'document', p_id_ressource: documentId, p_cle_s3: document.s3_cle,
      p_details: { type_document: document.type_document }, p_ip: null, p_navigateur: 'Jolene React Native',
    }, signal);
    if (audit.error || rejected(audit) || this.now().getTime() >= started + expiresIn * 1000) unavailable();
    await this.current(identity, signal);
    return { uri, mime: document.type_mime || 'application/octet-stream', fileName: document.nom_fichier,
      expiresAt: new Date(started + expiresIn * 1000).toISOString() };
  }

  private async active(identity: Identity, documentId: string, signal?: AbortSignal): Promise<CaregiverDocument> {
    checkedId(documentId); await this.current(identity, signal);
    let query = this.client.from('documents_soignants').select(DOCUMENT).eq('id', documentId)
      .eq('soignant_id', identity.userId).is('supprime_le', null).is('revoque_le', null)
      .setHeader('Authorization', identity.authorization);
    if (signal) query = query.abortSignal(signal);
    const result = await query.maybeSingle();
    await this.current(identity, signal);
    if (result.error) unavailable();
    if (!result.data) scope('Ce document a été remplacé ou supprimé. Rechargez votre dossier.');
    const document = checkedDocument(result.data, identity.userId);
    if (document.id !== documentId || document.supprime_le !== null || document.revoque_le !== null) scope();
    return document;
  }

  private async fresh(identity: Identity, signal?: AbortSignal): Promise<DocumentDossier | null> {
    try { return await this.dossier(identity, signal); }
    catch (error) {
      // Never turn a change of account or a cancelled view into an actionable response.
      abort(signal);
      if (error instanceof DocumentWorkflowError && ['SESSION_CHANGED', 'INVALID_SCOPE'].includes(error.code)) throw error;
      return null;
    }
  }

  private async exclusive<T>(context: DocumentContext, work: () => Promise<T>): Promise<T> {
    checkedId(context.userId);
    if (this.inFlight.has(context.userId)) throw new DocumentWorkflowError('BUSY', 'Une opération documentaire est déjà en cours.');
    this.inFlight.add(context.userId);
    try { return await work(); } finally { this.inFlight.delete(context.userId); }
  }

  private async rpc(identity: Identity, name: string, args: Record<string, unknown>, signal?: AbortSignal): Promise<Response> {
    await this.current(identity, signal);
    let response: Response;
    try {
      let query = this.client.rpc(name, args).setHeader('Authorization', identity.authorization);
      if (signal) query = query.abortSignal(signal);
      response = await query;
    } catch { response = { data: null, error: true }; }
    await this.current(identity, signal);
    return response;
  }

  async upload(context: DocumentContext, input: UploadDocumentInput, signal?: AbortSignal): Promise<DocumentMutationResult> {
    return this.exclusive(context, async () => {
      if (!/^[A-Z][A-Z0-9_]{1,79}$/.test(input.typeDocument) || TYPES_DOCUMENTS_EXCLUS_UPLOAD.includes(input.typeDocument)
        || (input.label?.length ?? 0) > 500) throw new DocumentWorkflowError('INVALID_INPUT', 'Ce type de pièce ou son libellé est invalide.');
      const file = await validateDocumentBytes(input.file); abort(signal);
      const identity = await this.identity(context, signal);
      const before = await this.dossier(identity, signal);
      if (!before.profile) scope('Complétez votre profil avant de transmettre un document.');
      // Server rules can introduce a legitimate proof type before its display label is added locally.
      if (!Object.hasOwn(TYPES_DOCUMENTS, input.typeDocument)
        && !before.requirements.some(rule => rule.type_document === input.typeDocument)
        && !before.documents.some(document => document.type_document === input.typeDocument)) {
        throw new DocumentWorkflowError('INVALID_INPUT', 'Ce type de document n’est pas disponible dans votre dossier.');
      }
      if (input.replacesDocumentId) {
        const original = await this.active(identity, input.replacesDocumentId, signal);
        if (original.type_document !== input.typeDocument) scope();
      }
      const uploadId = this.newId(); checkedId(uploadId);
      const path = `${identity.userId}/documents/${input.typeDocument}/${uploadId}-${file.safeName}`;
      checkedPath(path, identity.userId, input.typeDocument);
      const bucket = this.client.storage.from(BUCKET);
      try {
        // Persistence can succeed before its read-back rejects. Storage still has
        // not been invoked, so the same exact local receipt is safe to clear.
        await input.onPrepared?.({ storageKey: path });
        await this.current(identity, signal); abort(signal);
      }
      catch (cause) {
        // This is the sole pre-Storage boundary. Cleanup is local and remains valid after
        // logout/unmount. Once upload() is invoked below its outcome may be uncertain.
        if (input.onPrepared && input.onNotStarted) {
          try { await input.onNotStarted({ storageKey: path }); }
          catch (cleanupCause) {
            const reason = cause instanceof Error ? cause.message : 'L’envoi a été interrompu.';
            throw Object.assign(new DocumentWorkflowError('UNAVAILABLE',
              `${reason} Aucun envoi n’a commencé, mais le reçu local n’a pas pu être effacé. Le reçu reste conservé.`),
            { cause, cleanupCause, reconciliation: { storageKey: path } });
          }
        }
        throw cause;
      }
      let storage: Response;
      try {
        storage = await bucket.upload(path, file.bytes, {
          contentType: file.mime, upsert: false, cacheControl: '0', headers: { Authorization: identity.authorization },
        });
      } catch { storage = { data: null, error: true }; }
      await this.current(identity, signal);
      if (storage.error || !storage.data || storage.data.path !== path) {
        return { kind: 'unconfirmed', dossier: await this.fresh(identity, signal), document: null,
          message: 'Le téléversement ne peut pas être confirmé. L’ancienne pièce est conservée.', reconciliation: { storageKey: path } };
      }
      // Re-check the displayed original. The server still owns atomic replacement of its proof class.
      if (input.replacesDocumentId) await this.active(identity, input.replacesDocumentId, signal);
      const response = await this.rpc(identity, 'fn_remplacer_document_soignant', {
        p_type_document: input.typeDocument, p_libelle: input.label?.trim() ?? '', p_s3_cle: path,
        p_nom_fichier: file.originalName, p_type_mime: file.mime, p_taille_octets: file.size,
      }, signal);
      const dossier = await this.fresh(identity, signal);
      const document = dossier?.documents.find(row => row.s3_cle === path) ?? null;
      if (document && (!response.data?.document_id || response.data.document_id === document.id)) {
        return { kind: 'confirmed', dossier, document, message: 'Document reçu. Son statut de vérification est affiché dans votre dossier.' };
      }
      // No destructive cleanup after a timeout: the transaction may have committed without its response.
      // Originals and uploaded objects stay intact; reconcileUpload is read-only.
      return { kind: rejected(response) ? 'rejected' : 'unconfirmed', dossier, document: null,
        message: rejected(response) ? 'Le serveur a refusé l’enregistrement. Rechargez votre dossier.' : UNCONFIRMED,
        reconciliation: { storageKey: path } };
    });
  }

  async reconcileUpload(context: DocumentContext, storageKey: string, signal?: AbortSignal): Promise<DocumentMutationResult> {
    checkedPath(storageKey, context.userId);
    const dossier = await this.readDossier(context, signal);
    const document = dossier.documents.find(row => row.s3_cle === storageKey) ?? null;
    return { kind: document ? 'confirmed' : 'unconfirmed', dossier, document,
      message: document ? 'Le document est bien enregistré.' : UNCONFIRMED,
      ...(document ? {} : { reconciliation: { storageKey } }) };
  }

  async verify(context: DocumentContext, documentId: string, signal?: AbortSignal): Promise<DocumentMutationResult> {
    return this.exclusive(context, async () => {
      const identity = await this.identity(context, signal);
      await this.active(identity, documentId, signal);
      await this.current(identity, signal);
      let response: Response;
      try {
        response = await this.client.functions.invoke('verify-document', {
          body: { document_id: documentId }, headers: { Authorization: identity.authorization }, signal,
        });
      } catch { response = { data: null, error: true }; }
      await this.current(identity, signal);
      const dossier = await this.fresh(identity, signal);
      const document = dossier?.documents.find(row => row.id === documentId) ?? null;
      const confirmed = !response.error && !!response.data && !response.data.error && !response.data.error_code
        && response.data.success !== false && !!document;
      return { kind: confirmed ? 'confirmed' : 'unconfirmed', dossier, document,
        message: confirmed ? 'Le statut du document a été actualisé.' : 'La vérification n’a pas pu être confirmée. Le statut relu du serveur est conservé.' };
    });
  }

  async requestReview(context: DocumentContext, documentId: string, motif: string, signal?: AbortSignal): Promise<DocumentMutationResult> {
    return this.exclusive(context, async () => {
      const reason = motif.trim();
      if (reason.length < 10 || reason.length > 1000) throw new DocumentWorkflowError('INVALID_INPUT', 'Le motif doit contenir entre 10 et 1 000 caractères.');
      const identity = await this.identity(context, signal);
      await this.active(identity, documentId, signal);
      const response = await this.rpc(identity, 'fn_demander_revue_document', { p_document_id: documentId, p_motif: reason }, signal);
      const dossier = await this.fresh(identity, signal);
      const document = dossier?.documents.find(row => row.id === documentId) ?? null;
      const confirmed = !response.error && response.data?.success === true && !!response.data.revue_id
        && document?.statut_verification === 'REVUE_MANUELLE_REQUISE';
      return { kind: confirmed ? 'confirmed' : rejected(response) ? 'rejected' : 'unconfirmed', dossier, document,
        message: confirmed ? 'Demande transmise — en attente d’attribution.' : UNCONFIRMED };
    });
  }

  async logicalDelete(context: DocumentContext, documentId: string, signal?: AbortSignal): Promise<DocumentMutationResult> {
    return this.exclusive(context, async () => {
      const identity = await this.identity(context, signal);
      await this.active(identity, documentId, signal);
      await this.current(identity, signal);
      let response: Response;
      try {
        let query = this.client.from('documents_soignants').update({ supprime_le: this.now().toISOString() })
          .eq('id', documentId).eq('soignant_id', identity.userId).is('supprime_le', null).is('revoque_le', null)
          .select('id,soignant_id,supprime_le').setHeader('Authorization', identity.authorization);
        if (signal) query = query.abortSignal(signal);
        response = await query.maybeSingle();
      } catch { response = { data: null, error: true }; }
      await this.current(identity, signal);
      if (response.data && (response.data.id !== documentId || response.data.soignant_id !== identity.userId)) scope();
      const dossier = await this.fresh(identity, signal);
      const confirmed = !response.error && !!response.data?.supprime_le && !!dossier
        && !dossier.documents.some(row => row.id === documentId);
      let warning: string | undefined;
      if (confirmed) {
        const audit = await this.rpc(identity, 'fn_ecrire_audit_safe', {
          p_acteur_id: identity.userId, p_type_acteur: 'SOIGNANT', p_action: 'DOCUMENT_SUPPRESSION',
          p_type_ressource: 'document', p_id_ressource: documentId, p_cle_s3: null, p_details: {},
          p_ip: null, p_navigateur: 'Jolene React Native',
        }, signal);
        if (audit.error || rejected(audit)) warning = 'La suppression est confirmée, mais son journal complémentaire n’a pas pu être confirmé.';
      }
      return { kind: confirmed ? 'confirmed' : 'unconfirmed', dossier, document: null, warning,
        message: confirmed ? 'Document retiré de votre dossier actif. L’original reste conservé dans l’historique.' : UNCONFIRMED };
    });
  }
}
