import { readFileSync } from 'node:fs';
import { webcrypto } from 'node:crypto';
import { runInNewContext } from 'node:vm';
import ts from 'typescript';
import { describe, expect, it, vi } from 'vitest';
import { traiterEmailFacturation } from '../../../supabase/functions/_shared/facturation-email-queue';

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

function simulationEnvoi() {
  const etat = { legacyStatus: null as 'ERREUR' | 'EN_COURS' | null, testAccount: false, testSource: false, preferences: 0, envois: [] as any[], audits: [] as any[] };
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
    const query = {
      select: () => query, eq: () => query,
      maybeSingle: async () => ({ data: table === 'etablissements' ? { email_contact: 'facture@example.invalid' } : null, error: null }),
      insert: async (data: unknown) => { etat.audits.push({ table, data }); return { error: null }; },
    };
    if (!['soignants', 'etablissements', 'journaux_audit', 'emails_envoyes'].includes(table)) throw new Error(`Table inattendue ${table}`);
    return query;
  } };
  const modules: Record<string, unknown> = {
    'npm:@supabase/supabase-js@2.99.2': { createClient: () => client },
    '../_shared/preferences-alertes-email.ts': { verifierPreferencesEvenementsEmail: async () => { etat.preferences++; return false; } },
    '../_shared/rate-limit.ts': { applyRateLimit: () => false, getClientIp: () => '127.0.0.1' },
    '../_shared/admin-auth.ts': { verifyAdminOrServiceRole: async () => ({ ok: true }) },
    '../_shared/test-account.ts': {
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
  return { etat, lancer: (type: string, idempotencyKey?: string) => handler(new Request('https://example.invalid/send-email', {
    method: 'POST', headers: { Authorization: 'Bearer simulation-service', 'Content-Type': 'application/json' },
    body: JSON.stringify({ type, ...(idempotencyKey ? { idempotency_key: idempotencyKey } : {}), destinataire_id: '69510000-0000-4000-8000-000000000001',
      data: { numero: 'C-1', destinataire_role: 'ETABLISSEMENT', famille_document: 'COMMISSION', facture_id: 'commission-1' } }),
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
