// Fenêtre d'un cron pg_cron pour les tests Playwright joués contre la base partagée
// (scripts/lib/playwright-fenetre-cron.mjs). Sans réseau ni horloge : l'heure est un paramètre.
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';
import {
  delaiAvantFenetreCron,
  FENETRE_AUTO_TRANSITIONS_MISSIONS,
} from '../../scripts/lib/playwright-fenetre-cron.mjs';

const F = FENETRE_AUTO_TRANSITIONS_MISSIONS;
// 20/11/2026 18:00:00 UTC, un multiple de dix minutes.
const PASSAGE = Date.UTC(2026, 10, 20, 18, 0, 0);

test('le passage de référence tombe bien sur un multiple de la période', () => {
  assert.equal(PASSAGE % F.periodeMs, 0);
});

test('aucune attente quand la section tient entre deux passages', () => {
  assert.equal(delaiAvantFenetreCron(PASSAGE + F.margeApresPassageMs, F), 0);
  assert.equal(delaiAvantFenetreCron(PASSAGE + 5 * 60_000, F), 0);
  assert.equal(delaiAvantFenetreCron(PASSAGE + F.periodeMs - F.sectionCritiqueMs - 1, F), 0);
});

test('juste après un passage, attendre la fin de la marge', () => {
  assert.equal(delaiAvantFenetreCron(PASSAGE, F), F.margeApresPassageMs);
  assert.equal(delaiAvantFenetreCron(PASSAGE + 4_000, F), F.margeApresPassageMs - 4_000);
  assert.equal(delaiAvantFenetreCron(PASSAGE + F.margeApresPassageMs - 1, F), 1);
});

test('trop près du prochain passage, commencer après lui et sa marge', () => {
  // Cas mesuré le 18/11/2026 : acceptation à 23:49:59, cron à 23:50:00, signature refusée à 23:50:17.
  const acceptation = Date.UTC(2026, 10, 18, 23, 49, 59);
  assert.equal(delaiAvantFenetreCron(acceptation, F), 1_000 + F.margeApresPassageMs);
  assert.equal(
    delaiAvantFenetreCron(PASSAGE + F.periodeMs - F.sectionCritiqueMs, F),
    F.sectionCritiqueMs + F.margeApresPassageMs,
  );
});

test('après l’attente, la section entière précède le passage suivant', () => {
  for (let decalage = 0; decalage < F.periodeMs; decalage += 1_000) {
    const depart = PASSAGE + decalage + delaiAvantFenetreCron(PASSAGE + decalage, F);
    const depuisPassage = depart % F.periodeMs;
    assert.ok(depuisPassage >= F.margeApresPassageMs, `marge non tenue à +${decalage} ms`);
    assert.ok(depuisPassage + F.sectionCritiqueMs < F.periodeMs, `section coupée à +${decalage} ms`);
    assert.equal(delaiAvantFenetreCron(depart, F), 0, `seconde attente demandée à +${decalage} ms`);
  }
});

test('l’attente reste bornée par la section et deux marges', () => {
  let maximum = 0;
  for (let decalage = 0; decalage < F.periodeMs; decalage += 250) {
    maximum = Math.max(maximum, delaiAvantFenetreCron(PASSAGE + decalage, F));
  }
  assert.equal(maximum, F.sectionCritiqueMs + F.margeApresPassageMs);
});

test('paramètres incohérents refusés', () => {
  const refuse = (heure, fenetre, code) => assert.throws(() => delaiAvantFenetreCron(heure, fenetre), { message: code });
  refuse(-1, F, 'FENETRE_CRON_HEURE_INVALIDE');
  refuse(1.5, F, 'FENETRE_CRON_HEURE_INVALIDE');
  // Sept minutes ne divisent pas une heure : « */7 » ne suit pas l'époque Unix.
  refuse(PASSAGE, { ...F, periodeMs: 420_000 }, 'FENETRE_CRON_PERIODE_INVALIDE');
  refuse(PASSAGE, { ...F, periodeMs: 0 }, 'FENETRE_CRON_PERIODE_INVALIDE');
  refuse(PASSAGE, { ...F, sectionCritiqueMs: 0 }, 'FENETRE_CRON_SECTION_INVALIDE');
  refuse(PASSAGE, { ...F, sectionCritiqueMs: F.periodeMs }, 'FENETRE_CRON_SECTION_INVALIDE');
});

test('le test daté dans le passé attend hors du passage du cron avant de dater sa mission', () => {
  const source = readFileSync(new URL('../../e2e/flows/presences-autovalidation.spec.ts', import.meta.url), 'utf8');
  const attente = source.indexOf('delaiAvantFenetreCron(Date.now(), FENETRE_AUTO_TRANSITIONS_MISSIONS)');
  const datation = source.indexOf(".update({ debut: debut.toISOString(), fin: fin.toISOString() })");
  const signature = source.indexOf('await seedContratMissionSigne(');
  assert.ok(attente > 0, 'attente absente');
  assert.ok(datation > attente, 'la mission est datée dans le passé avant l’attente');
  assert.ok(signature > datation, 'la signature précède la datation');
});
