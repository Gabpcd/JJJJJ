// Boucle de purge RGPD des fichiers Storage (supabase/functions/_shared/rgpd-purge-stockage.ts), sans réseau :
// réservation par lots, effacement par l'API Storage groupé par bucket, confirmation par la base (qui seule décide),
// buckets conservés jamais touchés, aucune ligne invalide effacée, aucun chemin dans les erreurs.
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { BUCKETS_PURGEABLES, purgerStockageRgpd, TAILLE_LOT_MAX } from '../../supabase/functions/_shared/rgpd-purge-stockage.ts';

const id = n => `00000000-0000-4000-8000-${String(n).padStart(12, '0')}`;

/** Faux client : file en mémoire, objets Storage en mémoire, confirmation « base » = objet absent. */
function faux({ file, objets, erreurRemove = null, erreurReserver = null }) {
  const appels = { rpc: [], remove: [] };
  const reservees = new Set();
  return {
    appels,
    objets,
    rpc: async (nom, args) => {
      appels.rpc.push([nom, args]);
      if (nom === 'fn_rgpd_purges_stockage_reserver') {
        if (erreurReserver) return { data: null, error: erreurReserver };
        const lot = file.filter(l => !l.purge && !reservees.has(l.id)).slice(0, args.p_limite);
        lot.forEach(l => reservees.add(l.id));
        return { data: lot.map(({ id, bucket, chemin }) => ({ id, bucket, chemin })), error: null };
      }
      if (nom === 'fn_rgpd_purges_stockage_confirmer') {
        let confirmes = 0;
        let enEchec = 0;
        for (const i of args.p_ids) {
          const l = file.find(x => x.id === i);
          if (!objets.has(`${l.bucket}/${l.chemin}`)) { l.purge = true; confirmes += 1; } else { l.erreur = args.p_erreur; enEchec += 1; }
        }
        return { data: { confirmes, en_echec: enEchec }, error: null };
      }
      throw new Error(`RPC inattendue ${nom}`);
    },
    storage: {
      from: bucket => ({
        remove: async chemins => {
          appels.remove.push([bucket, chemins]);
          if (erreurRemove) return { data: null, error: erreurRemove };
          for (const c of chemins) objets.delete(`${bucket}/${c}`);
          return { data: chemins.map(name => ({ name })), error: null };
        },
      }),
    },
  };
}

test('efface par bucket, confirme par la base, s’arrête quand la file est vide', async () => {
  const file = [
    { id: id(1), bucket: 'jolene-documents', chemin: 'u/documents/A/1.pdf' },
    { id: id(2), bucket: 'jolene-documents', chemin: 'u/heures-externes/2.pdf' },
    { id: id(3), bucket: 'justificatifs', chemin: 'u/reclamations/x/3.pdf' },
    { id: id(4), bucket: 'attestations-heures-externes', chemin: 'u/4.pdf' },
  ];
  const objets = new Set(file.map(l => `${l.bucket}/${l.chemin}`));
  const c = faux({ file, objets });
  const bilan = await purgerStockageRgpd(c, { taille: 10 });
  assert.deepEqual(bilan, { reserves: 4, confirmes: 4, en_echec: 0, lots: 1 });
  assert.equal(objets.size, 0);
  assert.deepEqual(c.appels.remove.map(([b, ch]) => [b, ch.length]).sort(),
    [['attestations-heures-externes', 1], ['jolene-documents', 2], ['justificatifs', 1]]);
  assert.ok(file.every(l => l.purge));
});

test('échec de l’API Storage : rien n’est tenu pour effacé, code borné sans chemin', async () => {
  const file = [{ id: id(1), bucket: 'jolene-documents', chemin: 'u/documents/A/NOMPERSONNE.pdf' }];
  const objets = new Set(['jolene-documents/u/documents/A/NOMPERSONNE.pdf']);
  const c = faux({ file, objets, erreurRemove: { message: 'refus pour u/documents/A/NOMPERSONNE.pdf', statusCode: 403 } });
  const bilan = await purgerStockageRgpd(c);
  assert.deepEqual(bilan, { reserves: 1, confirmes: 0, en_echec: 1, lots: 1 });
  assert.equal(file[0].erreur, 'STORAGE_REMOVE:403');
  assert.doesNotMatch(JSON.stringify(c.appels.rpc), /NOMPERSONNE/, 'aucun chemin renvoyé à la base comme erreur');
});

test('ligne hors des buckets purgeables ou chemin suspect : jamais effacée, consignée', async () => {
  const file = [
    { id: id(1), bucket: 'contrats-signes', chemin: 'm/contrat.pdf' },
    { id: id(2), bucket: 'jolene-documents', chemin: 'u/../autre/x.pdf' },
    { id: id(3), bucket: 'copies-bulletins-paie', chemin: 'b.pdf' },
  ];
  const objets = new Set(file.map(l => `${l.bucket}/${l.chemin}`));
  const c = faux({ file, objets });
  const bilan = await purgerStockageRgpd(c);
  assert.equal(c.appels.remove.length, 0, 'aucun appel Storage');
  assert.equal(objets.size, 3);
  assert.deepEqual(bilan, { reserves: 3, confirmes: 0, en_echec: 3, lots: 1 });
  assert.ok(file.every(l => l.erreur === 'LIGNE_INVALIDE'));
  assert.ok(!BUCKETS_PURGEABLES.includes('contrats-signes') && !BUCKETS_PURGEABLES.includes('copies-bulletins-paie'));
});

test('lots bornés, réservation refusée remontée', async () => {
  const file = Array.from({ length: 250 }, (_, i) => ({ id: id(i + 1), bucket: 'jolene-documents', chemin: `u/documents/A/${i}.pdf` }));
  const objets = new Set(file.map(l => `${l.bucket}/${l.chemin}`));
  const c = faux({ file, objets });
  const bilan = await purgerStockageRgpd(c, { taille: 1000, lots: 2 });
  assert.equal(TAILLE_LOT_MAX, 100);
  assert.deepEqual(bilan, { reserves: 200, confirmes: 200, en_echec: 0, lots: 2 });
  assert.ok(c.appels.rpc.filter(([n]) => n === 'fn_rgpd_purges_stockage_reserver').every(([, a]) => a.p_limite === 100));
  await assert.rejects(purgerStockageRgpd(faux({ file: [], objets: new Set(), erreurReserver: { code: '42501', message: 'x' } })),
    /^Error: RESERVATION_REFUSEE:42501$/);
});

test('edge : garde cron avant tout effet, sonde sans effet, aucun chemin journalisé', () => {
  const source = readFileSync(new URL('../../supabase/functions/purge-stockage-rgpd/index.ts', import.meta.url), 'utf8')
    .replace(/\/\*[\s\S]*?\*\//g, '').replace(/^\s*\/\/.*$/gm, '');
  const garde = source.search(/await\s+verifyCronServiceAuth\s*\(\s*req\s*,\s*admin\s*\)/);
  const refus = source.search(/if\s*\(\s*!auth\.ok\s*\)\s*return\s+cronAuthErrorResponse/);
  const sonde = source.search(/if\s*\(\s*isCronAuthProbe\s*\(\s*req\s*\)\s*\)\s*return\s+cronAuthProbeResponse/);
  const effet = source.search(/purgerStockageRgpd\s*\(/g);
  assert.ok(garde > 0 && refus > garde && sonde > refus && effet > sonde, 'garde, refus, sonde, puis purge');
  assert.doesNotMatch(source, /console\.(log|error|warn)\([^)]*chemin/);
  const config = readFileSync(new URL('../../supabase/config.toml', import.meta.url), 'utf8');
  assert.match(config, /\[functions\.purge-stockage-rgpd\]\nverify_jwt = false\n/);
});
