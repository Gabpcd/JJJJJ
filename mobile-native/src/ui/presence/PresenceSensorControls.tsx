import { useCallback, useEffect, useLayoutEffect, useRef, useState, useSyncExternalStore } from 'react';
import { AppState, Modal, Pressable, ScrollView, StyleSheet, Text, View } from 'react-native';
import { useIsFocused } from '@react-navigation/native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { CameraView } from 'expo-camera';
import type { ManagedPresenceSensors } from '../../media/presence/types';
import type { PresenceContext } from '../../workflows/presence/types';
import type { PresenceScreenGateway } from './types';
import { ActionButton, StatusPanel } from '../components';
import { colors, shared } from '../theme';

/** Only capture and opt-in controls. This component never invokes gateway.scan or any mutation. */
export function PresenceSensorControls({ sensors, gateway, context, enabled, gpsConsentEnabled, onCode, onBusy }: {
  sensors: ManagedPresenceSensors; gateway: PresenceScreenGateway; context: PresenceContext; enabled: boolean;
  gpsConsentEnabled: boolean; onCode(code: string): void; onBusy(value: boolean): void;
}) {
  const focused = useIsFocused(); const focusedRef = useRef(focused); focusedRef.current = focused;
  const [activity, setActivity] = useState(AppState.currentState);
  const qr = useSyncExternalStore(sensors.qr.subscribe, sensors.qr.snapshot);
  const choice = useSyncExternalStore(sensors.gps.subscribe, sensors.gps.snapshot);
  const [message, setMessage] = useState<string | null>(null); const [busy, setBusy] = useState(false);
  const operation = useRef<AbortController | null>(null); const mounted = useRef(false);
  const sameScope = sensors.scope.userId === context.userId && sensors.scope.epoch === context.epoch;
  const identity = `${context.userId}:${context.epoch}`; const latestIdentity = useRef(identity); latestIdentity.current = identity;
  const busyCallback = useRef(onBusy); busyCallback.current = onBusy;
  const cancel = useCallback(() => { operation.current?.abort(); operation.current = null; sensors.cancel();
    if (mounted.current) { setBusy(false); busyCallback.current(false); } }, [sensors]);
  useLayoutEffect(() => {
    mounted.current = true;
    const subscription = AppState.addEventListener('change', value => {
      setActivity(value);
      // A temporary inactive phase can be the OS permission sheet. No preview is mounted then.
      if (value === 'background') { cancel(); setMessage(null); }
    });
    return () => { mounted.current = false; operation.current?.abort(); operation.current = null; sensors.cancel();
      busyCallback.current(false); subscription.remove(); };
  }, [sensors, cancel]);
  useLayoutEffect(() => {
    if (!focused || !sameScope) { cancel(); setMessage(null); }
    return () => { cancel(); };
  }, [focused, sameScope, identity, cancel]);
  useEffect(() => { if (!gpsConsentEnabled) void sensors.gps.choose(false); }, [gpsConsentEnabled, sensors]);
  const isHere = (controller: AbortController) => mounted.current && focusedRef.current
    && latestIdentity.current === identity && !controller.signal.aborted && operation.current === controller;
  const start = async (kind: 'qr' | 'gps') => {
    if (!enabled || busy || operation.current || !focused || !sameScope || AppState.currentState !== 'active') return;
    const controller = new AbortController(); operation.current = controller; setBusy(true); busyCallback.current(true); setMessage(null);
    try {
      if (kind === 'qr') {
        const capture = await gateway.captureCode(context, sensors.qr, controller.signal);
        if (!isHere(controller)) return;
        if (capture.kind === 'code') { onCode(capture.code); setMessage('Code lu. Vérifiez les six chiffres puis appuyez sur « Enregistrer le pointage ».'); }
        else if (capture.kind === 'invalid') setMessage('Ce QR ne contient pas un code de pointage à six chiffres. Saisissez le code affiché par l’établissement.');
        else if (capture.kind === 'denied') setMessage('Accès à la caméra refusé. Vous pouvez saisir le code manuellement.');
        else if (capture.kind === 'unavailable') setMessage('La caméra est indisponible. Vous pouvez saisir le code manuellement.');
      } else {
        if (!gpsConsentEnabled) return;
        await sensors.gps.choose(choice === 'off', controller.signal);
      }
    } catch { if (isHere(controller)) setMessage('Cette fonction ne peut pas être ouverte maintenant. La saisie manuelle reste disponible.'); }
    finally { if (operation.current === controller) { operation.current = null;
      if (mounted.current) { setBusy(false); busyCallback.current(false); } } }
  };
  const cameraVisible = focused && sameScope && activity === 'active' && qr.phase !== 'closed';
  return <View style={styles.controls}>
    <ActionButton secondary label="Lire le QR de pointage" onPress={() => void start('qr')} disabled={!enabled || busy || !sameScope} testID="presence-open-camera" />
    {message ? <Text style={shared.body} accessibilityLiveRegion="polite" testID="presence-camera-message">{message}</Text> : null}
    {gpsConsentEnabled ? <>
      <Pressable accessibilityRole="checkbox" accessibilityLabel="Joindre ma position pour ce pointage, facultatif"
        accessibilityState={{ checked: choice !== 'off', disabled: !enabled || busy }} disabled={!enabled || busy}
        onPress={() => void start('gps')} testID="presence-gps-choice" style={styles.choice}>
        <Text style={styles.check}>{choice !== 'off' ? '☑' : '☐'}</Text>
        <Text style={[shared.body, styles.grow]}>Joindre ma position pour ce pointage (facultatif)</Text>
      </Pressable>
      <Text style={shared.small} testID="presence-gps-status">{choice === 'ready' ? 'La position sera recherchée uniquement lorsque vous confirmerez le pointage.'
        : choice === 'denied' ? 'Autorisation refusée. Le pointage pourra être envoyé sans position.'
        : choice === 'unavailable' ? 'Localisation indisponible. Le pointage pourra être envoyé sans position.'
        : choice === 'permission' ? 'Autorisation de localisation en cours…' : 'Aucune position ne sera demandée pour ce pointage.'}</Text>
    </> : <Text style={shared.small}>Le pointage sera envoyé sans demander votre position.</Text>}
    <Modal visible={cameraVisible} animationType="slide" presentationStyle="fullScreen" onRequestClose={() => sensors.qr.cancel()}>
      <SafeAreaView style={shared.screen}>
        <ScrollView contentContainerStyle={styles.modal}>
          <Text style={shared.title} accessibilityRole="header">Lire le QR de pointage</Text>
          <Text style={shared.body}>Placez le QR présenté par l’établissement dans le cadre. Le pointage sera envoyé seulement après votre confirmation.</Text>
          {cameraVisible && qr.phase === 'scanning' ? <CameraView testID="presence-camera-preview" style={styles.camera} facing="back"
            barcodeScannerSettings={{ barcodeTypes: ['qr'] }}
            onBarcodeScanned={event => sensors.qr.barcode(qr.requestId, event.type, event.data)}
            onMountError={() => sensors.qr.unavailable(qr.requestId)} /> : <StatusPanel loading title="Autorisation de la caméra" />}
          <ActionButton secondary label="Fermer la caméra" onPress={() => sensors.qr.cancel()} testID="presence-close-camera" />
        </ScrollView>
      </SafeAreaView>
    </Modal>
  </View>;
}

const styles = StyleSheet.create({ controls: { gap: 12 }, modal: { flexGrow: 1, gap: 18, padding: 22 },
  camera: { width: '100%', minHeight: 260, height: 360, maxWidth: 640, alignSelf: 'center' },
  choice: { flexDirection: 'row', alignItems: 'center', gap: 12, minHeight: 48 },
  check: { color: colors.purple, fontSize: 26 }, grow: { flex: 1 } });
