import { useEffect, useRef, useState, type PropsWithChildren } from 'react';
import { KeyboardAvoidingView, Modal, Platform, Pressable, ScrollView, StyleSheet, Text, TextInput, View, type TextInputProps } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { accountErrorMessage } from '../../account/errors';
import { ActionButton, ErrorNotice } from '../components';
import { colors, shared } from '../theme';

export function AccountLayout({ title, mode, onBack, includeTop = false, children }: PropsWithChildren<{ title: string; mode: 'demo' | 'staging'; onBack?: () => void; includeTop?: boolean }>) {
  return <SafeAreaView style={shared.screen} edges={includeTop ? ['top', 'left', 'right', 'bottom'] : ['left', 'right', 'bottom']}>
    <KeyboardAvoidingView style={shared.flex} behavior={Platform.OS === 'ios' ? 'padding' : 'height'}>
      <ScrollView contentContainerStyle={formStyles.scroll} keyboardShouldPersistTaps="handled" keyboardDismissMode="on-drag" testID="account-scroll">
        <View style={[shared.content, formStyles.content]}>
          {onBack ? <ActionButton label="Retour" secondary onPress={onBack} testID="account-back" /> : null}
          <Text style={shared.title} accessibilityRole="header">{title}</Text>
          <Text style={formStyles.environment} testID="account-environment">{mode === 'demo' ? 'Démo · formulaire fictif, aucune donnée envoyée' : 'Environnement TEST · votre compte de test'}</Text>
          {children}
        </View>
      </ScrollView>
    </KeyboardAvoidingView>
  </SafeAreaView>;
}
export function AccountField({ label, ...props }: TextInputProps & { label: string }) {
  return <View style={formStyles.field}>
    <Text style={formStyles.label}>{label}</Text>
    <TextInput accessibilityLabel={label} style={formStyles.input} placeholderTextColor={colors.muted} {...props} />
  </View>;
}
export function AccountCheck({ label, checked, onChange, disabled, testID }: { label: string; checked: boolean; onChange: (value: boolean) => void; disabled?: boolean; testID?: string }) {
  return <Pressable onPress={() => onChange(!checked)} disabled={disabled} accessibilityRole="checkbox" accessibilityLabel={label}
    accessibilityState={{ checked, disabled }} style={formStyles.check} testID={testID}>
    <Text style={[formStyles.tick, checked && formStyles.tickChecked]}>{checked ? '✓' : ''}</Text><Text style={[shared.body, shared.flex]}>{label}</Text>
  </Pressable>;
}
export function AccountChoice({ label, value, choices, onChange, disabled, testID }: {
  label: string; value: string; choices: readonly { valeur: string; label: string }[];
  onChange: (value: string) => void; disabled?: boolean; testID: string;
}) {
  const [open, setOpen] = useState(false);
  const [presented, setPresented] = useState(false);
  const [search, setSearch] = useState('');
  const normalize = (text: string) => text.normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase();
  const visible = choices.filter(choice => normalize(`${choice.label} ${choice.valeur}`).includes(normalize(search)));
  return <View style={formStyles.field}>
    <Text style={formStyles.label}>{label}</Text>
    <Pressable onPress={() => { setSearch(''); setPresented(false); setOpen(true); }} disabled={disabled} accessibilityRole="button" accessibilityLabel={`${label} : ${choices.find(c => c.valeur === value)?.label ?? 'Choisir'}`}
      accessibilityState={{ expanded: open, disabled }}
      style={formStyles.input} testID={testID}><Text style={shared.body}>{choices.find(c => c.valeur === value)?.label ?? 'Choisir…'}</Text></Pressable>
    <Modal visible={open} animationType="slide" onRequestClose={() => setOpen(false)} presentationStyle="pageSheet"
      onShow={() => setPresented(true)} onDismiss={() => setPresented(false)}>
      <SafeAreaView style={shared.screen}>
        <View style={[shared.content, formStyles.content, shared.flex]} accessibilityViewIsModal>
          <Text style={shared.sectionTitle} accessibilityRole="header" testID={presented ? `${testID}-presented` : `${testID}-presenting`}>{label}</Text>
          <AccountField label="Rechercher" value={search} onChangeText={setSearch} autoCorrect={false} testID={`${testID}-search`} />
          <ScrollView keyboardShouldPersistTaps="handled" testID={`${testID}-choices`}>
            {visible.length ? visible.map(choice => <Pressable key={choice.valeur} accessibilityRole="button" accessibilityState={{ selected: choice.valeur === value }}
              style={formStyles.choice} testID={`${testID}-${choice.valeur}`} onPress={() => { onChange(choice.valeur); setOpen(false); }}>
              <Text style={shared.body}>{choice.label}{choice.valeur === value ? ' ✓' : ''}</Text>
            </Pressable>) : <Text style={shared.body}>Aucun résultat.</Text>}
          </ScrollView>
          <ActionButton label="Fermer" secondary onPress={() => setOpen(false)} />
        </View>
      </SafeAreaView>
    </Modal>
  </View>;
}
export function useAccountAction() {
  const mounted = useRef(true);
  const lock = useRef(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  useEffect(() => { mounted.current = true; return () => { mounted.current = false; }; }, []);
  const run = async (action: () => Promise<void>) => {
    if (lock.current) return;
    lock.current = true; setBusy(true); setError(null);
    try { await action(); }
    catch (e) { if (mounted.current) setError(accountErrorMessage(e)); }
    finally { lock.current = false; if (mounted.current) setBusy(false); }
  };
  return { busy, error, run, mounted, Error: error ? <ErrorNotice message={error} /> : null };
}
export const formStyles = StyleSheet.create({
  scroll: { paddingVertical: 24, flexGrow: 1 },
  content: { maxWidth: 640, gap: 18 },
  field: { gap: 8 },
  label: { color: colors.text, fontWeight: '600', fontSize: 15, lineHeight: 22 },
  input: { minHeight: 54, borderWidth: 1, borderColor: colors.border, borderRadius: 14, padding: 14, backgroundColor: colors.surface, color: colors.text, fontSize: 17 },
  check: { minHeight: 52, flexDirection: 'row', gap: 12, alignItems: 'center', paddingVertical: 6 },
  tick: { width: 26, height: 26, borderRadius: 6, borderWidth: 1, borderColor: colors.pink, textAlign: 'center', fontSize: 19, color: colors.pink },
  tickChecked: { backgroundColor: colors.lightPink },
  environment: { color: colors.purple, backgroundColor: colors.lightPurple, padding: 13, borderRadius: 12, fontSize: 14, lineHeight: 20 },
  choice: { minHeight: 54, paddingVertical: 16, borderBottomWidth: 1, borderBottomColor: colors.border },
});
