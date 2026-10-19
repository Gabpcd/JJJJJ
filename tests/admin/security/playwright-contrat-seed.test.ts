import { describe, it, expect, afterEach } from 'vitest';
import { readFileSync, mkdtempSync, rmSync, realpathSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import * as cleanupStorage from '../../../e2e/helpers/contrat-fixture-storage';
const temporaryDirectories: string[] = [];
afterEach(() => { for (const directory of temporaryDirectories.splice(0)) rmSync(directory, { recursive: true, force: true }); });
import { createHash } from 'node:crypto';
import { Blob } from 'node:buffer';
import { runInNewContext } from 'node:vm';
import ts from 'typescript';

// Charge le vrai helper entier. Seuls les transports sont simulés ; aucune
// variable d'environnement, session, base distante ou Edge n'est consultée.
const compiled = ts.transpileModule(readFileSync('e2e/helpers/seed.ts', 'utf8'), {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022 },
  reportDiagnostics: true,
});
const S = '11111111-1111-4111-8111-111111111111';
const M = '22222222-2222-4222-8222-222222222222';
const C = '33333333-3333-4333-8333-333333333333';
const fixture = { id: S, email: 'playwright-test-caregiver-simulation@jolene.invalid', password: 'synthetique' };

function banc(options: {
  realAccount?: boolean; renderError?: boolean; responseLost?: boolean;
  badHash?: boolean; placeholder?: boolean; differentStoredObject?: boolean;
  firstSignatureRefused?: boolean; changedAfterSignatures?: boolean;
} = {}) {
  const calls: string[] = [];
  const contract: any = { id: C, mission_id: M, soignant_id: S, type_contrat: 'CDD', statut: 'EN_ATTENTE_SIGNATURES',
    signature_soignant: false, signature_etablissement: false, contenu_html: null,
    hash_document: null, storage_path: null, contenu_html_rendu_le: null };
  let stored = '';
  const admin = {
    from(table: string) {
      if (!['soignants', 'contrats_mission'].includes(table)) throw new Error(`Table interdite: ${table}`);
      const filters: Record<string, unknown> = {};
      const chain: any = {
        select(columns: string) { expect(columns).toContain('id'); return chain; },
        eq(column: string, value: unknown) { filters[column] = value; return chain; },
        neq(column: string, value: unknown) { expect([column, value]).toEqual(['statut', 'ANNULE']); return chain; },
        order(column: string, opts: unknown) { expect([column, opts]).toEqual(['cree_le', { ascending: false }]); return chain; },
        limit(count: number) { expect(count).toBe(1); return chain; },
        single: read, maybeSingle: read,
      };
      async function read() {
        calls.push(`read:${table}`);
        if (table === 'soignants') {
          expect(filters).toEqual({ id: S });
          return { data: { id: S, email: fixture.email, est_compte_test: !options.realAccount }, error: null };
        }
        expect(filters).toEqual(filters.id ? { id: C } : { mission_id: M, soignant_id: S });
        return { data: structuredClone(contract), error: null };
      }
      return chain;
    },
    storage: { from(bucket: string) {
      expect(bucket).toBe('contrats-signes');
      return { async download(path: string) {
        expect(path).toBe(contract.storage_path); calls.push('download:original');
        return { data: new Blob([options.differentStoredObject ? 'autre document fictif' : stored]), error: null };
      } };
    } },
  };
  const soignant = {
    async rpc(name: string, args: any) {
      expect(name).toBe('fn_signer_contrat_soignant'); expect(args.p_contrat_id).toBe(C);
      expect(Object.keys(args).sort()).toEqual(['p_contrat_id', 'p_signature_image']);
      const png = Buffer.from(args.p_signature_image.split(',')[1], 'base64');
      expect(png.subarray(0, 8)).toEqual(Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]));
      expect(calls.at(-1)).toBe('download:original'); calls.push('sign:soignant');
      if (options.firstSignatureRefused) return { data: { success: false, error_code: 'HASH_DOCUMENT_CHANGE' }, error: null };
      contract.signature_soignant = true; contract.statut = 'SIGNE_SOIGNANT';
      return { data: { success: true }, error: null };
    },
  };
  const etablissement = {
    functions: { async invoke(name: string, args: any) {
      expect(name).toBe('generate-contrat-mission-pdf');
      expect(Object.keys(args)).toEqual(['body']);
      expect(Object.keys(args.body).sort()).toEqual(['contrat_id', 'donnees_cdd']);
      expect(args.body.contrat_id).toBe(C);
      expect(Object.keys(args.body.donnees_cdd).sort()).toEqual(['cadre', 'cadre_declare', 'confirme', 'representant_nom', 'representant_qualite', 'texte_employeur']);
      expect(args.body.donnees_cdd).toMatchObject({ cadre: 'TEXTE_EMPLOYEUR', confirme: true,
        cadre_declare: 'RECETTE SYNTHÉTIQUE TEST — aucune portée juridique' });
      expect(args.body.donnees_cdd.texte_employeur).toContain(M);
      expect(args.body.donnees_cdd.texte_employeur).toContain(S);
      calls.push('render:etablissement');
      if (options.renderError) return { data: null, error: { message: 'Refus fictif' } };
      stored = '<!doctype html><html lang="fr"><body>Original fictif éphémère</body></html>';
      contract.contenu_html = options.placeholder ? '<p>{{nom}}</p>' : stored;
      contract.hash_document = createHash('sha256').update(contract.contenu_html).digest('hex');
      if (options.badHash) contract.hash_document = '0'.repeat(64);
      contract.storage_path = `${C}/44444444-4444-4444-8444-444444444444.html`;
      contract.contenu_html_rendu_le = '2026-10-19T10:00:00.000Z';
      if (options.responseLost) throw new Error('Réponse perdue simulée');
      return { data: { success: true, contrat_id: C, hash_document: contract.hash_document, storage_path: contract.storage_path }, error: null };
    } },
    async rpc(name: string, args: any) {
      expect(name).toBe('fn_signer_contrat_etablissement'); expect(args.p_contrat_id).toBe(C);
      expect(contract.signature_soignant).toBe(true); calls.push('sign:etablissement');
      contract.signature_etablissement = true; contract.statut = 'SIGNE_COMPLET';
      if (options.changedAfterSignatures) contract.contenu_html += '<p>altération</p>';
      return { data: { success: true }, error: null };
    },
  };
  const exports: any = {};
  runInNewContext(compiled.outputText, { exports, Buffer, Date, console,
    require(name: string) {
      if (name === 'node:crypto') return { createHash };
      if (name === './auth') return { TEST_ACCOUNTS: { etab: { email: 'fixture-etab@jolene.invalid', password: 'synthetique' } } };
      if (name === './db') return { adminClient: () => admin, userClient: () => { throw new Error('Session inattendue'); } };
      if (name === './liberal-eligibility-policy' || name === './cleanup-mission-test' || name === './contrat-fixture-storage') return {};
      throw new Error(`Import interdit: ${name}`);
    },
    fetch() { throw new Error('Réseau interdit'); },
  });
  return { calls, contract, run: () => exports.seedContratMissionSigne(M, fixture, { caregiver: soignant, etablissement }) };
}

describe('préparation canonique du contrat E2E', () => {
  it('prépare le CDD sous l’employeur, relit HTML/Storage, signe S puis E et vérifie le même original', async () => {
    expect(compiled.diagnostics).toEqual([]);
    const b = banc(); expect(await b.run()).toBe(C);
    expect(b.calls).toEqual(['read:soignants', 'read:contrats_mission', 'render:etablissement',
      'read:contrats_mission', 'download:original', 'sign:soignant', 'sign:etablissement', 'read:contrats_mission']);
    expect(b.contract.statut).toBe('SIGNE_COMPLET');
  });
  it.each([
    ['compte non TEST', { realAccount: true }],
    ['génération refusée', { renderError: true }],
    ['réponse perdue après rendu', { responseLost: true }],
    ['empreinte discordante', { badHash: true }],
    ['variables non rendues', { placeholder: true }],
    ['objet Storage différent', { differentStoredObject: true }],
  ] as const)('refuse avant signature, sans retry : %s', async (_name, options) => {
    const b = banc(options); await expect(b.run()).rejects.toThrow();
    expect(b.calls.filter(call => call.startsWith('sign:'))).toEqual([]);
    expect(b.calls.filter(call => call.startsWith('render:')).length).toBe(options.realAccount ? 0 : 1);
  });
  it('ne signe pas pour E si la signature S est refusée et ne masque pas une altération finale', async () => {
    const refused = banc({ firstSignatureRefused: true }); await expect(refused.run()).rejects.toThrow('HASH_DOCUMENT_CHANGE');
    expect(refused.calls).not.toContain('sign:etablissement');
    const changed = banc({ changedAfterSignatures: true }); await expect(changed.run()).rejects.toThrow('original incohérents');
  });
});

function bancNettoyage(options: { purgeError?: boolean; stillPresent?: boolean; otherReference?: boolean;
  badPath?: boolean; storageError?: boolean; nonTechnical?: boolean; quarantine?: boolean; readError?: boolean; captureReadError?: boolean; registryWriteError?: boolean } = {}) {
  const calls: string[] = [];
  const directory = realpathSync(mkdtempSync(path.join(tmpdir(), 'jolene-contrat-cleanup-test-'))); temporaryDirectories.push(directory);
  if (options.registryWriteError) writeFileSync(path.join(directory, 'abcdefghijklmnopqrst'), 'obstacle synthétique');
  const registry = () => cleanupStorage.registreOriginauxFixture('https://abcdefghijklmnopqrst.supabase.co', directory);
  const originalPath = `${C}/44444444-4444-4444-8444-444444444444.html`;
  let present = true;
  let assigned = true;
  const profile = { email: fixture.email, est_compte_test: true, rpps_verifie: true };
  let contractsPresent = true;
  let removeError = options.storageError;
  const allowedDeletes = new Set(['stripe_transfers', 'paiements_escrow', 'partages_rib', 'notifications', 'email_queue',
    'conformite_travail', 'cotisations_sociales', 'bulletins_paie', 'contrats_travail_missions', 'contrats_mission',
    'rappels_contrat_travail', 'scans_pointage', 'presences', 'codes_secours_mission', 'qr_codes_mission',
    'messages_mission', 'conversations', 'swipes', 'matching_scores', 'candidatures']);
  const admin = {
    from(table: string) {
      let deleting = false, projection = '';
      const filters: Record<string, unknown> = {};
      const chain: any = {
        select(value: string) { projection = value; return chain; },
        eq(key: string, value: unknown) { filters[key] = value; return chain; },
        in(key: string, value: unknown) { filters[key] = value; return chain; },
        contains(key: string, value: unknown) { filters[key] = value; return chain; },
        limit(n: number) { expect(n).toBe(1); return chain; },
        delete() { calls.push(`delete-attempt:${table}`); expect(allowedDeletes.has(table)).toBe(true); deleting = true; return chain; },
        update() { calls.push(`update-attempt:${table}`); throw new Error('Update imprévu'); },
        maybeSingle: read,
        then(resolve: (value: unknown) => unknown, reject: (error: unknown) => unknown) { return read().then(resolve, reject); },
      };
      async function read() {
        if (deleting) {
          expect(calls).toContain('capture:original');
          expect(registry().lire(M).map(entry => entry.storagePath)).toEqual([originalPath]);
          calls.push(`delete:${table}`);
          if (table === 'contrats_mission') contractsPresent = false;
          return { data: null, error: null };
        }
        if (table === 'soignants') {
          expect(filters).toEqual({ id: S }); expect(projection).toBe('email, est_compte_test');
          calls.push('read:caregiver'); return { data: { ...profile }, error: null };
        }
        if (table === 'candidatures') {
          expect(filters).toEqual({ soignant_id: S }); expect(projection).toBe('mission_id');
          return { data: [], error: null };
        }
        if (table === 'missions' && Object.hasOwn(filters, 'soignant_assigne_id')) {
          expect(filters).toEqual({ soignant_assigne_id: S }); expect(projection).toBe('id');
          calls.push('read:assigned-missions'); return { data: assigned ? [{ id: M }] : [], error: null };
        }
        if (table === 'contrats_mission' && projection === 'mission_id') {
          expect(filters).toEqual({ soignant_id: S }); calls.push('read:contract-missions');
          return { data: contractsPresent ? [{ mission_id: M }] : [], error: null };
        }
        if (table === 'missions') {
          expect(filters).toEqual({ id: M }); calls.push('read:mission');
          if (projection === 'id' && options.readError) return { data: null, error: { code: 'READ_FAILED' } };
          return { data: present ? { id: M, intitule: options.nonTechnical ? 'Mission réelle' : '[pw-test:canvas] Contrat',
            etablissement_id: '55555555-5555-4555-8555-555555555555', soignant_assigne_id: S, statut: 'ASSIGNEE' } : null, error: null };
        }
        if (table === 'contrats_mission' && projection === 'id, mission_id, storage_path') {
          expect(filters).toEqual({ mission_id: M }); expect(calls).toContain('validate:test-scope');
          calls.push('capture:original');
          if (options.captureReadError) return { data: null, error: { code: 'CAPTURE_READ_FAILED' } };
          return { data: [{ id: C, mission_id: M, storage_path: options.badPath ? 'autre-contrat/original.html' : originalPath }], error: null };
        }
        if (table === 'contrats_mission') {
          expect(projection).toBe('id');
          const referenced = Object.hasOwn(filters, 'storage_path');
          expect(filters).toEqual(referenced ? { storage_path: [originalPath] } : { mission_id: M });
          calls.push(referenced ? 'read:references' : 'read:contracts');
          return { data: (referenced ? options.otherReference : contractsPresent) ? [{ id: C }] : [], error: null };
        }
        if (['paiements_escrow', 'conversations'].includes(table)) {
          expect(filters).toEqual({ mission_id: M }); return { data: [], error: null };
        }
        throw new Error(`Lecture inattendue ${table}`);
      }
      return chain;
    },
    storage: { from(bucket: string) {
      expect(bucket).toBe('contrats-signes');
      return { async remove(paths: string[]) {
        expect(paths).toEqual([originalPath]); expect(present).toBe(false); expect(contractsPresent).toBe(false);
        expect(calls).toContain('read:references'); calls.push('storage:remove-exact');
        const error = removeError ? { message: 'Indisponible fictif' } : null; removeError = false;
        return { data: error ? null : [{ name: path }], error };
      } };
    } },
  };
  Object.assign(admin, { auth: { admin: { async deleteUser() { calls.push('auth:delete'); throw new Error('Auth delete imprévu'); } } } });
  const exports: any = {};
  runInNewContext(compiled.outputText, { exports, Buffer, Date, console,
    require(name: string) {
      if (name === 'node:crypto') return { createHash };
      if (name === './auth') return { TEST_ACCOUNTS: {} };
      if (name === './db') return { adminClient: () => admin };
      if (name === './liberal-eligibility-policy') return {};
      if (name === './contrat-fixture-storage') return {
        memoriserOriginauxContratsFixture: (client: any, id: string) => cleanupStorage.memoriserOriginauxContratsFixture(client, id, registry()),
        supprimerOriginauxFixtureApresPurge: (client: any, id: string) => cleanupStorage.supprimerOriginauxFixtureApresPurge(client, id, registry()),
      };
      if (name === './cleanup-mission-test') return {
        estQuarantainePurgeAutorisee: () => true,
        estBlocagePurgeTechniqueAttendu: (error: any) => error.code === '23514',
        async preparerMissionTechniquePourPurge(client: unknown, mission: any) {
          expect(client).toBe(admin); expect(mission.id).toBe(M); calls.push('validate:test-scope'); assigned = false; return options.quarantine ? 'QUARANTAINEE' : 'PREPAREE';
        },
        async purgerMissionTechniqueAvecTimeout(client: unknown, id: string) {
          expect(client).toBe(admin); expect(id).toBe(M); calls.push('purge:rpc');
          if (options.quarantine) return { code: '23514', message: 'Créneaux PREVISIONNEL immutables après gel' };
          if (options.purgeError) return { code: 'NETWORK_UNKNOWN', message: 'Purge ambiguë fictive' };
          present = !!options.stillPresent; return null;
        },
      };
      throw new Error(`Import interdit: ${name}`);
    },
    fetch() { throw new Error('Réseau interdit'); },
  });
  return { calls, directory, registry, profile, run: () => exports.cleanupMissionCascade(M),
    runCaregiver: () => exports.cleanupEphemeralVerifiedCaregiver(fixture),
    resume: () => cleanupStorage.reprendreOriginauxContratsFixture(admin as any, 'https://abcdefghijklmnopqrst.supabase.co', registry()) };
}

describe('retrait borné des originaux de contrats TEST', () => {
  it.each([
    ['lecture des références', { captureReadError: true }, 'références des originaux indisponibles'],
    ['écriture durable du registre', { registryWriteError: true }, 'dossier refusé'],
  ] as const)('arrête le cleanup soignant après échec de %s, même au nouvel essai détaché', async (_name, options, message) => {
    const b = bancNettoyage(options);
    for (let attempt = 0; attempt < 2; attempt++) await expect(b.runCaregiver()).rejects.toThrow(message);
    expect(b.calls.filter(call => call === 'capture:original')).toHaveLength(2);
    expect(b.calls.filter(call => call === 'read:contract-missions')).toHaveLength(2);
    expect(b.calls.filter(call => /^(delete|update)-attempt:|^auth:|^storage:/.test(call))).toEqual([]);
    expect(b.calls).not.toContain('purge:rpc');
    expect(b.profile).toEqual({ email: fixture.email, est_compte_test: true, rpps_verifie: true });
  });
  it('capture l’original même non signé et le retire seulement après la purge confirmée', async () => {
    const b = bancNettoyage(); await b.run();
    expect(b.calls.indexOf('capture:original')).toBeLessThan(b.calls.indexOf('delete:contrats_mission'));
    expect(b.calls.indexOf('purge:rpc')).toBeLessThan(b.calls.indexOf('storage:remove-exact'));
    expect(b.calls.at(-1)).toBe('storage:remove-exact');
    await b.run(); expect(b.calls.filter(c => c === 'storage:remove-exact')).toHaveLength(1);
  });
  it.each([
    ['purge ambiguë', { purgeError: true }, 'Purge ambiguë'], ['mission persistante', { stillPresent: true }, 'purge non confirmée'],
    ['référence restante', { otherReference: true }, 'purge non confirmée'], ['chemin hors contrat', { badPath: true }, 'référence refusée'],
    ['mission non technique', { nonTechnical: true }, 'non technique'],
    ['lecture postpurge indisponible', { readError: true }, 'purge non confirmée'],
  ] as const)('conserve Storage en cas de %s', async (_name, options, message) => {
    const b = bancNettoyage(options); await expect(b.run()).rejects.toThrow(message);
    expect(b.calls).not.toContain('storage:remove-exact');
  });
  it('conserve le registre et Storage en quarantaine, y compris dans un nouveau lecteur', async () => {
    const b = bancNettoyage({ quarantine: true }); await b.run();
    expect(b.registry().lire(M)).toHaveLength(1);
    await b.resume(); expect(b.calls).not.toContain('storage:remove-exact');
    expect(b.registry().lire(M)).toHaveLength(1);
  });
  it('ne reprend pas un registre d’un autre projet et conserve le reçu immuable', async () => {
    const b = bancNettoyage({ storageError: true }); await expect(b.run()).rejects.toThrow('Storage non confirmé');
    const before = b.registry().lire(M);
    expect(cleanupStorage.registreOriginauxFixture('https://tsrqponmlkjihgfedcba.supabase.co', b.directory).lire()).toEqual([]);
    b.registry().enregistrer(M, C, before[0].storagePath);
    expect(b.registry().lire(M)).toEqual(before);
    expect(Object.keys(before[0]).sort()).toEqual(['contratId','missionId','projectRef','recordedAt','schema','sourceSha','storagePath']);
  });
  it('remonte l’échec Storage et garde le chemin exact pour un cleanup ultérieur', async () => {
    const b = bancNettoyage({ storageError: true }); await expect(b.run()).rejects.toThrow('Storage non confirmé');
    // Une nouvelle instance relit le disque, sans Map ni ancien worker.
    expect(b.registry().lire(M)).toHaveLength(1);
    await b.resume(); expect(b.calls.filter(c => c === 'storage:remove-exact')).toHaveLength(2);
    expect(b.registry().lire(M)).toEqual([]);
    expect(b.calls.filter(c => c === 'purge:rpc')).toHaveLength(1);
  });
});
