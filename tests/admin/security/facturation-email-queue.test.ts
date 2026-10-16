import { readFileSync } from 'node:fs';
import { webcrypto } from 'node:crypto';
import { runInNewContext } from 'node:vm';
import ts from 'typescript';
import { describe, expect, it, vi } from 'vitest';
import { traiterEmailFacturation } from '../../../supabase/functions/_shared/facturation-email-queue';
import { resolveOperationalTestAccount, resolveOperationalTestSource } from '../../../supabase/functions/_shared/test-account';
import { resolveFacturationEmailSource } from '../../../supabase/functions/_shared/facturation-email-source';

const corps = { type: 'FACTURE_EMISE', destinataire_id: 'etab', data: { numero: 'F-1' } };
const cle = 'facture-emise-commission:facture:etab';
function client(statut = 'RESERVE') {
  const rpc = vi.fn().mockImplementation(async (nom: string) => nom === 'fn_reserver_email_facturation'
    ? { data: { statut, reservation: 'reservation-1', corps, idempotency_key: cle }, error: null }
    : { data: null, error: null });
  return { rpc };
}

describe('file durable des émissions de factures', () => {
  it('utilise le reçu serveur puis acquitte seulement après acceptation du transport', async () => {
    const sb = client();
    const envoyer = vi.fn().mockImplementation(async () => {
      expect(sb.rpc).toHaveBeenCalledTimes(1);
      return 'sent';
    });
    expect(await traiterEmailFacturation(sb, 'email-1', envoyer)).toBe('envoye');
    expect(envoyer).toHaveBeenCalledWith(corps, cle);
    expect(sb.rpc).toHaveBeenLastCalledWith('fn_acquitter_email_facturation', {
      p_email_id: 'email-1', p_reservation: 'reservation-1', p_resultat: 'ENVOYE', p_erreur: null,
    });
  });
  it.each(['ATTENDRE', 'ANNULE', 'ABSENT', 'ERREUR', 'DEJA_ENVOYE'])('n’expédie pas un reçu %s', async statut => {
    const envoyer = vi.fn();
    await traiterEmailFacturation(client(statut), 'email-1', envoyer);
    expect(envoyer).not.toHaveBeenCalled();
  });
  it.each(['pending', 'error'])('un résultat %s ne peut jamais marquer la facture envoyée', async resultat => {
    const sb = client();
    const envoyer = vi.fn().mockImplementation(async () => {
      if (resultat === 'error') throw new Error('503 fournisseur');
      return 'pending';
    });
    expect(await traiterEmailFacturation(sb, 'email-1', envoyer)).toBe('erreur');
    expect(sb.rpc.mock.calls[1][1]).toMatchObject({ p_resultat: 'ERREUR' });
    expect(sb.rpc.mock.calls[1][1].p_erreur).toBeTruthy();
  });
  it('conserve l’identité après perte de l’acquittement', async () => {
    const sb = client();
    sb.rpc.mockImplementationOnce(async () => ({ data: { statut: 'RESERVE', reservation: 'r1', corps, idempotency_key: cle }, error: null }));
    sb.rpc.mockImplementationOnce(async () => ({ data: null, error: { message: 'Stockage indisponible' } }));
    const envoyer = vi.fn().mockResolvedValue('sent');
    await expect(traiterEmailFacturation(sb, 'email-1', envoyer)).rejects.toThrow('Acquittement');
    expect(await traiterEmailFacturation(sb, 'email-1', envoyer)).toBe('envoye');
    expect(envoyer.mock.calls[0]).toEqual(envoyer.mock.calls[1]);
  });
  it('annule un transport écarté par les préférences sans le présenter comme livré', async () => {
    const sb = client();
    expect(await traiterEmailFacturation(sb, 'email-1', async () => 'skipped')).toBe('annule');
    expect(sb.rpc.mock.calls[1][1].p_resultat).toBe('ANNULE');
  });
});

// Exécute les vrais modèles HTML ; ni serveur ni fournisseur ne sont appelés.
const fichier = readFileSync('supabase/functions/send-email/index.ts', 'utf8');
const code = ts.transpileModule(fichier.slice(0, fichier.indexOf('Deno.serve(')) + '\nglobalThis.modeleFacture = renderTemplate;', {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022 },
}).outputText;
const contexte: any = { exports: {}, require: () => ({}), Deno: { env: { get: () => undefined } } };
runInNewContext(code, contexte);
describe('emails factures : accès et échéances', () => {
  it('pointe une facture d’honoraires vers la liste qui peut réellement l’ouvrir', () => {
    const rendu = contexte.modeleFacture('FACTURE_EMISE', {
      destinataire_role: 'ETABLISSEMENT', famille_document: 'HONORAIRES', facture_id: 'honoraires-1', numero: 'H-1',
      libelle_document: 'Facture d’honoraires', date_echeance: '18/11/2026', montant_ht: '100', montant_tva: '0', montant_ttc: '100',
    });
    expect(rendu.html).toContain('href="https://jolene.app/etablissement/facturation"');
    expect(rendu.html).not.toContain('/facturation/honoraires-1');
    expect(rendu.html).toContain('Échéance : 18/11/2026');
    expect(rendu.html).not.toContain('30 jours');
  });
  it('pointe la commission sur sa propre page et n’invente pas d’échéance absente', () => {
    const rendu = contexte.modeleFacture('FACTURE_EMISE', {
      famille_document: 'COMMISSION', facture_id: 'commission-1', numero: 'C-1',
    });
    expect(rendu.html).toContain('/etablissement/facturation/commission-1');
    expect(rendu.html).not.toContain('Échéance :');
    expect(rendu.html).not.toContain('payer');
  });
  it('garde l’heure limite d’origine dans une copie honoraires retardée', () => {
    const rendu = contexte.modeleFacture('FACTURE_EMISE', {
      destinataire_role: 'SOIGNANT', numero: 'H-1', verification_echeance: '18/10/2026 à 10:00',
    });
    expect(rendu.html).toContain('18/10/2026 à 10:00');
    expect(rendu.html).toContain('(heure de Paris)');
    expect(rendu.html).not.toContain('48</strong> heures');
  });
});

const sourceEtablissement = '69510000-0000-4000-8000-000000000001';
const sourceSoignant = '69510000-0000-4000-8000-000000000002';
const sourceMission = '69510000-0000-4000-8000-000000000003';
const sourceHonoraires = '69510000-0000-4000-8000-000000000004';
const sourceCommission = '69510000-0000-4000-8000-000000000005';
const autreSoignant = '69510000-0000-4000-8000-000000000006';
const autreMission = '69510000-0000-4000-8000-000000000007';
type SourceCanonique = {
  etablissementTest: boolean | null; soignantTest: boolean | null;
  missionAbsente?: boolean; honoraire?: boolean; groupee?: boolean; liee?: boolean;
  assigneChange?: boolean; autreSoignantTest?: boolean; groupeCount?: number; documentAmbigu?: boolean;
};
function simulationEnvoi(sourceCanonique?: SourceCanonique) {
  const etat = { legacyStatus: null as 'ERREUR' | 'EN_COURS' | null, testAccount: false, testSource: false, preferences: 0, envois: [] as any[], audits: [] as any[], lecturesSources: [] as string[] };
  let handler!: (req: Request) => Promise<Response>;
  const client = { rpc: async (nom: string, args: Record<string, unknown>) => {
    expect(nom).toBe('fn_reserver_envoi_email_idempotent');
    expect(args.p_idempotency_key).toBe('facture-emise-etablissement:69510000-0000-4000-8000-000000000201');
    expect(args.p_request_fingerprint).toMatch(/^[a-f0-9]{64}$/);
    if (!etat.legacyStatus) throw new Error('Aucune réservation idempotente attendue');
    // Le reçu historique porte un autre payload. Le vrai RPC refuse ce hash
    // quelle que soit l'issue antérieure ; aucune nouvelle clé n'est fabriquée.
    return { data: { statut: 'CONFLIT' }, error: null };
  }, from: (table: string) => {
    let id: unknown; let filtre: string;
    const resultat = () => {
      if (!sourceCanonique) return { data: table === 'etablissements' ? { email_contact: 'facture@example.invalid' } : null, error: null };
      etat.lecturesSources.push(table + ':' + filtre + ':' + String(id));
      if (table === 'factures') return { data: id === sourceCommission && (!sourceCanonique.honoraire || sourceCanonique.documentAmbigu)
        ? { id, etablissement_id: sourceEtablissement, mission_id: sourceCanonique.groupee ? null : sourceMission,
          facture_honoraire_id: sourceCanonique.liee ? sourceHonoraires : null, nombre_missions: sourceCanonique.groupee ? 2 : 1 } : null, error: null };
      if (table === 'factures_honoraires') return { data: (id === sourceHonoraires && (sourceCanonique.honoraire || sourceCanonique.liee)) || (id === sourceCommission && sourceCanonique.documentAmbigu)
        ? { id, etablissement_id: sourceEtablissement, soignant_id: sourceSoignant, mission_id: sourceMission } : null, error: null };
      if (table === 'missions' && filtre === 'facture_id') {
        expect(id).toBe(sourceCommission);
        const data = sourceCanonique.groupee ? [
          { id: sourceMission, etablissement_id: sourceEtablissement, soignant_assigne_id: sourceSoignant },
          { id: autreMission, etablissement_id: sourceEtablissement, soignant_assigne_id: autreSoignant },
        ] : [];
        return { data, error: null, count: sourceCanonique.groupeCount ?? data.length };
      }
      if (table === 'missions') {
        expect([sourceMission, autreMission]).toContain(id);
        return { data: sourceCanonique.missionAbsente ? null : { etablissement_id: sourceEtablissement,
          soignant_assigne_id: sourceCanonique.assigneChange || id === autreMission ? autreSoignant : sourceSoignant }, error: null };
      }
      if (table === 'soignants') return { data: id === sourceSoignant ? { est_compte_test: sourceCanonique.soignantTest }
        : id === autreSoignant ? { est_compte_test: sourceCanonique.autreSoignantTest ?? false } : null, error: null };
      if (table === 'etablissements') return { data: id === sourceEtablissement ? { est_compte_test: sourceCanonique.etablissementTest, email_contact: 'facture@example.invalid' } : null, error: null };
      throw new Error('Lecture source inattendue : ' + table);
    };
    const query = {
      select: () => query, eq: (colonne: string, valeur: unknown) => {
        if (sourceCanonique) { expect(['id', 'facture_id']).toContain(colonne); filtre = colonne; id = valeur; }
        return query;
      },
      limit: (n: number) => { expect(n).toBe(1000); return query; },
      maybeSingle: async () => resultat(),
      then: (resolve: (value: unknown) => unknown, reject: (cause: unknown) => unknown) => Promise.resolve().then(resultat).then(resolve, reject),
      insert: async (data: unknown) => { etat.audits.push({ table, data }); return { error: null }; },
    };
    if (!['soignants', 'etablissements', 'journaux_audit', 'emails_envoyes', ...(sourceCanonique ? ['missions', 'factures', 'factures_honoraires'] : [])].includes(table)) throw new Error(`Table inattendue ${table}`);
    return query;
  } };
  const modules: Record<string, unknown> = {
    'npm:@supabase/supabase-js@2.99.2': { createClient: () => client },
    '../_shared/preferences-alertes-email.ts': { verifierPreferencesEvenementsEmail: async () => { etat.preferences++; return false; } },
    '../_shared/rate-limit.ts': { applyRateLimit: () => false, getClientIp: () => '127.0.0.1' },
    '../_shared/admin-auth.ts': { verifyAdminOrServiceRole: async () => ({ ok: true }) },
    '../_shared/facturation-email-source.ts': { resolveFacturationEmailSource: sourceCanonique ? resolveFacturationEmailSource : async () => ({ ok: true, isTest: etat.testSource }) },
    '../_shared/test-account.ts': sourceCanonique ? { resolveOperationalTestAccount, resolveOperationalTestSource } : {
      resolveOperationalTestAccount: async () => ({ ok: true, isTest: etat.testAccount }),
      resolveOperationalTestSource: async () => ({ ok: true, isTest: etat.testSource }),
    },
  };
  const env: Record<string, string> = { SUPABASE_SERVICE_ROLE_KEY: 'simulation-service', SUPABASE_URL: 'https://example.invalid', RESEND_API_KEY: 'simulation-provider' };
  const code = ts.transpileModule(fichier, { compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022 } }).outputText;
  runInNewContext(code, { exports: {}, Request, Response, TextEncoder, crypto: webcrypto,
    console: { log() {}, warn() {}, error() {} },
    require: (nom: string) => { if (!(nom in modules)) throw new Error(`Import imprévu ${nom}`); return modules[nom]; },
    Deno: { env: { get: (nom: string) => env[nom] }, serve: (h: typeof handler) => { handler = h; } },
    fetch: async (url: string, options: RequestInit) => {
      expect(url).toBe('https://api.resend.com/emails'); expect(options.method).toBe('POST');
      etat.envois.push(JSON.parse(options.body as string));
      return Response.json({ id: 'envoi-simule' });
    },
  });
  return { etat, lancer: (type: string, idempotencyKey?: string, sourceData?: Record<string, unknown>) => handler(new Request('https://example.invalid/send-email', {
    method: 'POST', headers: { Authorization: 'Bearer simulation-service', 'Content-Type': 'application/json' },
    body: JSON.stringify({ type, ...(idempotencyKey ? { idempotency_key: idempotencyKey } : {}), destinataire_id: '69510000-0000-4000-8000-000000000001',
      data: { numero: 'C-1', destinataire_role: 'ETABLISSEMENT', famille_document: 'COMMISSION', facture_id: 'commission-1', ...sourceData } }),
  })) };
}

describe('vrai transport email : copie documentaire obligatoire, fournisseur simulé', () => {
  it('envoie FACTURE_EMISE malgré les préférences email désactivées', async () => {
    const s = simulationEnvoi(); const response = await s.lancer('FACTURE_EMISE');
    expect(response.status).toBe(200); expect(await response.json()).toEqual({ success: true });
    expect(s.etat.preferences).toBe(0); expect(s.etat.envois).toHaveLength(1);
    expect(s.etat.envois[0].to).toEqual(['facture@example.invalid']);
  });
  it.each(['RAPPEL_FACTURE', 'AVOIR_EMIS'])('%s conserve le traitement de préférence existant', async type => {
    const s = simulationEnvoi(); const response = await s.lancer(type);
    expect(await response.json()).toMatchObject({ success: true, skipped: true, reason: 'preference_user_off' });
    expect(s.etat.preferences).toBe(1); expect(s.etat.envois).toHaveLength(0);
  });
  it.each(['testAccount', 'testSource'] as const)('la copie obligatoire ne contourne pas la garde %s', async garde => {
    const s = simulationEnvoi(); s.etat[garde] = true; const response = await s.lancer('FACTURE_EMISE');
    expect(await response.json()).toMatchObject({ success: true, skipped: true });
    expect(s.etat.envois).toHaveLength(0);
  });
});


describe('déploiement mixte : ancien résultat indéterminé et payload différent', () => {
  it.each(['ERREUR', 'EN_COURS'] as const)('un ancien %s reste à rapprocher sans appel fournisseur ni nouvelle clé', async statut => {
    const s = simulationEnvoi(); s.etat.legacyStatus = statut;
    const response = await s.lancer('FACTURE_EMISE', 'facture-emise-etablissement:69510000-0000-4000-8000-000000000201');
    expect(response.status).toBe(409);
    expect(await response.json()).toEqual({ error: 'idempotency_key déjà utilisée pour une autre requête' });
    expect(s.etat.envois).toEqual([]);
  });
  it('le worker conserve le conflit dans la file en erreur et ne lance pas de second transport', async () => {
    const sb = client();
    const envoyer = vi.fn().mockRejectedValue(new Error('409 idempotency_key déjà utilisée pour une autre requête'));
    expect(await traiterEmailFacturation(sb, 'email-1', envoyer)).toBe('erreur');
    expect(envoyer).toHaveBeenCalledTimes(1);
    expect(envoyer).toHaveBeenCalledWith(corps, cle);
    expect(sb.rpc).toHaveBeenLastCalledWith('fn_acquitter_email_facturation', {
      p_email_id: 'email-1', p_reservation: 'reservation-1', p_resultat: 'ERREUR',
      p_erreur: '409 idempotency_key déjà utilisée pour une autre requête',
    });
  });
});


describe('FACTURE_EMISE : vrai handler et classification documentaire canonique', () => {
  it('bloque E réel / S TEST même si les champs source du payload prétendent être réels', async () => {
    const s = simulationEnvoi({ etablissementTest: false, soignantTest: true });
    const response = await s.lancer('FACTURE_EMISE', undefined, {
      facture_id: sourceCommission, etablissement_id: sourceEtablissement, soignant_id: autreSoignant,
    });
    expect(response.status).toBe(200);
    expect(await response.json()).toMatchObject({ success: true, skipped: true, reason: 'test_source' });
    expect(s.etat.lecturesSources).toContain('missions:id:' + sourceMission);
    expect(s.etat.lecturesSources).toContain('soignants:id:' + sourceSoignant);
    expect(s.etat.envois).toHaveLength(0);
  });
  it('bloque E TEST / S réel avant tout fournisseur', async () => {
    const s = simulationEnvoi({ etablissementTest: true, soignantTest: false });
    const response = await s.lancer('FACTURE_EMISE', undefined, { facture_id: sourceCommission });
    expect(response.status).toBe(200);
    expect(await response.json()).toMatchObject({ success: true, skipped: true, reason: 'test_account' });
    expect(s.etat.envois).toHaveLength(0);
  });
  it.each([false, true])('conserve une ancienne copie réelle sans contexte/famille, honoraires=%s', async honoraire => {
    const s = simulationEnvoi({ etablissementTest: false, soignantTest: false, honoraire });
    const response = await s.lancer('FACTURE_EMISE', undefined, {
      facture_id: honoraire ? sourceHonoraires : sourceCommission, famille_document: undefined,
    });
    expect(response.status).toBe(200); expect(await response.json()).toEqual({ success: true });
    expect(s.etat.lecturesSources.some(r => r.startsWith('factures:id:'))).toBe(true);
    expect(s.etat.lecturesSources.some(r => r.startsWith('factures_honoraires:id:'))).toBe(true);
    expect(s.etat.envois).toHaveLength(1); expect(s.etat.preferences).toBe(0);
  });
  it.each([false, true])('classe tous les acteurs de la facture groupée, un soignant TEST=%s', async autreSoignantTest => {
    const s = simulationEnvoi({ etablissementTest: false, soignantTest: false, groupee: true, autreSoignantTest });
    const response = await s.lancer('FACTURE_EMISE', undefined, { facture_id: sourceCommission });
    expect(response.status).toBe(200);
    expect(await response.json()).toEqual(autreSoignantTest ? { success: true, skipped: true, reason: 'test_source' } : { success: true });
    expect(s.etat.lecturesSources).toContain('missions:facture_id:' + sourceCommission);
    expect(s.etat.lecturesSources).toContain('soignants:id:' + autreSoignant);
    expect(s.etat.envois).toHaveLength(autreSoignantTest ? 0 : 1);
  });
  it('conserve le soignant TEST de la FH liée quand la mission est désormais assignée à un réel', async () => {
    const s = simulationEnvoi({ etablissementTest: false, soignantTest: true, liee: true, assigneChange: true });
    const response = await s.lancer('FACTURE_EMISE', undefined, { facture_id: sourceCommission });
    expect(await response.json()).toMatchObject({ success: true, skipped: true, reason: 'test_source' });
    expect(s.etat.lecturesSources).toContain('factures_honoraires:id:' + sourceHonoraires);
    expect(s.etat.envois).toHaveLength(0);
  });
  it.each([
    { missionAbsente: true },
    { soignantTest: null },
    { groupee: true, groupeCount: 3 },
    { documentAmbigu: true },
  ])('une source inconnue/partielle/ambiguë reste une erreur reprenable sans fournisseur', async scenario => {
    const s = simulationEnvoi({ etablissementTest: false, soignantTest: false, ...scenario });
    const response = await s.lancer('FACTURE_EMISE', undefined, {
      facture_id: sourceCommission, ...(scenario.documentAmbigu ? { famille_document: undefined } : {}),
    });
    expect(response.status).toBe(503);
    expect(await response.json()).toEqual({ error: 'Classification de la source indisponible' });
    expect(s.etat.envois).toHaveLength(0);
  });
});
