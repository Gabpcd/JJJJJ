import { StyleSheet, View } from 'react-native';

/** Small native views, no font download, web image or icon accessibility duplicate. */
export function TabIcon({ name, color }: { name: 'search' | 'list' | 'person' | 'home'; color: string }) {
  return <View style={styles.box} accessible={false} importantForAccessibility="no-hide-descendants">
    {name === 'search' ? <><View style={[styles.lens, { borderColor: color }]} /><View style={[styles.handle, { backgroundColor: color }]} /></>
      : name === 'person' ? <><View style={[styles.head, { borderColor: color }]} /><View style={[styles.shoulders, { borderColor: color }]} /></>
        : name === 'home' ? <><View style={[styles.roof, { borderColor: color }]} /><View style={[styles.house, { borderColor: color }]} /></>
          : <View style={[styles.sheet, { borderColor: color }]}>{[0, 1, 2].map(i => <View key={i} style={[styles.line, { backgroundColor: color }]} />)}</View>}
  </View>;
}
const styles = StyleSheet.create({
  box: { width: 26, height: 26 }, lens: { position: 'absolute', top: 1, left: 2, width: 17, height: 17, borderWidth: 2, borderRadius: 9 },
  handle: { position: 'absolute', top: 18, left: 16, width: 10, height: 2, transform: [{ rotate: '45deg' }] },
  head: { position: 'absolute', top: 1, left: 9, width: 9, height: 9, borderWidth: 2, borderRadius: 5 },
  shoulders: { position: 'absolute', top: 14, left: 4, width: 19, height: 10, borderWidth: 2, borderTopLeftRadius: 10, borderTopRightRadius: 10 },
  sheet: { position: 'absolute', top: 2, left: 5, width: 17, height: 22, borderWidth: 2, borderRadius: 3, paddingTop: 4, gap: 3, paddingHorizontal: 3 },
  line: { height: 2, width: 7, borderRadius: 1 },
  roof: { position: 'absolute', top: 3, left: 6, width: 15, height: 15, borderTopWidth: 2, borderLeftWidth: 2, transform: [{ rotate: '45deg' }] },
  house: { position: 'absolute', top: 12, left: 5, width: 18, height: 12, borderWidth: 2, borderTopWidth: 0, borderBottomLeftRadius: 2, borderBottomRightRadius: 2 },
});
