import { Platform, RefreshControl, ScrollView, StyleSheet, Text, View } from 'react-native';
import type { NativeStackScreenProps } from '@react-navigation/native-stack';
import { SafeAreaView } from 'react-native-safe-area-context';
import { formatMissionPeriod, getMissionRemuneration, getProfessionLabel } from '../data/presentation';
import { useSession } from '../session/SessionProvider';
import { ActionButton, ErrorNotice, LabelValue, ModeNotice, StatusPanel } from './components';
import { useGateway } from './gateway';
import { contractLabel } from './MissionListScreen';
import type { NativeStackParams } from './navigation';
import { missionResourceKey } from './resource-key';
import { colors, shared } from './theme';
import { useMissionResource } from './useMissionResource';

const slotDate = (value: string) => new Intl.DateTimeFormat('fr-FR', { weekday: 'long', day: 'numeric', month: 'long', timeZone: 'Europe/Paris' }).format(new Date(value));
const slotTime = (value: string) => new Intl.DateTimeFormat('fr-FR', { hour: '2-digit', minute: '2-digit', timeZone: 'Europe/Paris' }).format(new Date(value));

export function MissionDetailScreen({ route, navigation }: NativeStackScreenProps<NativeStackParams, 'Mission'>) {
  const { snapshot } = useSession();
  const gateway = useGateway();
  const context = snapshot.context!;
  const resource = useMissionResource(missionResourceKey(snapshot.epoch, context, { kind: 'detail', id: route.params.id }), signal => gateway.getMission(route.params.id, context, signal));
  const mission = resource.data;

  return <SafeAreaView style={shared.screen} edges={['left', 'right', 'bottom']}>
    <ScrollView testID="mission-detail-scroll" contentContainerStyle={styles.scrollContent}
      keyboardDismissMode={Platform.OS === 'ios' ? 'interactive' : 'on-drag'}
      refreshControl={<RefreshControl refreshing={resource.loading && mission !== null} onRefresh={resource.refresh} tintColor={colors.pink} colors={[colors.pink]} />}>
      <View style={[shared.content, styles.content]}>
        <ModeNotice mode={snapshot.mode} />
        {resource.error ? <ErrorNotice message={resource.error} onRetry={resource.refresh} /> : null}
        {resource.loading && mission === null ? <StatusPanel loading title="Ouverture de la mission" testID="mission-detail-loading" />
          : !mission ? <StatusPanel title={resource.error ? 'La mission ne peut pas être chargée' : 'Cette mission n’est plus disponible'}
            message={resource.error ? 'Vérifiez votre connexion puis réessayez.' : 'Elle a pu être pourvue ou retirée. Retrouvez les autres missions dans la liste.'} testID="mission-unavailable">
            <ActionButton secondary label="Revenir aux missions" onPress={() => navigation.goBack()} testID="back-to-missions" />
          </StatusPanel> : <>
            <View style={styles.hero}>
              <Text style={styles.contract}>{contractLabel(mission.type_contrat_recherche)}{mission.est_urgente ? ' · Urgent' : ''}</Text>
              <Text style={shared.title} accessibilityRole="header" testID="mission-detail-title">{mission.intitule}</Text>
              <Text style={styles.establishment}>{mission.etablissements?.nom ?? 'Établissement'}</Text>
              <Text style={shared.subtitle}>{mission.etablissements?.adresse_ville ?? 'Localisation à préciser'}</Text>
            </View>
            <View style={styles.payCard}>
              <Text style={styles.payLabel}>{mission.mode_remuneration === 'RETROCESSION' ? 'Rémunération annoncée' : 'Tarif horaire annoncé'}</Text>
              <Text style={styles.payValue}>{getMissionRemuneration(mission)}</Text>
            </View>
            <View style={shared.card}>
              <Text style={shared.sectionTitle} accessibilityRole="header">En quelques mots</Text>
              <LabelValue label="Profession recherchée" value={getProfessionLabel(mission.profession_requise)} />
              <LabelValue label="Dates" value={formatMissionPeriod(mission)} />
              {mission.service ? <LabelValue label="Service" value={mission.service} /> : null}
              <LabelValue label="Établissement" value={mission.etablissements?.nom ?? 'Non renseigné'} />
              <LabelValue label="Localisation" value={[mission.etablissements?.adresse_code_postal, mission.etablissements?.adresse_ville].filter(Boolean).join(' ') || 'Non renseignée'} />
              <LabelValue label="Contrat recherché" value={contractLabel(mission.type_contrat_recherche)} />
            </View>
            <View style={[shared.card, styles.section]}>
              <Text style={shared.sectionTitle} accessibilityRole="header">La mission</Text>
              <Text style={shared.body} selectable>{mission.description?.trim() || 'L’établissement n’a pas ajouté de description.'}</Text>
            </View>
            <View style={[shared.card, styles.section]}>
              <Text style={shared.sectionTitle} accessibilityRole="header">Votre planning</Text>
              {mission.erreur_planning || !mission.planning_exact ? <Text style={shared.subtitle}>Le planning détaillé n’est pas disponible pour le moment. Actualisez pour réessayer.</Text>
                : mission.creneaux_planifies.map((slot, index) => <View key={slot.id ?? `${slot.debut}-${index}`} style={styles.slot}>
                  <Text style={styles.slotDay}>{slotDate(slot.debut)}</Text>
                  <Text style={shared.body}>{slotTime(slot.debut)} — {slot.fin ? slotTime(slot.fin) : 'Fin à préciser'}</Text>
                  {slot.fin && slotDate(slot.fin) !== slotDate(slot.debut) ? <Text style={shared.small}>Fin le {slotDate(slot.fin)}</Text> : null}
                </View>)}
              <Text style={shared.small}>Horaires de Paris.</Text>
            </View>
            <View style={styles.pilotNote}>
              <Text style={styles.pilotTitle}>Vous consultez le pilote natif</Text>
              <Text style={shared.small}>La candidature, le contrat et le paiement restent dans l’application actuelle. Aucune candidature n’est envoyée depuis cet écran.</Text>
            </View>
          </>}
      </View>
    </ScrollView>
  </SafeAreaView>;
}

const styles = StyleSheet.create({
  scrollContent: { flexGrow: 1, paddingTop: 18, paddingBottom: 28 },
  content: { gap: 20 },
  hero: { gap: 9, paddingVertical: 6 },
  contract: { color: colors.purple, fontWeight: '700', fontSize: 14, lineHeight: 21, marginBottom: 4 },
  establishment: { color: colors.text, fontSize: 18, lineHeight: 27, fontWeight: '600' },
  payCard: { backgroundColor: colors.lightPink, padding: 22, borderRadius: 24, gap: 9 },
  payLabel: { color: '#7D315B', fontSize: 13, lineHeight: 20, fontWeight: '600' },
  payValue: { color: colors.pink, fontSize: 27, lineHeight: 36, fontWeight: '700', letterSpacing: -0.5 },
  section: { gap: 16 },
  slot: { gap: 4, paddingTop: 12, borderTopWidth: 1, borderTopColor: colors.border },
  slotDay: { color: colors.text, fontSize: 16, lineHeight: 24, fontWeight: '600' },
  pilotNote: { padding: 18, gap: 8, borderRadius: 18, backgroundColor: colors.lightPurple },
  pilotTitle: { fontSize: 15, lineHeight: 22, fontWeight: '600', color: colors.purple },
});
