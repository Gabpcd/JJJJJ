import { webcrypto } from 'node:crypto';
import { describe, expect, it, vi } from 'vitest';
import { creerHandlerCopies, type AccesCopie, type DependancesCopies } from '../../../supabase/functions/copies-bulletins/handler';
import { authentifierCopie } from '../../../supabase/functions/copies-bulletins/auth';

const id = '88700000-0000-4000-8000-000000000001';
const acteur = '88700000-0000-4000-8000-000000000002';
const bytes = new Uint8Array([37,80,68,70,45,49,46,55,0,255,10]);
Object.defineProperty(globalThis, 'crypto', { value: webcrypto, configurable: true });
async function scenario() {
  const digest = await webcrypto.subtle.digest('SHA-256', bytes);
  const hash = Buffer.from(digest).toString('hex');
  const copie: AccesCopie = { id, statut: 'RESERVEE', storage_path: `${id}/original.pdf`, sha256_attendu: hash, taille_attendue: bytes.length };
  const deps: DependancesCopies = {
    authentifier: vi.fn(async () => acteur), acces: vi.fn(async () => copie),
    lire: vi.fn(async () => bytes), verifierPdf: vi.fn(async () => {}),
    publier: vi.fn(async () => ({ ok: true as const, id, statut: 'PUBLIEE' })), cors: () => ({}),
  };
  const req = (body: unknown = { action: 'finaliser', copie_id: id, destinataire_confirme: true }) => new Request('https://example.invalid', {
    method: 'POST', body: JSON.stringify(body), headers: { Authorization: 'Bearer fictif' },
  });
  return { deps, copie, hash, req, run: creerHandlerCopies(deps) };
}
describe('copies officielles — orchestration fermée et confidentialité', () => {
  it('contrôle les octets avant publication et conserve leur hash', async () => {
    const { deps, hash, req, run } = await scenario();
    expect((await run(req())).status).toBe(200);
    expect(deps.verifierPdf).toHaveBeenCalledWith(bytes);
    expect(deps.publier).toHaveBeenCalledWith(id, acteur, hash, bytes.length);
    expect(vi.mocked(deps.verifierPdf).mock.invocationCallOrder[0]).toBeLessThan(vi.mocked(deps.publier).mock.invocationCallOrder[0]);
  });
  it('livre les octets identiques, jamais une URL signée ni un PDF recalculé', async () => {
    const { deps, req, run } = await scenario();
    const response = await run(req({ action: 'telecharger', copie_id: id }));
    expect(response.status).toBe(200);
    expect(new Uint8Array(await response.arrayBuffer())).toEqual(bytes);
    expect(response.headers.get('Cache-Control')).toBe('no-store');
    expect(response.headers.get('Content-Disposition')).toBe('attachment; filename="copie-bulletin.pdf"');
    expect(deps.acces).toHaveBeenCalledTimes(2);
    expect(deps.publier).not.toHaveBeenCalled();
    expect(deps.verifierPdf).not.toHaveBeenCalled();
  });
  it('refuse avant lecture si non authentifié', async () => {
    const { deps, req, run } = await scenario(); vi.mocked(deps.authentifier).mockResolvedValue(null);
    expect((await run(req())).status).toBe(401); expect(deps.lire).not.toHaveBeenCalled();
  });
  it.each(['COPIE_ACCES_REFUSE','COPIE_RETIREE','COPIE_RESERVATION_EXPIREE'])('respecte %s avant Storage', async (code) => {
    const { deps, req, run } = await scenario(); vi.mocked(deps.acces).mockRejectedValue(new Error(code));
    const response = await run(req()); expect(response.ok).toBe(false);
    expect(await response.json()).toEqual({ error: code }); expect(deps.lire).not.toHaveBeenCalled();
  });
  it.each([
    { action: 'finaliser', copie_id: id },
    { action: 'finaliser', copie_id: id, destinataire_confirme: false },
    { action: 'finaliser', copie_id: id, destinataire_confirme: true, path: 'foreign.pdf' },
    { action: 'telecharger', copie_id: '../foreign' },
    { action: 'payer', copie_id: id },
  ])('refuse un corps non canonique %#', async (body) => {
    const { deps, req, run } = await scenario(); expect((await run(req(body))).status).toBe(400);
    expect(deps.acces).not.toHaveBeenCalled();
  });
  it.each(['id','storage_path','sha256_attendu','taille_attendue'])('refuse metadata incohérente %s', async (champ) => {
    const { deps, copie, req, run } = await scenario();
    vi.mocked(deps.acces).mockResolvedValue({ ...copie, [champ]: champ === 'taille_attendue' ? 0 : 'foreign' });
    expect((await run(req())).status).toBe(409); expect(deps.lire).not.toHaveBeenCalled();
  });
  it('un autre fichier de même taille ne peut pas être publié après un upload409', async () => {
    const { deps, req, run } = await scenario(); vi.mocked(deps.lire).mockResolvedValue(bytes.map((x) => x ^ 1));
    expect((await run(req())).status).toBe(409); expect(deps.publier).not.toHaveBeenCalled();
  });
  it('refuse une taille différente et ne parse pas', async () => {
    const { deps, req, run } = await scenario(); vi.mocked(deps.lire).mockResolvedValue(bytes.slice(1));
    expect((await run(req())).status).toBe(409); expect(deps.verifierPdf).not.toHaveBeenCalled();
  });
  it('refuse le PDF illisible sans publication', async () => {
    const { deps, req, run } = await scenario(); vi.mocked(deps.verifierPdf).mockRejectedValue(new Error('COPIE_PDF_INVALIDE'));
    expect((await run(req())).status).toBe(422); expect(deps.publier).not.toHaveBeenCalled();
  });
  it('une suspension/retrait pendant la lecture empêche de retourner les octets', async () => {
    const { deps, copie, req, run } = await scenario();
    vi.mocked(deps.acces).mockResolvedValueOnce(copie).mockRejectedValueOnce(new Error('COPIE_ACCES_REFUSE'));
    const response = await run(req({ action: 'telecharger', copie_id: id }));
    expect(response.status).toBe(403); expect(await response.json()).toEqual({ error: 'COPIE_ACCES_REFUSE' });
  });
  it('un commit suivi de réponse perdue se rejoue avec la même identité, sans effacement', async () => {
    const { deps, req, run } = await scenario();
    vi.mocked(deps.publier).mockRejectedValueOnce(new Error('réponse réseau perdue avec contenu sensible')).mockResolvedValueOnce({ ok: true, id, statut: 'PUBLIEE' });
    const first = await run(req()); expect(first.status).toBe(503);
    expect(await first.text()).not.toContain('sensible');
    expect((await run(req())).status).toBe(200);
    expect(vi.mocked(deps.publier).mock.calls[0]).toEqual(vi.mocked(deps.publier).mock.calls[1]);
    // Aucune primitive de suppression ou de paiement n'existe dans ce handler.
    expect(Object.keys(deps).sort()).toEqual(['acces','authentifier','cors','lire','publier','verifierPdf'].sort());
  });
  it('un conflit transactionnel ne devient pas un succès', async () => {
    const { deps, req, run } = await scenario(); vi.mocked(deps.publier).mockRejectedValue(new Error('COPIE_VERSION_CONFLIT'));
    expect((await run(req())).status).toBe(409);
  });
  it('une réponse de publication vide ou incohérente ne devient pas un succès', async () => {
    const { deps, req, run } = await scenario();
    vi.mocked(deps.publier).mockResolvedValue({ ok: true, id: acteur, statut: 'PUBLIEE' });
    expect((await run(req())).status).toBe(503);
  });
  it('expurge les erreurs inconnues sans log', async () => {
    const { deps, req, run } = await scenario(); const log = vi.spyOn(console, 'error').mockImplementation(() => {});
    vi.mocked(deps.lire).mockRejectedValue(new Error('NIR SECRET https://storage/secret?token=abc'));
    expect(await (await run(req())).json()).toEqual({ error: 'COPIE_SERVICE_INDISPONIBLE' });
    expect(log).not.toHaveBeenCalled(); log.mockRestore();
  });
});
describe('copies officielles — Auth courant sans bypass service', () => {
  const request = (bearer?: string) => new Request('https://example.invalid', { headers: bearer ? { Authorization: `Bearer ${bearer}` } : {} });
  it.each([undefined, 'cle-service-fictive', 'sb_secret_fictif'])('rejette le bearer absent/service %s avant getUser', async (bearer) => {
    const getUser = vi.fn();
    expect(await authentifierCopie(request(bearer), getUser, 'cle-service-fictive')).toBeNull();
    expect(getUser).not.toHaveBeenCalled();
  });
  it('un JWT falsifié décodable ne donne aucun droit', async () => {
    const getUser = vi.fn(async () => ({ data: { user: null }, error: new Error('JWT invalide') }));
    expect(await authentifierCopie(request('eyJ.role_service_role.faux'), getUser, 'service')).toBeNull();
    expect(getUser).toHaveBeenCalledOnce();
  });
  it.each([{ deleted_at: '2026-09-01' }, { banned_until: '2099-01-01' }, { banned_until: 'invalide' }])('rejette compte supprimé/suspendu %#', async (state) => {
    const getUser = vi.fn(async () => ({ data: { user: { id: acteur, ...state } }, error: null }));
    expect(await authentifierCopie(request('jwt-fictif'), getUser, 'service')).toBeNull();
  });
  it('retient uniquement l’identité relue depuis Auth, les droits tenant viennent ensuite du RPC', async () => {
    const getUser = vi.fn(async () => ({ data: { user: { id: acteur } }, error: null }));
    expect(await authentifierCopie(request('jwt-fictif'), getUser, 'service')).toBe(acteur);
    expect(getUser).toHaveBeenCalledWith('jwt-fictif');
  });
});
