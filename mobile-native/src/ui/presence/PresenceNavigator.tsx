import { useMemo } from 'react';
import { Alert, Pressable, StyleSheet, Text, View } from 'react-native';
import { createNativeStackNavigator, type NativeStackScreenProps } from '@react-navigation/native-stack';
import { useSession } from '../../session/SessionProvider';
import { nativePresenceContext } from '../../presence/runtime';
import { useNativeRuntime } from '../runtime';
import { StatusPanel } from '../components';
import { colors, shared } from '../theme';
import { PresenceDetailScreen, PresenceListScreen, PresenceScanScreen } from './screens';
import { usePresenceGpsConsent } from './usePresenceGpsConsent';
import { diagnosticStackListeners } from '../../navigationDiagnostics';

type Params = { Presences: undefined; Presence: { id: string }; Pointer: undefined };
const Stack = createNativeStackNavigator<Params>();
function SignOut() {
  const { snapshot, signOut } = useSession();
  return <Pressable accessibilityRole="button" accessibilityLabel="Se déconnecter" testID="sign-out" style={styles.exit}
    onPress={() => Alert.alert(snapshot.mode === 'demo' ? 'Quitter la démo ?' : 'Se déconnecter ?', 'Vous reviendrez à l’écran de connexion.', [
      { text: 'Annuler', style: 'cancel' }, { text: 'Quitter', style: 'destructive', onPress: () => { void signOut(); } },
    ])}><Text style={styles.exitText}>Quitter</Text></Pressable>;
}
function usePresenceSession() {
  const { snapshot } = useSession(); const runtime = useNativeRuntime();
  const context = snapshot.status === 'authenticated' ? nativePresenceContext(snapshot.context, snapshot.epoch) : null;
  const identity = context ? JSON.stringify(context) : null;
  return useMemo(() => {
    if (!context) return null;
    try { return runtime.presence.session(context); } catch { return null; }
  }, [runtime.presence, identity]);
}
function Unavailable() { return <StatusPanel title="Votre session de pointage doit être ouverte à nouveau" testID="presence-session-unavailable" />; }
function List({ navigation }: NativeStackScreenProps<Params, 'Presences'>) {
  const session = usePresenceSession();
  return session ? <PresenceListScreen {...session} onMission={id => navigation.navigate('Presence', { id })}
    onScan={session.context.kind === 'soignant' ? () => navigation.navigate('Pointer') : undefined} /> : <Unavailable />;
}
function Detail({ navigation, route }: NativeStackScreenProps<Params, 'Presence'>) {
  const session = usePresenceSession();
  return session ? <PresenceDetailScreen {...session} missionId={route.params.id}
    onScan={session.context.kind === 'soignant' ? () => navigation.navigate('Pointer') : undefined} /> : <Unavailable />;
}
function ScanContent({ session, navigation }: { session: NonNullable<ReturnType<typeof usePresenceSession>>;
  navigation: NativeStackScreenProps<Params, 'Pointer'>['navigation'] }) {
  const consent = usePresenceGpsConsent(session);
  return <View style={shared.flex}>
    {consent.error ? <Text style={styles.consent} testID="presence-gps-consent-unavailable">Le consentement à la localisation n’a pas pu être relu. Vous pouvez pointer sans transmettre votre position.</Text> : null}
    <PresenceScanScreen {...session} gpsConsentEnabled={!consent.loading && consent.data === true}
      onMission={id => navigation.replace('Presence', { id })} />
  </View>;
}
function Scan({ navigation }: NativeStackScreenProps<Params, 'Pointer'>) {
  const session = usePresenceSession();
  return session?.context.kind === 'soignant' ? <ScanContent session={session} navigation={navigation} /> : <Unavailable />;
}
export function PresenceNavigator() {
  return <Stack.Navigator screenListeners={diagnosticStackListeners} screenOptions={{ headerTintColor: colors.pink, headerStyle: { backgroundColor: colors.surface },
    contentStyle: { backgroundColor: colors.background }, headerShadowVisible: false, gestureEnabled: true,
    fullScreenGestureEnabled: false, animation: 'default', headerRight: () => <SignOut /> }}>
    <Stack.Screen name="Presences" component={List} options={{ title: 'Présences' }} />
    <Stack.Screen name="Presence" component={Detail} options={{ title: 'Le pointage', headerBackTitle: 'Présences' }} />
    <Stack.Screen name="Pointer" component={Scan} options={{ title: 'Pointer ma présence', headerBackTitle: 'Présences' }} />
  </Stack.Navigator>;
}
const styles = StyleSheet.create({ exit: { minHeight: 44, paddingHorizontal: 3, justifyContent: 'center' },
  exitText: { color: colors.pink, fontSize: 15, fontWeight: '600' },
  consent: { color: colors.secondary, backgroundColor: colors.background, padding: 12, fontSize: 14 } });
