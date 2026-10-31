import { useMemo } from 'react';
import { StyleSheet, View } from 'react-native';
import { presenceQr, PRESENCE_QR_CELL, PRESENCE_QR_MARGIN } from './qr';

/** Native views: no browser, remote image request or cached code bitmap. */
export function PresenceQr({ code }: { code: string }) {
  const matrix = useMemo(() => presenceQr(code), [code]);
  const side = (matrix.size + 2 * PRESENCE_QR_MARGIN) * PRESENCE_QR_CELL;
  return <View accessible accessibilityRole="image" accessibilityLabel="QR code de pointage"
    testID="presence-establishment-qr" style={[styles.background, { width: side, height: side }]}>
    {matrix.runs.map(run => <View key={`${run.row}-${run.start}`} style={[styles.dark, {
      top: (run.row + PRESENCE_QR_MARGIN) * PRESENCE_QR_CELL,
      left: (run.start + PRESENCE_QR_MARGIN) * PRESENCE_QR_CELL,
      width: run.length * PRESENCE_QR_CELL, height: PRESENCE_QR_CELL,
    }]} />)}
  </View>;
}

const styles = StyleSheet.create({
  background: { alignSelf: 'center', backgroundColor: '#ffffff' },
  dark: { position: 'absolute', backgroundColor: '#000000' },
});
