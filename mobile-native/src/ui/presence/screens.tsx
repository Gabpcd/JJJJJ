import { useEffect, useRef, useState } from 'react';
import { AppState, Keyboard, KeyboardAvoidingView, Platform, Pressable, RefreshControl, ScrollView, StyleSheet, Text, TextInput, View } from 'react-native';
import { useIsFocused } from '@react-navigation/native';
import { SafeAreaView } from 'react-native-safe-area-context';
import type { PresenceContext } from '../../workflows/presence/types';
import { ActionButton, ErrorNotice, LabelValue, ModeNotice, StatusPanel } from '../components';
import { colors, shared } from '../theme';
import { presenceDate, presencePeriod, presenceReason, presenceStatus } from './presentation';
import { presenceScopeKey, type PresenceScreenGateway, type PresenceScreenProps } from './types';
import { usePresenceResource } from './usePresenceResource';
import { usePresenceScan } from './usePresenceScan';
import type { ManagedPresenceSensors } from '../../media/presence/types';
import { PresenceSensorControls } from './PresenceSensorControls';
import { PresenceQr } from './PresenceQr';

function Notice({ gateway }: { gateway: PresenceScreenGateway }) {
  return <><ModeNotice mode={gateway.mode === 'demo' ? 'demo' : 'staging'} />
    {gateway.mode === 'demo' ? <Text style={shared.small} testID="presence-demo-notice">Tous les pointages, horaires et codes de cette démonstration sont fictifs.</Text> : null}</>;
}

export function PresenceListScreen({ gateway, context, onMission, onScan }: PresenceScreenProps & { onScan?: () => void }) {
  const [filter, setFilter] = useState<'active' | 'history'>('active'); const [offset, setOffset] = useState(0);
  const key = presenceScopeKey(gateway, context);
  const resource = usePresenceResource(`${key}:${filter}:${offset}`, signal => gateway.list(context, { status: filter, offset }, signal));
  useEffect(() => { setOffset(0); setFilter('active'); }, [key]);
  return <SafeAreaView style={shared.screen} edges={['left', 'right']}>
    <ScrollView testID="presence-list-scroll" contentContainerStyle={styles.scroll}
      refreshControl={<RefreshControl refreshing={resource.loading && resource.data !== null} onRefresh={() => void resource.refresh()} tintColor={colors.pink} />}>
      <View style={[shared.content, styles.content]}>
        <Notice gateway={gateway} />
        <Text style={shared.title} accessibilityRole="header">Présences</Text>
        <Text style={shared.subtitle}>{context.kind === 'soignant' ? 'Retrouvez vos arrivées et vos départs.' : 'Affichez le code et suivez les présences des missions de votre établissement.'}</Text>
        {context.kind === 'soignant' && onScan ? <ActionButton label="Saisir un code de pointage" onPress={onScan} testID="presence-open-scan" /> : null}
        <View style={styles.tabs} accessibilityRole="tablist">
          {(['active', 'history'] as const).map(value => <Pressable key={value} accessibilityRole="tab" accessibilityState={{ selected: filter === value }}
            testID={`presence-tab-${value}`} onPress={() => { setOffset(0); setFilter(value); }} style={[styles.tab, filter === value && styles.selectedTab]}>
            <Text style={[styles.tabText, filter === value && styles.selectedText]}>{value === 'active' ? 'En cours / à venir' : 'Historique'}</Text>
          </Pressable>)}
        </View>
        {resource.error ? <ErrorNotice message={resource.error} onRetry={() => void resource.refresh()} /> : null}
        {resource.loading && !resource.data ? <StatusPanel title="Chargement des présences" loading testID="presence-list-loading" /> : null}
        {resource.data?.rows.map(mission => <Pressable key={mission.id} accessibilityRole="button" accessibilityLabel={`${mission.intitule}, ${presenceStatus(mission.statut)}`}
          testID={`presence-mission-${mission.id}`} onPress={() => onMission(mission.id)} style={({ pressed }) => [shared.card, styles.mission, pressed && styles.pressed]}>
          <Text style={styles.tag}>{presenceStatus(mission.statut)}</Text><Text style={shared.sectionTitle}>{mission.intitule}</Text>
          {mission.service ? <Text style={shared.small}>{mission.service}</Text> : null}
          <Text style={shared.body}>{presencePeriod(mission)}</Text><Text style={styles.link}>Voir les présences ›</Text>
        </Pressable>)}
        {resource.data && !resource.data.rows.length ? <StatusPanel title="Aucune mission dans cette liste" testID="presence-list-empty"
          message={filter === 'active' ? 'Vos missions attribuées apparaîtront ici.' : 'Les missions terminées apparaîtront ici.'} /> : null}
        {offset > 0 ? <ActionButton secondary label="Revenir au début de la liste" onPress={() => setOffset(0)} testID="presence-first-page" /> : null}
        {resource.data?.nextOffset !== null && resource.data?.nextOffset !== undefined ? <ActionButton secondary label="Missions suivantes"
          onPress={() => setOffset(resource.data!.nextOffset!)} testID="presence-next-page" /> : null}
        <Text style={shared.small}>Horaires de Paris.</Text>
      </View>
    </ScrollView>
  </SafeAreaView>;
}

export function PresenceDetailScreen({ gateway, context, missionId, onScan }: {
  gateway: PresenceScreenGateway; context: PresenceContext; missionId: string; onScan?: () => void;
}) {
  const resource = usePresenceResource(`${presenceScopeKey(gateway, context)}:${missionId}`,
    signal => gateway.read(context, missionId, signal), context.kind === 'etablissement' ? 5_000 : 15_000);
  const data = resource.data;
  const reason = data ? presenceReason(data.availability.reason) : null;
  return <SafeAreaView style={shared.screen} edges={['left', 'right']}>
    <ScrollView testID="presence-detail-scroll" contentContainerStyle={styles.scroll}
      refreshControl={<RefreshControl refreshing={resource.loading && !!data} onRefresh={() => void resource.refresh()} tintColor={colors.pink} />}>
      <View style={[shared.content, styles.content]}>
        <Notice gateway={gateway} />
        {resource.error ? <ErrorNotice message={resource.error} onRetry={() => void resource.refresh()} /> : null}
        {resource.loading && !data ? <StatusPanel loading title="Chargement du pointage" testID="presence-detail-loading" /> : null}
        {data ? <>
          <Text style={shared.title} accessibilityRole="header" testID="presence-detail-title">{data.mission.intitule}</Text>
          <Text style={shared.subtitle}>{presencePeriod(data.mission)}</Text>
          <View style={shared.card} testID="presence-current-state">
            <Text style={shared.sectionTitle} accessibilityRole="header" testID="presence-state-label">{data.hasOpenSegment ? 'Présence ouverte' : 'Aucune présence ouverte'}</Text>
            <Text style={shared.body}>{data.hasOpenSegment ? 'Une arrivée est enregistrée. Le prochain pointage enregistrera le départ.'
              : data.numberOfScans > 0 ? 'Les derniers pointages ont été relus.' : 'Aucun pointage n’est encore enregistré.'}</Text>
            <LabelValue label="Pointages enregistrés" value={String(data.numberOfScans)} testID="presence-scan-count" />
          </View>
          {context.kind === 'etablissement' ? <View style={[shared.card, styles.codeCard]} testID="presence-establishment-code-card">
            <Text style={shared.sectionTitle} accessibilityRole="header">Code de pointage</Text>
            {data.permissions.displayCode && data.establishmentCode ? <>
              <Text style={styles.code} accessibilityLabel={`Code de pointage ${data.establishmentCode.split('').join(' ')}`} testID="presence-establishment-code">{data.establishmentCode}</Text>
              <PresenceQr code={data.establishmentCode} />
              <Text style={shared.body}>Présentez ce code au soignant de cette mission. Il est renouvelé après chaque pointage enregistré.</Text>
              <Text style={shared.small}>{resource.loading ? 'Actualisation du code…'
                : gateway.mode === 'demo' ? 'Code fictif relu en mémoire.' : 'Code relu auprès du serveur.'}</Text>
            </> : <Text style={shared.body} testID="presence-code-unavailable">{!data.permissions.displayCode ? 'Votre accès ne permet pas d’afficher le code.'
              : reason ?? 'Le code n’est pas disponible pour le moment. Actualisez pour réessayer.'}</Text>}
          </View> : <>
            {reason ? <View style={shared.card}><Text style={shared.body} testID="presence-unavailable-reason">{reason}</Text></View> : null}
            {onScan && data.availability.canScan ? <ActionButton label="Saisir le code de pointage" onPress={onScan} testID="presence-detail-open-scan" /> : null}
          </>}
          <View style={[shared.card, styles.content]}>
            <Text style={shared.sectionTitle} accessibilityRole="header">Créneaux prévus</Text>
            {!data.planningComplete ? <Text style={shared.body}>Le planning complet ne peut pas être confirmé.</Text>
              : data.planned.map((segment, index) => <Text key={segment.id ?? index} style={shared.body}>{presenceDate(segment.debut)} → {segment.fin ? presenceDate(segment.fin) : 'Fin non renseignée'}</Text>)}
          </View>
          <View style={[shared.card, styles.content]}>
            <Text style={shared.sectionTitle} accessibilityRole="header">Présences enregistrées</Text>
            {data.segments.filter(segment => segment.type_creneau === 'EFFECTIF' && !segment.est_pause).map(segment => <View key={segment.id} style={styles.period}
              testID={`presence-effective-${segment.id}`}><LabelValue label="Arrivée" value={presenceDate(segment.debut)} />
              <LabelValue label="Départ" value={segment.fin ? presenceDate(segment.fin) : 'Pas encore enregistré'} /></View>)}
            {!data.segments.some(segment => segment.type_creneau === 'EFFECTIF' && !segment.est_pause) ? <Text style={shared.body}>Aucune présence enregistrée.</Text> : null}
          </View>
          <ActionButton secondary label="Actualiser le pointage" onPress={() => void resource.refresh()} disabled={resource.loading} testID="presence-detail-refresh" />
          <Text style={shared.small}>Horaires de Paris. Les heures affichées proviennent des pointages enregistrés.</Text>
        </> : null}
      </View>
    </ScrollView>
  </SafeAreaView>;
}

export function PresenceScanScreen({ gateway, context, onMission, sensors, gpsConsentEnabled = false }: PresenceScreenProps & {
  sensors?: ManagedPresenceSensors; gpsConsentEnabled?: boolean;
}) {
  const state = usePresenceScan(gateway, context); const [code, setCode] = useState('');
  const focused = useIsFocused(); const [sensorBusy, setSensorBusy] = useState(false); const sensorBusyRef = useRef(false);
  const [sensorError, setSensorError] = useState<string | null>(null);
  const key = presenceScopeKey(gateway, context);
  useEffect(() => { setCode(''); setSensorError(null); }, [key, focused]);
  useEffect(() => { const subscription = AppState.addEventListener('change', value => { if (value === 'background') setCode(''); });
    return () => subscription.remove(); }, []);
  const nativeSensors = gateway.mode === 'supabase' && sensors?.scope.userId === context.userId && sensors.scope.epoch === context.epoch ? sensors : undefined;
  const submit = async () => {
    if (!state.canScan || sensorBusyRef.current) return;
    Keyboard.dismiss(); const entered = code; let release: (() => void) | undefined;
    setSensorError(null);
    try {
      if (nativeSensors && gpsConsentEnabled) {
        try { release = nativeSensors.gps.arm(); }
        catch { nativeSensors.gps.cancel(); setSensorError('La localisation est indisponible. Cette tentative n’utilisera pas votre position.'); }
      }
      setCode(''); await state.scan(entered);
    }
    finally { release?.(); }
  };
  const result = state.result;
  if (context.kind !== 'soignant') return <SafeAreaView style={shared.screen}><StatusPanel title="Pointage soignant" message="La saisie du code se fait depuis le compte du soignant affecté." /></SafeAreaView>;
  return <SafeAreaView style={shared.screen} edges={['left', 'right']}>
    <KeyboardAvoidingView style={shared.flex} behavior={Platform.OS === 'ios' ? 'padding' : undefined}>
      <ScrollView testID="presence-scan-scroll" contentContainerStyle={styles.scroll} keyboardShouldPersistTaps="handled"
        keyboardDismissMode={Platform.OS === 'ios' ? 'interactive' : 'on-drag'}>
        <View style={[shared.content, styles.content]}>
          <Notice gateway={gateway} /><Text style={shared.title} accessibilityRole="header">Pointer ma présence</Text>
          <Text style={shared.subtitle}>Saisissez les six chiffres présentés par l’établissement. Le code sélectionne la mission ; sa confirmation indiquera celle qui a été pointée.</Text>
          {gateway.mode === 'demo' ? <View style={shared.card}><Text style={shared.body} testID="presence-demo-instructions">Pour essayer : 123456 pour « Mission A fictive », 654321 pour « Mission B fictive ». Les codes suivants apparaissent dans l’espace établissement fictif.</Text></View> : null}
          {state.journalError ? <ErrorNotice message={state.journalError} onRetry={() => void state.readJournal()} /> : null}
          {!state.journalReady && !state.journalError && !state.busy ? <StatusPanel loading title="Vérification du dernier pointage" testID="presence-journal-loading" /> : null}
          {state.error ? <ErrorNotice message={state.error} onRetry={() => void state.readJournal()} /> : null}
          {sensorError ? <ErrorNotice message={sensorError} /> : null}
          {result?.kind === 'confirmed' ? <View style={[shared.card, styles.confirmed]} accessibilityLiveRegion="polite" testID="presence-confirmed">
            <Text style={[shared.sectionTitle, styles.success]} accessibilityRole="header">{gateway.mode === 'demo' ? 'Simulation enregistrée' : result.proof.type_scan === 'OUVERTURE' ? 'Arrivée enregistrée' : 'Départ enregistré'}</Text>
            <Text style={shared.sectionTitle} testID="presence-actual-mission">{result.mission.intitule}</Text>
            <Text style={shared.body}>{presencePeriod(result.mission)}</Text>
            <LabelValue label={result.proof.type_scan === 'OUVERTURE' ? 'Arrivée' : 'Départ'} value={presenceDate(result.proof.scanne_le)} testID="presence-confirmed-time" />
            {result.proof.validation_etab_requise ? <Text style={shared.body}>Ce pointage doit être validé par l’établissement.</Text> : null}
            <Text style={shared.small}>{result.gps === 'available' ? 'Position transmise avec votre consentement.'
              : result.gps === 'denied' ? 'Position non transmise : accès à la localisation refusé.'
              : result.gps === 'unavailable' ? 'Position non transmise : localisation indisponible.' : 'Position non demandée.'}</Text>
            {result.journalStatus === 'unverified' && (!state.journalReady || state.pending) ? <Text style={shared.body} testID="presence-cleanup-unverified">Le pointage est enregistré. Son suivi local doit encore être relu avant une autre saisie.</Text> : null}
            <ActionButton label="Voir la mission pointée" onPress={() => onMission(result.mission.id)} testID="presence-open-actual-mission" />
          </View> : result ? <View style={shared.card} accessibilityLiveRegion="polite" testID={`presence-${result.kind}`}>
            <Text style={shared.sectionTitle}>{result.kind === 'rejected' ? 'Pointage refusé' : 'Confirmation en attente'}</Text><Text style={shared.body}>{result.message}</Text>
          </View> : null}
          {state.pending ? <View style={[shared.card, styles.content]} testID="presence-pending">
            <Text style={shared.sectionTitle}>Vérifier le dernier pointage</Text>
            <Text style={shared.body}>Ne saisissez pas de nouveau code. Cette vérification relit le résultat sans envoyer un autre pointage.</Text>
            <ActionButton label="Vérifier le pointage enregistré" onPress={() => void state.reconcile()} busy={state.busy}
              disabled={!state.canReconcile} testID="presence-reconcile" />
          </View> : null}
          <View style={[shared.card, styles.content]}>
            <Text style={shared.sectionTitle}>Code à six chiffres</Text>
            {nativeSensors ? <PresenceSensorControls sensors={nativeSensors} gateway={gateway} context={context}
              enabled={state.canScan} gpsConsentEnabled={gpsConsentEnabled} onCode={setCode}
              onBusy={value => { sensorBusyRef.current = value; setSensorBusy(value); }} /> : null}
            <TextInput accessibilityLabel="Code de pointage à six chiffres" testID="presence-code-input" value={code}
              onChangeText={value => setCode(value.trim())} keyboardType="number-pad" maxLength={64}
              autoCorrect={false} autoCapitalize="none" editable={state.canScan && !sensorBusy} style={[styles.input, (!state.canScan || sensorBusy) && styles.disabled]}
              placeholder="000000" placeholderTextColor={colors.muted} returnKeyType="done" onSubmitEditing={() => Keyboard.dismiss()} />
            <ActionButton label={gateway.mode === 'demo' ? 'Simuler le pointage' : 'Enregistrer le pointage'} onPress={() => void submit()}
              busy={state.busy && !state.pending} disabled={!state.canScan || sensorBusy || !/^\d{6}$/.test(code)} testID="presence-submit" />
            <Text style={shared.small}>{nativeSensors ? 'Le QR remplit le code. Confirmez ensuite le pointage ; la localisation reste facultative.'
              : 'La saisie manuelle du code reste possible sans caméra ni GPS.'}</Text>
          </View>
          <ActionButton secondary label="Actualiser le suivi" onPress={() => void state.readJournal()} disabled={state.busy} testID="presence-refresh-journal" />
        </View>
      </ScrollView>
    </KeyboardAvoidingView>
  </SafeAreaView>;
}

const styles = StyleSheet.create({
  scroll: { flexGrow: 1, paddingTop: 18, paddingBottom: 30 }, content: { gap: 18 }, mission: { gap: 9 },
  pressed: { opacity: 0.7 }, tag: { color: colors.purple, fontSize: 14, fontWeight: '700' },
  link: { color: colors.pink, fontSize: 15, fontWeight: '600', paddingTop: 8 },
  tabs: { flexDirection: 'row', flexWrap: 'wrap', gap: 10 }, tab: { flexGrow: 1, paddingHorizontal: 16, paddingVertical: 14,
    minHeight: 48, borderRadius: 16, borderWidth: 1, borderColor: colors.border, backgroundColor: colors.surface },
  selectedTab: { backgroundColor: colors.lightPurple, borderColor: colors.purple }, tabText: { textAlign: 'center', color: colors.secondary, fontSize: 15 },
  selectedText: { color: colors.purple, fontWeight: '700' }, codeCard: { gap: 15, backgroundColor: colors.lightPink },
  code: { fontSize: 44, lineHeight: 56, letterSpacing: 7, fontWeight: '700', color: colors.pink, textAlign: 'center', fontVariant: ['tabular-nums'] },
  period: { borderTopWidth: 1, borderTopColor: colors.border, paddingTop: 6 },
  confirmed: { gap: 14, borderColor: colors.success }, success: { color: colors.success },
  input: { minHeight: 60, paddingHorizontal: 18, paddingVertical: 13, borderWidth: 1, borderColor: colors.purple,
    borderRadius: 16, color: colors.text, backgroundColor: colors.surface, fontSize: 28, letterSpacing: 7, textAlign: 'center', fontVariant: ['tabular-nums'] },
  disabled: { opacity: 0.5 },
});
