import * as Crypto from 'expo-crypto';
import * as DocumentPicker from 'expo-document-picker';
import { Directory, File, Paths } from 'expo-file-system';
import * as ImagePicker from 'expo-image-picker';
import * as WebBrowser from 'expo-web-browser';
import { Platform } from 'react-native';
import { DocumentMediaError } from '../../ui/documents/adapters';
import { createDocumentMediaAdapter } from './core';
import { assertLocalDocumentUri, DOCUMENT_MIMES, isCacheDescendant, MAX_DOCUMENT_BYTES } from './policy';
import type { DocumentMediaPorts, DocumentMediaScope, ManagedDocumentMediaAdapter } from './types';

/** Expo SDK57 boundary only. Construct once per admitted session; dispose on epoch change. */
export function createExpoDocumentMediaAdapter(input: {
  scope: DocumentMediaScope; isCurrent: (scope: DocumentMediaScope) => boolean;
}): ManagedDocumentMediaAdapter {
  if (Platform.OS !== 'ios' && Platform.OS !== 'android') {
    throw new DocumentMediaError('UNAVAILABLE', 'La sélection de documents est disponible dans l’application iOS ou Android.');
  }
  const platform = Platform.OS;
  // No personal identifiers in temporary paths. This random directory belongs to this instance.
  const directory = new Directory(Paths.cache, 'jolene-document-copies', Crypto.randomUUID());
  let directoryCreated = false;
  const owned = new Map<string, File>();
  const pickedCacheCopies = new Map<string, File>();
  const cleanupFile = (files: Map<string, File>, uri: string) => {
    const file = files.get(uri);
    if (!file) return;
    if (file.exists) file.delete();
    files.delete(uri);
  };
  const ports: DocumentMediaPorts = {
    platform,
    requestCameraPermission: async () => (await ImagePicker.requestCameraPermissionsAsync()).granted,
    discardPendingResult: async () => {
      // Android can return the previous Activity's result after process/activity recreation.
      // There is no persisted trusted account binding here: drain it, do not expose or upload it.
      // Its URIs are not proven to be ours, so do not delete them either.
      await ImagePicker.getPendingResultAsync();
    },
    choose: async source => {
      if (source === 'file') {
        const result = await DocumentPicker.getDocumentAsync({
          type: [...DOCUMENT_MIMES], copyToCacheDirectory: true, multiple: false,
        });
        if (result.canceled) return null;
        const asset = result.assets[0];
        if (!asset || result.assets.length !== 1) throw new DocumentMediaError('INVALID_FILE', 'Sélectionnez un seul document.');
        // This exact result was requested as a cache copy in this invocation. An external
        // content URI or path outside app cache is readable, but never considered ours to delete.
        if (isCacheDescendant(asset.uri, Paths.cache.uri)) pickedCacheCopies.set(asset.uri, new File(asset.uri));
        return { uri: asset.uri, name: asset.name, mime: asset.mimeType };
      }
      const options: ImagePicker.ImagePickerOptions = {
        mediaTypes: ['images'], base64: true, allowsEditing: false,
        allowsMultipleSelection: false, quality: 1, exif: false,
      };
      const result = source === 'camera' ? await ImagePicker.launchCameraAsync(options)
        : await ImagePicker.launchImageLibraryAsync(options);
      if (result.canceled) return null;
      const asset = result.assets[0];
      if (!asset || result.assets.length !== 1) throw new DocumentMediaError('INVALID_FILE', 'Sélectionnez une seule photo.');
      // base64 is Expo's JPEG data. The source URI may still point to HEIC/AVIF: do not
      // rename or overwrite that original. Only a fresh SDK copy proven inside app cache
      // is registered for cleanup; external/library originals are never registered.
      if (isCacheDescendant(asset.uri, Paths.cache.uri)) pickedCacheCopies.set(asset.uri, new File(asset.uri));
      return { uri: asset.uri, name: asset.fileName, base64: asset.base64 };
    },
    readLocalDocument: async uri => {
      assertLocalDocumentUri(uri);
      const file = new File(uri); const size = file.size;
      if (!file.exists || !Number.isSafeInteger(size) || size <= 0 || size > MAX_DOCUMENT_BYTES) {
        throw new DocumentMediaError('INVALID_FILE', 'Choisissez un fichier lisible et non vide de 10 Mo maximum.');
      }
      const bytes = new Uint8Array(await file.arrayBuffer());
      if (!bytes.byteLength || bytes.byteLength > MAX_DOCUMENT_BYTES || bytes.byteLength !== size) {
        bytes.fill(0); throw new DocumentMediaError('INVALID_FILE', 'Le fichier a changé pendant sa lecture. Sélectionnez-le à nouveau.');
      }
      return bytes;
    },
    createPrivateCopy: async file => {
      if (!directoryCreated) {
        directory.create({ intermediates: true, idempotent: false, overwrite: false }); directoryCreated = true;
      }
      const extensions: Record<string, string> = { 'application/pdf': 'pdf', 'image/jpeg': 'jpg', 'image/png': 'png', 'image/webp': 'webp' };
      const extension = extensions[file.mime];
      if (!extension) throw new DocumentMediaError('INVALID_FILE', 'Ce type de document ne peut pas être ouvert.');
      const copy = new File(directory, `${Crypto.randomUUID()}.${extension}`);
      owned.set(copy.uri, copy);
      try {
        copy.create({ intermediates: false, overwrite: false }); copy.write(file.bytes);
        if (copy.size !== file.bytes.byteLength) throw new Error('Incomplete private copy');
      } catch (error) {
        cleanupFile(owned, copy.uri); throw error;
      }
      return { uri: copy.uri, release: async () => { cleanupFile(owned, copy.uri); } };
    },
    cleanupPickedAsset: async asset => { cleanupFile(pickedCacheCopies, asset.uri); },
    cleanup: async () => {
      let failed = false;
      for (const files of [owned, pickedCacheCopies]) {
        for (const uri of [...files.keys()]) { try { cleanupFile(files, uri); } catch { failed = true; } }
      }
      // Never recursively delete cache, originals, or another instance's directory.
      if (directoryCreated && directory.exists && directory.list().length === 0) {
        try { directory.delete(); directoryCreated = false; } catch { failed = true; }
      }
      if (failed) throw new DocumentMediaError('UNAVAILABLE', 'Certaines copies temporaires n’ont pas pu être supprimées.');
    },
    openSystemDocument: async uri => {
      const result = await WebBrowser.openBrowserAsync(uri, {
        dismissButtonStyle: 'close', presentationStyle: WebBrowser.WebBrowserPresentationStyle.FULL_SCREEN,
        readerMode: false, enableBarCollapsing: false, showTitle: false,
        enableDefaultShareMenuItem: false, showInRecents: false, createTask: false, useProxyActivity: false,
      });
      if (result.type === 'opened' || result.type === 'cancel' || result.type === 'dismiss' || result.type === 'locked') return result.type;
      throw new DocumentMediaError('UNAVAILABLE', 'L’ouverture du document n’a pas pu être confirmée.');
    },
    ...(platform === 'ios' ? { dismissSystemDocument: async () => { await WebBrowser.dismissBrowser(); } } : {}),
  };
  return createDocumentMediaAdapter({ ...input, ports });
}

/** Compatibility name for the initial preparation contract. Both factories are synchronous. */
export const createExpoDocumentMedia = createExpoDocumentMediaAdapter;
