import { useEffect, useState } from 'react';
import { Alert, Linking, Pressable, ScrollView, StyleSheet, Text } from 'react-native';
import { DefaultTheme, NavigationContainer } from '@react-navigation/native';
import { createNativeStackNavigator, type NativeStackScreenProps } from '@react-navigation/native-stack';
import { createBottomTabNavigator } from '@react-navigation/bottom-tabs';
import { SafeAreaProvider, SafeAreaView } from 'react-native-safe-area-context';
import { StatusBar } from 'expo-status-bar';
import { SessionProvider, useSession } from './src/session/SessionProvider';
import { createNativeRuntime } from './src/session/nativeRuntime';
import { CONFIRMATION_CALLBACK } from './src/account/callbacks';
import { DEMO_ONBOARDING_CONTEXT } from './src/account/demoAccountGateway';
import { DEMO_ESTABLISHMENT_CONTEXT } from './src/establishment';
import { GatewayProvider } from './src/ui/gateway';
import { LoginScreen } from './src/ui/LoginScreen';
import { MissionListScreen } from './src/ui/MissionListScreen';
import { MissionDetailScreen } from './src/ui/MissionDetailScreen';
import { CaregiverProfileScreen } from './src/ui/CaregiverProfileScreen';
import { MyMissionsScreen, MissionApplicationScreen } from './src/ui/workflows';
import { EstablishmentHomeScreen, EstablishmentProfileScreen, EstablishmentMissionListScreen, EstablishmentMissionDetailScreen } from './src/ui/establishment';
import { RegistrationScreen, OnboardingScreen, AuthConfirmationScreen } from './src/ui/account';
import { AccountServicesProvider, RuntimeProvider, useAccountServices, useNativeRuntime } from './src/ui/runtime';
import { useCaregiverSession } from './src/ui/useCaregiverSession';
import { TabIcon } from './src/ui/TabIcon';
import { StatusPanel } from './src/ui/components';
import type { NativeStackParams } from './src/ui/navigation';
import { colors, shared } from './src/ui/theme';

const Stack = createNativeStackNavigator<NativeStackParams>();
const Tabs = createBottomTabNavigator();
const navigationTheme = { ...DefaultTheme, colors: { ...DefaultTheme.colors, primary: colors.pink,
  background: colors.background, card: colors.surface, text: colors.text, border: colors.border } };
const stackOptions = { headerTintColor: colors.pink, headerStyle: { backgroundColor: colors.surface },
  headerTitleStyle: { color: colors.text, fontWeight: '600' as const }, contentStyle: { backgroundColor: colors.background },
  headerShadowVisible: false, gestureEnabled: true, animation: 'default' as const };

function useSignOut() {
  const { snapshot, signOut } = useSession();
  return () => Alert.alert(snapshot.mode === 'demo' ? 'Quitter la démo ?' : 'Se déconnecter ?',
    'Vous reviendrez à l’écran de connexion.', [
      { text: 'Annuler', style: 'cancel' }, { text: 'Quitter', style: 'destructive', onPress: () => { void signOut(); } },
    ]);
}
function SignOutButton() {
  const leave = useSignOut();
  return <Pressable accessibilityRole="button" accessibilityLabel="Se déconnecter" onPress={leave} hitSlop={8}
    style={({ pressed }) => [styles.headerButton, pressed && styles.pressed]} testID="sign-out">
    <Text style={styles.headerButtonText}>Quitter</Text>
  </Pressable>;
}
function Application({ route, navigation }: NativeStackScreenProps<NativeStackParams, 'Candidature'>) {
  const { context } = useCaregiverSession();
  const { missions } = useAccountServices();
  return <MissionApplicationScreen context={context} gateway={missions} missionId={route.params.id}
    onBack={() => navigation.goBack()} onMyMissions={() => navigation.getParent()?.navigate('SuiviSoignant', { screen: 'MesMissions', pop: true })}
    onCompleteProfile={() => navigation.getParent()?.navigate('CompteSoignant')} />;
}
function ExploreNavigator() {
  return <Stack.Navigator screenOptions={stackOptions}>
    <Stack.Screen name="Missions" component={MissionListScreen} options={{ title: 'Jolene', headerRight: () => <SignOutButton /> }} />
    <Stack.Screen name="Mission" component={MissionDetailScreen} options={{ title: 'La mission', headerBackTitle: 'Missions', fullScreenGestureEnabled: true }} />
    <Stack.Screen name="Candidature" component={Application} options={{ title: 'Ma candidature', headerBackTitle: 'Mission' }} />
  </Stack.Navigator>;
}
function MyMissions({ navigation }: NativeStackScreenProps<NativeStackParams, 'MesMissions'>) {
  const { context } = useCaregiverSession();
  const { missions } = useAccountServices();
  return <MyMissionsScreen context={context} gateway={missions} onOpenMission={id => navigation.navigate('Candidature', { id })}
    onBrowseMissions={() => navigation.getParent()?.navigate('ExplorationSoignant')} />;
}
function MyMissionsNavigator() {
  return <Stack.Navigator screenOptions={stackOptions}>
    <Stack.Screen name="MesMissions" component={MyMissions} options={{ title: 'Mes missions', headerRight: () => <SignOutButton /> }} />
    <Stack.Screen name="Candidature" component={Application} options={{ title: 'Ma candidature', headerBackTitle: 'Mes missions' }} />
  </Stack.Navigator>;
}
function CaregiverProfile() {
  const { context, retry } = useCaregiverSession();
  const { profile } = useAccountServices();
  const leave = useSignOut();
  return <CaregiverProfileScreen context={context} gateway={profile} onSaved={() => { void retry(); }} onSignOut={leave} />;
}
function CaregiverProfileNavigator() {
  return <Stack.Navigator screenOptions={stackOptions}>
    <Stack.Screen name="Profil" component={CaregiverProfile} options={{ title: 'Mon profil', headerRight: () => <SignOutButton /> }} />
  </Stack.Navigator>;
}
function useEstablishment() {
  const { snapshot } = useSession();
  const { establishment } = useAccountServices();
  if (snapshot.context?.kind !== 'etablissement') throw new Error('Compte établissement absent.');
  return { context: snapshot.context, gateway: establishment };
}
function EstablishmentHome({ navigation }: NativeStackScreenProps<NativeStackParams, 'AccueilEtablissement'>) {
  const props = useEstablishment(); const leave = useSignOut();
  return <EstablishmentHomeScreen {...props} onOpenMissions={() => navigation.getParent()?.navigate('SuiviEtablissement')}
    onOpenProfile={() => navigation.getParent()?.navigate('CompteEtablissement')} onSignOut={leave} />;
}
function EstablishmentHomeNavigator() {
  return <Stack.Navigator screenOptions={stackOptions}>
    <Stack.Screen name="AccueilEtablissement" component={EstablishmentHome} options={{ title: 'Jolene', headerRight: () => <SignOutButton /> }} />
  </Stack.Navigator>;
}
function EstablishmentMissions({ navigation }: NativeStackScreenProps<NativeStackParams, 'MissionsEtablissement'>) {
  return <EstablishmentMissionListScreen {...useEstablishment()} onOpenMission={id => navigation.navigate('MissionEtablissement', { id })} />;
}
function EstablishmentMission({ navigation, route }: NativeStackScreenProps<NativeStackParams, 'MissionEtablissement'>) {
  return <EstablishmentMissionDetailScreen {...useEstablishment()} missionId={route.params.id} onBack={() => navigation.goBack()} />;
}
function EstablishmentMissionsNavigator() {
  return <Stack.Navigator screenOptions={stackOptions}>
    <Stack.Screen name="MissionsEtablissement" component={EstablishmentMissions} options={{ title: 'Mes missions', headerRight: () => <SignOutButton /> }} />
    <Stack.Screen name="MissionEtablissement" component={EstablishmentMission} options={{ title: 'La mission', headerBackTitle: 'Missions', fullScreenGestureEnabled: true }} />
  </Stack.Navigator>;
}
function EstablishmentProfile() { return <EstablishmentProfileScreen {...useEstablishment()} />; }
function EstablishmentProfileNavigator() {
  return <Stack.Navigator screenOptions={stackOptions}>
    <Stack.Screen name="ProfilEtablissement" component={EstablishmentProfile} options={{ title: 'Mon établissement', headerRight: () => <SignOutButton /> }} />
  </Stack.Navigator>;
}
function AccountNavigator() {
  const { snapshot } = useSession();
  const isEstablishment = snapshot.context?.kind === 'etablissement';
  return <Tabs.Navigator backBehavior="history" screenOptions={{ headerShown: false, tabBarActiveTintColor: colors.pink,
    tabBarInactiveTintColor: colors.secondary, tabBarHideOnKeyboard: true,
    tabBarStyle: { backgroundColor: colors.surface, borderTopColor: colors.border },
    tabBarLabelStyle: { fontSize: 12, fontWeight: '600' } }}>
    {isEstablishment ? <>
      <Tabs.Screen name="TableauEtablissement" component={EstablishmentHomeNavigator} options={{ title: 'Accueil', tabBarButtonTestID: 'tab-establishment-home', tabBarIcon: ({ color }) => <TabIcon name="home" color={color} /> }} />
      <Tabs.Screen name="SuiviEtablissement" component={EstablishmentMissionsNavigator} options={{ title: 'Missions', tabBarButtonTestID: 'tab-establishment-missions', tabBarIcon: ({ color }) => <TabIcon name="list" color={color} /> }} />
      <Tabs.Screen name="CompteEtablissement" component={EstablishmentProfileNavigator} options={{ title: 'Établissement', tabBarButtonTestID: 'tab-establishment-profile', tabBarIcon: ({ color }) => <TabIcon name="person" color={color} /> }} />
    </> : <>
      <Tabs.Screen name="ExplorationSoignant" component={ExploreNavigator} options={{ title: 'Explorer', tabBarButtonTestID: 'tab-explore', tabBarIcon: ({ color }) => <TabIcon name="search" color={color} /> }} />
      <Tabs.Screen name="SuiviSoignant" component={MyMissionsNavigator} options={{ title: 'Mes missions', tabBarButtonTestID: 'tab-my-missions', tabBarIcon: ({ color }) => <TabIcon name="list" color={color} /> }} />
      <Tabs.Screen name="CompteSoignant" component={CaregiverProfileNavigator} options={{ title: 'Profil', tabBarButtonTestID: 'tab-profile', tabBarIcon: ({ color }) => <TabIcon name="person" color={color} /> }} />
    </>}
  </Tabs.Navigator>;
}
function Login({ navigation }: NativeStackScreenProps<NativeStackParams, 'Connexion'>) {
  const { enterDemo } = useSession();
  return <LoginScreen onRegister={() => navigation.navigate('Inscription')}
    onEnterEstablishmentDemo={() => enterDemo({ ...DEMO_ESTABLISHMENT_CONTEXT, kind: 'etablissement', membershipRole: 'PROPRIETAIRE' })}
    onEnterOnboardingDemo={() => enterDemo(DEMO_ONBOARDING_CONTEXT)} />;
}
function Registration({ navigation }: NativeStackScreenProps<NativeStackParams, 'Inscription'>) {
  const runtime = useNativeRuntime();
  return <RegistrationScreen gateway={runtime.accountGateway} onBack={() => navigation.goBack()} onContinue={() => { void runtime.controller.revalidate(); }} />;
}
function Onboarding() {
  const { snapshot, signOut, retry } = useSession();
  const runtime = useNativeRuntime();
  if (snapshot.context?.kind !== 'onboarding') return null;
  return <OnboardingScreen context={snapshot.context} gateway={runtime.accountGateway}
    onComplete={() => { void retry(); }} onRefresh={() => { void retry(); }} onSignOut={() => { void signOut(); }} />;
}
function NativeNavigator() {
  const { snapshot, retry } = useSession();
  const runtime = useNativeRuntime();
  const [confirmationUrl, setConfirmationUrl] = useState<string | null>(null);
  useEffect(() => {
    let active = true;
    const receive = (url: string | null) => {
      // Confirmation tokens live only in memory, never in navigation params or logs.
      if (active && url && (url === CONFIRMATION_CALLBACK || url.startsWith(`${CONFIRMATION_CALLBACK}?`))) setConfirmationUrl(url);
    };
    const listener = Linking.addEventListener('url', event => receive(event.url));
    void Linking.getInitialURL().then(receive).catch(() => {});
    return () => { active = false; listener.remove(); };
  }, []);
  const context = snapshot.status === 'authenticated' ? snapshot.context : null;
  const key = context ? `session-${snapshot.epoch}:${context.kind}` : 'signed-out';
  if (confirmationUrl) return <AuthConfirmationScreen url={confirmationUrl} gateway={runtime.accountGateway}
    onComplete={() => { setConfirmationUrl(null); void retry(); }} onBack={() => setConfirmationUrl(null)} />;
  return <NavigationContainer key={key} theme={navigationTheme}>
    {context?.kind === 'onboarding' ? <Stack.Navigator screenOptions={stackOptions}>
      <Stack.Screen name="CompleterProfil" component={Onboarding} options={{ title: 'Mon inscription', headerRight: () => <SignOutButton /> }} />
    </Stack.Navigator>
      : context ? <AccountServicesProvider key={key}><AccountNavigator /></AccountServicesProvider>
        : <Stack.Navigator screenOptions={stackOptions}>
          <Stack.Screen name="Connexion" component={Login} options={{ headerShown: false }} />
          <Stack.Screen name="Inscription" component={Registration} options={{ title: 'Créer mon compte', headerBackTitle: 'Connexion' }} />
        </Stack.Navigator>}
  </NavigationContainer>;
}
export default function App() {
  const [runtime] = useState(createNativeRuntime);
  return <SafeAreaProvider>
    <StatusBar style="dark" />
    {runtime.configError ? <SafeAreaView style={shared.screen}><ScrollView contentContainerStyle={styles.configContent}>
      <StatusPanel title="Configuration native à compléter" message={runtime.configError} testID="configuration-error" />
    </ScrollView></SafeAreaView> : <RuntimeProvider runtime={runtime}><SessionProvider controller={runtime.controller}>
      <GatewayProvider gateway={runtime.gateway}><NativeNavigator /></GatewayProvider>
    </SessionProvider></RuntimeProvider>}
  </SafeAreaProvider>;
}
const styles = StyleSheet.create({
  headerButton: { minHeight: 44, paddingHorizontal: 3, justifyContent: 'center' },
  headerButtonText: { color: colors.pink, fontSize: 15, fontWeight: '600' }, pressed: { opacity: 0.65 },
  configContent: { flexGrow: 1, justifyContent: 'center' },
});
