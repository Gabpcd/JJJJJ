import { useCallback, useRef, useState } from 'react';
import { AppState, FlatList, Pressable, RefreshControl, StyleSheet, Text, View } from 'react-native';
import { useFocusEffect } from '@react-navigation/native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { ContractWorkflowError, type ContractContext, type ContractGateway, type ContractPage, type ContractRecord } from '../../workflows/contracts/types';
import { ActionButton, ErrorNotice, ModeNotice, StatusPanel } from '../components';
import { colors, shared } from '../theme';
import { contractContextKey, contractDate, contractStatus, contractType } from './presentation';

export interface ContractsListScreenProps {
  context: ContractContext; sessionEpoch: number; gateway: ContractGateway; onOpenContract: (contractId: string) => void;
}
export function ContractsListScreen(props: ContractsListScreenProps) {
  return <Content key={contractContextKey(props.context, props.sessionEpoch)} {...props} />;
}
function Content({ context, gateway, onOpenContract }: ContractsListScreenProps) {
  const [page, setPage] = useState(0);
  const [resource, setResource] = useState<{ data: ContractPage | null; loading: boolean; error: string | null }>({ data: null, loading: true, error: null });
  const [active, setActive] = useState(false); const current = useRef(false);
  const request = useRef<AbortController | null>(null); const generation = useRef(0); const list = useRef<FlatList<ContractRecord>>(null);
  const latestContext = useRef(context); latestContext.current = context;
  const cancel = useCallback(() => { ++generation.current; request.current?.abort(); request.current = null; }, []);
  const reload = useCallback(() => {
    if (!current.current) return;
    cancel(); const sequence = ++generation.current; const abort = new AbortController(); request.current = abort;
    setResource(previous => ({ ...previous, loading: true, error: null }));
    let timer: ReturnType<typeof setTimeout> | undefined;
    const timeout = new Promise<never>((_, reject) => { timer = setTimeout(() => { abort.abort(); reject(new Error('timeout')); }, 20_000); });
    void Promise.race([gateway.list(latestContext.current, page, abort.signal), timeout]).then(data => {
      if (!current.current || sequence !== generation.current || abort.signal.aborted) return;
      const identity = latestContext.current;
      if (data.page !== page || data.rows.some(row => identity.kind === 'soignant'
        ? row.soignant_id !== identity.userId : row.etablissement_id !== identity.etablissementId)) throw new Error('scope');
      setResource({ data, loading: false, error: null });
    }).catch(error => {
      if (current.current && sequence === generation.current) setResource({ data: null, loading: false,
        error: error instanceof ContractWorkflowError ? error.message : 'Vos contrats ne peuvent pas être chargés. Vérifiez votre connexion puis réessayez.' });
    }).finally(() => { if (timer) clearTimeout(timer); if (request.current === abort) request.current = null; });
  }, [cancel, gateway, page]);
  useFocusEffect(useCallback(() => {
    const changed = (next: string) => {
      current.current = next === 'active'; setActive(current.current);
      if (current.current) reload(); else cancel();
    };
    changed(AppState.currentState);
    const listener = AppState.addEventListener('change', changed);
    return () => { current.current = false; setActive(false); listener.remove(); cancel(); };
  }, [cancel, reload]));
  const go = (next: number) => {
    if (resource.loading || !active || next < 0) return;
    cancel(); setResource({ data: null, loading: true, error: null }); setPage(next); list.current?.scrollToOffset({ offset: 0, animated: false });
  };
  return <SafeAreaView style={shared.screen} edges={['left', 'right', 'bottom']}>
    <FlatList ref={list} testID="contracts-list" data={resource.data?.rows ?? []} keyExtractor={item => item.id}
      contentContainerStyle={styles.list} refreshControl={<RefreshControl refreshing={resource.loading && !!resource.data}
        onRefresh={reload} tintColor={colors.pink} colors={[colors.pink]} />}
      ListHeaderComponent={<View style={[shared.content, styles.header]}>
        <ModeNotice mode={gateway.mode === 'demo' ? 'demo' : 'staging'} /><Text style={shared.title} accessibilityRole="header">Mes contrats</Text>
        <Text style={shared.subtitle}>Retrouvez les originaux de vos contrats et leurs signatures.</Text>
        {resource.error ? <ErrorNotice message={resource.error} onRetry={reload} /> : null}
        {resource.data ? <Text style={shared.small} testID="contracts-count">{resource.data.total} contrat{resource.data.total > 1 ? 's' : ''} · Page {page + 1}</Text> : null}
      </View>}
      renderItem={({ item }) => <View style={[shared.content, styles.row]}>
        <Pressable disabled={!active || resource.loading} onPress={() => onOpenContract(item.id)} testID={`contract-card-${item.id}`}
          accessibilityRole="button" accessibilityLabel={`Contrat ${item.numero_contrat}, ${contractStatus(item.statut)}`}
          style={({ pressed }) => [shared.card, styles.card, pressed && styles.pressed]}>
          <Text style={styles.status}>{contractStatus(item.statut)}</Text>
          <Text style={shared.sectionTitle}>{item.numero_contrat}</Text>
          <Text style={shared.body}>{contractType(item.type_contrat)}</Text>
          {contractDate(item.cree_le) ? <Text style={shared.small}>Créé le {contractDate(item.cree_le)}</Text> : null}
          <Text style={styles.open}>Consulter le contrat ›</Text>
        </Pressable>
      </View>}
      ListEmptyComponent={resource.loading ? <StatusPanel loading title="Chargement de vos contrats" /> : resource.error ? null
        : <StatusPanel title="Aucun contrat sur cette page" message="Les contrats liés à vos missions apparaîtront ici." testID="contracts-empty" />}
      ListFooterComponent={<View style={[shared.content, styles.footer]}>
        {page > 0 ? <ActionButton secondary label="Page précédente" disabled={!active || resource.loading} onPress={() => go(page - 1)} testID="contracts-previous" /> : null}
        {resource.data?.nextPage != null ? <ActionButton secondary label="Page suivante" disabled={!active || resource.loading}
          onPress={() => go(resource.data!.nextPage!)} testID="contracts-next" /> : null}
      </View>} />
  </SafeAreaView>;
}
const styles = StyleSheet.create({
  list: { paddingTop: 18, paddingBottom: 30, flexGrow: 1 }, header: { gap: 16, paddingBottom: 22 }, row: { marginBottom: 12 },
  card: { gap: 10 }, status: { color: colors.purple, fontSize: 14, lineHeight: 21, fontWeight: '600' },
  open: { color: colors.pink, fontSize: 16, lineHeight: 24, fontWeight: '600', marginTop: 8 }, pressed: { opacity: 0.7 },
  footer: { gap: 12, paddingTop: 12, paddingBottom: 22 },
});
