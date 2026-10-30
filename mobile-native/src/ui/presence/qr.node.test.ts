import assert from 'node:assert/strict';
import test from 'node:test';
import jsQR from 'jsqr';
import { presenceQr, PRESENCE_QR_CELL, PRESENCE_QR_MARGIN } from './qr';

function raster(code: string) {
  const matrix = presenceQr(code);
  const side = (matrix.size + 2 * PRESENCE_QR_MARGIN) * PRESENCE_QR_CELL;
  const pixels = new Uint8ClampedArray(side * side * 4).fill(255);
  for (const run of matrix.runs) {
    for (let y = (run.row + PRESENCE_QR_MARGIN) * PRESENCE_QR_CELL; y < (run.row + PRESENCE_QR_MARGIN + 1) * PRESENCE_QR_CELL; y += 1) {
      for (let x = (run.start + PRESENCE_QR_MARGIN) * PRESENCE_QR_CELL; x < (run.start + PRESENCE_QR_MARGIN + run.length) * PRESENCE_QR_CELL; x += 1) {
        const offset = (y * side + x) * 4;
        pixels[offset] = pixels[offset + 1] = pixels[offset + 2] = 0;
      }
    }
  }
  return { pixels, side };
}

test('un décodeur indépendant relit chaque code, y compris les zéros initiaux et le renouvellement', () => {
  for (const code of ['123456', '654321', '100001', '100002', '000001', '000000']) {
    const { pixels, side } = raster(code);
    assert.equal(jsQR(pixels, side, side)?.data, code);
  }
});

test('aucune URL ou valeur partielle n’est transformée en QR de présence', () => {
  for (const value of ['12345', '1234567', ' 123456', 'https://jolene.app/123456', '１２３４５６']) {
    assert.throws(() => presenceQr(value), /invalide/);
  }
});
