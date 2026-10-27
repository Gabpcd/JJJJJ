import { StyleSheet, Text, View } from 'react-native';
import { colors } from '../theme';

export function WorkflowNotice({ mode }: { mode: 'demo' | 'supabase' }) {
  return <View style={styles.notice} testID="workflow-environment">
    <Text style={styles.text}>{mode === 'demo'
      ? 'Démonstration · données et candidatures fictives'
      : 'Environnement TEST · candidatures connectées'}</Text>
  </View>;
}
const styles = StyleSheet.create({
  notice: { padding: 14, backgroundColor: colors.lightPurple, borderRadius: 14 },
  text: { color: colors.purple, fontSize: 13, lineHeight: 20, fontWeight: '600' },
});
