const PNG_SIGNATURE = Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]);

function readExifOrientation(tiff) {
  if (tiff.length < 8) throw new Error('En-tête TIFF tronqué.');
  const byteOrder = tiff.toString('ascii', 0, 2);
  if (byteOrder !== 'II' && byteOrder !== 'MM') throw new Error('Ordre des octets TIFF invalide.');
  const short = offset => byteOrder === 'II' ? tiff.readUInt16LE(offset) : tiff.readUInt16BE(offset);
  const long = offset => byteOrder === 'II' ? tiff.readUInt32LE(offset) : tiff.readUInt32BE(offset);
  if (short(2) !== 42) throw new Error('Signature TIFF invalide.');
  const directory = long(4);
  if (directory < 8 || directory > tiff.length - 2) throw new Error('Répertoire TIFF hors limites.');
  const count = short(directory);
  if (directory + 2 + count * 12 + 4 > tiff.length) throw new Error('Répertoire TIFF tronqué.');
  let orientation;
  for (let index = 0; index < count; index++) {
    const entry = directory + 2 + index * 12;
    if (short(entry) !== 0x0112) continue;
    if (orientation !== undefined) throw new Error('Orientation TIFF dupliquée.');
    if (short(entry + 2) !== 3 || long(entry + 4) !== 1) throw new Error('Type de champ Orientation TIFF invalide.');
    orientation = short(entry + 8);
    if (orientation < 1 || orientation > 8) throw new Error('Valeur Orientation TIFF invalide.');
  }
  return orientation ?? 1;
}

/**
 * Read display dimensions without decoding or rewriting the PNG pixels.
 * eXIf contains a TIFF header directly (not JPEG's Exif\0\0 prefix).
 * This checks metadata bounds, not CRCs or compressed image data.
 * https://www.w3.org/TR/png-3/#eXIf
 */
export function readPngDimensions(image) {
  if (!Buffer.isBuffer(image) || !image.subarray(0, 8).equals(PNG_SIGNATURE)) {
    throw new Error('Signature PNG invalide.');
  }
  let encodedWidth;
  let encodedHeight;
  let exifOrientation = 1;
  let hasExif = false;
  let hasEnd = false;
  let offset = 8;
  while (offset < image.length) {
    if (offset + 12 > image.length) throw new Error('Chunk PNG tronqué.');
    const length = image.readUInt32BE(offset);
    const next = offset + 12 + length;
    if (next > image.length) throw new Error('Données du chunk PNG tronquées.');
    const type = image.toString('ascii', offset + 4, offset + 8);
    const data = image.subarray(offset + 8, offset + 8 + length);
    if (offset === 8 && type !== 'IHDR') throw new Error('En-tête IHDR manquant.');
    if (type === 'IHDR') {
      if (offset !== 8 || length !== 13) throw new Error('En-tête IHDR invalide.');
      encodedWidth = data.readUInt32BE(0);
      encodedHeight = data.readUInt32BE(4);
      if (!encodedWidth || !encodedHeight || encodedWidth > 0x7fffffff || encodedHeight > 0x7fffffff) {
        throw new Error('Dimensions PNG invalides.');
      }
    } else if (type === 'eXIf') {
      if (hasExif) throw new Error('Chunk eXIf dupliqué.');
      hasExif = true;
      exifOrientation = readExifOrientation(data);
    } else if (type === 'IEND') {
      if (length !== 0 || next !== image.length) throw new Error('Fin PNG invalide.');
      hasEnd = true;
    }
    offset = next;
  }
  if (!hasEnd || encodedWidth === undefined) throw new Error('PNG incomplet.');
  // TIFF orientations 5–8 transpose the axes; mirrors 2–4 preserve dimensions.
  const transposed = exifOrientation >= 5;
  return {
    width: transposed ? encodedHeight : encodedWidth,
    height: transposed ? encodedWidth : encodedHeight,
    encodedWidth,
    encodedHeight,
    exifOrientation,
  };
}
