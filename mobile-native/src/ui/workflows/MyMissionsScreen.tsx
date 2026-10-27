import { useCallback, useEffect, useRef, useState } from 'react';
import { AppState, FlatList, Pressable, RefreshControl, StyleSheet, Text, View } from 'react-native';
import { useFocusEffect } from '@react-navigation/native';
import { SafeAreaView } from 'react-native-safe-area-context';
import type { MissionReadContext } from '../../data/types';
import { statusLabel, workflowContextKey, type MissionWorkflowGateway, type MyMission, type MyMissionsPage, type MyMissionsTab } from '../../workflows/missions/types';
import { ActionButton, ErrorNotice, StatusPanel } from '../components';
import { colors, shared } from '../theme';
import { WorkflowNotice } from './WorkflowNotice';

export interface MyMissionsScreenProps {
  context: MissionReadContext; gateway: MissionWorkflowGateway;
  onOpenMission: (missionId: string) => void; onBrowseMissions: () => void;
}
const tabs: Array<{ value: MyMissionsTab; label: string }> = [
  { value: 'candidatures', label: 'Candidatures' }, { value: 'actives', label: 'En cours / à venir' }, { value: 'passees', label: 'Historique' },
];
const date = (value: string) => new Intl.DateTimeFormat('fr-FR', { day: 'numeric', month: 'short', year: 'numeric', timeZone: 'Europe/Paris' }).format(new Date(value));

export function MyMissionsScreen(props: MyMissionsScreenProps) {
  return <MyMissionsContent key={workflowContextKey(props.context)} {...props} />;
}
function MyMissionsContent({ context, gateway, onOpenMission, onBrowseMissions }: MyMissionsScreenProps) {
  const [tab, setTab] = useState<MyMissionsTab>('candidatures');
  const [page, setPage] = useState(0);
  const [resource, setResource] = useState<{ key: string; data: MyMissionsPage | null; loading: boolean; error: string | null }>({ key: '', data: null, loading: true, error: null });
  const key = `${workflowContextKey(context)}:${tab}:${page}:${gateway.mode}`;
  const abortRef = useRef<AbortController | null>(null);
  const latestContext = useRef(context); latestContext.current = context;
  const generation = useRef(0); const listRef = useRef<FlatList<MyMission>>(null);
  const cancel = useCallback(() => { ++generation.current; abortRef.current?.abort(); }, []);
  const load = useCallback(() => {
    cancel(); const current = ++generation.current; const abort = new AbortController(); abortRef.current = abort;
    setResource(previous => ({ key, data: previous.key === key ? previous.data : null, loading: true, error: null }));
    let timer: ReturnType<typeof setTimeout>;
    const timeout = new Promise<never>((_, reject) => { timer = setTimeout(() => { abort.abort(); reject(new Error('La connexion prend trop de temps. Réessayez.')); }, 20_000); });
    void Promise.race([gateway.listMine(latestContext.current, tab, page, abort.signal), timeout]).then(data => {
      if (current === generation.current && !abort.signal.aborted) setResource({ key, data, loading: false, error: null });
    }).catch(error => {
      if (current === generation.current) setResource(previous => ({ ...previous, loading: false,
        error: error instanceof Error ? error.message : 'Vos missions ne peuvent pas être chargées.' }));
    }).finally(() => clearTimeout(timer));
  }, [cancel, gateway, key, page, tab]);
  useFocusEffect(useCallback(() => {
    if (AppState.currentState === 'active') load();
    const listener = AppState.addEventListener('change', state => { if (state === 'active') load(); else cancel(); });
    return () => { listener.remove(); cancel(); };
  }, [cancel, load]));
  useEffect(() => () => cancel(), [cancel]);
  const current = resource.key === key ? resource : { key, data: null, loading: true, error: null };
  const chooseTab = (next: MyMissionsTab) => { if (next === tab) return; setTab(next); setPage(0); listRef.current?.scrollToOffset({ offset: 0, animated: false }); };
  return <SafeAreaView style={shared.screen} edges={['left', 'right', 'bottom']}>
    <FlatList ref={listRef} testID="my-missions-list" data={current.data?.rows ?? []} keyExtractor={item => item.id}
      contentContainerStyle={styles.list} keyboardShouldPersistTaps="handled"
      refreshControl={<RefreshControl refreshing={current.loading && current.data !== null} onRefresh={load} tintColor={colors.pink} colors={[colors.pink]} />}
      ListHeaderComponent={<View style={[shared.content, styles.header]}>
        <WorkflowNotice mode={gateway.mode} />
        <Text style={shared.title} accessibilityRole="header">Mes missions</Text>
        <Text style={shared.subtitle}>Retrouvez vos candidatures et les missions qui vous sont attribuées.</Text>
        <View style={styles.tabs}>{tabs.map(item => <Pressable key={item.value} accessibilityRole="tab"
          accessibilityState={{ selected: tab === item.value }} testID={`my-missions-tab-${item.value}`} onPress={() => chooseTab(item.value)}
          style={[styles.tab, tab === item.value && styles.selected]}><Text style={[styles.tabText, tab === item.value && styles.selectedText]}>{item.label}</Text></Pressable>)}</View>
        {current.error ? <ErrorNotice message={current.error} onRetry={load} /> : null}
      </View>}
      renderItem={({ item }) => <View style={[shared.content, styles.row]}><Pressable onPress={() => onOpenMission(item.id)}
        accessibilityRole="button" accessibilityLabel={`${item.title}, ${statusLabel(item.applicationStatus ?? item.status)}`}
        testID={`my-mission-${item.id}`} style={({ pressed }) => [shared.card, styles.card, pressed && styles.pressed]}>
        <Text style={styles.status}>{statusLabel(item.applicationStatus ?? item.status)}</Text>
        <Text style={styles.title}>{item.title}</Text>
        <Text style={shared.body}>{item.establishment}</Text>
        {item.city ? <Text style={shared.small}>{item.city}</Text> : null}
        <Text style={shared.small}>Période : {date(item.startsAt)} — {date(item.endsAt)}</Text>
        <Text style={styles.open}>Consulter le dossier ›</Text>
      </Pressable></View>}
      ListEmptyComponent={current.loading ? <StatusPanel loading title="Chargement de vos missions" /> : current.error ? null
        : <StatusPanel title={tab === 'candidatures' ? 'Aucune candidature' : tab === 'actives' ? 'Aucune mission active' : 'Aucune mission dans l’historique'}
          message={gateway.mode === 'demo' ? 'Envoyez une candidature fictive pour découvrir son suivi.' : 'Votre suivi apparaîtra ici au fil de vos missions.'} testID="my-missions-empty">
          <ActionButton label="Explorer les missions" onPress={onBrowseMissions} testID="my-missions-explore" />
        </StatusPanel>}
      ListFooterComponent={current.data?.hasMore ? <View style={[shared.content, styles.footer]}>
        <ActionButton secondary label="Afficher plus" busy={current.loading} onPress={() => setPage(value => value + 1)} testID="my-missions-more" />
      </View> : <View style={styles.footer} />}
    />
  </SafeAreaView>;
}
const styles = StyleSheet.create({
  list: { paddingTop: 18, paddingBottom: 30, flexGrow: 1 }, header: { gap: 16, paddingBottom: 22 },
  tabs: { flexDirection: 'row', flexWrap: 'wrap', gap: 8 }, tab: { minHeight: 46, paddingHorizontal: 14, paddingVertical: 12, borderRadius: 16, backgroundColor: colors.surface, borderWidth: 1, borderColor: colors.border },
  selected: { borderColor: colors.purple, backgroundColor: colors.lightPurple }, tabText: { fontSize: 14, lineHeight: 21, color: colors.secondary, fontWeight: '600' }, selectedText: { color: colors.purple },
  row: { marginBottom: 12 }, card: { gap: 7 }, title: { fontSize: 19, lineHeight: 27, color: colors.text, fontWeight: '700' },
  status: { color: colors.purple, fontSize: 13, lineHeight: 20, fontWeight: '700' }, open: { color: colors.pink, fontSize: 15, lineHeight: 23, fontWeight: '600', marginTop: 8 },
  pressed: { opacity: 0.7 }, footer: { paddingVertical: 16 },
});
