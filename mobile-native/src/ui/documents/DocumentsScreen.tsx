import { useEffect, useRef, useState } from 'react';
import { ActivityIndicator, Alert, AppState, Pressable, RefreshControl, ScrollView, StyleSheet, Text, View } from 'react-native';
import { useIsFocused } from '@react-navigation/native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { DocumentWorkflowError, type CaregiverDocument, type DocumentContext, type DocumentRequirement } from '../../workflows/documents/types';
import { ActionButton, ErrorNotice, ModeNotice, StatusPanel } from '../components';
import { colors, shared } from '../theme';
import { DocumentMediaError, type DocumentMediaAdapter, type DocumentScreenGateway, type DocumentSelection, type DocumentUploadJournal } from './adapters';
import { DocumentUploadSheet } from './DocumentUploadSheet';
import { displayDate, documentPresentation, documentProgress, documentRows, documentTitle } from './presentation';
import { useDocuments } from './useDocuments';

export interface DocumentsScreenProps {
  context: DocumentContext;
  /** Increment on every session change, including a new session for the same account. */
  sessionEpoch: number;
  gateway: DocumentScreenGateway;
  /** Stable adapter instance for a session. Only implemented capabilities are displayed. */
  media: DocumentMediaAdapter;
  uploadJournal: DocumentUploadJournal;
  onOpenProfile: () => void;
  onExploreMissions: () => void;
  /** Invalidate dependent profile/eligibility reads; this screen never grants eligibility. */
  onDocumentsChanged?: () => void;
}

/** Keying the entire dossier also discards picker drafts and signed URLs on account changes. */
export function DocumentsScreen(props: DocumentsScreenProps) {
  return <DocumentsContent key={`${props.gateway.mode}:${props.context.userId}:${props.sessionEpoch}`} {...props} />;
}

type UploadTarget = { type: string; replacesDocumentId?: string };

function DocumentsContent({ context, gateway, media, uploadJournal, onOpenProfile, onExploreMissions, onDocumentsChanged }: DocumentsScreenProps) {
  const state = useDocuments(gateway, context, uploadJournal);
  const focused = useIsFocused();
  const [target, setTarget] = useState<UploadTarget | null>(null);
  const [uploadError, setUploadError] = useState<string | null>(null);
  const [viewError, setViewError] = useState<string | null>(null);
  const [viewing, setViewing] = useState<string | null>(null);
  const [watch, setWatch] = useState<{ id: string; until: number } | null>(null);
  const originalRequest = useRef<AbortController | null>(null);
  const alive = useRef(true);
  const scroll = useRef<ScrollView | null>(null);
  const submitLock = useRef(false);
  useEffect(() => { alive.current = true; return () => { alive.current = false; originalRequest.current?.abort(); }; }, []);
  useEffect(() => {
    if (focused) return;
    setTarget(null); setUploadError(null);
    originalRequest.current?.abort(); originalRequest.current = null; setViewing(null);
  }, [focused]);

  const dossier = state.data;
  const canUpload = media.sources.length > 0;
  const locked = !state.interactive || !!viewing;
  const now = Date.now();
  const progress = dossier ? documentProgress(dossier, now) : null;
  const rows = dossier ? documentRows(dossier) : [];

  // Match the existing web behaviour: bounded READS after analysis, never retry a mutation.
  useEffect(() => {
    if (!watch || !focused || !dossier || Date.now() >= watch.until) return;
    const doc = dossier.documents.find(item => item.id === watch.id);
    if (!doc || doc.statut_verification !== 'EN_ATTENTE') return;
    const timer = setInterval(() => {
      if (Date.now() >= watch.until) { clearInterval(timer); setWatch(null); return; }
      if (!state.busy && !target && AppState.currentState === 'active') void state.refresh();
    }, 5_000);
    return () => clearInterval(timer);
  }, [watch, focused, dossier, state.busy, state.refresh, target]);

  const changed = () => { if (alive.current) onDocumentsChanged?.(); };
  const showReceipt = () => { if (alive.current) scroll.current?.scrollTo({ y: 0, animated: true }); };
  const runVerify = async (documentId: string) => {
    const result = await state.perform(`verify:${documentId}`, signal => gateway.verify(context, documentId, signal));
    if (!result || !alive.current) return;
    if (result.dossier) changed();
    if (result.kind === 'confirmed') setWatch({ id: documentId, until: Date.now() + 60_000 });
    showReceipt();
  };
  const beginUpload = (type: string, replacesDocumentId?: string) => {
    if (locked || !canUpload) return;
    setUploadError(null); setTarget({ type, replacesDocumentId });
  };
  const upload = async (selection: DocumentSelection, label: string) => {
    if (!target || locked || submitLock.current) return;
    submitLock.current = true;
    setUploadError(null);
    try {
      const result = await state.perform('upload', (signal, onPrepared, onNotStarted) => gateway.upload(context, {
        typeDocument: target.type, file: selection.file, label: label.trim() || undefined,
        replacesDocumentId: target.replacesDocumentId, onPrepared, onNotStarted,
      }, signal));
      if (!result || !alive.current) return;
      if (result.dossier) changed();
      if (result.kind !== 'confirmed') {
        setUploadError(result.message);
        return;
      }
      setTarget(null);
      showReceipt();
      // Upload is now re-read and confirmed. Verification is a separate action: it never resends the file.
      if (result.document) await runVerify(result.document.id);
    } finally { submitLock.current = false; }
  };
  const review = (doc: CaregiverDocument) => {
    if (locked) return;
    Alert.alert('Demander une revue humaine ?', 'Un membre de l’équipe examinera ce justificatif. Cette demande ne valide pas automatiquement le document.', [
      { text: 'Annuler', style: 'cancel' },
      { text: 'Demander la revue', onPress: () => {
        void state.perform(`review:${doc.id}`, signal => gateway.requestReview(context, doc.id,
          'Contestation du verdict automatique depuis l’espace Documents', signal)).then(result => {
          if (result?.dossier) changed();
          if (result) showReceipt();
        });
      } },
    ]);
  };
  const remove = (doc: CaregiverDocument) => {
    if (locked) return;
    Alert.alert('Supprimer ce document ?', 'Le document sera archivé. Tu pourras en téléverser un nouveau.', [
      { text: 'Annuler', style: 'cancel' },
      { text: 'Supprimer', style: 'destructive', onPress: () => {
        void state.perform(`delete:${doc.id}`, signal => gateway.logicalDelete(context, doc.id, signal)).then(result => {
          if (result?.dossier) changed();
          if (result) showReceipt();
        });
      } },
    ]);
  };
  const view = async (doc: CaregiverDocument) => {
    if (locked || !media.open || originalRequest.current) return;
    const abort = new AbortController(); originalRequest.current = abort;
    setViewing(doc.id); setViewError(null);
    let timer: ReturnType<typeof setTimeout> | undefined;
    try {
      const timeout = new Promise<never>((_, reject) => { timer = setTimeout(() => { abort.abort(); reject(new Error('timeout')); }, 20_000); });
      const original = await Promise.race([gateway.getOriginal(context, doc.id, abort.signal), timeout]);
      if (timer) clearTimeout(timer);
      if (!alive.current || abort.signal.aborted) return;
      await media.open(original, abort.signal);
    } catch (reason) {
      if (!alive.current || originalRequest.current !== abort) return;
      setViewError(reason instanceof DocumentMediaError || reason instanceof DocumentWorkflowError
        ? reason.message : 'Impossible d’ouvrir ce document. Vérifie ta connexion puis réessaie.');
      showReceipt();
    } finally {
      if (timer) clearTimeout(timer);
      if (originalRequest.current === abort) { originalRequest.current = null; if (alive.current) setViewing(null); }
    }
  };
  const reconcile = async () => {
    if (!state.uncertainUpload || state.busy) return;
    const result = await state.perform('reconcile', signal => gateway.reconcileUpload(context, state.uncertainUpload!, signal));
    if (result?.dossier) changed();
    if (result) showReceipt();
  };

  return <SafeAreaView style={shared.screen} edges={['left', 'right']}>
    <ScrollView ref={scroll} testID="documents-scroll" contentContainerStyle={styles.scroll}
      refreshControl={<RefreshControl refreshing={state.loading && !!dossier} onRefresh={() => { void state.readJournal(); void state.refresh(); }}
        tintColor={colors.pink} enabled={!state.busy && !viewing} /> }>
      <View style={[shared.content, styles.content]}>
        <ModeNotice mode={gateway.mode === 'demo' ? 'demo' : 'staging'} />
        <View style={styles.gap}><Text accessibilityRole="header" style={shared.title} testID="documents-title">Mes documents</Text>
          <Text style={shared.subtitle}>Tes justificatifs professionnels, réunis au même endroit.</Text>
        </View>
        <ActionButton label="Actualiser le dossier" secondary busy={state.loading && !!dossier} disabled={!!state.busy || !!viewing}
          onPress={() => { void state.readJournal(); void state.refresh(); }} testID="documents-refresh" />
        {viewError ? <ErrorNotice message={viewError} /> : null}
        {state.journalError ? <ErrorNotice message={state.journalError} /> : null}
        {state.uncertainUpload && !state.receipt ? <View style={[shared.card, styles.gap, styles.receiptWarning]} testID="documents-pending-upload">
          <Text style={shared.sectionTitle}>Un envoi reste à vérifier</Text>
          <Text style={shared.body}>Vérifie son résultat avant d’envoyer un nouveau document. Le fichier ne sera pas renvoyé.</Text>
          <ActionButton label="Vérifier l’envoi précédent" secondary busy={state.busy === 'reconcile'} disabled={!!state.busy || !!viewing || !state.journalReady}
            onPress={() => { void reconcile(); }} testID="documents-reconcile" />
        </View> : null}
        {state.receipt ? <View style={[shared.card, styles.gap, state.receipt.kind !== 'confirmed' && styles.receiptWarning]}
          accessibilityLiveRegion="polite" testID={`documents-result-${state.receipt.kind}`}>
          <Text style={shared.sectionTitle}>{state.receipt.kind === 'confirmed' ? 'Dossier actualisé'
            : state.receipt.kind === 'rejected' ? 'Action non effectuée' : 'Confirmation à vérifier'}</Text>
          <Text style={shared.body}>{state.receipt.message}</Text>
          {state.receipt.warning ? <Text style={shared.small}>{state.receipt.warning}</Text> : null}
          {state.uncertainUpload ? <ActionButton label="Vérifier l’envoi précédent" secondary busy={state.busy === 'reconcile'}
            disabled={!!state.busy || !!viewing} onPress={() => { void reconcile(); }} testID="documents-reconcile" /> : null}
          {state.needsRead && !state.uncertainUpload ? <Text style={shared.small}>Actualise le dossier avant toute nouvelle action.</Text> : null}
        </View> : null}
        {state.error ? <ErrorNotice message={state.error} onRetry={() => { void state.refresh(); }} /> : null}
        {!dossier && state.loading ? <StatusPanel title="Chargement du dossier" message="Récupération de tes justificatifs et de leurs statuts." loading /> : null}
        {dossier && !dossier.profile ? <StatusPanel title="Ton dossier, quand tu en auras besoin"
          message="Complète ton profil pour retrouver les justificatifs correspondant à ta profession." testID="documents-missing-profile">
          <ActionButton label="Compléter mon profil" onPress={onOpenProfile} testID="documents-open-profile" />
          <ActionButton label="Explorer les missions" secondary onPress={onExploreMissions} testID="documents-explore" />
        </StatusPanel> : null}
        {dossier?.profile && !dossier.profile.profession ? <View style={[shared.card, styles.gap]}>
          <Text style={shared.body}>Renseigne ta profession pour connaître les justificatifs correspondants.</Text>
          <ActionButton label="Compléter mon profil" onPress={onOpenProfile} testID="documents-open-profile" />
        </View> : null}
        {dossier?.profile?.profession ? <>
          {!dossier.profile.type_exercice ? <View style={[shared.card, styles.gap]}>
            <Text style={shared.body}>Précise ton mode d’exercice dans ton profil pour afficher les justificatifs qui le concernent.</Text>
            <ActionButton label="Compléter mon profil" secondary onPress={onOpenProfile} testID="documents-open-profile" />
          </View> : null}
          {progress && progress.total > 0 ? <View style={[shared.card, styles.progress, styles.gap]} testID="documents-progress">
            <Text accessibilityRole="header" style={shared.sectionTitle}>{progress.valid} sur {progress.total} justificatifs obligatoires à jour</Text>
            <View accessibilityRole="progressbar" accessibilityValue={{ min: 0, max: progress.total, now: progress.valid }}
              style={styles.track}><View style={[styles.fill, { width: `${progress.valid / progress.total * 100}%` }]} /></View>
            <Text style={shared.small}>Le dépôt d’un fichier et sa validation sont deux étapes distinctes.</Text>
            {progress.next ? <Text style={shared.body}>À compléter : {documentTitle(progress.next.type_document)}</Text>
              : <Text style={shared.body}>Les justificatifs obligatoires affichés sont à jour.</Text>}
          </View> : null}
          {!canUpload ? <Text style={shared.small} testID="documents-upload-unavailable">L’ajout de fichiers n’est pas disponible sur cet appareil.</Text> : null}
          {rows.length === 0 ? <Text style={shared.body} testID="documents-no-requirements">Aucun justificatif à afficher pour ce dossier.</Text> : null}
          {rows.map(rule => {
            const doc = dossier.documents.find(item => item.type_document === rule.type_document);
            return <DocumentCard key={rule.type_document} rule={rule} doc={doc} profession={dossier.profile!.profession}
              now={now} disabled={locked} canUpload={canUpload} canView={!!media.open}
              busy={state.busy} viewing={viewing === doc?.id}
              onUpload={() => beginUpload(rule.type_document, doc?.id)} onView={() => { if (doc) void view(doc); }}
              onVerify={() => { if (doc && !locked) void runVerify(doc.id); }} onReview={() => { if (doc) review(doc); }}
              onRemove={() => { if (doc) remove(doc); }} />;
          })}
          <Text style={shared.small}>Les documents de vaccination et de médecine du travail ne sont pas téléversés dans cet espace.</Text>
        </> : null}
      </View>
    </ScrollView>
    {target && focused ? <DocumentUploadSheet key={`${target.type}:${target.replacesDocumentId ?? 'new'}`}
      type={target.type} replacing={!!target.replacesDocumentId} media={media} busy={state.busy === 'upload'}
      blocked={!state.busy && (state.needsRead || !!state.uncertainUpload)} error={uploadError}
      onSubmit={upload} onClose={() => { if (!state.busy) { setTarget(null); setUploadError(null); } }} /> : null}
  </SafeAreaView>;
}

function DocumentCard({ rule, doc, profession, now, disabled, canUpload, canView, busy, viewing,
  onUpload, onView, onVerify, onReview, onRemove }: {
  rule: DocumentRequirement; doc?: CaregiverDocument; profession: string | null; now: number;
  disabled: boolean; canUpload: boolean; canView: boolean; busy: string | null; viewing: boolean;
  onUpload: () => void; onView: () => void; onVerify: () => void; onReview: () => void; onRemove: () => void;
}) {
  const presentation = doc ? documentPresentation(doc, profession, now) : null;
  const soon = doc?.valide_jusqua && doc.statut_verification === 'VERIFIE'
    && Date.parse(doc.valide_jusqua) > now && Date.parse(doc.valide_jusqua) - now < 30 * 86_400_000;
  return <View style={[shared.card, styles.gap]} testID={`document-card-${rule.type_document}`}>
    <View style={styles.row}>
      <Text style={[shared.small, rule.est_critique ? styles.required : styles.optional]}>{rule.est_critique ? 'Obligatoire' : 'Complémentaire'}</Text>
    </View>
    <Text accessibilityRole="header" style={shared.sectionTitle}>{documentTitle(rule.type_document)}</Text>
    {rule.description ? <Text style={shared.small}>{rule.description}</Text> : null}
    {doc && presentation ? <>
      <Text style={shared.body}>{doc.libelle || doc.nom_fichier}</Text>
      {doc.libelle ? <Text style={shared.small}>{doc.nom_fichier}</Text> : null}
      {displayDate(doc.televerse_le) ? <Text style={shared.small}>Téléversé le {displayDate(doc.televerse_le)}</Text> : null}
      <View style={[styles.badge, presentation.tone === 'success' ? styles.successBadge : presentation.tone === 'danger' ? styles.dangerBadge : styles.pendingBadge]}>
        <Text style={[styles.badgeText, presentation.tone === 'success' ? styles.successText : presentation.tone === 'danger' ? styles.dangerText : styles.pendingText]}
          testID={`document-status-${rule.type_document}`}>{presentation.label}</Text>
      </View>
      {presentation.explanation ? <Text style={shared.small}>{presentation.explanation}</Text> : null}
      {displayDate(doc.valide_jusqua) ? <Text style={shared.small}>Échéance : {displayDate(doc.valide_jusqua)}</Text> : null}
      {soon ? <Text style={styles.dangerText}>Ce document expire dans moins de 30 jours.</Text> : null}
      <View style={styles.row}>
        {canView ? <InlineAction label="Ouvrir le document" disabled={disabled} busy={viewing} onPress={onView} testID={`document-view-${rule.type_document}`} /> : null}
        {presentation.reverify ? <InlineAction label="Revérifier" disabled={disabled} busy={busy === `verify:${doc.id}`} onPress={onVerify} testID={`document-verify-${rule.type_document}`} /> : null}
        {canUpload ? <InlineAction label="Remplacer" disabled={disabled} onPress={onUpload} testID={`document-replace-${rule.type_document}`} /> : null}
      </View>
      {presentation.review ? <ActionButton label="Demander une revue humaine" secondary disabled={disabled} busy={busy === `review:${doc.id}`}
        onPress={onReview} testID={`document-review-${rule.type_document}`} /> : null}
      <InlineAction label="Supprimer" destructive disabled={disabled} busy={busy === `delete:${doc.id}`} onPress={onRemove} testID={`document-delete-${rule.type_document}`} />
    </> : canUpload ? <ActionButton label={`Ajouter — ${documentTitle(rule.type_document)}`} disabled={disabled}
      onPress={onUpload} testID={`document-add-${rule.type_document}`} /> : <Text style={shared.small}>Aucun fichier téléversé.</Text>}
  </View>;
}

function InlineAction({ label, onPress, disabled, busy = false, destructive = false, testID }: {
  label: string; onPress: () => void; disabled: boolean; busy?: boolean; destructive?: boolean; testID: string;
}) {
  return <Pressable accessibilityRole="button" accessibilityState={{ disabled: disabled || busy, busy }} testID={testID}
    onPress={onPress} disabled={disabled || busy} style={({ pressed }) => [styles.inline, (pressed || disabled || busy) && styles.dimmed]}>
    {busy ? <ActivityIndicator color={destructive ? colors.danger : colors.pink} /> : null}
    <Text style={[styles.link, destructive && styles.dangerText]}>{label}</Text>
  </Pressable>;
}

const styles = StyleSheet.create({
  scroll: { paddingVertical: 22, paddingBottom: 36 }, content: { gap: 20 }, gap: { gap: 12 },
  row: { flexDirection: 'row', flexWrap: 'wrap', alignItems: 'center', columnGap: 18, rowGap: 4 },
  inline: { minHeight: 44, alignSelf: 'flex-start', justifyContent: 'center', alignItems: 'center', flexDirection: 'row', gap: 8, paddingVertical: 8 },
  link: { color: colors.pink, fontSize: 16, lineHeight: 24, fontWeight: '600' }, dimmed: { opacity: 0.55 },
  required: { color: colors.danger, fontWeight: '700' }, optional: { color: colors.secondary, fontWeight: '600' },
  badge: { alignSelf: 'flex-start', borderRadius: 12, paddingHorizontal: 12, paddingVertical: 8 },
  badgeText: { fontWeight: '600', fontSize: 14, lineHeight: 21 },
  pendingBadge: { backgroundColor: colors.lightPurple }, pendingText: { color: colors.purple },
  successBadge: { backgroundColor: '#E6F2EC' }, successText: { color: colors.success },
  dangerBadge: { backgroundColor: colors.dangerBackground }, dangerText: { color: colors.danger },
  progress: { backgroundColor: colors.lightPink }, track: { height: 8, borderRadius: 4, backgroundColor: '#E5C8DE', overflow: 'hidden' },
  fill: { height: '100%', borderRadius: 4, backgroundColor: colors.pink }, receiptWarning: { borderColor: '#D8AE6A', backgroundColor: '#FFF9EF' },
});
