import type { ReactNode } from 'react';
import { ActivityIndicator, Pressable, StyleSheet, Text, View } from 'react-native';
import { LinearGradient } from 'expo-linear-gradient';
import { colors, shared } from './theme';

export function ActionButton({ label, onPress, busy = false, secondary = false, disabled = false, testID }: {
  label: string;
  onPress: () => void;
  busy?: boolean;
  secondary?: boolean;
  disabled?: boolean;
  testID?: string;
}) {
  const blocked = disabled || busy;
  const content = <View style={styles.buttonContent}>
    {busy ? <ActivityIndicator color={secondary ? colors.pink : '#FFFFFF'} /> : null}
    <Text style={[styles.buttonText, secondary && styles.secondaryText]}>{label}</Text>
  </View>;
  return <Pressable accessibilityRole="button" accessibilityState={{ disabled: blocked, busy }}
    onPress={onPress} disabled={blocked} testID={testID}
    style={({ pressed }) => [styles.button, secondary && styles.secondary, (pressed || blocked) && styles.dimmed]}>
    {secondary ? content : <LinearGradient colors={[colors.pink, colors.purple]}
      start={{ x: 0, y: 0 }} end={{ x: 1, y: 1 }}>{content}</LinearGradient>}
  </Pressable>;
}

export function ModeNotice({ mode }: { mode: 'demo' | 'staging' }) {
  return <View style={styles.mode} testID="environment-banner">
    <View style={styles.modeDot} />
    <Text style={styles.modeText}>{mode === 'demo' ? 'Démo · données fictives' : 'Environnement TEST'}</Text>
  </View>;
}

export function StatusPanel({ title, message, loading, children, testID }: {
  title: string;
  message?: string;
  loading?: boolean;
  children?: ReactNode;
  testID?: string;
}) {
  return <View style={styles.status} testID={testID}>
    {loading ? <ActivityIndicator size="large" color={colors.pink} /> : <View style={styles.statusMark}><Text style={styles.statusMarkText}>J</Text></View>}
    <Text style={[shared.sectionTitle, styles.center]} accessibilityRole="header">{title}</Text>
    {message ? <Text style={[shared.subtitle, styles.center]}>{message}</Text> : null}
    {children ? <View style={styles.statusActions}>{children}</View> : null}
  </View>;
}

export function ErrorNotice({ message, onRetry }: { message: string; onRetry?: () => void }) {
  return <View accessibilityLiveRegion="polite" style={styles.error} testID="error-notice">
    <Text style={styles.errorText}>{message}</Text>
    {onRetry ? <Pressable accessibilityRole="button" accessibilityLabel="Réessayer" onPress={onRetry}
      style={({ pressed }) => [styles.retry, pressed && styles.dimmed]} testID="retry-button">
      <Text style={styles.retryText}>Réessayer</Text>
    </Pressable> : null}
  </View>;
}

export function LabelValue({ label, value }: { label: string; value: string }) {
  return <View style={styles.labelValue}>
    <Text style={shared.small}>{label}</Text>
    <Text style={styles.value}>{value}</Text>
  </View>;
}

export const styles = StyleSheet.create({
  button: { borderRadius: 18, overflow: 'hidden', minHeight: 54 },
  buttonContent: { minHeight: 54, paddingVertical: 16, paddingHorizontal: 22, flexDirection: 'row', gap: 10, alignItems: 'center', justifyContent: 'center' },
  buttonText: { fontSize: 16, lineHeight: 23, fontWeight: '700', color: '#FFFFFF', textAlign: 'center', flexShrink: 1 },
  secondary: { borderWidth: 1, borderColor: colors.border, backgroundColor: colors.surface },
  secondaryText: { color: colors.pink },
  dimmed: { opacity: 0.65 },
  mode: { paddingVertical: 11, paddingHorizontal: 15, borderRadius: 14, flexDirection: 'row', alignItems: 'center', gap: 9, backgroundColor: colors.lightPurple },
  modeDot: { height: 6, width: 6, borderRadius: 3, backgroundColor: colors.purple },
  modeText: { flex: 1, color: '#5A3977', fontSize: 13, lineHeight: 19, fontWeight: '600' },
  status: { alignItems: 'center', gap: 14, paddingHorizontal: 26, paddingVertical: 46, width: '100%', maxWidth: 600, alignSelf: 'center' },
  statusMark: { height: 56, width: 56, borderRadius: 18, backgroundColor: colors.lightPink, alignItems: 'center', justifyContent: 'center' },
  statusMarkText: { fontSize: 30, fontWeight: '700', color: colors.pink },
  center: { textAlign: 'center' },
  statusActions: { width: '100%', marginTop: 8, gap: 12 },
  error: { padding: 16, gap: 8, borderRadius: 16, backgroundColor: colors.dangerBackground },
  errorText: { color: colors.danger, fontSize: 15, lineHeight: 22 },
  retry: { alignSelf: 'flex-start', minHeight: 44, justifyContent: 'center', paddingHorizontal: 5 },
  retryText: { color: colors.danger, fontSize: 15, fontWeight: '700' },
  labelValue: { gap: 4, paddingVertical: 12 },
  value: { fontSize: 17, lineHeight: 25, color: colors.text, fontWeight: '600' },
});
