import { webcrypto } from 'node:crypto';
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
