// Cohorte STAGING du lot 5 (L5-T13) : TOUT le SQL de scripts/mobile/staging-lot5-fixture.mjs exécuté sur PostgreSQL 17
// éphémère chargé avec supabase/schema/public.sql (job « Paiements — verrous PostgreSQL 17 éphémère » de validate-pr,
// base dédiée staging_lot5_banc). Garde née du premier run STAGING du 25/11/2026 (uuid = uuid[] ; code de pointage
// régénéré par le gel à l'assignation) : un tel défaut casse désormais cette garde, pas un run.
import test from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { charger, parcours, moteurPsql } from '../../scripts/mobile/staging-lot5-banc-sql.mjs';

test('cohorte STAGING du lot 5 : préparation, parcours, résidus, nettoyage et reprise partielle sur le schéma du dépôt', async () => {
  assert.equal(process.env.JOLENE_PG_CONCURRENCY, 'CI_EPHEMERE', 'PostgreSQL éphémère de la CI seulement');
  assert.equal(process.env.PGHOST, '127.0.0.1');
  assert.equal(process.env.PGDATABASE, 'staging_lot5_banc', 'base dédiée, jamais partagée avec les autres étapes');
  const moteur = moteurPsql({ spawn: spawnSync });
  const [version] = await moteur.executer("SELECT current_setting('server_version_num')::int / 10000 AS majeure;");
  assert.equal(version.majeure, 17);
  const { instructions, passe } = await charger(moteur.executer, { lot: moteur.lot, journal: console.log });
  assert.ok(passe > instructions * 0.98, `schéma chargé : ${passe}/${instructions}`);
  const etapes = await parcours(moteur.executer, { journal: console.log });
  assert.ok(etapes.length >= 20 && etapes.every(e => e.ok), JSON.stringify(etapes.filter(e => !e.ok)));
});
