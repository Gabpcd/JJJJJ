import { useEffect, useRef, useState, type ReactNode } from 'react';
import { FlatList, Keyboard, Platform, Pressable, RefreshControl, ScrollView, StyleSheet, Text, TextInput, View } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import type { Mission } from '../../data/types';
import { formatMissionPeriod, getMissionRemuneration, getProfessionLabel } from '../../data/presentation';
import { ESTABLISHMENT_PAGE_SIZE, ESTABLISHMENT_PERMISSION_KEYS, MISSION_STATUS_OPTIONS, establishmentResourceKey,
  type EstablishmentContext, type EstablishmentReadGateway } from '../../establishment';
import { ActionButton, ErrorNotice, LabelValue, ModeNotice, StatusPanel } from '../components';
import { colors, shared } from '../theme';
import { useEstablishmentResource } from './useEstablishmentResource';

export interface EstablishmentScreenProps { gateway: EstablishmentReadGateway; context: EstablishmentContext; }
export interface EstablishmentHomeScreenProps extends EstablishmentScreenProps {
  onOpenMissions: () => void; onOpenProfile: () => void; onSignOut: () => void;
}
export interface EstablishmentMissionListScreenProps extends EstablishmentScreenProps { onOpenMission: (id: string) => void; }
export interface EstablishmentMissionDetailScreenProps extends EstablishmentScreenProps { missionId: string; onBack: () => void; }

const permissionLabels: Record<typeof ESTABLISHMENT_PERMISSION_KEYS[number], string> = {
  lecture: 'Consulter l’établissement', missions: 'Gérer les missions', candidatures: 'Traiter les candidatures',
  contrats: 'Gérer les contrats', pointage: 'Gérer les présences', rh: 'Consulter le pilotage RH',
  lecture_paiement: 'Consulter la facturation', paiement: 'Effectuer des paiements',
  profil_etab: 'Modifier le profil', gerer_equipe: 'Gérer l’équipe', supprimer_compte: 'Supprimer le compte',
};
const roles: Record<string, string> = { PROPRIETAIRE: 'Propriétaire', ADMIN_GROUPE: 'Administrateur du groupe', RH: 'Ressources humaines', POINTAGE_ONLY: 'Présences uniquement', LECTURE_SEULE: 'Lecture seule' };
const statusLabels: Record<string, string> = { OUVERTE: 'Ouverte', ASSIGNEE: 'Assignée', EN_COURS: 'En cours', TERMINEE: 'Terminée', EXPIREE: 'Expirée', ANNULEE_PAR_ETABLISSEMENT: 'Annulée par l’établissement', ANNULEE_PAR_SOIGNANT: 'Annulée par le soignant', ABSENCE: 'Absence', LITIGE: 'Litige' };
const verificationLabels: Record<string, string> = { EN_ATTENTE: 'En attente', VERIFIE: 'Vérifié', REJETE: 'À régulariser', EXPIRE: 'À renouveler', REVUE_MANUELLE_REQUISE: 'Examen en cours', API_INDISPONIBLE: 'Vérification indisponible' };
const yesNo = (value: boolean | null) => value === null ? 'Non renseigné' : value ? 'Oui' : 'Non';
const formatDate = (value: string) => new Intl.DateTimeFormat('fr-FR', { weekday: 'long', day: 'numeric', month: 'long', timeZone: 'Europe/Paris' }).format(new Date(value));
const formatTime = (value: string) => new Intl.DateTimeFormat('fr-FR', { hour: '2-digit', minute: '2-digit', timeZone: 'Europe/Paris' }).format(new Date(value));
const contract = (value: string | null) => value === 'LIBERAL' ? 'Libéral' : value === 'SALARIE' || value === 'CDD' ? 'CDD' : 'Contrat à préciser';

function Frame({ children, refreshing, onRefresh, testID }: { children: ReactNode; refreshing: boolean; onRefresh: () => void; testID: string }) {
  return <SafeAreaView style={shared.screen} edges={['left', 'right', 'bottom']}>
    <ScrollView testID={testID} contentContainerStyle={styles.scroll} keyboardShouldPersistTaps="handled"
      keyboardDismissMode={Platform.OS === 'ios' ? 'interactive' : 'on-drag'}
      refreshControl={<RefreshControl refreshing={refreshing} onRefresh={onRefresh} tintColor={colors.pink} colors={[colors.pink]} />}>
      <View style={[shared.content, styles.content]}>{children}</View>
    </ScrollView>
  </SafeAreaView>;
}
function Notice({ gateway }: { gateway: EstablishmentReadGateway }) { return <ModeNotice mode={gateway.mode === 'demo' ? 'demo' : 'staging'} />; }
function ReadOnlyNote() { return <Text style={shared.small}>Cet espace permet de consulter votre établissement et ses missions. Les actions de gestion restent disponibles dans l’application actuelle.</Text>; }

export function EstablishmentHomeScreen({ gateway, context, onOpenMissions, onOpenProfile, onSignOut }: EstablishmentHomeScreenProps) {
  const resource = useEstablishmentResource(establishmentResourceKey(context, 'home', gateway.mode), signal => gateway.getProfile(context, signal));
  const profile = resource.data;
  return <Frame testID="establishment-home" refreshing={resource.loading && profile !== null} onRefresh={resource.refresh}>
    <Notice gateway={gateway} />
    <Text accessibilityRole="header" style={shared.title}>Votre établissement</Text>
    {resource.error ? <ErrorNotice message={resource.error} onRetry={resource.refresh} /> : null}
    {resource.loading && !profile ? <StatusPanel loading title="Ouverture de votre espace" /> : profile ? <>
      <View style={[shared.card, styles.content]}>
        <Text style={shared.sectionTitle} testID="establishment-name">{profile.nom}</Text>
        <Text style={shared.subtitle}>{[profile.adresse_code_postal, profile.adresse_ville].filter(Boolean).join(' ') || 'Adresse non renseignée'}</Text>
        <LabelValue label="Votre rôle" value={roles[context.membershipRole ?? ''] ?? 'Membre de l’établissement'} />
        <LabelValue label="Vérification" value={verificationLabels[profile.statut_verification ?? ''] ?? 'Statut non renseigné'} />
      </View>
      <ActionButton label="Consulter les missions" onPress={onOpenMissions} testID="establishment-open-missions" />
      <ActionButton secondary label="Profil et accès" onPress={onOpenProfile} testID="establishment-open-profile" />
      <ReadOnlyNote />
    </> : !resource.error ? <StatusPanel title="Établissement indisponible" message="Actualisez pour vérifier votre accès." /> : null}
    <ActionButton secondary label="Se déconnecter" onPress={onSignOut} testID="establishment-sign-out" />
  </Frame>;
}

export function EstablishmentProfileScreen({ gateway, context }: EstablishmentScreenProps) {
  const resource = useEstablishmentResource(establishmentResourceKey(context, 'profile', gateway.mode), signal => gateway.getProfile(context, signal));
  const profile = resource.data;
  return <Frame testID="establishment-profile" refreshing={resource.loading && profile !== null} onRefresh={resource.refresh}>
    <Notice gateway={gateway} /><Text accessibilityRole="header" style={shared.title}>Profil et accès</Text>
    {resource.error ? <ErrorNotice message={resource.error} onRetry={resource.refresh} /> : null}
    {resource.loading && !profile ? <StatusPanel loading title="Chargement de votre établissement" /> : profile ? <>
      <View style={shared.card}>
        <Text style={shared.sectionTitle}>{profile.nom}</Text>
        <LabelValue label="Adresse" value={[profile.adresse_rue, profile.adresse_code_postal, profile.adresse_ville].filter(Boolean).join(' ') || 'Non renseignée'} />
        <LabelValue label="SIRET" value={profile.siret ?? 'Non renseigné'} /><LabelValue label="FINESS" value={profile.finess ?? 'Non renseigné'} />
        <LabelValue label="Email de contact" value={profile.email_contact ?? 'Non renseigné'} /><LabelValue label="Téléphone" value={profile.telephone_contact ?? 'Non renseigné'} />
        <LabelValue label="Vérification" value={verificationLabels[profile.statut_verification ?? ''] ?? 'Statut non renseigné'} />
        <LabelValue label="Contrat de service signé" value={yesNo(profile.contrat_service_signe)} />
        <LabelValue label="Publication autorisée pour l’établissement" value={yesNo(profile.peut_publier_missions)} />
      </View>
      <View style={shared.card}><Text accessibilityRole="header" style={shared.sectionTitle}>Vos droits dans l’établissement</Text>
        <LabelValue label="Votre rôle" value={roles[context.membershipRole ?? ''] ?? 'Membre de l’établissement'} />
        {ESTABLISHMENT_PERMISSION_KEYS.map(key => <LabelValue key={key} label={permissionLabels[key]} value={context.permissions[key] ? 'Autorisé' : 'Non autorisé'} />)}
      </View><ReadOnlyNote />
    </> : !resource.error ? <StatusPanel title="Profil indisponible" message="Actualisez pour vérifier votre accès." /> : null}
  </Frame>;
}

export function EstablishmentMissionListScreen({ gateway, context, onOpenMission }: EstablishmentMissionListScreenProps) {
  const [input, setInput] = useState('');
  const [search, setSearch] = useState('');
  const [status, setStatus] = useState('');
  const [offset, setOffset] = useState(0);
  const list = useRef<FlatList<Mission>>(null);
  useEffect(() => { const timer = setTimeout(() => { setSearch(input.trim()); setOffset(0); }, 300); return () => clearTimeout(timer); }, [input]);
  const resource = useEstablishmentResource(establishmentResourceKey(context, { kind: 'missions', status, search, offset }, gateway.mode),
    signal => gateway.listMissions(context, { status, search, offset }, signal));
  const goPage = (value: number) => { Keyboard.dismiss(); setOffset(value); list.current?.scrollToOffset({ offset: 0, animated: false }); };
  const reset = () => { Keyboard.dismiss(); setInput(''); setSearch(''); setStatus(''); goPage(0); };
  return <SafeAreaView style={shared.screen} edges={['left', 'right', 'bottom']}>
    <FlatList ref={list} testID="establishment-missions-list" data={resource.data?.missions ?? []} keyExtractor={item => item.id}
      contentContainerStyle={styles.scroll} keyboardShouldPersistTaps="handled" keyboardDismissMode={Platform.OS === 'ios' ? 'interactive' : 'on-drag'}
      refreshControl={<RefreshControl refreshing={resource.loading && resource.data !== null} onRefresh={resource.refresh} tintColor={colors.pink} colors={[colors.pink]} />}
      ListHeaderComponent={<View style={[shared.content, styles.content, styles.header]}><Notice gateway={gateway} />
        <Text accessibilityRole="header" style={shared.title}>Vos missions</Text>
        <Text style={shared.subtitle}>Retrouvez les missions de votre établissement, à chaque étape.</Text>
        <TextInput accessibilityLabel="Rechercher une mission" testID="establishment-mission-search" value={input} onChangeText={setInput}
          placeholder="Rechercher une mission" placeholderTextColor={colors.muted} style={styles.input} returnKeyType="search" autoCorrect={false}
          onSubmitEditing={() => { setSearch(input.trim()); goPage(0); }} />
        <View style={styles.filters} accessibilityRole="radiogroup" accessibilityLabel="Statut des missions">
          {MISSION_STATUS_OPTIONS.map(option => <Pressable key={option.value} accessibilityRole="radio" accessibilityState={{ checked: status === option.value }}
            testID={`establishment-status-${option.value || 'TOUTES'}`} onPress={() => { setStatus(option.value); goPage(0); }}
            style={({ pressed }) => [styles.filter, status === option.value && styles.selected, pressed && styles.pressed]}>
            <Text style={styles.filterText}>{option.label}</Text>
          </Pressable>)}
        </View>
        {resource.error ? <ErrorNotice message={resource.error} onRetry={resource.refresh} /> : null}
        {resource.data ? <Text accessibilityLiveRegion="polite" style={shared.small} testID="establishment-mission-count">{resource.data.missions.length} mission{resource.data.missions.length === 1 ? '' : 's'} sur cette page</Text> : null}
      </View>}
      renderItem={({ item }) => <View style={[shared.content, styles.row]}>
        <Pressable accessibilityRole="button" accessibilityLabel={`${item.intitule}, ${statusLabels[item.statut] ?? item.statut}, ${formatMissionPeriod(item)}`}
          testID={`establishment-mission-${item.id}`} onPress={() => { Keyboard.dismiss(); onOpenMission(item.id); }} style={({ pressed }) => [shared.card, styles.content, pressed && styles.pressed]}>
          <Text style={styles.badge}>{statusLabels[item.statut] ?? item.statut}{item.est_urgente ? ' · Urgent' : ''}</Text>
          <Text style={shared.sectionTitle}>{item.intitule}</Text>
          <Text style={shared.small}>{getProfessionLabel(item.profession_requise)} · {contract(item.type_contrat_recherche)}</Text>
          <Text style={shared.body}>{formatMissionPeriod(item)}</Text>
          <Text style={styles.rate}>{getMissionRemuneration(item)}</Text>
          <Text style={shared.small}>Consulter le détail ›</Text>
        </Pressable>
      </View>}
      ListEmptyComponent={<StatusPanel loading={resource.loading} title={resource.loading ? 'Chargement des missions' : resource.error ? 'Missions indisponibles' : 'Aucune mission sur cette page'}
        message={resource.error ? 'Réessayez pour vérifier votre accès.' : input || status ? 'Essayez une autre recherche ou un autre statut.' : 'Les missions publiées apparaîtront ici.'}>
        {!resource.loading && !resource.error && (input || status) ? <ActionButton secondary label="Effacer les filtres" onPress={reset} testID="establishment-reset-filters" /> : null}
      </StatusPanel>}
      ListFooterComponent={<View style={[shared.content, styles.content, styles.footer]}>
        {offset > 0 ? <ActionButton secondary label="Page précédente" onPress={() => goPage(Math.max(0, offset - ESTABLISHMENT_PAGE_SIZE))} disabled={resource.loading} /> : null}
        {resource.data?.nextOffset !== null && resource.data?.nextOffset !== undefined ? <ActionButton secondary label="Page suivante" onPress={() => goPage(resource.data!.nextOffset!)} disabled={resource.loading} testID="establishment-next-page" /> : null}
        <ReadOnlyNote />
      </View>} />
  </SafeAreaView>;
}

export function EstablishmentMissionDetailScreen({ gateway, context, missionId, onBack }: EstablishmentMissionDetailScreenProps) {
  const resource = useEstablishmentResource(establishmentResourceKey(context, { kind: 'mission', missionId }, gateway.mode), signal => gateway.getMission(missionId, context, signal));
  const mission = resource.data;
  return <Frame testID="establishment-mission-detail" refreshing={resource.loading && mission !== null} onRefresh={resource.refresh}>
    <Notice gateway={gateway} />
    {resource.error ? <ErrorNotice message={resource.error} onRetry={resource.refresh} /> : null}
    {resource.loading && !mission ? <StatusPanel loading title="Ouverture de la mission" /> : !mission ? <StatusPanel title="Mission indisponible" message="Elle a pu être retirée, ou votre accès a changé.">
      <ActionButton secondary label="Revenir aux missions" onPress={onBack} />
    </StatusPanel> : <>
      <Text style={styles.badge}>{statusLabels[mission.statut] ?? mission.statut}{mission.est_urgente ? ' · Urgent' : ''}</Text>
      <Text accessibilityRole="header" style={shared.title} testID="establishment-mission-detail-title">{mission.intitule}</Text>
      <View style={shared.card}>
        <LabelValue label="Profession recherchée" value={getProfessionLabel(mission.profession_requise)} />
        <LabelValue label="Contrat recherché" value={contract(mission.type_contrat_recherche)} />
        {mission.service ? <LabelValue label="Service" value={mission.service} /> : null}
        <LabelValue label="Période" value={formatMissionPeriod(mission)} />
        <LabelValue label={mission.mode_remuneration === 'RETROCESSION' ? 'Rémunération annoncée' : 'Tarif horaire annoncé'} value={getMissionRemuneration(mission)} />
        {mission.rist_plafond_applique ? <Text style={shared.small}>Le tarif affiché tient compte du plafond appliqué à cette mission.</Text> : null}
      </View>
      <View style={[shared.card, styles.content]}><Text accessibilityRole="header" style={shared.sectionTitle}>Description</Text>
        <Text selectable style={shared.body}>{mission.description?.trim() || 'Aucune description ajoutée.'}</Text>
      </View>
      <View style={[shared.card, styles.content]}><Text accessibilityRole="header" style={shared.sectionTitle}>Planning prévisionnel</Text>
        {!mission.planning_exact ? <Text style={shared.subtitle} testID="establishment-planning-incomplete">Le planning détaillé est incomplet. Actualisez pour le vérifier.</Text>
          : mission.creneaux_planifies.map((slot, index) => <View key={slot.id ?? `${slot.debut}-${index}`} style={styles.slot}>
            <Text style={shared.body}>{formatDate(slot.debut)}</Text><Text style={shared.body}>{formatTime(slot.debut)} — {slot.fin ? formatTime(slot.fin) : 'Fin non renseignée'}</Text>
            {slot.fin && formatDate(slot.fin) !== formatDate(slot.debut) ? <Text style={shared.small}>Fin le {formatDate(slot.fin)}</Text> : null}
          </View>)}
        <Text style={shared.small}>Horaires de Paris.</Text>
      </View><ReadOnlyNote />
    </>}
  </Frame>;
}

const styles = StyleSheet.create({
  scroll: { flexGrow: 1, paddingTop: 18, paddingBottom: 28 }, content: { gap: 16 }, header: { paddingBottom: 20 },
  footer: { paddingTop: 20 }, row: { paddingBottom: 14 }, pressed: { opacity: 0.7 },
  input: { minHeight: 54, padding: 16, borderRadius: 17, borderWidth: 1, borderColor: colors.border, backgroundColor: colors.surface, fontSize: 16, color: colors.text },
  filters: { flexDirection: 'row', flexWrap: 'wrap', gap: 8 },
  filter: { minHeight: 44, paddingHorizontal: 14, paddingVertical: 12, borderRadius: 22, borderWidth: 1, borderColor: colors.border, backgroundColor: colors.surface, justifyContent: 'center' },
  selected: { backgroundColor: colors.lightPurple, borderColor: colors.purple },
  filterText: { color: colors.secondary, fontSize: 14, lineHeight: 20, fontWeight: '600' },
  badge: { color: colors.purple, fontSize: 14, lineHeight: 21, fontWeight: '700' },
  rate: { color: colors.pink, fontSize: 19, lineHeight: 27, fontWeight: '700' },
  slot: { gap: 5, paddingTop: 12, borderTopWidth: 1, borderTopColor: colors.border },
});
