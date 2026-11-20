import { createHash } from 'node:crypto';
import { describe, expect, it } from 'vitest';
import { toutesLesRoutesSeo } from './seo-routes';

/**
 * Empreinte du contenu de chaque page publique indexable (`src/lib/seo-empreintes.json`).
 *
 * À quoi elle sert : le protocole IndexNow demande de ne signaler que les pages ajoutées,
 * modifiées ou supprimées, jamais tout le site à chaque mise en ligne. Le workflow
 * `indexnow.yml` compare ce fichier entre deux commits de main et ne signale que les adresses
 * dont l'empreinte a changé (`scripts/seo/indexnow.mjs`).
 *
 * Ce test échoue quand le contenu d'une page a changé sans que le fichier suive. Pour le
 * mettre à jour : `npm run seo:empreintes`. Le diff du fichier montre alors, dans la PR, les
 * pages dont le contenu change.
 */
export function empreintesSeo(): Record<string, string> {
  const pages = toutesLesRoutesSeo().filter((p) => p.indexable);
  return Object.fromEntries(
    pages
      .map((p): [string, string] => [p.path, createHash('sha256').update(JSON.stringify(p)).digest('hex').slice(0, 12)])
      .sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0)),
  );
}

describe('empreintes des pages publiques', () => {
  it('une empreinte par page indexable, stable d\'un calcul à l\'autre', () => {
    const e = empreintesSeo();
    expect(Object.keys(e).length).toBe(toutesLesRoutesSeo().filter((p) => p.indexable).length);
    expect(e['/']).toMatch(/^[0-9a-f]{12}$/);
    expect(empreintesSeo()).toEqual(e);
  });

  it('le fichier versionné est à jour (sinon : npm run seo:empreintes)', async () => {
    await expect(`${JSON.stringify(empreintesSeo(), null, 1)}\n`).toMatchFileSnapshot('./seo-empreintes.json');
  });
});
