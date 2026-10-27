import type { NativeDocumentFile } from './types';

/** Three synthetic pixels, no professional or identity data. Never a real justificatif. */
const PNG = [137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82, 0, 0, 0, 3, 0, 0, 0, 1, 8, 2, 0, 0, 0, 148, 130, 131, 227, 0, 0, 0, 18, 73, 68, 65, 84, 120, 156, 99, 56, 41, 90, 88, 104, 185, 240, 255, 255, 255, 0, 23, 27, 5, 152, 82, 199, 73, 41, 0, 0, 0, 0, 73, 69, 78, 68, 174, 66, 96, 130] as const;

export function createDemoDocumentFile(name = 'justificatif-demo.png'): NativeDocumentFile {
  return { name, mime: 'image/png', bytes: new Uint8Array(PNG) };
}
