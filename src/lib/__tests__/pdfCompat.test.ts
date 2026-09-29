import { execFileSync } from 'node:child_process';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';

describe('polyfills chargés avant PDF.js', () => {
  it('rétablit les API absentes dans un contexte isolé sans API modernes natives', () => {
    const module = resolve(process.cwd(), 'src/lib/pdfCompat.ts');
    const programme = `
      delete Promise.withResolvers;
      delete ArrayBuffer.prototype.transferToFixedLength;
      delete globalThis.structuredClone;
      delete Array.prototype.at;
      await import(${JSON.stringify(module)});
      const pending = Promise.withResolvers(); pending.resolve(42);
      const original = new Uint8Array([10, 20, 30]).buffer;
      const transfer = original.transferToFixedLength(2);
      const copy = structuredClone({ bytes: new Uint8Array([4, 5]), nested: { ok: true } });
      console.log(JSON.stringify({ resolved: await pending.promise, transfer: [...new Uint8Array(transfer)], detached: original.byteLength, copy: [...copy.bytes], nested: copy.nested.ok, at: [1, 2].at(-1) }));
      process.exit(0);
    `;
    const resultat = JSON.parse(execFileSync(process.execPath, ['--input-type=module', '-e', programme], { encoding: 'utf8', timeout: 5000 }).trim());
    expect(resultat).toEqual({ resolved: 42, transfer: [10, 20], detached: 0, copy: [4, 5], nested: true, at: 2 });
  });
});
