import { StyleSheet } from 'react-native';

export const colors = {
  background: '#FCF9FC',
  surface: '#FFFFFF',
  text: '#241C2C',
  secondary: '#685D71',
  muted: '#81748B',
  border: '#E9E1ED',
  pink: '#C91571',
  purple: '#7139A1',
  lightPink: '#FAEAF4',
  lightPurple: '#F0EAF8',
  danger: '#A32435',
  dangerBackground: '#FFF1F2',
  success: '#24644A',
};

export const shared = StyleSheet.create({
  flex: { flex: 1 },
  screen: { flex: 1, backgroundColor: colors.background },
  content: { width: '100%', maxWidth: 760, alignSelf: 'center', paddingHorizontal: 22 },
  title: { color: colors.text, fontSize: 30, lineHeight: 38, fontWeight: '700', letterSpacing: -0.6 },
  subtitle: { color: colors.secondary, fontSize: 16, lineHeight: 24 },
  sectionTitle: { color: colors.text, fontSize: 20, lineHeight: 28, fontWeight: '700' },
  body: { color: colors.text, fontSize: 16, lineHeight: 24 },
  small: { color: colors.secondary, fontSize: 14, lineHeight: 21 },
  card: {
    padding: 20,
    backgroundColor: colors.surface,
    borderWidth: 1,
    borderColor: colors.border,
    borderRadius: 24,
  },
});
