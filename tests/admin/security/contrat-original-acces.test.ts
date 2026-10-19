import { readFileSync } from 'node:fs';
import { webcrypto } from 'node:crypto';
import { Blob } from 'node:buffer';
import { runInNewContext } from 'node:vm';
import ts from 'typescript';
import { describe, expect, it } from 'vitest';

const source = ts.transpileModule(readFileSync('supabase/functions/generate-contrat-mission-pdf/index.ts', 'utf8'), {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022 },
}).outputText;
const cddSource = ts.transpileModule(readFileSync('supabase/functions/_shared/cdd-employeur.ts', 'utf8'), {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022 },
}).outputText;
const cddExports: Record<string, unknown> = {};
runInNewContext(cddSource, { exports: cddExports });
const donneesCddTest = {
  cadre: 'PRIVE_TERME_PRECIS', confirme: true, representant_nom: 'Représentant fictif', representant_qualite: 'Responsable TEST',
  motif_type: 'REMPLACEMENT', motif_precis: 'Remplacement synthétique du banc fermé', remplace_nom: 'Personne fictive',
  remplace_qualification: 'Qualification fictive', poste: 'Poste TEST', qualification: 'Qualification TEST', lieu_travail: 'Adresse fictive TEST',
  risques: 'NON', convention_collective: 'Convention fictive du banc, non applicable en production', renouvellement: 'Non prévu',
  essai: 'AUCUN', remuneration_accessoires: 'Salaire et accessoires fictifs du banc', temps_partiel: 'NON',
  retraite_nom: 'Organisme fictif TEST', retraite_adresse: 'Adresse fictive TEST', prevoyance: 'NON',
};
const id = '88900000-0000-4000-8000-000000000011';
const original = { storage_path: 'original/signe.html', hash_document: 'a'.repeat(64),
  contenu_html: '<article>Original signé</article>', contenu_html_rendu_le: '2026-09-20T00:00:00Z' };
function simulation(options: { contrat?: Record<string, unknown>; auth?: boolean; denied?: boolean; rpcError?: boolean;
  rpcData?: unknown; uploadError?: boolean; updateError?: boolean; urlError?: boolean; authorization?: string;
  soignant?: Record<string, unknown>; etablissement?: Record<string, unknown>; templateHtml?: string;
  donneesCdd?: unknown; permissionCdd?: boolean;
  afterUpload?: (s: any) => void; afterUrl?: (s: any) => void } = {}) {
  const state = { denied: options.denied || false, calls: [] as string[], urls: [] as string[], uploads: [] as { path: string; bytes: Blob; config: any }[],
    soignant: { nom: '<Synthetic>', prenom: 'Test', ...options.soignant } as Record<string, unknown>,
    etablissement: { nom: 'Simulation', ...options.etablissement } as Record<string, unknown>,
    templateHtml: options.templateHtml ?? '<article>Contrat {{numero_contrat}} — {{soignant_nom}}</article>',
    contrat: { id, mission_id: 'mission', etablissement_id: 'etab', soignant_id: 'soignant', numero_contrat: 'SYNTHETIQUE-1', type_contrat: 'CDD',
      statut: 'EN_ATTENTE_SIGNATURES', signature_soignant: false, signature_etablissement: false,
      signature_soignant_le: null, signature_etablissement_le: null, storage_path: null, hash_document: null,
      contenu_html: null, contenu_html_rendu_le: null, ...options.contrat } as Record<string, any> };
  const etablissementInitial = state.contrat.etablissement_id;
  let handler!: (r: Request) => Promise<Response>;
  const admin = { from(table: string) {
    state.calls.push(`read:${table}`); const conditions: [string, any][] = []; let patch: any;
    const query = {
      select() { return query; }, eq(k: string, v: any) { conditions.push([k, v]); return query; },
      is(k: string, v: any) { conditions.push([k, v]); return query; }, order() { return query; }, limit() { return query; },
      update(p: any) { state.calls.push('update'); patch = p; return query; },
      async single() { return query.maybeSingle(); },
      async maybeSingle() {
        if (patch) {
          if (options.updateError) return { error: { message: 'Synthetic database outage' }, data: null };
          if (!conditions.every(([k, v]) => (state.contrat[k] ?? null) === v)) return { data: null, error: null };
          Object.assign(state.contrat, patch); return { data: { ...state.contrat }, error: null };
        }
        const data = table === 'contrats_mission' ? { ...state.contrat }
          : table === 'templates_contrat' ? { contenu_html: state.templateHtml, nom: 'Test', version: 1 }
          : table === 'soignants' ? { ...state.soignant } : table === 'etablissements' ? { ...state.etablissement }
          : table === 'missions' ? { intitule: 'Simulation', debut_le: '2035-01-01', fin_le: '2035-01-02' } : null;
        if (!data) throw new Error(`Table inattendue ${table}`);
        return { data, error: null };
      },
    }; return query;
  }, storage: { from(bucket: string) {
    expect(bucket).toBe('contrats-signes'); return {
      async upload(path: string, bytes: Blob, config: any) {
        state.calls.push('upload'); state.uploads.push({ path, bytes, config }); options.afterUpload?.(state);
        return { error: options.uploadError ? { message: 'Synthetic Storage outage' } : null };
      },
      async createSignedUrl(path: string) {
        state.calls.push('url'); state.urls.push(path); options.afterUrl?.(state);
        return { data: options.urlError ? null : { signedUrl: 'https://example.invalid/signed-original' }, error: options.urlError ? {} : null };
      },
    };
  } } };
  const user = { auth: { async getUser() { state.calls.push('auth'); return { data: { user: options.auth === false ? null : { id: 'user' } }, error: null }; } },
    async rpc(name: string, params: any) {
      if (name === 'fn_a_permission_etablissement') {
        expect(params).toEqual({ p_permission: 'contrats', p_etablissement_id: etablissementInitial });
        state.calls.push('permission'); return { data: options.permissionCdd !== false, error: null };
      }
      expect(name).toBe('fn_contrat_storage_path'); expect(params).toEqual({ p_contrat_id: id }); state.calls.push('guard');
      return { error: options.rpcError ? {} : null, data: 'rpcData' in options ? options.rpcData : state.denied ? { success: false, error: 'Non autorisé' }
        : { success: true, storage_path: state.contrat.storage_path, hash_document: state.contrat.hash_document } };
    } };
  runInNewContext(source, { exports: {}, require(name: string) {
    if (name === 'npm:@supabase/supabase-js@2.99.2') return { createClient: (_url: string, key: string) => key === 'service' ? admin : user };
    if (name === '../_shared/cors.ts') return { corsHeaders: () => ({}) };
    if (name === '../_shared/cdd-employeur.ts') return cddExports;
    throw new Error(`Import inattendu ${name}`);
  }, Deno: { env: { get: (key: string) => ({ SUPABASE_URL: 'https://example.invalid', SUPABASE_SERVICE_ROLE_KEY: 'service', SUPABASE_ANON_KEY: 'anon' }[key]) },
    serve: (h: typeof handler) => { handler = h; } }, Date, Request, Response, Blob, TextEncoder, crypto: webcrypto,
    fetch: () => { throw new Error('Réseau interdit'); } });
  return { state, async lancer() {
    const response = await handler(new Request('https://example.invalid/generate-contrat-mission-pdf', {
      method: 'POST', headers: { Authorization: options.authorization || 'Bearer synthetic-user' }, body: JSON.stringify({
        contrat_id: id, donnees_cdd: 'donneesCdd' in options ? options.donneesCdd : donneesCddTest,
      }),
    })); return { status: response.status, body: await response.json() };
  } };
}
describe('Edge contrats : autorisation canonique et preuve originale', () => {
  it('ne prépare aucun CDD sans données confirmées ni permission employeur', async () => {
    for (const options of [{ donneesCdd: null }, { donneesCdd: { ...donneesCddTest, confirme: false } }, { permissionCdd: false }]) {
      const s = simulation(options);
      expect((await s.lancer()).status).toBe('permissionCdd' in options ? 403 : 422);
      expect(s.state.uploads).toEqual([]);
      expect(s.state.calls).not.toContain('update');
    }
  });
  it('fige le motif et le remplacé fournis sans ajouter un jour d’essai', async () => {
    const s = simulation();
    expect((await s.lancer()).status).toBe(200);
    const html = await s.state.uploads[0].bytes.text();
    expect(html).toContain('Remplacement synthétique du banc fermé');
    expect(html).toContain('Personne fictive');
    expect(html).toContain('Qualification fictive');
    expect(html).toContain('Aucune période d’essai n’est convenue.');
    expect(html).not.toContain('surcroît temporaire');
  });
  it('conserve un texte employeur échappé sans lui ajouter les clauses privées', async () => {
    const s = simulation({ donneesCdd: { cadre: 'TEXTE_EMPLOYEUR', confirme: true,
      representant_nom: 'Employeur fictif', representant_qualite: 'Recette',
      cadre_declare: 'Cadre synthétique', texte_employeur: 'Texte employeur fictif <script>interdit</script> Référence data:exemple et javascript:exemple' } });
    expect((await s.lancer()).status).toBe(200);
    const html = await s.state.uploads[0].bytes.text();
    expect(html).toContain('Texte employeur fictif &lt;script&gt;interdit&lt;/script&gt;');
    expect(html).toContain('data&#58;exemple et javascript&#58;exemple');
    expect(html).not.toContain('<script>');
    expect(html).not.toContain('Période d’essai');
    expect(html).not.toContain('Convention collective');
  });
  it.each(['soignant fermé', 'établissement suspendu', 'membre sans lecture_contrats', 'tenant tiers', 'profil admin fermé'])('refuse %s malgré Auth valide', async () => {
    const s = simulation({ denied: true, contrat: original }); expect(await s.lancer()).toMatchObject({ status: 403 });
    expect(s.state.calls).toEqual(['auth', 'guard']); expect(s.state.urls).toEqual([]);
  });
  it.each([null, {}, { success: 'true' }, { success: false }])('refuse la garde non concluante %j', async rpcData => {
    const s = simulation({ rpcData }); expect((await s.lancer()).status).toBe(403); expect(s.state.uploads).toEqual([]);
  });
  it('refuse l’erreur de garde avant lecture privilégiée', async () => {
    const s = simulation({ rpcError: true }); expect((await s.lancer()).status).toBe(403); expect(s.state.calls).toEqual(['auth', 'guard']);
  });
  it('n’accepte pas un fragment de clé service comme authentification', async () => {
    const s = simulation({ auth: false, authorization: 'Bearer prefix-service-suffix' });
    expect((await s.lancer()).status).toBe(401); expect(s.state.calls).toEqual(['auth']);
  });
  it.each([
    { statut: 'SIGNE_COMPLET' }, { statut: 'SIGNE_SOIGNANT' }, { signature_etablissement: true },
    { signature_soignant_le: '2026-09-01' }, {},
  ])('relit exactement l’original sans templates ni écriture : %j', async signature => {
    const s = simulation({ contrat: { ...original, ...signature } }); const before = { ...s.state.contrat };
    expect(await s.lancer()).toMatchObject({ status: 200, body: { success: true, ...{ storage_path: original.storage_path, hash_document: original.hash_document } } });
    expect(s.state.contrat).toEqual(before); expect(s.state.calls).toEqual(['auth', 'guard', 'read:contrats_mission', 'guard', 'url', 'guard']);
    expect(s.state.urls).toEqual([original.storage_path]); expect(s.state.uploads).toEqual([]);
  });
  it.each([{ statut: 'SIGNE_COMPLET' }, { signature_soignant: true }, { signature_etablissement_le: '2026-09-01' }, { hash_document: 'a'.repeat(64) }])('ne reconstruit pas une preuve absente/partielle : %j', async contrat => {
    const s = simulation({ contrat }); expect((await s.lancer()).status).toBe(409); expect(s.state.uploads).toEqual([]); expect(s.state.urls).toEqual([]);
  });
  it('prépare aussi le HTML initial prérempli par attribution, sans hash ni Storage', async () => {
    const s = simulation({ contrat: { contenu_html: '<p>Initial {{motif_cdd}}</p>' } });
    expect((await s.lancer()).status).toBe(200); expect(s.state.uploads).toHaveLength(1);
    expect(s.state.contrat.contenu_html).toContain('SYNTHETIQUE-1');
  });
  it('rend un nouveau contrat autorisé avec hash des octets, échappement et publication conditionnelle', async () => {
    const s = simulation(); expect((await s.lancer()).status).toBe(200); expect(s.state.uploads).toHaveLength(1);
    const upload = s.state.uploads[0]; expect(upload.config.upsert).toBe(false);
    const bytes = await upload.bytes.text(); expect(bytes).toContain('&lt;Synthetic&gt;');
    const hash = Buffer.from(await webcrypto.subtle.digest('SHA-256', new TextEncoder().encode(bytes))).toString('hex');
    expect(s.state.contrat.hash_document).toBe(hash); expect(s.state.contrat.contenu_html).toBe(bytes);
    expect(s.state.calls.slice(-7)).toEqual(['guard', 'permission', 'read:contrats_mission', 'update', 'guard', 'url', 'guard']);
    expect((await s.lancer()).status).toBe(200); expect(s.state.uploads).toHaveLength(1);
  });
  it('fige le SIRET libéral du soignant et préserve cet original après changement du profil et du modèle', async () => {
    const s = simulation({ contrat: { type_contrat: 'LIBERAL' },
      soignant: { siret_liberal: '11111111111111', siret: '99999999999999' },
      etablissement: { siret: '22222222222222' },
      templateHtml: '<article><p>Soignant : {{soignant_siret}}</p><p>Établissement : {{etablissement_siret}}</p></article>' });
    expect(await s.lancer()).toMatchObject({ status: 200, body: { success: true } });
    expect(s.state.uploads).toHaveLength(1);
    const bytes = await s.state.uploads[0].bytes.text();
    expect(bytes).toContain('<p>Soignant : 11111111111111</p>');
    expect(bytes).toContain('<p>Établissement : 22222222222222</p>');
    expect(bytes).not.toContain('99999999999999');
    expect(bytes).not.toContain('{{');
    expect(s.state.contrat.hash_document).toBe(Buffer.from(await webcrypto.subtle.digest('SHA-256', new TextEncoder().encode(bytes))).toString('hex'));
    expect(s.state.contrat.contenu_html).toBe(bytes);
    const frozen = { ...s.state.contrat };
    s.state.soignant.siret_liberal = '33333333333333';
    s.state.etablissement.siret = '44444444444444';
    s.state.templateHtml = '<article>Modèle modifié : {{soignant_siret}}</article>';
    s.state.calls.length = 0;
    expect(await s.lancer()).toMatchObject({ status: 200, body: { storage_path: frozen.storage_path, hash_document: frozen.hash_document } });
    expect(s.state.contrat).toEqual(frozen);
    expect(s.state.uploads).toHaveLength(1);
    expect(s.state.calls).toEqual(['auth', 'guard', 'read:contrats_mission', 'guard', 'url', 'guard']);
  });
  it.each([null, ''])('n’utilise pas une propriété siret non canonique si siret_liberal vaut %j', async siretLiberal => {
    const s = simulation({ contrat: { type_contrat: 'LIBERAL' },
      soignant: { siret_liberal: siretLiberal, siret: '99999999999999' },
      templateHtml: '<article><p>Soignant : {{soignant_siret}}</p></article>' });
    expect((await s.lancer()).status).toBe(200);
    expect(await s.state.uploads[0].bytes.text()).toContain('<p>Soignant : </p>');
    expect(s.state.contrat.contenu_html).not.toContain('99999999999999');
  });
  it('ne réécrit pas le SIRET manquant d’un original déjà signé avec le profil actuel', async () => {
    const historical = { ...original, contenu_html: '<article>Original signé — SIRET : </article>' };
    const s = simulation({ contrat: { ...historical, type_contrat: 'LIBERAL', statut: 'SIGNE_COMPLET', signature_soignant: true },
      soignant: { siret_liberal: '11111111111111' } });
    const before = { ...s.state.contrat };
    expect(await s.lancer()).toMatchObject({ status: 200, body: { hash_document: historical.hash_document } });
    expect(s.state.contrat).toEqual(before);
    expect(s.state.uploads).toEqual([]);
    expect(s.state.calls).not.toContain('read:soignants');
    expect(s.state.calls).not.toContain('read:templates_contrat');
  });
  it.each([{ signature_soignant: true, statut: 'SIGNE_SOIGNANT' }, { ...original }, { etablissement_id: 'autre-etab' }])('ne remplace pas une signature/rendu/affectation concurrente : %j', async concurrent => {
    const s = simulation({ afterUpload: st => Object.assign(st.contrat, concurrent) });
    expect((await s.lancer()).status).toBe(409); expect(s.state.contrat).toMatchObject(concurrent); expect(s.state.urls).toEqual([]);
    if (!('hash_document' in concurrent)) expect(s.state.contrat.hash_document).toBeNull();
  });
  it('une révocation pendant Storage interdit ensuite la publication', async () => {
    const s = simulation({ afterUpload: st => { st.denied = true; } }); expect((await s.lancer()).status).toBe(403);
    expect(s.state.calls).not.toContain('update'); expect(s.state.urls).toEqual([]);
  });
  it('une révocation pendant la signature URL interdit de livrer le lien', async () => {
    const s = simulation({ contrat: original, afterUrl: st => { st.denied = true; } }); const r = await s.lancer();
    expect(r.status).toBe(403); expect(r.body.signed_url).toBeUndefined();
  });
  it.each(['uploadError', 'updateError', 'urlError'] as const)('échoue fermé lors de %s', async error => {
    const s = simulation({ [error]: true }); const r = await s.lancer(); expect(r.status).toBe(503); expect(r.body.signed_url).toBeUndefined();
  });
  it('conserve l’appel système exact tout en préservant le signé', async () => {
    const s = simulation({ authorization: 'Bearer service', contrat: { ...original, statut: 'SIGNE_COMPLET' } });
    expect((await s.lancer()).status).toBe(200); expect(s.state.uploads).toEqual([]); expect(s.state.calls).not.toContain('auth');
  });
});
