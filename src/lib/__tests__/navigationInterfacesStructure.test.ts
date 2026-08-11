import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';

const racine = process.cwd();
const app = readFileSync(resolve(racine, 'src/App.tsx'), 'utf8');
const navigation = readFileSync(resolve(racine, 'src/components/BarreNavigation.tsx'), 'utf8');
const compteSoignant = readFileSync(resolve(racine, 'src/pages/MonCompteSoignant.tsx'), 'utf8');
const compteEtablissement = readFileSync(resolve(racine, 'src/pages/MonCompteEtablissement.tsx'), 'utf8');

const routesDeclarees = new Set(
  [...app.matchAll(/<Route path="([^"]+)"/g)].map((match) => match[1]),
);

function routesLitterales(source: string): string[] {
  const routes = [
    ...source.matchAll(/route:\s*['"](\/[^'"]+)['"]/g),
    ...source.matchAll(/navigate\(\s*['"](\/[^'"]+)['"]/g),
  ].map((match) => match[1]);

  return [...new Set(routes.map((route) => route.split(/[?#]/, 1)[0]))];
}

function routesManquantes(source: string): string[] {
  return routesLitterales(source).filter((route) => !routesDeclarees.has(route));
}

function routesDansConstante(nom: string): string[] {
  const bloc = navigation.match(new RegExp(`const ${nom}: NavItem\\[\\] = \\[([\\s\\S]*?)\\n\\];`));
  expect(bloc, `${nom} doit rester déclarée explicitement`).not.toBeNull();
  return routesLitterales(bloc?.[1] ?? '');
}

describe('Navigation frontend — soignant et établissement', () => {
  it('ne laisse aucun lien de navigation principal sans route déclarée', () => {
    expect(routesManquantes(navigation)).toEqual([]);
  });

  it('ne laisse aucun lien du hub compte soignant sans route déclarée', () => {
    expect(routesManquantes(compteSoignant)).toEqual([]);
  });

  it('ne laisse aucun lien du hub compte établissement sans route déclarée', () => {
    expect(routesManquantes(compteEtablissement)).toEqual([]);
  });

  it('conserve cinq onglets mobiles distincts et accessibles pour chaque interface', () => {
    const soignant = routesDansConstante('NAV_SOIGNANT_MOBILE');
    const etablissement = routesDansConstante('NAV_ETABLISSEMENT_MOBILE');

    expect(soignant).toHaveLength(5);
    expect(new Set(soignant).size).toBe(5);
    expect(soignant).toContain('/soignant/mon-compte');
    expect(soignant.every((route) => routesDeclarees.has(route))).toBe(true);

    expect(etablissement).toHaveLength(5);
    expect(new Set(etablissement).size).toBe(5);
    expect(etablissement).toContain('/etablissement/mon-compte');
    expect(etablissement).toContain('/etablissement/missions/creer');
    expect(etablissement.every((route) => routesDeclarees.has(route))).toBe(true);
  });
});
