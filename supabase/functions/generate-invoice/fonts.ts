import fontkit from 'npm:@pdf-lib/fontkit@1.1.1';
import { NOTO_REGULAR_BASE64, NOTO_REGULAR_SHA256, NOTO_BOLD_BASE64, NOTO_BOLD_SHA256 } from './fonts/noto-sans-data.ts';

type Polices = { regular: Uint8Array; bold: Uint8Array; caracteres: ReadonlySet<number> };
let polices: Promise<Polices> | undefined;

export class ErreurPoliceFacture extends Error {
  constructor(public readonly code: 'POLICE_PDF_INVALIDE' | 'CARACTERE_PDF_NON_PRIS_EN_CHARGE', public readonly detail = '') {
    super(detail ? `${code}: ${detail}` : code);
  }
}

async function decoderPolice(base64: string, sha256: string): Promise<Uint8Array> {
  const bytes = Uint8Array.from(atob(base64), c => c.charCodeAt(0));
  const hash = [...new Uint8Array(await crypto.subtle.digest('SHA-256', bytes))]
    .map(b => b.toString(16).padStart(2, '0')).join('');
  if (hash !== sha256) throw new ErreurPoliceFacture('POLICE_PDF_INVALIDE');
  return bytes;
}

export function chargerPolicesFacture(): Promise<Polices> {
  if (!polices) polices = (async () => {
    try {
      const [regular, bold] = await Promise.all([
        decoderPolice(NOTO_REGULAR_BASE64, NOTO_REGULAR_SHA256),
        decoderPolice(NOTO_BOLD_BASE64, NOTO_BOLD_SHA256),
      ]);
      const normal = fontkit.create(regular).characterSet;
      const gras = new Set(fontkit.create(bold).characterSet);
      return { regular, bold, caracteres: new Set(normal.filter(cp => gras.has(cp))) };
    } catch {
      // Never fall back to Helvetica, an altered name or a missing-glyph box.
      throw new ErreurPoliceFacture('POLICE_PDF_INVALIDE');
    }
  })();
  return polices;
}

export async function verifierCaracteresFacture(textes: readonly unknown[]): Promise<void> {
  const { caracteres } = await chargerPolicesFacture();
  for (const texte of textes) if (typeof texte === 'string') {
    for (const caractere of texte) {
      const cp = caractere.codePointAt(0)!;
      // PDF-lib treats these as layout controls rather than font glyphs.
      if (cp === 9 || cp === 10 || cp === 13) continue;
      if (!caracteres.has(cp)) throw new ErreurPoliceFacture('CARACTERE_PDF_NON_PRIS_EN_CHARGE', `U+${cp.toString(16).toUpperCase()}`);
    }
  }
}

export { fontkit };
