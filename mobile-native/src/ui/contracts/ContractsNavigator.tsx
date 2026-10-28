import { Alert, Pressable, StyleSheet, Text } from 'react-native';
import { createNativeStackNavigator, type NativeStackScreenProps } from '@react-navigation/native-stack';
import { useSession } from '../../session/SessionProvider';
import { nativeContractContext } from '../../contracts/runtime';
import { diagnosticStackListeners } from '../../navigationDiagnostics';
import { useNativeRuntime } from '../runtime';
import { StatusPanel } from '../components';
import { colors } from '../theme';
import { ContractsListScreen } from './ContractsListScreen';
import { ContractDetailScreen } from './ContractDetailScreen';

type Params = { Contrats: undefined; Contrat: { id: string } };
const Stack = createNativeStackNavigator<Params>();
function SignOut() {
  const { snapshot, signOut } = useSession();
  return <Pressable accessibilityRole="button" accessibilityLabel="Se déconnecter" testID="sign-out" style={styles.exit}
    onPress={() => Alert.alert(snapshot.mode === 'demo' ? 'Quitter la démo ?' : 'Se déconnecter ?', 'Vous reviendrez à l’écran de connexion.', [
      { text: 'Annuler', style: 'cancel' }, { text: 'Quitter', style: 'destructive', onPress: () => { void signOut(); } },
    ])}><Text style={styles.exitText}>Quitter</Text></Pressable>;
}
function List({ navigation }: NativeStackScreenProps<Params, 'Contrats'>) {
  const { snapshot } = useSession(); const runtime = useNativeRuntime(); const context = nativeContractContext(snapshot.context);
  return context ? <ContractsListScreen context={context} sessionEpoch={snapshot.epoch} gateway={runtime.contracts}
    onOpenContract={id => navigation.navigate('Contrat', { id })} /> : <StatusPanel title="Votre session doit être ouverte à nouveau" />;
}
function Detail({ route }: NativeStackScreenProps<Params, 'Contrat'>) {
  const { snapshot } = useSession(); const runtime = useNativeRuntime(); const context = nativeContractContext(snapshot.context);
  return context ? <ContractDetailScreen context={context} sessionEpoch={snapshot.epoch} gateway={runtime.contracts}
    contractId={route.params.id} /> : <StatusPanel title="Votre session doit être ouverte à nouveau" />;
}
export function ContractsNavigator() {
  return <Stack.Navigator screenListeners={diagnosticStackListeners} screenOptions={{ headerTintColor: colors.pink, headerStyle: { backgroundColor: colors.surface },
    contentStyle: { backgroundColor: colors.background }, headerShadowVisible: false, gestureEnabled: true,
    fullScreenGestureEnabled: false, animation: 'default', headerRight: () => <SignOut /> }}>
    <Stack.Screen name="Contrats" component={List} options={{ title: 'Mes contrats' }} />
    <Stack.Screen name="Contrat" component={Detail} options={{ title: 'Le contrat', headerBackTitle: 'Contrats' }} />
  </Stack.Navigator>;
}
const styles = StyleSheet.create({ exit: { minHeight: 44, paddingHorizontal: 3, justifyContent: 'center' },
  exitText: { color: colors.pink, fontSize: 15, fontWeight: '600' } });
