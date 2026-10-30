import qrcode from 'qrcode-generator';

export const PRESENCE_QR_CELL = 7;
export const PRESENCE_QR_MARGIN = 4;
export interface PresenceQrRun { row: number; start: number; length: number }

/** Encodes the same six characters as the manual entry, including leading zeroes. */
export function presenceQr(code: string): { size: number; runs: PresenceQrRun[] } {
  if (!/^\d{6}$/.test(code)) throw new Error('Code de pointage invalide.');
  const qr = qrcode(0, 'M');
  qr.addData(code, 'Numeric');
  qr.make();
  const size = qr.getModuleCount();
  const runs: PresenceQrRun[] = [];
  for (let row = 0; row < size; row += 1) {
    let start = -1;
    for (let column = 0; column <= size; column += 1) {
      const dark = column < size && qr.isDark(row, column);
      if (dark && start === -1) start = column;
      if (!dark && start !== -1) {
        runs.push({ row, start, length: column - start });
        start = -1;
      }
    }
  }
  return { size, runs };
}
