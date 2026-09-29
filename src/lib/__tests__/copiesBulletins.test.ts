import { createHash, webcrypto } from 'node:crypto';
import { Blob as NodeBlob } from 'node:buffer';
import { FunctionsFetchError, FunctionsHttpError, FunctionsRelayError } from '@supabase/supabase-js';
import { StorageApiError, StorageClient } from '@supabase/storage-js';
import { PostgrestClient } from '@supabase/postgrest-js';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { chargerMissionsCopies, copieBulletinTelechargeable, CopieRetireeErreur, idempotenceCopie, nouvelleIdempotenceCopie, ouvrirCopieBulletin, publierCopieBulletin, validerListeCopiesBulletins, type CopieBulletin, type DepotCopieBulletin } from '../copiesBulletins';

const banc = vi.hoisted(() => ({ rpc: vi.fn(), from: vi.fn(), storage: vi.fn(), invoke: vi.fn(), native: vi.fn(() => false), partager: vi.fn() }));
vi.mock('@/integrations/supabase/client', () => ({ supabase: { rpc: banc.rpc, from: banc.from, storage: { from: banc.storage }, functions: { invoke: banc.invoke } } }));
vi.mock('@/lib/platform', () => ({ isNative: banc.native }));
vi.mock('@/lib/copiesBulletinsPartageNatif', () => ({ partagerPdfCopieNatif: banc.partager }));
const copie: CopieBulletin = {
  id: '10000000-0000-4000-8000-000000000001', etablissement_id: '10000000-0000-4000-8000-000000000002',
  soignant_id: '10000000-0000-4000-8000-000000000003', etablissement_nom: 'Employeur de test',
  soignant_nom: 'Test', soignant_prenom: 'Salarié', periode_debut: '2026-09-01', periode_fin: '2026-09-30',
  statut: 'PUBLIEE', publie_le: '2026-09-29T12:00:00Z', remplace_id: null, version: 1,
  motif_remplacement: null, mission_ids: ['10000000-0000-4000-8000-000000000004'], taille_octets: 256,
  sha256: 'a'.repeat(64), signalee: false,
};

describe('copies officielles : lecture bornée et réponses vérifiables', () => {
  it('conserve les anciennes versions consultables, refuse le PDF retiré', () => {
    expect(copieBulletinTelechargeable(copie)).toBe(true);
    expect(copieBulletinTelechargeable({ statut: 'REMPLACEE' })).toBe(true);
    expect(copieBulletinTelechargeable({ statut: 'RETIREE' })).toBe(false);
  });
  it('accepte une liste vide et un document complet sans fabriquer de données', () => {
    expect(validerListeCopiesBulletins([])).toEqual([]);
    expect(validerListeCopiesBulletins([copie])).toEqual([copie]);
  });
  it.each([
    null, {}, [null], [{ ...copie, statut: 'PAYE' }], [{ ...copie, mission_ids: [] }],
    [{ ...copie, mission_ids: ['autre'] }], [{ ...copie, version: 0 }],
    [{ ...copie, taille_octets: '256' }], [{ ...copie, taille_octets: 10485761 }],
    [{ ...copie, sha256: 'non-verifiable' }], [{ ...copie, periode_debut: 'date inconnue' }],
    [{ ...copie, publie_le: null }], [{ ...copie, periode_fin: '2026-08-01' }],
  ])('une réponse invalide entraîne une erreur explicite (%j)', reponse => {
    expect(() => validerListeCopiesBulletins(reponse)).toThrow('ne peut pas être vérifiée');
  });
});

describe('copies officielles : téléchargement vers le partage natif', () => {
  const bytes = Buffer.from('%PDF-original-de-test');
  const document = { ...copie, sha256: createHash('sha256').update(bytes).digest('hex'), taille_octets: bytes.length };
  beforeEach(() => {
    vi.stubGlobal('crypto', webcrypto); vi.stubGlobal('Blob', NodeBlob);
    banc.native.mockReturnValue(true); banc.partager.mockReset().mockResolvedValue(undefined);
    banc.invoke.mockReset().mockResolvedValue({ data: new NodeBlob([bytes], { type: 'application/pdf' }), error: null });
  });
  afterEach(() => { banc.native.mockReturnValue(false); vi.unstubAllGlobals(); });

  it('transmet les octets originaux contrôlés au cycle de conservation natif', async () => {
    await ouvrirCopieBulletin(document);
    expect(banc.partager).toHaveBeenCalledExactlyOnceWith(bytes.toString('base64'));
    expect(banc.invoke).toHaveBeenCalledWith('copies-bulletins', { body: { action: 'telecharger', copie_id: copie.id } });
  });
  it('ne prépare aucun fichier local si l’intégrité n’est pas confirmée', async () => {
    await expect(ouvrirCopieBulletin({ ...document, sha256: 'a'.repeat(64) })).rejects.toThrow('L’intégrité du PDF ne peut pas être confirmée');
    expect(banc.partager).not.toHaveBeenCalled();
  });
  it('conserve le traitement silencieux de l’annulation du sélecteur', async () => {
    banc.partager.mockRejectedValue(new Error('Share canceled'));
    await expect(ouvrirCopieBulletin(document)).resolves.toBeUndefined();
  });
});

describe('copies officielles : destinataires et missions paginés', () => {
  const profilsPremierePage = Array.from({ length: 200 }, (_, i) => ({
    id: `00000000-0000-4000-8000-${String(i).padStart(12, '0')}`, nom: 'Autre', prenom: `Salarié ${i}`,
  }));
  const profilCible = { id: copie.soignant_id, nom: copie.soignant_nom, prenom: copie.soignant_prenom };
  const missionCible = { id: copie.mission_ids[0], intitule: 'Mission cible', debut_le: '2026-09-15T08:00:00Z', fin_le: '2026-09-15T16:00:00Z', soignant_assigne_id: copie.soignant_id };
  const missions = [...profilsPremierePage.map(p => ({ ...missionCible, id: p.id, soignant_assigne_id: p.id })), missionCible];
  function installer(mode: 'complet' | 'indisponible' | 'invalide' | 'destinataire absent' = 'complet') {
    const appels: URL[] = [];
    const requete = vi.fn<typeof fetch>().mockImplementation(async input => {
      const url = new URL(String(input)); appels.push(url);
      expect(url.searchParams.get('order')).toBe('id.asc');
      expect(url.searchParams.get('limit')).toBe('200');
      const offset = Number(url.searchParams.get('offset'));
      let data: unknown;
      if (url.pathname.endsWith('/rpc/fn_mes_soignants_etablissement')) {
        if (offset === 200 && mode === 'indisponible') return new Response(JSON.stringify({ message: 'Service indisponible' }), { status: 503 });
        data = offset === 0 ? profilsPremierePage : mode === 'invalide' ? {} : mode === 'destinataire absent' ? [] : [profilCible];
      } else {
        expect(url.pathname).toBe('/rest/v1/missions');
        expect(url.searchParams.get('etablissement_id')).toBe(`eq.${copie.etablissement_id}`);
        expect(url.searchParams.get('type_contrat_applique')).toBe('eq.SALARIE');
        data = missions.slice(offset, offset + 200);
      }
      return new Response(JSON.stringify(data), { status: 200, headers: { 'Content-Type': 'application/json' } });
    });
    const client = new PostgrestClient('https://recette.invalid/rest/v1', { fetch: requete });
    banc.rpc.mockImplementation(() => client.rpc('fn_mes_soignants_etablissement'));
    banc.from.mockImplementation(() => client.from('missions'));
    return appels;
  }
  beforeEach(() => { banc.rpc.mockReset(); banc.from.mockReset(); });

  it('retrouve exactement le salarié et sa mission sur la deuxième page, avec un ordre stable', async () => {
    const appels = installer();
    const resultat = await chargerMissionsCopies(copie.etablissement_id, copie.periode_debut, copie.periode_fin);
    expect(resultat).toHaveLength(201);
    expect(resultat[200]).toEqual({ id: missionCible.id, intitule: missionCible.intitule, debut_le: missionCible.debut_le,
      fin_le: missionCible.fin_le, soignant_id: profilCible.id, soignant_nom: profilCible.nom, soignant_prenom: profilCible.prenom });
    expect(appels.map(u => [u.pathname.split('/').pop(), u.searchParams.get('offset')])).toEqual([
      ['fn_mes_soignants_etablissement', '0'], ['fn_mes_soignants_etablissement', '200'], ['missions', '0'], ['missions', '200'],
    ]);
  });

  it.each(['indisponible', 'invalide'] as const)('ne conserve pas une liste partielle si la deuxième page est %s', async mode => {
    const appels = installer(mode);
    await expect(chargerMissionsCopies(copie.etablissement_id, copie.periode_debut, copie.periode_fin)).rejects.toThrow('Les destinataires ne peuvent pas être vérifiés. Réessayez.');
    expect(appels.map(u => u.searchParams.get('offset'))).toEqual(['0', '200']);
    expect(banc.from).not.toHaveBeenCalled();
  });

  it('refuse encore une mission dont le destinataire exact reste absent après toutes les pages', async () => {
    installer('destinataire absent');
    await expect(chargerMissionsCopies(copie.etablissement_id, copie.periode_debut, copie.periode_fin)).rejects.toThrow('Le destinataire d’une mission ne peut pas être vérifié. Réessayez.');
  });
});

describe('copies officielles : refus du PDF distinct d’une publication incertaine', () => {
  const depot: DepotCopieBulletin = { etablissementId: copie.etablissement_id, soignantId: copie.soignant_id,
    periodeDebut: copie.periode_debut, periodeFin: copie.periode_fin, missionIds: copie.mission_ids,
    remplaceId: null, motifRemplacement: null };
  const file = new File(['%PDF-test'], 'copie.pdf', { type: 'application/pdf' });
  const reservation = Object.freeze({ id: copie.id, statut: 'RESERVEE', bucket: 'copies-bulletins-paie', storage_path: `${copie.id}/original.pdf` });
  const messageReprise = 'La publication n’a pas été confirmée. Le serveur doit vérifier le PDF et vos droits. Réessayez avec ce même fichier ; aucun second dépôt ne sera créé.';
  const messageRefus = 'Le PDF a été refusé : il est illisible, invalide ou protégé. Choisissez « Modifier le dépôt », puis sélectionnez un PDF lisible et non protégé.';
  const erreurHttp = (body: unknown, status = 422) => new FunctionsHttpError(new Response(JSON.stringify(body), { status }));
  const upload = vi.fn();
  beforeEach(() => {
    sessionStorage.clear(); vi.stubGlobal('crypto', webcrypto);
    banc.rpc.mockReset().mockResolvedValue({ data: reservation, error: null });
    banc.storage.mockReset().mockReturnValue({ upload });
    upload.mockReset().mockResolvedValue({ error: null }); banc.invoke.mockReset();
  });
  afterEach(() => { vi.restoreAllMocks(); vi.useRealTimers(); vi.unstubAllGlobals(); });

  it('indique le changement de fichier pour le refus 422 exact, sans renouveler l’intention ni consommer la réponse', async () => {
    const id = await idempotenceCopie('employeur', depot, copie.sha256);
    const error = erreurHttp({ error: 'COPIE_PDF_INVALIDE', message: 'Détail interne à ne pas afficher' });
    banc.invoke.mockResolvedValue({ data: null, error });
    await expect(publierCopieBulletin(depot, file, copie.sha256, id, vi.fn())).rejects.toThrow(messageRefus);
    expect(error.context.bodyUsed).toBe(false);
    expect(await idempotenceCopie('employeur', depot, copie.sha256)).toBe(id);
    expect(banc.rpc).toHaveBeenCalledTimes(1);
    expect(banc.rpc).toHaveBeenCalledWith('fn_reserver_copie_bulletin', expect.objectContaining({ p_idempotence: id, p_sha256_attendu: copie.sha256 }));
    expect(upload).toHaveBeenCalledTimes(1);
    expect(upload).toHaveBeenCalledWith(reservation.storage_path, expect.any(Blob), { contentType: 'application/pdf', upsert: false });
    expect(banc.invoke).toHaveBeenCalledTimes(1);
    expect(banc.invoke).toHaveBeenCalledWith('copies-bulletins', { body: { action: 'finaliser', copie_id: copie.id, destinataire_confirme: true } });

    // An explicit same-file retry still uses the immutable reservation/upload.
    upload.mockResolvedValue({ error: new StorageApiError('The resource already exists', 409, '409') });
    await expect(publierCopieBulletin(depot, file, copie.sha256, id, vi.fn())).rejects.toThrow(messageRefus);
    expect(await idempotenceCopie('employeur', depot, copie.sha256)).toBe(id);
    expect(error.context.bodyUsed).toBe(false);
    expect(reservation.statut).toBe('RESERVEE');
  });

  it.each([
    ['code inconnu', () => erreurHttp({ error: 'COPIE_ACCES_REFUSE', message: 'COPIE_PDF_INVALIDE' })],
    ['autre statut HTTP', () => erreurHttp({ error: 'COPIE_PDF_INVALIDE' }, 503)],
    ['code avec suffixe', () => erreurHttp({ error: 'COPIE_PDF_INVALIDE: détail serveur' })],
    ['JSON null', () => erreurHttp(null)],
    ['JSON tableau', () => erreurHttp([{ error: 'COPIE_PDF_INVALIDE' }])],
    ['JSON illisible', () => new FunctionsHttpError(new Response('COPIE_PDF_INVALIDE', { status: 422 }))],
    ['contexte absent', () => new FunctionsHttpError(undefined)],
    ['contexte non Response', () => new FunctionsHttpError({ status: 422, body: { error: 'COPIE_PDF_INVALIDE' } })],
    ['transport réseau', () => new FunctionsFetchError(new Error('COPIE_PDF_INVALIDE'))],
    ['relais', () => new FunctionsRelayError(new Response(JSON.stringify({ error: 'COPIE_PDF_INVALIDE' }), { status: 422 }))],
    ['message brut', () => new Error('COPIE_PDF_INVALIDE')],
  ])('garde le message de reprise pour %s', async (_nom, creerErreur) => {
    const id = await idempotenceCopie('employeur', depot, copie.sha256);
    banc.invoke.mockResolvedValue({ data: null, error: creerErreur() });
    await expect(publierCopieBulletin(depot, file, copie.sha256, id, vi.fn())).rejects.toThrow(messageReprise);
    expect(await idempotenceCopie('employeur', depot, copie.sha256)).toBe(id);
    expect(banc.rpc).toHaveBeenCalledTimes(1); expect(banc.invoke).toHaveBeenCalledTimes(1);
  });

  it('conserve le message de reprise si le corps a déjà été consommé', async () => {
    const error = erreurHttp({ error: 'COPIE_PDF_INVALIDE' });
    await error.context.json();
    banc.invoke.mockResolvedValue({ data: null, error });
    await expect(publierCopieBulletin(depot, file, copie.sha256, copie.id, vi.fn())).rejects.toThrow(messageReprise);
  });

  it('borne la lecture du corps à une seconde et conserve la reprise si elle reste suspendue', async () => {
    vi.useFakeTimers();
    const error = erreurHttp({ error: 'COPIE_PDF_INVALIDE' });
    const clone = error.context.clone();
    vi.spyOn(error.context, 'clone').mockReturnValue(clone);
    vi.spyOn(clone, 'json').mockReturnValue(new Promise(() => {}));
    banc.invoke.mockResolvedValue({ data: null, error });
    const resultat = publierCopieBulletin(depot, file, copie.sha256, copie.id, vi.fn()).catch(e => e);
    await vi.advanceTimersByTimeAsync(1_000);
    expect(await resultat).toMatchObject({ message: messageReprise });
    expect(error.context.bodyUsed).toBe(false);
    expect(vi.getTimerCount()).toBe(0);
  });

  it('ne traite pas un code non confirmé par une erreur HTTP comme un refus PDF', async () => {
    banc.invoke.mockResolvedValue({ data: { error: 'COPIE_PDF_INVALIDE' }, error: null });
    await expect(publierCopieBulletin(depot, file, copie.sha256, copie.id, vi.fn())).rejects.toThrow(messageReprise);
  });
});

describe('copies officielles : doublons transformés par le vrai SDK Storage', () => {
  const depot: DepotCopieBulletin = { etablissementId: copie.etablissement_id, soignantId: copie.soignant_id,
    periodeDebut: copie.periode_debut, periodeFin: copie.periode_fin, missionIds: copie.mission_ids,
    remplaceId: null, motifRemplacement: null };
  const file = new File(['%PDF-test'], 'copie.pdf', { type: 'application/pdf' });
  const reservation = Object.freeze({ id: copie.id, statut: 'RESERVEE', bucket: 'copies-bulletins-paie', storage_path: `${copie.id}/original.pdf` });
  function storageRepond(status: number, body: Record<string, string>) {
    const requete = vi.fn<typeof fetch>().mockImplementation(async () => new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } }));
    const api = new StorageClient('https://recette.invalid/storage/v1', {}, requete).from(reservation.bucket);
    banc.storage.mockReturnValue(api);
    return { requete, upload: vi.spyOn(api, 'upload') };
  }
  beforeEach(() => {
    sessionStorage.clear(); vi.stubGlobal('crypto', webcrypto);
    banc.rpc.mockReset().mockResolvedValue({ data: reservation, error: null }); banc.storage.mockReset();
    banc.invoke.mockReset().mockResolvedValue({ data: { ok: true, statut: 'PUBLIEE' }, error: null });
  });
  afterEach(() => { vi.restoreAllMocks(); vi.unstubAllGlobals(); });

  it.each([
    { nom: 'legacy HTTP 400', status: 400, code: '400', body: { statusCode: '400', error: 'Duplicate', message: 'The resource already exists' } },
    { nom: 'legacy HTTP 409', status: 409, code: '409', body: { statusCode: '409', error: 'Duplicate', message: 'The resource already exists' } },
    { nom: 'code moderne ResourceAlreadyExists', status: 409, code: 'ResourceAlreadyExists', body: { code: 'ResourceAlreadyExists', message: 'The resource already exists' } },
  ])('reprend $nom sans écraser le fichier, puis exige la finalisation', async ({ status, code, body }) => {
    const id = await idempotenceCopie('employeur', depot, copie.sha256);
    const sdk = storageRepond(status, body);
    await expect(publierCopieBulletin(depot, file, copie.sha256, id, vi.fn())).resolves.toBe(copie.id);
    const resultat = await sdk.upload.mock.results[0].value;
    expect(resultat.error).toBeInstanceOf(StorageApiError);
    expect(resultat.error).toMatchObject({ status, statusCode: code, message: 'The resource already exists' });
    expect(resultat.error).not.toHaveProperty('error');
    expect(sdk.requete).toHaveBeenCalledTimes(1);
    expect(sdk.requete.mock.calls[0][0]).toBe(`https://recette.invalid/storage/v1/object/${reservation.bucket}/${reservation.storage_path}`);
    expect(new Headers(sdk.requete.mock.calls[0][1]?.headers).get('x-upsert')).toBe('false');
    expect(banc.invoke).toHaveBeenCalledExactlyOnceWith('copies-bulletins', { body: { action: 'finaliser', copie_id: copie.id, destinataire_confirme: true } });
    expect(await idempotenceCopie('employeur', depot, copie.sha256)).toBe(id);
    expect(banc.rpc).toHaveBeenCalledTimes(1); expect(reservation.statut).toBe('RESERVEE');
  });

  it.each([
    { nom: '400 générique', status: 400, body: { statusCode: '400', error: 'InvalidRequest', message: 'Invalid request' } },
    { nom: 'message partiel', status: 400, body: { statusCode: '400', message: 'The resource already exists: access denied' } },
    { nom: 'code de droit en HTTP 400', status: 400, body: { code: 'AccessDenied', message: 'The resource already exists' } },
    { nom: '401 avec code doublon', status: 401, body: { code: 'ResourceAlreadyExists', message: 'The resource already exists' } },
    { nom: '403 avec ancien code 400', status: 403, body: { statusCode: '400', error: 'Duplicate', message: 'The resource already exists' } },
    { nom: 'erreur serveur', status: 500, body: { statusCode: '500', message: 'The resource already exists' } },
  ])('ne finalise pas après $nom', async ({ status, body }) => {
    storageRepond(status, body);
    await expect(publierCopieBulletin(depot, file, copie.sha256, copie.id, vi.fn())).rejects.toThrow('L’envoi n’a pas été confirmé. Gardez ce fichier et réessayez');
    expect(banc.invoke).not.toHaveBeenCalled();
  });

  it.each(['COPIE_INTEGRITE_INVALIDE', 'COPIE_ACCES_REFUSE'])('le doublon ne masque jamais le refus final de contrôle %s', async code => {
    storageRepond(400, { statusCode: '400', error: 'Duplicate', message: 'The resource already exists' });
    banc.invoke.mockResolvedValue({ data: null, error: new FunctionsHttpError(new Response(JSON.stringify({ error: code }), { status: code === 'COPIE_INTEGRITE_INVALIDE' ? 409 : 403 })) });
    await expect(publierCopieBulletin(depot, file, copie.sha256, copie.id, vi.fn())).rejects.toThrow('La publication n’a pas été confirmée. Le serveur doit vérifier le PDF et vos droits.');
    expect(banc.invoke).toHaveBeenCalledTimes(1);
  });
});

describe('copies officielles : reprise explicite après retrait', () => {
  const depot: DepotCopieBulletin = { etablissementId: copie.etablissement_id, soignantId: copie.soignant_id,
    periodeDebut: copie.periode_debut, periodeFin: copie.periode_fin, missionIds: copie.mission_ids,
    remplaceId: null, motifRemplacement: null };
  const file = new File(['%PDF-test'], 'copie.pdf', { type: 'application/pdf' });
  beforeEach(() => {
    sessionStorage.clear(); vi.stubGlobal('crypto', webcrypto);
    banc.rpc.mockReset(); banc.storage.mockReset(); banc.invoke.mockReset();
  });
  afterEach(() => { vi.unstubAllGlobals(); });

  it('conserve une intention au rejeu ; une action explicite renouvelle seulement la clé retirée', async () => {
    const ancienne = await idempotenceCopie('employeur', depot, copie.sha256);
    expect(await idempotenceCopie('employeur', depot, copie.sha256)).toBe(ancienne);
    const nouvelle = await nouvelleIdempotenceCopie('employeur', depot, copie.sha256, ancienne);
    expect(nouvelle).not.toBe(ancienne);
    expect(await idempotenceCopie('employeur', depot, copie.sha256)).toBe(nouvelle);
    // Repeating the preparation for the old withdrawn intention must not
    // replace a newer intention that may already have been submitted.
    expect(await nouvelleIdempotenceCopie('employeur', depot, copie.sha256, ancienne)).toBe(nouvelle);
    expect(banc.rpc).not.toHaveBeenCalled();
    expect(banc.storage).not.toHaveBeenCalled();
  });

  it('un fichier ou un destinataire différent ne réemploie pas la même intention', async () => {
    const initiale = await idempotenceCopie('employeur', depot, copie.sha256);
    expect(await idempotenceCopie('employeur', depot, 'b'.repeat(64))).not.toBe(initiale);
    expect(await idempotenceCopie('employeur', { ...depot, soignantId: copie.etablissement_id }, copie.sha256)).not.toBe(initiale);
    expect(await idempotenceCopie('employeur', depot, copie.sha256)).toBe(initiale);
  });

  it('sans randomUUID, conserve un UUID v4 sécurisé après rechargement et renouvelle seulement sur action explicite', async () => {
    const alea = vi.fn((octets: Uint8Array) => webcrypto.getRandomValues(octets));
    vi.stubGlobal('crypto', { subtle: webcrypto.subtle, getRandomValues: alea });
    const initiale = await idempotenceCopie('employeur', depot, copie.sha256);
    expect(initiale).toMatch(/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/);
    expect(alea).toHaveBeenCalledTimes(1);
    expect(alea.mock.calls[0][0]).toHaveLength(16);
    vi.resetModules();
    const rechargement = await import('../copiesBulletins');
    expect(await rechargement.idempotenceCopie('employeur', depot, copie.sha256)).toBe(initiale);
    expect(alea).toHaveBeenCalledTimes(1);
    const nouvelle = await rechargement.nouvelleIdempotenceCopie('employeur', depot, copie.sha256, initiale);
    expect(nouvelle).not.toBe(initiale);
    expect(nouvelle).toMatch(/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/);
    expect(alea).toHaveBeenCalledTimes(2);
    expect(await rechargement.idempotenceCopie('employeur', depot, copie.sha256)).toBe(nouvelle);
  });

  it.each([
    { data: null, error: { message: 'COPIE_RETIREE', code: '55000' } },
    { data: { id: copie.id, statut: 'RETIREE' }, error: null },
  ])('expose un retrait confirmé sans upload, republication ni changement automatique de clé', async reponse => {
    const id = await idempotenceCopie('employeur', depot, copie.sha256);
    banc.rpc.mockResolvedValue(reponse);
    await expect(publierCopieBulletin(depot, file, copie.sha256, id, vi.fn())).rejects.toBeInstanceOf(CopieRetireeErreur);
    expect(banc.rpc).toHaveBeenCalledWith('fn_reserver_copie_bulletin', expect.objectContaining({ p_idempotence: id }));
    expect(banc.storage).not.toHaveBeenCalled(); expect(banc.invoke).not.toHaveBeenCalled();
    expect(await idempotenceCopie('employeur', depot, copie.sha256)).toBe(id);
  });

  it.each(['COPIE_ACCES_REFUSE', 'COPIE_IDEMPOTENCE_CONFLIT', 'COPIE_VERSION_CONFLIT', 'Network request failed'])('ne propose pas de nouvelle intention pour %s', async message => {
    const id = await idempotenceCopie('employeur', depot, copie.sha256);
    banc.rpc.mockResolvedValue({ data: null, error: { message } });
    const erreur = await publierCopieBulletin(depot, file, copie.sha256, id, vi.fn()).catch(e => e);
    expect(erreur).toBeInstanceOf(Error); expect(erreur).not.toBeInstanceOf(CopieRetireeErreur);
    expect(await idempotenceCopie('employeur', depot, copie.sha256)).toBe(id);
    expect(banc.storage).not.toHaveBeenCalled(); expect(banc.invoke).not.toHaveBeenCalled();
  });
});
