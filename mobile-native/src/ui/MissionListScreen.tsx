import { useEffect, useMemo, useState } from 'react';
import { FlatList, Keyboard, Platform, Pressable, RefreshControl, StyleSheet, Text, TextInput, View } from 'react-native';
import type { NativeStackScreenProps } from '@react-navigation/native-stack';
import { SafeAreaView } from 'react-native-safe-area-context';
import { defaultFilters, formatMissionPeriod, getMissionRemuneration } from '../data/presentation';
import type { Mission, MissionFilters } from '../data/types';
import { useSession } from '../session/SessionProvider';
import { ActionButton, ErrorNotice, ModeNotice, StatusPanel } from './components';
import { useGateway } from './gateway';
import type { NativeStackParams } from './navigation';
import { missionResourceKey } from './resource-key';
import { colors, shared } from './theme';
import { useMissionResource } from './useMissionResource';

type ContractFilter = NonNullable<MissionFilters['typeContrat']>;
const contractOptions: { value: ContractFilter; label: string }[] = [
  { value: 'TOUS', label: 'Tous les contrats' }, { value: 'CDD', label: 'CDD' }, { value: 'LIBERAL', label: 'Libéral' },
];

export function contractLabel(value: string | null) {
  if (value === 'LIBERAL') return 'Libéral';
  if (value === 'CDD' || value === 'SALARIE') return 'CDD';
  if (value === 'TOUS') return 'CDD ou libéral';
  return 'Contrat à préciser';
}

function MissionCard({ mission, onPress }: { mission: Mission; onPress: () => void }) {
  const location = mission.etablissements?.adresse_ville ?? 'Localisation à préciser';
  return <Pressable onPress={onPress} accessibilityRole="button"
    accessibilityLabel={`${mission.intitule}, ${mission.etablissements?.nom ?? 'Établissement'}, ${location}, ${formatMissionPeriod(mission)}, ${getMissionRemuneration(mission)}`}
    accessibilityHint="Ouvre le détail de la mission" testID={`mission-card-${mission.id}`}
    style={({ pressed }) => [styles.missionCard, pressed && styles.pressed]}>
    <View style={styles.cardBadges}>
      <Text style={styles.contractBadge}>{contractLabel(mission.type_contrat_recherche)}</Text>
      {mission.est_urgente ? <Text style={styles.urgentBadge}>Urgent</Text> : null}
    </View>
    <Text style={styles.missionTitle}>{mission.intitule}</Text>
    <Text style={styles.establishment}>{mission.etablissements?.nom ?? 'Établissement'}</Text>
    <Text style={shared.small}>{location}{mission.distance_km !== null ? ` · ${Math.round(mission.distance_km)} km` : ''}</Text>
    <View style={styles.cardSeparator} />
    <Text style={styles.date}>{formatMissionPeriod(mission)}</Text>
    <View style={styles.cardBottom}>
      <Text style={styles.remuneration}>{getMissionRemuneration(mission)}</Text>
      <Text style={styles.chevron} accessible={false}>›</Text>
    </View>
  </Pressable>;
}

export function MissionListScreen({ navigation }: NativeStackScreenProps<NativeStackParams, 'Missions'>) {
  const { snapshot } = useSession();
  const gateway = useGateway();
  const context = snapshot.context!;
  const [cityInput, setCityInput] = useState('');
  const [city, setCity] = useState('');
  const [contract, setContract] = useState<ContractFilter>('TOUS');
  useEffect(() => {
    const delay = setTimeout(() => setCity(cityInput.trim()), 300);
    return () => clearTimeout(delay);
  }, [cityInput]);
  const filters = useMemo<MissionFilters>(() => ({ ...defaultFilters(context.profile), ville: city || undefined, typeContrat: contract }), [context.profile, city, contract]);
  const resource = useMissionResource(missionResourceKey(snapshot.epoch, context, { kind: 'list', filters }), signal => gateway.listMissions(context, filters, signal));
  const hasFilters = cityInput.length > 0 || contract !== 'TOUS';
  const resetFilters = () => { Keyboard.dismiss(); setCityInput(''); setCity(''); setContract('TOUS'); };

  return <SafeAreaView style={shared.screen} edges={['left', 'right', 'bottom']}>
    <FlatList data={resource.data ?? []} keyExtractor={mission => mission.id} testID="missions-list"
      renderItem={({ item }) => <View style={shared.content}><MissionCard mission={item} onPress={() => { Keyboard.dismiss(); navigation.navigate('Mission', { id: item.id }); }} /></View>}
      ItemSeparatorComponent={() => <View style={styles.cardGap} />}
      contentContainerStyle={styles.listContent} keyboardShouldPersistTaps="handled"
      keyboardDismissMode={Platform.OS === 'ios' ? 'interactive' : 'on-drag'}
      refreshControl={<RefreshControl refreshing={resource.loading && resource.data !== null} onRefresh={resource.refresh}
        tintColor={colors.pink} colors={[colors.pink]} />}
      ListHeaderComponent={<View style={[shared.content, styles.header]}>
        <ModeNotice mode={snapshot.mode} />
        <View style={styles.heading}>
          <Text style={shared.title} accessibilityRole="header">À vous de choisir.</Text>
          <Text style={shared.subtitle}>Des missions pour exercer à votre rythme.</Text>
        </View>
        <View style={styles.searchRow}>
          <TextInput accessibilityLabel="Rechercher une ville" value={cityInput} onChangeText={setCityInput}
            placeholder="Rechercher une ville" placeholderTextColor={colors.muted} autoCorrect={false}
            autoComplete="off" returnKeyType="search" onSubmitEditing={() => { setCity(cityInput.trim()); Keyboard.dismiss(); }}
            style={styles.search} testID="mission-city" />
          {cityInput ? <Pressable accessibilityRole="button" accessibilityLabel="Effacer la ville" onPress={() => { setCityInput(''); setCity(''); }}
            style={styles.clearSearch} testID="clear-city"><Text style={styles.clearText}>×</Text></Pressable> : null}
        </View>
        <View style={styles.filterRow} accessibilityRole="radiogroup" accessibilityLabel="Type de contrat">
          {contractOptions.map(option => <Pressable key={option.value} accessibilityRole="radio" accessibilityState={{ checked: contract === option.value }}
            onPress={() => { Keyboard.dismiss(); setContract(option.value); }} testID={`contract-filter-${option.value}`}
            style={({ pressed }) => [styles.filter, contract === option.value && styles.selectedFilter, pressed && styles.pressed]}>
            <Text style={[styles.filterText, contract === option.value && styles.selectedFilterText]}>{option.label}</Text>
          </Pressable>)}
        </View>
        {resource.error ? <ErrorNotice message={resource.error} onRetry={resource.refresh} /> : null}
        {resource.data !== null ? <Text style={styles.count} accessibilityLiveRegion="polite" testID="mission-count">
          {resource.data.length} mission{resource.data.length === 1 ? '' : 's'} disponible{resource.data.length === 1 ? '' : 's'}
        </Text> : null}
      </View>}
      ListEmptyComponent={resource.loading ? <StatusPanel loading title="Recherche des missions" message="Un instant, nous préparons votre sélection." testID="missions-loading" />
        : resource.error ? <StatusPanel title="Connexion interrompue" message="Vous pouvez réessayer à tout moment." testID="missions-error" />
          : <StatusPanel title="Aucune mission pour le moment" message={hasFilters ? 'Essayez une autre ville ou un autre type de contrat.' : 'Les nouvelles missions apparaîtront ici dès leur publication.'} testID="missions-empty">
            {hasFilters ? <ActionButton secondary label="Effacer les filtres" onPress={resetFilters} testID="reset-filters" />
              : <ActionButton secondary label="Actualiser" onPress={resource.refresh} testID="refresh-empty" />}
          </StatusPanel>}
      ListFooterComponent={<View style={[shared.content, styles.footer]}><Text style={styles.footerText}>Vous explorez le premier parcours natif de Jolene.{"\n"}Les candidatures restent dans l’application actuelle.</Text></View>}
    />
  </SafeAreaView>;
}

const styles = StyleSheet.create({
  listContent: { flexGrow: 1, paddingTop: 18, paddingBottom: 20 },
  header: { gap: 18, paddingBottom: 16 },
  heading: { gap: 7, marginTop: 4 },
  searchRow: { flexDirection: 'row', alignItems: 'center', borderRadius: 17, backgroundColor: colors.surface, borderWidth: 1, borderColor: colors.border },
  search: { flex: 1, minWidth: 0, minHeight: 54, paddingVertical: 15, paddingHorizontal: 16, fontSize: 16, color: colors.text },
  clearSearch: { minWidth: 44, minHeight: 54, alignItems: 'center', justifyContent: 'center' },
  clearText: { color: colors.secondary, fontSize: 26 },
  filterRow: { flexDirection: 'row', flexWrap: 'wrap', gap: 8 },
  filter: { minHeight: 44, paddingHorizontal: 16, paddingVertical: 12, borderRadius: 22, borderWidth: 1, borderColor: colors.border, backgroundColor: colors.surface, justifyContent: 'center' },
  selectedFilter: { borderColor: colors.purple, backgroundColor: colors.lightPurple },
  filterText: { fontSize: 14, lineHeight: 20, fontWeight: '600', color: colors.secondary },
  selectedFilterText: { color: colors.purple },
  count: { fontSize: 14, lineHeight: 21, fontWeight: '600', color: colors.secondary, marginTop: 2 },
  cardGap: { height: 14 },
  missionCard: { ...shared.card, gap: 7 },
  pressed: { opacity: 0.7 },
  cardBadges: { flexDirection: 'row', flexWrap: 'wrap', gap: 8, marginBottom: 7 },
  contractBadge: { overflow: 'hidden', paddingVertical: 5, paddingHorizontal: 10, borderRadius: 8, fontSize: 12, lineHeight: 18, fontWeight: '600', color: colors.purple, backgroundColor: colors.lightPurple },
  urgentBadge: { overflow: 'hidden', paddingVertical: 5, paddingHorizontal: 10, borderRadius: 8, fontSize: 12, lineHeight: 18, fontWeight: '600', color: '#9A3E1C', backgroundColor: '#FFF0E6' },
  missionTitle: { fontSize: 20, lineHeight: 27, fontWeight: '700', color: colors.text, letterSpacing: -0.3 },
  establishment: { fontSize: 15, lineHeight: 22, color: colors.secondary },
  cardSeparator: { height: 1, backgroundColor: colors.border, marginVertical: 9 },
  date: { fontSize: 14, lineHeight: 21, color: colors.secondary },
  cardBottom: { flexDirection: 'row', alignItems: 'center', gap: 12 },
  remuneration: { flex: 1, fontSize: 18, lineHeight: 26, fontWeight: '700', color: colors.pink },
  chevron: { color: colors.pink, fontSize: 30, lineHeight: 35, marginRight: 1 },
  footer: { paddingTop: 28, paddingBottom: 12 },
  footerText: { fontSize: 12, lineHeight: 19, color: colors.secondary, textAlign: 'center' },
});
