import { useEffect, useRef, useState } from 'react';
import { Image, Keyboard, KeyboardAvoidingView, Modal, Platform, ScrollView, StyleSheet, Text, TextInput, View } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { validateDocumentBytes } from '../../workflows/documents/bytes';
import { DocumentWorkflowError } from '../../workflows/documents/types';
import { ActionButton, ErrorNotice } from '../components';
import { colors, shared } from '../theme';
import { DocumentMediaError, type DocumentMediaAdapter, type DocumentSelection, type DocumentSource } from './adapters';
import { documentTitle } from './presentation';

export function DocumentUploadSheet({ type, replacing, media, busy, blocked, error, onSubmit, onClose }: {
  type: string; replacing: boolean; media: DocumentMediaAdapter; busy: boolean; blocked: boolean; error: string | null;
  onSubmit: (selection: DocumentSelection, label: string) => Promise<void>; onClose: () => void;
}) {
  const [selection, setSelection] = useState<DocumentSelection | null>(null);
  const [label, setLabel] = useState('');
  const [picking, setPicking] = useState<DocumentSource | null>(null);
  const [localError, setLocalError] = useState<string | null>(null);
  const [previewFailed, setPreviewFailed] = useState(false);
  const request = useRef<AbortController | null>(null);
  const current = useRef<DocumentSelection | null>(null);
  const release = (value: DocumentSelection | null) => { if (value) void Promise.resolve(media.release?.(value)).catch(() => {}); };
  useEffect(() => () => { request.current?.abort(); release(current.current); current.current = null; }, [media]);
  const pick = async (source: DocumentSource) => {
    if (busy || picking || request.current || blocked) return;
    Keyboard.dismiss();
    const abort = new AbortController(); request.current = abort;
    setPicking(source); setLocalError(null);
    let candidate: DocumentSelection | null = null;
    try {
      candidate = await media.pick(source, abort.signal);
      if (abort.signal.aborted) { release(candidate); return; }
      if (!candidate) return;
      await validateDocumentBytes(candidate.file);
      if (abort.signal.aborted) { release(candidate); return; }
      release(current.current); current.current = candidate;
      setSelection(candidate); setPreviewFailed(false);
    } catch (reason) {
      release(candidate);
      if (!abort.signal.aborted) setLocalError(reason instanceof DocumentMediaError || reason instanceof DocumentWorkflowError
        ? reason.message : 'Impossible de sélectionner ce document. Vérifie les autorisations puis réessaie.');
    } finally {
      if (request.current === abort) { request.current = null; if (!abort.signal.aborted) setPicking(null); }
    }
  };
  const locked = busy || !!picking;
  const previewUri = selection?.localPreviewUri;
  const canPreview = !!previewUri && /^(file|content):\/\//.test(previewUri) && selection?.file.mime.startsWith('image/');
  const chooseLabels: Record<DocumentSource, string> = { camera: 'Prendre une photo', library: 'Choisir dans la galerie', file: 'Choisir un fichier' };
  return <Modal visible animationType="slide" presentationStyle="pageSheet" onRequestClose={() => { if (!locked) onClose(); }}>
    <SafeAreaView style={shared.screen}>
      <KeyboardAvoidingView style={shared.flex} behavior={Platform.OS === 'ios' ? 'padding' : 'height'}>
        <ScrollView testID="document-upload-scroll" keyboardShouldPersistTaps="handled" keyboardDismissMode="on-drag" contentContainerStyle={styles.scroll}>
          <View style={[shared.content, styles.content]} accessibilityViewIsModal>
            <Text accessibilityRole="header" style={shared.title} testID="document-upload-title">{replacing ? 'Remplacer le justificatif' : 'Ajouter un justificatif'}</Text>
            <Text style={shared.sectionTitle}>{documentTitle(type)}</Text>
            <Text style={shared.body}>Une photo nette suffit — les dates de validité sont lues automatiquement sur votre document.</Text>
            <Text style={shared.small}>PDF, JPEG, PNG ou WebP · 10 Mo maximum.</Text>
            {replacing ? <Text style={shared.small}>Le document actuel sera remplacé lorsque le nouveau fichier aura été enregistré.</Text> : null}
            {media.sources.map(source => <ActionButton key={source} label={chooseLabels[source]} onPress={() => { void pick(source); }}
              secondary={source !== 'camera'} busy={picking === source} disabled={locked || blocked} testID={`document-pick-${source}`} />)}
            {selection ? <View style={[shared.card, styles.content]} testID="document-upload-selection">
              <Text style={shared.body}>{selection.file.name}</Text>
              <Text style={shared.small}>{Math.ceil(selection.file.bytes.byteLength / 1024)} Ko</Text>
              {canPreview && !previewFailed ? <Image source={{ uri: previewUri }} style={styles.preview} resizeMode="contain"
                accessibilityLabel="Aperçu du document sélectionné" onError={() => setPreviewFailed(true)} testID="document-local-preview" /> : null}
              {previewFailed ? <Text style={shared.small}>L’aperçu n’est pas disponible. Le fichier reste sélectionné.</Text> : null}
            </View> : null}
            <View style={styles.content}><Text style={shared.small}>Libellé (optionnel)</Text>
              <TextInput testID="document-upload-label" accessibilityLabel="Libellé du document, optionnel" value={label}
                onChangeText={setLabel} maxLength={200} editable={!locked && !blocked} style={styles.input} placeholder="Ex. Pièce d’identité recto-verso" />
            </View>
            {localError || error ? <ErrorNotice message={localError ?? error!} /> : null}
            {blocked ? <Text style={shared.body}>L’envoi précédent doit être vérifié. Ferme cette fenêtre puis actualise le dossier ; aucun nouvel envoi automatique ne sera effectué.</Text> : null}
            <ActionButton label={busy ? 'Enregistrement…' : 'Téléverser'} busy={busy} disabled={!selection || locked || blocked || !!localError}
              onPress={() => { if (selection) { Keyboard.dismiss(); void onSubmit(selection, label); } }} testID="document-upload-submit" />
            <ActionButton label="Annuler" secondary disabled={locked} onPress={onClose} testID="document-upload-cancel" />
          </View>
        </ScrollView>
      </KeyboardAvoidingView>
    </SafeAreaView>
  </Modal>;
}
const styles = StyleSheet.create({
  scroll: { flexGrow: 1, paddingVertical: 24 }, content: { gap: 16 },
  input: { minHeight: 54, padding: 14, borderWidth: 1, borderColor: colors.border, borderRadius: 14, fontSize: 17, color: colors.text, backgroundColor: colors.surface },
  preview: { width: '100%', height: 240, borderRadius: 12, backgroundColor: colors.background },
});
