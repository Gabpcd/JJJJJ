import assert from 'node:assert/strict';
import test from 'node:test';
import { readPngDimensions } from './png-dimensions.mjs';

// Metadata fixtures only: the reader deliberately does not decode pixels or CRCs.
function chunk(type, data = Buffer.alloc(0)) {
  const buffer = Buffer.alloc(data.length + 12);
  buffer.writeUInt32BE(data.length);
  buffer.write(type, 4, 'ascii');
  data.copy(buffer, 8);
  return buffer;
}

function tiff(orientation, order = 'MM') {
  const buffer = Buffer.alloc(38);
  buffer.write(order, 0, 'ascii');
  const short = (value, offset) => order === 'II' ? buffer.writeUInt16LE(value, offset) : buffer.writeUInt16BE(value, offset);
  const long = (value, offset) => order === 'II' ? buffer.writeUInt32LE(value, offset) : buffer.writeUInt32BE(value, offset);
  short(42, 2);
  long(8, 4);
  short(2, 8);
  // An unrelated entry precedes Orientation, so the tag must be located by ID.
  short(0x0100, 10);
  short(4, 12);
  long(1, 14);
  long(1640, 18);
  short(0x0112, 22);
  short(3, 24);
  long(1, 26);
  short(orientation, 30);
  return buffer;
}

function png(exif, width = 1640, height = 2360) {
  const header = Buffer.alloc(13);
  header.writeUInt32BE(width);
  header.writeUInt32BE(height, 4);
  header[8] = 8;
  header[9] = 2;
  return Buffer.concat([
    Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]),
    chunk('IHDR', header),
    chunk('IDAT'),
    ...(exif === undefined ? [] : [chunk('eXIf', exif)]),
    chunk('IEND'),
  ]);
}

test('ordinary PNG and explicit orientation 1 retain portrait dimensions', () => {
  for (const image of [png(), png(tiff(1))]) {
    assert.deepEqual(readPngDimensions(image), {
      width: 1640, height: 2360, encodedWidth: 1640, encodedHeight: 2360, exifOrientation: 1,
    });
  }
});

test('iPad orientations 6 and 8 display in landscape without modifying the capture', () => {
  for (const orientation of [6, 8]) {
    const image = png(tiff(orientation));
    const original = Buffer.from(image);
    assert.deepEqual(readPngDimensions(image), {
      width: 2360, height: 1640, encodedWidth: 1640, encodedHeight: 2360, exifOrientation: orientation,
    });
    assert.deepEqual(image, original);
  }
});

test('little-endian TIFF and mirrored transposed orientations use display dimensions', () => {
  for (const orientation of [5, 6, 7, 8]) {
    const result = readPngDimensions(png(tiff(orientation, 'II')));
    assert.equal(result.width, 2360);
    assert.equal(result.height, 1640);
    assert.equal(result.exifOrientation, orientation);
  }
  assert.equal(readPngDimensions(png(tiff(3, 'II'))).width, 1640);
});

test('an EXIF directory without Orientation preserves the encoded dimensions', () => {
  const metadata = tiff(8);
  metadata.writeUInt16BE(0x0101, 22);
  assert.equal(readPngDimensions(png(metadata)).exifOrientation, 1);
});

test('invalid PNG signature, missing end, dimensions and truncated chunks are rejected', () => {
  assert.throws(() => readPngDimensions(Buffer.from('not a PNG')), /Signature PNG/);
  assert.throws(() => readPngDimensions(png().subarray(0, -12)), /PNG incomplet/);
  assert.throws(() => readPngDimensions(png().subarray(0, -1)), /tronqué/);
  assert.throws(() => readPngDimensions(png(undefined, 0)), /Dimensions PNG/);
  const oversizedChunk = png();
  oversizedChunk.writeUInt32BE(0xffffffff, 8);
  assert.throws(() => readPngDimensions(oversizedChunk), /tronquées/);
});

test('malformed TIFF is rejected rather than silently treated as portrait', () => {
  assert.throws(() => readPngDimensions(png(Buffer.alloc(7))), /TIFF tronqué/);
  const badOrder = tiff(8);
  badOrder.write('XX');
  assert.throws(() => readPngDimensions(png(badOrder)), /Ordre des octets/);
  const badOffset = tiff(8, 'II');
  badOffset.writeUInt32LE(0xffffffff, 4);
  assert.throws(() => readPngDimensions(png(badOffset)), /hors limites/);
  assert.throws(() => readPngDimensions(png(tiff(8).subarray(0, 31))), /Répertoire TIFF tronqué/);
  for (const orientation of [0, 9]) {
    assert.throws(() => readPngDimensions(png(tiff(orientation))), /Valeur Orientation/);
  }
  const badType = tiff(8);
  badType.writeUInt16BE(4, 24);
  assert.throws(() => readPngDimensions(png(badType)), /Type de champ/);
});

test('duplicate EXIF orientation data is rejected as ambiguous', () => {
  const metadata = tiff(8);
  metadata.subarray(22, 34).copy(metadata, 10);
  assert.throws(() => readPngDimensions(png(metadata)), /Orientation TIFF dupliquée/);
  const image = png(tiff(8));
  const duplicated = Buffer.concat([image.subarray(0, -12), chunk('eXIf', tiff(1)), chunk('IEND')]);
  assert.throws(() => readPngDimensions(duplicated), /eXIf dupliqué/);
});
