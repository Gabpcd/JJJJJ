import { useState } from 'react';
import { Alert, Pressable, ScrollView, StyleSheet, Text } from 'react-native';
import { DefaultTheme, NavigationContainer } from '@react-navigation/native';
import { createNativeStackNavigator } from '@react-navigation/native-stack';
import { SafeAreaProvider, SafeAreaView } from 'react-native-safe-area-context';
import { StatusBar } from 'expo-status-bar';
import { SessionProvider, useSession } from './src/session/SessionProvider';
import { createNativeRuntime } from './src/session/nativeRuntime';
import { GatewayProvider } from './src/ui/gateway';
import { LoginScreen } from './src/ui/LoginScreen';
import { MissionListScreen } from './src/ui/MissionListScreen';
import { MissionDetailScreen } from './src/ui/MissionDetailScreen';
import { StatusPanel } from './src/ui/components';
import type { NativeStackParams } from './src/ui/navigation';
import { colors, shared } from './src/ui/theme';

const Stack = createNativeStackNavigator<NativeStackParams>();
const navigationTheme = { ...DefaultTheme, colors: { ...DefaultTheme.colors, primary: colors.pink,
  background: colors.background, card: colors.surface, text: colors.text, border: colors.border } };

function SignOutButton() {
  const { snapshot, signOut } = useSession();
  const leave = () => {
    const title = snapshot.mode === 'demo' ? 'Quitter la démo ?' : 'Se déconnecter ?';
    Alert.alert(title, 'Vous reviendrez à l’écran de connexion.', [
      { text: 'Annuler', style: 'cancel' },
      { text: 'Quitter', style: 'destructive', onPress: () => { void signOut(); } },
    ]);
  };
  return <Pressable accessibilityRole="button" accessibilityLabel={snapshot.mode === 'demo' ? 'Quitter la démo' : 'Se déconnecter'}
    onPress={leave} hitSlop={8} style={({ pressed }) => [styles.headerButton, pressed && styles.pressed]} testID="sign-out">
    <Text style={styles.headerButtonText}>Quitter</Text>
  </Pressable>;
}

function NativeNavigator() {
  const { snapshot } = useSession();
  const authenticated = snapshot.status === 'authenticated' && snapshot.context !== null;
  return <NavigationContainer key={authenticated ? `session-${snapshot.epoch}` : 'signed-out'} theme={navigationTheme}>
    <Stack.Navigator screenOptions={{ headerTintColor: colors.pink, headerStyle: { backgroundColor: colors.surface },
      headerTitleStyle: { color: colors.text, fontWeight: '600' }, contentStyle: { backgroundColor: colors.background },
      headerShadowVisible: false, gestureEnabled: true, animation: 'default' }}>
      {authenticated ? <>
        <Stack.Screen name="Missions" component={MissionListScreen}
          options={{ title: 'Jolene', headerTitleStyle: { color: colors.pink, fontWeight: '700', fontSize: 24 }, headerRight: () => <SignOutButton /> }} />
        {/* No horizontal interactions on this detail screen: allow a back swipe across its content. */}
        <Stack.Screen name="Mission" component={MissionDetailScreen}
          options={{ title: 'La mission', headerBackTitle: 'Missions', fullScreenGestureEnabled: true }} />
      </> : <Stack.Screen name="Connexion" component={LoginScreen} options={{ headerShown: false }} />}
    </Stack.Navigator>
  </NavigationContainer>;
}

export default function App() {
  const [runtime] = useState(createNativeRuntime);
  return <SafeAreaProvider>
    <StatusBar style="dark" />
    {runtime.configError ? <SafeAreaView style={shared.screen}>
      <ScrollView contentContainerStyle={styles.configContent}>
        <StatusPanel title="Configuration du pilote à compléter" message={runtime.configError} testID="configuration-error" />
      </ScrollView>
    </SafeAreaView> : <SessionProvider controller={runtime.controller}>
      <GatewayProvider gateway={runtime.gateway}><NativeNavigator /></GatewayProvider>
    </SessionProvider>}
  </SafeAreaProvider>;
}

const styles = StyleSheet.create({
  headerButton: { minHeight: 44, paddingHorizontal: 3, justifyContent: 'center' },
  headerButtonText: { color: colors.pink, fontSize: 15, fontWeight: '600' },
  pressed: { opacity: 0.65 },
  configContent: { flexGrow: 1, justifyContent: 'center' },
});
