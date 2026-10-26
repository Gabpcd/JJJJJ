import { useRef, useState } from 'react';
import { Image, Keyboard, KeyboardAvoidingView, Platform, Pressable, ScrollView, StyleSheet, Text, TextInput, View } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useSession } from '../session/SessionProvider';
import { ActionButton, ErrorNotice, ModeNotice, StatusPanel } from './components';
import { colors, shared } from './theme';

export function LoginScreen() {
  const { snapshot, signIn, enterDemo, signOut } = useSession();
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [visiblePassword, setVisiblePassword] = useState(false);
  const [validationError, setValidationError] = useState<string | null>(null);
  const passwordField = useRef<TextInput>(null);
  const busy = snapshot.status === 'signingIn';

  const submit = () => {
    if (busy) return;
    if (!email.trim() || !password) {
      setValidationError('Renseignez votre adresse email et votre mot de passe.');
      return;
    }
    setValidationError(null);
    Keyboard.dismiss();
    void signIn(email.trim(), password);
  };

  if (snapshot.status === 'loading') return <SafeAreaView style={shared.screen}><StatusPanel loading title="Ouverture de Jolene" message="Récupération de votre session…" /></SafeAreaView>;

  if (snapshot.status === 'signedOut' && snapshot.error) return <SafeAreaView style={shared.screen}>
    <ScrollView contentContainerStyle={styles.centered}>
      <StatusPanel title="Terminer la déconnexion" message={snapshot.error}>
        <ActionButton label="Réessayer la déconnexion" onPress={() => { void signOut(); }} testID="retry-sign-out" />
      </StatusPanel>
    </ScrollView>
  </SafeAreaView>;

  if (snapshot.status === 'unsupported') return <SafeAreaView style={shared.screen}>
    <ScrollView contentContainerStyle={styles.centered}>
      <StatusPanel title="Ce compte ne peut pas ouvrir le pilote" message={snapshot.error ?? 'Le pilote accueille les comptes soignants existants de l’environnement TEST.'}>
        <ActionButton label="Revenir à la connexion" onPress={() => { void signOut(); }} testID="unsupported-sign-out" />
      </StatusPanel>
    </ScrollView>
  </SafeAreaView>;

  return <SafeAreaView style={shared.screen} edges={['top', 'left', 'right', 'bottom']}>
    <KeyboardAvoidingView style={shared.flex} behavior={Platform.OS === 'ios' ? 'padding' : 'height'}>
      <ScrollView style={shared.flex} contentContainerStyle={styles.scrollContent} keyboardShouldPersistTaps="handled"
        keyboardDismissMode={Platform.OS === 'ios' ? 'interactive' : 'on-drag'} testID="login-scroll">
        <View style={[shared.content, styles.content]}>
          <View style={styles.brandRow}>
            <Image source={require('../../assets/icon.png')} style={styles.brandMark} accessible={false} />
            <Text style={styles.brandName}>Jolene</Text>
          </View>
          <View style={styles.heading}>
            <Text style={styles.eyebrow}>VOTRE PROCHAIN REMPLACEMENT</Text>
            <Text style={styles.title} accessibilityRole="header">Du temps pour soigner.{"\n"}Un quotidien plus libre.</Text>
            <Text style={shared.subtitle}>Retrouvez les missions qui vous correspondent, simplement.</Text>
          </View>
          <ModeNotice mode={snapshot.mode} />
          {snapshot.mode === 'demo' ? <View style={styles.form}>
            <Text style={shared.sectionTitle} accessibilityRole="header">Découvrez le parcours natif</Text>
            <Text style={shared.subtitle}>Explorez les missions et leurs détails avec un compte fictif. Aucun identifiant n’est nécessaire.</Text>
            {snapshot.error ? <ErrorNotice message={snapshot.error} /> : null}
            <ActionButton label="Explorer la démo" onPress={enterDemo} testID="enter-demo" />
          </View> : <View style={styles.form}>
            <Text style={shared.sectionTitle} accessibilityRole="header">Ravi de vous retrouver</Text>
            <View style={styles.fieldGroup}>
              <Text style={styles.label} nativeID="email-label">Adresse email</Text>
              <TextInput accessibilityLabel="Adresse email" accessibilityLabelledBy="email-label" style={styles.input}
                value={email} onChangeText={setEmail} placeholder="vous@exemple.fr" placeholderTextColor={colors.muted}
                autoCapitalize="none" autoCorrect={false} keyboardType="email-address" textContentType="username"
                autoComplete="email" returnKeyType="next" onSubmitEditing={() => passwordField.current?.focus()}
                editable={!busy} testID="login-email" />
            </View>
            <View style={styles.fieldGroup}>
              <Text style={styles.label} nativeID="password-label">Mot de passe</Text>
              <View style={styles.passwordRow}>
                <TextInput ref={passwordField} accessibilityLabel="Mot de passe" accessibilityLabelledBy="password-label"
                  style={[styles.input, styles.passwordInput]} value={password} onChangeText={setPassword}
                  secureTextEntry={!visiblePassword} autoCapitalize="none" autoCorrect={false} textContentType="password"
                  autoComplete="current-password" returnKeyType="go" onSubmitEditing={submit} editable={!busy} testID="login-password" />
                <Pressable accessibilityRole="button" accessibilityLabel={visiblePassword ? 'Masquer le mot de passe' : 'Afficher le mot de passe'}
                  onPress={() => setVisiblePassword(value => !value)} style={styles.showPassword} testID="toggle-password">
                  <Text style={styles.showPasswordText}>{visiblePassword ? 'Masquer' : 'Afficher'}</Text>
                </Pressable>
              </View>
            </View>
            {validationError || snapshot.error ? <ErrorNotice message={validationError ?? snapshot.error!} /> : null}
            <ActionButton label={busy ? 'Connexion en cours…' : 'Se connecter'} busy={busy} onPress={submit} testID="sign-in" />
            <Text style={shared.small}>Utilisez votre compte soignant TEST existant. L’inscription et la récupération du mot de passe restent dans l’application actuelle.</Text>
          </View>}
          <Text style={styles.footer}>Premier parcours natif · connexion, missions et détails.{"\n"}Aucune candidature ni opération financière dans ce pilote.</Text>
        </View>
      </ScrollView>
    </KeyboardAvoidingView>
  </SafeAreaView>;
}

const styles = StyleSheet.create({
  centered: { flexGrow: 1, justifyContent: 'center' },
  scrollContent: { flexGrow: 1, justifyContent: 'center', paddingTop: 24, paddingBottom: 28 },
  content: { maxWidth: 560, gap: 24 },
  brandRow: { flexDirection: 'row', alignItems: 'center', gap: 12 },
  brandMark: { width: 48, height: 48, borderRadius: 15 },
  brandName: { color: colors.pink, fontSize: 30, fontWeight: '700', letterSpacing: -1 },
  heading: { gap: 14, paddingVertical: 6 },
  eyebrow: { color: colors.purple, fontSize: 11, lineHeight: 17, fontWeight: '700', letterSpacing: 1.4 },
  title: { color: colors.text, fontSize: 34, lineHeight: 41, fontWeight: '700', letterSpacing: -1.1 },
  form: { gap: 17, paddingTop: 4 },
  fieldGroup: { gap: 8 },
  label: { color: colors.text, fontSize: 14, lineHeight: 21, fontWeight: '600' },
  input: { minHeight: 54, paddingHorizontal: 16, paddingVertical: 15, borderWidth: 1, borderRadius: 16,
    borderColor: colors.border, backgroundColor: colors.surface, color: colors.text, fontSize: 17 },
  passwordRow: { flexDirection: 'row', alignItems: 'stretch', borderWidth: 1, borderColor: colors.border, backgroundColor: colors.surface, borderRadius: 16 },
  passwordInput: { flex: 1, minWidth: 0, borderWidth: 0, backgroundColor: 'transparent' },
  showPassword: { minHeight: 54, justifyContent: 'center', paddingHorizontal: 12 },
  showPasswordText: { fontSize: 13, color: colors.pink, fontWeight: '600' },
  footer: { color: colors.secondary, fontSize: 12, lineHeight: 19, textAlign: 'center', marginTop: 5 },
});
