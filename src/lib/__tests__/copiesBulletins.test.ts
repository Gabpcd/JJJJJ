import { webcrypto } from 'node:crypto';
import { FunctionsFetchError, FunctionsHttpError, FunctionsRelayError } from '@supabase/supabase-js';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { copieBulletinTelechargeable, CopieRetireeErreur, idempotenceCopie, nouvelleIdempotenceCopie, publierCopieBulletin, validerListeCopiesBulletins, type CopieBulletin, type DepotCopieBulletin } from '../copiesBulletins';

const banc = vi.hoisted(() => ({ rpc: vi.fn(), storage: vi.fn(), invoke: vi.fn() }));
vi.mock('@/integrations/supabase/client', () => ({ supabase: { rpc: banc.rpc, storage: { from: banc.storage }, functions: { invoke: banc.invoke } } }));
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
    upload.mockResolvedValue({ error: { statusCode: '409' } });
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
