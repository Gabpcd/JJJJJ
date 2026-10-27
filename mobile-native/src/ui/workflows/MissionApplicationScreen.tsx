import { useCallback, useEffect, useMemo, useState, useSyncExternalStore } from 'react';
import { AppState, Keyboard, KeyboardAvoidingView, Platform, Pressable, ScrollView, StyleSheet, Text, TextInput, View } from 'react-native';
import { useFocusEffect } from '@react-navigation/native';
import { SafeAreaView } from 'react-native-safe-area-context';
import type { MissionReadContext } from '../../data/types';
import { getMissionRemuneration } from '../../data/presentation';
import { createApplicationController } from '../../workflows/missions/controller';
import { alreadyApplied, applicationAction, applicationDisplayStatus, hasActiveAssignment, isTerminalMission, statusLabel, workflowContextKey, type ContractChoice, type MissionWorkflowGateway } from '../../workflows/missions/types';
import { ActionButton, ErrorNotice, LabelValue, StatusPanel } from '../components';
import { colors, shared } from '../theme';
import { WorkflowNotice } from './WorkflowNotice';

export interface MissionApplicationScreenProps {
  context: MissionReadContext; gateway: MissionWorkflowGateway; missionId: string;
  onBack: () => void; onMyMissions: () => void;
  onCompleteProfile?: () => void; onOpenDocuments?: () => void;
}
const dateTime = (value: string) => new Intl.DateTimeFormat('fr-FR', { weekday: 'short', day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit', timeZone: 'Europe/Paris' }).format(new Date(value));

export function MissionApplicationScreen(props: MissionApplicationScreenProps) {
  return <ApplicationContent key={`${workflowContextKey(props.context)}:${props.missionId}`} {...props} />;
}
function ApplicationContent({ context, gateway, missionId, onBack, onMyMissions, onCompleteProfile, onOpenDocuments }: MissionApplicationScreenProps) {
  const contextKey = workflowContextKey(context);
  const controller = useMemo(() => createApplicationController(gateway, context, missionId), [gateway, contextKey, missionId]);
  const state = useSyncExternalStore(controller.subscribe, controller.getSnapshot, controller.getSnapshot);
  const [message, setMessage] = useState(''); const [confirmed, setConfirmed] = useState(false);
  const [choice, setChoice] = useState<ContractChoice | undefined>();
  useEffect(() => { controller.activate(); return () => controller.dispose(); }, [controller]);
  useFocusEffect(useCallback(() => {
    if (AppState.currentState === 'active') void controller.refresh();
    const listener = AppState.addEventListener('change', value => { if (value === 'active') void controller.refresh(); });
    return () => listener.remove();
  }, [controller]));
  const snapshot = state.data; const mission = snapshot?.mission;
  const reviewKey = JSON.stringify([mission?.id, mission?.creneaux_planifies, snapshot?.attribution, snapshot?.assignedTo, state.options]);
  useEffect(() => { setConfirmed(false); setChoice(undefined); }, [reviewKey]);
  useEffect(() => { if (state.loading) { setConfirmed(false); setChoice(undefined); } }, [state.loading]);
  const action = snapshot ? applicationAction(snapshot) : null;
  const applied = snapshot ? alreadyApplied(snapshot) : false;
  const assigned = snapshot ? hasActiveAssignment(snapshot) : false;
  const terminal = snapshot ? isTerminalMission(snapshot) : false;
  const submit = () => { Keyboard.dismiss(); if (confirmed) void controller.submit({ message, contractChoice: choice }); };
  return <SafeAreaView style={shared.screen} edges={['left', 'right', 'bottom']}>
    <KeyboardAvoidingView style={shared.flex} behavior={Platform.OS === 'ios' ? 'padding' : undefined} keyboardVerticalOffset={Platform.OS === 'ios' ? 100 : 0}>
      <ScrollView testID="application-scroll" contentContainerStyle={styles.scroll} keyboardShouldPersistTaps="handled"
        keyboardDismissMode={Platform.OS === 'ios' ? 'interactive' : 'on-drag'}>
        <View style={[shared.content, styles.content]}>
          <WorkflowNotice mode={gateway.mode} />
          {state.error ? <ErrorNotice message={state.error} onRetry={state.submitting ? undefined : () => void controller.refresh()} /> : null}
          {!mission || !snapshot ? <StatusPanel loading={state.loading} title={state.loading ? 'Chargement du dossier' : state.error ? 'Dossier indisponible' : 'Mission introuvable'}>
            {!state.loading ? <ActionButton secondary label="Revenir aux missions" onPress={onBack} /> : null}
          </StatusPanel> : <>
            <Text style={shared.title} accessibilityRole="header" testID="application-title">{mission.intitule}</Text>
            <Text style={shared.subtitle}>{mission.etablissements?.nom ?? 'Établissement'}{mission.etablissements?.adresse_ville ? ` · ${mission.etablissements.adresse_ville}` : ''}</Text>
            <View style={shared.card}>
              <LabelValue label={mission.mode_remuneration === 'RETROCESSION' ? 'Rémunération annoncée' : 'Tarif horaire annoncé'} value={getMissionRemuneration(mission)} />
              <LabelValue label="État" value={statusLabel(applicationDisplayStatus(snapshot))} />
            </View>
            <View style={[shared.card, styles.section]}>
              <Text style={shared.sectionTitle} accessibilityRole="header">Dates et horaires à confirmer</Text>
              {!snapshot.exactPersistedPlanning ? <Text style={shared.body}>Le planning exact n’est pas disponible. Rechargez le dossier avant de candidater.</Text>
                : mission.creneaux_planifies.map((slot, index) => <View key={slot.id ?? String(index)} style={styles.slot}>
                  <Text style={shared.body}>{dateTime(slot.debut)}</Text>
                  <Text style={shared.small}>jusqu’au {slot.fin ? dateTime(slot.fin) : 'horaire à confirmer'}</Text>
                </View>)}
              <Text style={shared.small}>Horaires de Paris. Tous les créneaux affichés sont concernés.</Text>
            </View>
            {applied || terminal ? <View style={[shared.card, styles.section]} testID="application-confirmed">
              <Text style={shared.sectionTitle} accessibilityRole="header">{terminal ? statusLabel(mission.statut) : gateway.mode === 'demo' ? 'Simulation enregistrée' : assigned ? 'Cette mission vous est attribuée' : statusLabel(snapshot.application?.statut ?? '')}</Text>
              <Text style={shared.body}>{terminal ? 'Ce dossier présente l’historique de la mission.' : gateway.mode === 'demo' ? 'Aucune candidature réelle n’a été envoyée.'
                : assigned ? 'L’attribution a été relue sur le serveur.' : 'L’établissement peut consulter votre candidature.'}</Text>
              <ActionButton label="Voir mes missions" onPress={onMyMissions} testID="application-my-missions" />
              <Text style={shared.small}>Le contrat et le pointage ne sont pas encore disponibles dans ce parcours natif.</Text>
              {assigned && snapshot.acceptanceEmails?.length ? <View style={styles.section} testID="application-emails">
                <Text style={styles.label}>Emails de confirmation</Text>
                {snapshot.acceptanceEmails.map(receipt => <Text key={receipt.recipient} style={shared.small}>
                  {receipt.recipient === 'soignant' ? 'Votre email' : 'Email de l’établissement'} : {receipt.state === 'sent' ? 'accepté par le service d’envoi'
                    : receipt.state === 'failed' ? 'envoi non confirmé'
                      : receipt.state === 'pending' ? 'envoi en cours de vérification'
                        : ['test_account', 'test_source', 'compte_test_e2e'].includes(receipt.reason ?? '') ? 'neutralisé pour la recette TEST'
                          : receipt.reason === 'preference_user_off' ? 'désactivé dans les préférences' : 'non envoyé par le service'}.
                </Text>)}
                {snapshot.acceptanceEmails.some(receipt => receipt.reason === 'preparation_failed') ?
                  <Text style={shared.small}>Les références nécessaires à ces emails n’ont pas pu être vérifiées. L’attribution est conservée ; aucun nouvel envoi n’est effectué.</Text> : null}
                {snapshot.acceptanceEmails.some(receipt => receipt.state === 'pending' || (receipt.state === 'failed' && receipt.reason !== 'preparation_failed')) ? <>
                  <Text style={shared.small}>L’attribution de la mission est conservée. Cette reprise concerne uniquement les emails.</Text>
                  <ActionButton secondary label="Vérifier / reprendre les emails" busy={state.submitting} disabled={state.loading}
                    onPress={() => void controller.retryEmails()} testID="application-retry-emails" />
                </> : null}
              </View> : assigned && gateway.mode === 'supabase' ? <Text style={shared.small}>L’attribution est confirmée ; la livraison des emails n’est pas vérifiée dans cet écran.</Text> : null}
            </View> : !snapshot.canApply ? <View style={[shared.card, styles.section]} testID="application-profile-required">
              <Text style={shared.sectionTitle}>Complétez votre profil</Text>
              <Text style={shared.body}>{snapshot.missingProfile.length ? `À compléter : ${snapshot.missingProfile.join(', ')}.` : 'Les informations nécessaires à votre candidature ne sont pas encore complètes.'}</Text>
              {onCompleteProfile ? <ActionButton label="Compléter mon profil" onPress={onCompleteProfile} /> : <Text style={shared.small}>Ces informations sont modifiables dans votre profil Jolene.</Text>}
            </View> : action ? <View style={[shared.card, styles.section]}>
              <Text style={shared.sectionTitle}>{action === 'POSTULER' ? 'Votre candidature' : 'Accepter cette mission'}</Text>
              <Text style={shared.body}>{action === 'POSTULER' ? 'L’établissement examinera votre candidature.' : 'Cette action demande l’attribution de tous les créneaux affichés. Le serveur vérifie votre dossier et vos disponibilités.'}</Text>
              {action === 'POSTULER' ? <View style={styles.section}>
                <Text style={styles.label}>Message à l’établissement (facultatif)</Text>
                <TextInput accessibilityLabel="Message à l’établissement" testID="application-message" value={message} onChangeText={setMessage}
                  editable={!state.submitting} multiline maxLength={2000} textAlignVertical="top" placeholder="Présentez votre disponibilité…" placeholderTextColor={colors.muted} style={styles.input} />
              </View> : null}
              {state.options.length ? <View style={styles.section} testID="application-contract-options">
                <Text style={styles.label}>Choisissez votre contrat</Text>
                {state.options.map(option => <Pressable key={option.value} onPress={() => setChoice(option.value)} disabled={state.submitting}
                  accessibilityRole="radio" accessibilityState={{ checked: choice === option.value, disabled: state.submitting }}
                  testID={`application-contract-${option.value}`} style={[styles.option, choice === option.value && styles.optionSelected]}>
                  <Text style={shared.body}>{choice === option.value ? '● ' : '○ '}{option.label}</Text>
                </Pressable>)}
              </View> : null}
              <Pressable accessibilityRole="checkbox" accessibilityState={{ checked: confirmed, disabled: state.submitting }}
                onPress={() => setConfirmed(value => !value)} disabled={state.submitting} testID="application-confirm-planning" style={styles.checkbox}>
                <Text style={styles.checkmark}>{confirmed ? '☑' : '☐'}</Text><Text style={[shared.body, styles.checkText]}>J’ai vérifié toutes les dates et tous les horaires affichés.</Text>
              </Pressable>
              <ActionButton label={gateway.mode === 'demo' ? 'Simuler la confirmation' : action === 'POSTULER' ? 'Envoyer ma candidature' : 'Accepter tous ces créneaux'}
                busy={state.submitting} disabled={state.loading || state.needsRecheck || !confirmed || (state.options.length > 0 && !choice)}
                onPress={submit} testID="application-submit" />
            </View> : <StatusPanel title="Aucune candidature possible dans cet état" message="La mission a pu être attribuée ou son état a changé. Rechargez le dossier pour le vérifier." testID="application-unavailable" />}
            {!snapshot.documentsComplete ? <View style={[shared.card, styles.section]} testID="application-documents">
              <Text style={styles.label}>Documents à compléter</Text>
              <Text style={shared.small}>Le serveur vérifie les documents nécessaires au moment de l’attribution. Une candidature envoyée ne signifie pas que vos documents ont été validés.</Text>
              {onOpenDocuments ? <ActionButton secondary label="Voir mes documents" onPress={onOpenDocuments} /> : null}
            </View> : null}
            <ActionButton secondary label="Actualiser le dossier" busy={state.loading} disabled={state.submitting} onPress={() => void controller.refresh()} testID="application-refresh" />
          </>}
        </View>
      </ScrollView>
    </KeyboardAvoidingView>
  </SafeAreaView>;
}
const styles = StyleSheet.create({
  scroll: { flexGrow: 1, paddingTop: 18, paddingBottom: 36 }, content: { gap: 18 }, section: { gap: 14 },
  slot: { gap: 5, paddingVertical: 10, borderBottomWidth: 1, borderBottomColor: colors.border },
  label: { color: colors.text, fontSize: 16, lineHeight: 24, fontWeight: '600' },
  input: { minHeight: 110, borderWidth: 1, borderColor: colors.border, borderRadius: 14, padding: 14, fontSize: 16, lineHeight: 24, color: colors.text, backgroundColor: colors.background },
  option: { minHeight: 48, padding: 14, borderRadius: 14, borderWidth: 1, borderColor: colors.border }, optionSelected: { borderColor: colors.purple, backgroundColor: colors.lightPurple },
  checkbox: { flexDirection: 'row', gap: 12, alignItems: 'flex-start', minHeight: 48, paddingVertical: 8 }, checkmark: { color: colors.purple, fontSize: 26, lineHeight: 30 }, checkText: { flex: 1 },
});
