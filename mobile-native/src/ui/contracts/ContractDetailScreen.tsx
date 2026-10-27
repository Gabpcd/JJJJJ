import { useCallback, useEffect, useMemo, useState, useSyncExternalStore } from 'react';
import { AppState, Keyboard, KeyboardAvoidingView, Platform, Pressable, RefreshControl, ScrollView, StyleSheet, Text, TextInput, View } from 'react-native';
import { useFocusEffect } from '@react-navigation/native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { canOfferSignature } from '../../workflows/contracts/business';
import type { ContractContext, ContractGateway } from '../../workflows/contracts/types';
import { ActionButton, ErrorNotice, ModeNotice, StatusPanel } from '../components';
import { colors, shared } from '../theme';
import { ContractOriginalReader } from './ContractOriginalReader';
import { createContractDetailController } from './detailController';
import { DEMO_CONTRACT_CODE } from '../../contracts/demoFixture';
import { createContractInputDiagnostics, type ContractCodeResetReason } from './inputDiagnostics';
import { contractContextKey, contractStatus, contractType, originalMessage, partyStatus, revisionKey } from './presentation';

export interface ContractDetailScreenProps { context: ContractContext; sessionEpoch: number; contractId: string; gateway: ContractGateway }
export function ContractDetailScreen(props: ContractDetailScreenProps) {
  return <Content key={`${contractContextKey(props.context, props.sessionEpoch)}:${props.contractId}`} {...props} />;
}
function Content({ context, contractId, gateway }: ContractDetailScreenProps) {
  const controller = useMemo(() => createContractDetailController(gateway, context, contractId), [gateway, contractId]);
  const state = useSyncExternalStore(controller.subscribe, controller.getSnapshot, controller.getSnapshot);
  const [code, setCode] = useState(''); const [clock, setClock] = useState(Date.now());
  const inputDiagnostics = useMemo(() => createContractInputDiagnostics({
    gatewayMode: gateway.mode, appMode: process.env.EXPO_PUBLIC_JOLENE_MODE,
    flag: process.env.EXPO_PUBLIC_JOLENE_NAVIGATION_DIAGNOSTICS,
    emit: entry => console.log('[jolene-native-contract-input]', JSON.stringify(entry)),
  }), [gateway.mode]);
  const clearCode = useCallback((reason: ContractCodeResetReason) => {
    inputDiagnostics.reset(reason); setCode('');
  }, [inputDiagnostics]);
  useEffect(() => { inputDiagnostics.committed(code.length); }, [code, inputDiagnostics]);
  useFocusEffect(useCallback(() => {
    if (AppState.currentState === 'active') controller.activate();
    const sub = AppState.addEventListener('change', next => {
      clearCode(next === 'active' ? 'app-active' : 'app-nonactive'); if (next === 'active') controller.activate(); else controller.deactivate();
    });
    return () => { sub.remove(); clearCode('focus-cleanup'); controller.deactivate(); };
  }, [controller, clearCode]));
  // Focus cleanup aborts requests and removes sensitive state. Do not permanently
  // dispose a memoized controller in an effect: Strict Mode reuses it on setup.
  const revision = revisionKey(state.details?.original ?? null);
  useEffect(() => { clearCode('revision-change'); }, [revision, clearCode]);
  useEffect(() => {
    if (!state.active) return;
    setClock(Date.now()); const timer = setInterval(() => setClock(Date.now()), 1000); return () => clearInterval(timer);
  }, [state.active]);
  const details = state.details;
  const admission = details?.otpAdmission;
  const eligible = !!details && canOfferSignature(details);
  const blocked = !state.active || state.loading || !!state.busy || state.needsRead || !!state.error || !!state.readerError;
  const consentReady = !blocked && !!state.accepted && !!state.presented;
  const admissionValid = !!admission && admission.expiresAt > clock;
  const canRequest = eligible && consentReady && admissionValid && admission!.canSend;
  const canSign = eligible && consentReady && admissionValid && admission!.canValidate && !!admission!.otpExpiresAt && admission!.otpExpiresAt > clock;
  const remaining = admission?.otpExpiresAt ? Math.max(0, Math.ceil((admission.otpExpiresAt - clock) / 1000)) : null;
  const submit = () => { if (!canSign || code.length !== 6) return; const supplied = code; clearCode('submit'); Keyboard.dismiss(); void controller.sign(supplied); };
  return <SafeAreaView style={shared.screen} edges={['left', 'right', 'bottom']}>
    <KeyboardAvoidingView style={shared.flex} behavior={Platform.OS === 'ios' ? 'padding' : undefined} keyboardVerticalOffset={Platform.OS === 'ios' ? 90 : 0}>
      <ScrollView testID="contract-detail-scroll" keyboardShouldPersistTaps="handled" keyboardDismissMode="on-drag"
        contentContainerStyle={[shared.content, styles.content]} refreshControl={<RefreshControl refreshing={state.loading && !!details}
          onRefresh={() => { clearCode('refresh'); void controller.reload(); }} tintColor={colors.pink} colors={[colors.pink]} />}>
        <ModeNotice mode={gateway.mode === 'demo' ? 'demo' : 'staging'} />
        {gateway.mode === 'demo' ? <Text style={shared.small} testID="contract-demo-notice">Simulation locale : aucun SMS envoyé et aucun contrat réel signé.</Text> : null}
        {state.loading ? <StatusPanel loading title="Lecture du contrat" message="Vérification de l’original et de ses signatures." /> : null}
        {state.error ? <ErrorNotice message={state.error} onRetry={() => { clearCode('error-reload'); void controller.reload(); }} /> : null}
        {details ? <>
          <View style={styles.gap}>
            <Text style={shared.small}>{contractType(details.record.type_contrat)}</Text>
            <Text style={shared.title} accessibilityRole="header" testID="contract-number">Contrat {details.record.numero_contrat}</Text>
            <Text style={styles.status} testID="contract-status">{contractStatus(details.record.statut)}</Text>
          </View>
          <View style={[shared.card, styles.gap]} testID="contract-signatures">
            <Text style={shared.sectionTitle} accessibilityRole="header">Signatures enregistrées</Text>
            <Text style={shared.body} testID="contract-signature-etablissement">Établissement : {partyStatus(details.record, 'etablissement')}</Text>
            <Text style={shared.body} testID="contract-signature-soignant">Soignant : {partyStatus(details.record, 'soignant')}</Text>
          </View>
          <Text style={shared.sectionTitle} accessibilityRole="header">{gateway.mode === 'demo' ? 'Document fictif du contrat' : 'Original du contrat'}</Text>
          {details.original ? <ContractOriginalReader key={revision} original={details.original}
            onPresented={controller.presented} onUnavailable={controller.unavailable} />
            : <ErrorNotice message={originalMessage(details.originalIssue)} onRetry={() => { void controller.reload(); }} />}
          {details.original ? <View style={styles.gap}>
            <Text style={shared.small}>{gateway.mode === 'demo' ? 'Empreinte SHA-256 du document fictif' : 'Empreinte SHA-256 de l’original vérifié'}</Text>
            <Text selectable style={styles.hash} testID="contract-sha256">{details.original.sha256}</Text>
          </View> : null}
          {!details.permissions.sign ? <Text style={shared.body} testID="contract-read-only">Votre accès permet de consulter ce contrat. La signature est réservée aux membres autorisés de l’établissement.</Text> : null}
          {state.result ? <View style={[shared.card, styles.gap]} accessibilityLiveRegion="polite" testID={`contract-result-${state.result.kind}`}>
            <Text style={shared.body} testID="contract-result-message">{state.result.message}</Text>
            {state.result.issue?.attemptsRemaining != null ? <Text style={shared.small}>Tentatives restantes : {state.result.issue.attemptsRemaining}</Text> : null}
          </View> : null}
          {state.needsRead ? <ActionButton secondary label="Actualiser l’état du contrat" onPress={() => { clearCode('reconcile'); void controller.reload(); }}
            busy={state.loading} testID="contract-reconcile" /> : null}
          {eligible ? <View style={[shared.card, styles.gap]}>
            <Text style={shared.sectionTitle} accessibilityRole="header">Votre signature</Text>
            {!admissionValid ? <Text style={shared.body} testID="contract-test-not-admitted">La signature de ce contrat n’est pas ouverte dans la recette TEST actuelle.</Text> : null}
            <Pressable accessibilityRole="checkbox" accessibilityState={{ checked: !!state.accepted, disabled: blocked || !state.presented }}
              disabled={blocked || !state.presented} onPress={() => controller.accept(!state.accepted)} testID="contract-consent"
              style={[styles.consent, (blocked || !state.presented) && styles.disabled]}>
              <Text accessibilityElementsHidden style={styles.check}>{state.accepted ? '☑' : '☐'}</Text>
              <Text style={[shared.body, styles.consentText]}>J'ai lu l'intégralité du contrat affiché ci-dessus et j'accepte ses termes.</Text>
            </Pressable>
            <ActionButton label={gateway.mode === 'demo' ? 'Simuler un code SMS' : admission?.canValidate ? 'Demander un nouveau code SMS' : 'Demander un code SMS'}
              disabled={!canRequest} busy={state.busy === 'request'} onPress={() => { clearCode('request-otp'); void controller.requestOtp(); }} testID="contract-request-otp" />
            {admission?.canValidate ? <>
              {gateway.mode === 'demo' ? <Text style={shared.body} testID="contract-demo-code">Code fictif : {DEMO_CONTRACT_CODE}. Aucun SMS envoyé.</Text> : null}
              <Text style={shared.small} testID="contract-otp-status">{remaining && remaining > 0
                ? `Code utilisable pendant ${Math.floor(remaining / 60)} min ${String(remaining % 60).padStart(2, '0')} s.`
                : 'Le code a expiré. Un nouvel envoi doit être demandé explicitement.'}</Text>
              <Text style={shared.body} nativeID="contract-code-label">Code reçu par SMS</Text>
              <TextInput value={code} onChange={event => inputDiagnostics.nativeChange(event.nativeEvent.text.length, event.nativeEvent.eventCount)}
                onChangeText={value => { inputDiagnostics.textChange(value.length); setCode(value.replace(/[^0-9]/g, '').slice(0, 6)); }} maxLength={6}
                keyboardType="number-pad" textContentType="oneTimeCode" autoComplete="sms-otp" autoCorrect={false}
                accessibilityLabel="Code reçu par SMS, six chiffres" editable={!blocked} style={styles.input} testID="contract-otp"
                placeholder="6 chiffres" placeholderTextColor={colors.muted} returnKeyType="done" onSubmitEditing={submit} />
              <ActionButton label={gateway.mode === 'demo' ? 'Simuler la signature' : 'Signer le contrat TEST'} disabled={!canSign || code.length !== 6} busy={state.busy === 'sign'} onPress={submit} testID="contract-sign" />
            </> : null}
          </View> : null}
        </> : null}
      </ScrollView>
    </KeyboardAvoidingView>
  </SafeAreaView>;
}
const styles = StyleSheet.create({
  content: { gap: 22, paddingTop: 18, paddingBottom: 40 }, gap: { gap: 12 }, status: { color: colors.purple, fontSize: 16, lineHeight: 24, fontWeight: '600' },
  hash: { color: colors.secondary, fontSize: 12, lineHeight: 20, fontFamily: Platform.OS === 'ios' ? 'Menlo' : 'monospace' },
  consent: { flexDirection: 'row', alignItems: 'flex-start', gap: 12, paddingVertical: 8, minHeight: 48 },
  consentText: { flex: 1 }, check: { color: colors.purple, fontSize: 24, lineHeight: 30 }, disabled: { opacity: 0.6 },
  input: { backgroundColor: colors.surface, color: colors.text, fontSize: 22, letterSpacing: 5, minHeight: 56,
    borderColor: colors.border, borderWidth: 1, borderRadius: 14, paddingHorizontal: 16, paddingVertical: 14 },
});
