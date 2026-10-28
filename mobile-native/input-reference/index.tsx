import { registerRootComponent } from 'expo';
import { useRef, useState } from 'react';
import { Pressable, StyleSheet, Text, TextInput, View } from 'react-native';

// Synthetic comparison only. No Jolene runtime, navigation, network or storage.
const variants = ['controlled-styled', 'uncontrolled-styled', 'controlled-basic'] as const;
function Field({ variant }: { variant: typeof variants[number] }) {
  const [value, setValue] = useState('');
  const [snapshot, setSnapshot] = useState('not-read');
  const events = useRef({ changes: 0, length: 0, eventCount: 0 });
  const controlled = variant !== 'uncontrolled-styled';
  return <View style={styles.group}>
    <Text style={styles.label}>{variant}</Text>
    <TextInput testID={variant} accessibilityLabel={variant}
      {...(controlled ? { value } : { defaultValue: '' })}
      onChange={event => { events.current.eventCount = event.nativeEvent.eventCount; }}
      onChangeText={text => { events.current.changes += 1; events.current.length = text.length; setValue(text); }}
      keyboardType="number-pad" textContentType="oneTimeCode" autoCorrect={false} maxLength={6}
      placeholder="6 chiffres" returnKeyType="default"
      style={variant === 'controlled-basic' ? styles.basic : styles.styled} />
    <Pressable testID={`${variant}-snapshot`} accessibilityRole="button"
      onPress={() => setSnapshot(JSON.stringify(events.current))} style={styles.button}>
      <Text>Lire les mesures</Text>
    </Pressable>
    <Text testID={`${variant}-metrics`}>{snapshot}</Text>
  </View>;
}
function Reference() {
  return <View style={styles.page}>
    <Text testID="rn-input-reference-title">Comparaison RN — données synthétiques</Text>
    {variants.map(variant => <Field key={variant} variant={variant} />)}
  </View>;
}
const styles = StyleSheet.create({
  page: { flex: 1, paddingTop: 64, paddingHorizontal: 20, backgroundColor: 'white' },
  group: { marginTop: 8, gap: 2 }, label: { fontSize: 12 }, button: { minHeight: 30, justifyContent: 'center' },
  basic: { minHeight: 56, borderWidth: 1, paddingHorizontal: 16, fontSize: 22 },
  styled: { backgroundColor: '#ffffff', color: '#151522', fontSize: 22, letterSpacing: 5, minHeight: 56,
    borderColor: '#e6e6ec', borderWidth: 1, borderRadius: 14, paddingHorizontal: 16, paddingVertical: 14 },
});
registerRootComponent(Reference);
