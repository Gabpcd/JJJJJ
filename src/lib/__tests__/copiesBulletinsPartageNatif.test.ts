import { webcrypto } from 'node:crypto';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const natif = vi.hoisted(() => ({ mkdir: vi.fn(), readdir: vi.fn(), writeFile: vi.fn(), getUri: vi.fn(), deleteFile: vi.fn(), share: vi.fn() }));
vi.mock('@capacitor/filesystem', () => ({ Directory: { Cache: 'CACHE' }, Filesystem: natif }));
vi.mock('@capacitor/share', () => ({ Share: { share: natif.share } }));
const dossier = 'copies-bulletins-partage';
const heure = 60 * 60 * 1_000;
const maintenant = new Date('2026-09-29T12:00:00Z').getTime();
const disque = new Map<string, { type: 'file' | 'directory'; data?: string; size?: number }>();
const nom = (timestamp: number) => `${dossier}/${timestamp}-${webcrypto.randomUUID()}.pdf`;

describe('copies natives : conservation bornée après le chooser, cache isolé', () => {
  beforeEach(() => {
    vi.resetModules(); vi.useFakeTimers(); vi.setSystemTime(maintenant); vi.stubGlobal('crypto', webcrypto); disque.clear();
    for (const mock of Object.values(natif)) mock.mockReset();
    natif.mkdir.mockResolvedValue(undefined);
    natif.readdir.mockImplementation(async ({ path, directory }) => {
      expect(path).toBe(dossier); expect(directory).toBe('CACHE');
      return { files: [...disque].filter(([p]) => p.startsWith(`${dossier}/`)).map(([p, f]) => ({ name: p.slice(dossier.length + 1), type: f.type, size: f.size })) };
    });
    natif.writeFile.mockImplementation(async ({ path, data, directory }) => {
      expect(directory).toBe('CACHE'); expect(disque.has(path)).toBe(false);
      disque.set(path, { type: 'file', data, size: atob(data).length }); return { uri: `file:///cache/${path}` };
    });
    natif.getUri.mockImplementation(async ({ path }) => ({ uri: `file:///cache/${path}` }));
    natif.deleteFile.mockImplementation(async ({ path, directory }) => { expect(directory).toBe('CACHE'); disque.delete(path); });
    natif.share.mockResolvedValue({ activityType: 'application-cible' });
  });
  afterEach(() => { vi.clearAllTimers(); vi.useRealTimers(); vi.unstubAllGlobals(); });

  it('conserve les octets pendant une heure après le résultat du chooser, sans suppression immédiate', async () => {
    const { partagerPdfCopieNatif } = await import('../copiesBulletinsPartageNatif');
    await partagerPdfCopieNatif('JVBERi1vY3RldHM=');
    const path = natif.writeFile.mock.calls[0][0].path;
    expect(natif.share).toHaveBeenCalledWith({ url: `file:///cache/${path}`, title: 'Copie du bulletin de paie' });
    expect(natif.deleteFile).not.toHaveBeenCalled();
    await vi.advanceTimersByTimeAsync(heure - 1);
    expect(disque.get(path)?.data).toBe('JVBERi1vY3RldHM=');
    await vi.advanceTimersByTimeAsync(1);
    expect(disque.has(path)).toBe(false); expect(natif.deleteFile).toHaveBeenCalledTimes(1);
  });

  it('ne purge jamais un chooser actif, même après 24 h ; sa garde commence seulement à sa fermeture', async () => {
    let terminer!: () => void;
    natif.share.mockImplementationOnce(() => new Promise<void>(resolve => { terminer = resolve; }));
    const { partagerPdfCopieNatif } = await import('../copiesBulletinsPartageNatif');
    const premier = partagerPdfCopieNatif('premier');
    await vi.advanceTimersByTimeAsync(0);
    const path = natif.writeFile.mock.calls[0][0].path;
    await vi.advanceTimersByTimeAsync(25 * heure);
    await partagerPdfCopieNatif('second');
    expect(disque.has(path)).toBe(true); expect(natif.deleteFile).not.toHaveBeenCalled();
    terminer(); await premier;
    await vi.advanceTimersByTimeAsync(heure - 1); expect(disque.has(path)).toBe(true);
    await vi.advanceTimersByTimeAsync(1); expect(disque.has(path)).toBe(false);
  });

  it('sérialise les créations concurrentes et refuse le 101e petit fichier sans éviction', async () => {
    let terminer!: () => void;
    const chooser = new Promise<void>(resolve => { terminer = resolve; });
    natif.share.mockReturnValue(chooser);
    const { partagerPdfCopieNatif } = await import('../copiesBulletinsPartageNatif');
    const demandes = Array.from({ length: 101 }, () => partagerPdfCopieNatif('cGRm').catch(e => e));
    await vi.advanceTimersByTimeAsync(0);
    expect(natif.writeFile).toHaveBeenCalledTimes(100); expect(natif.share).toHaveBeenCalledTimes(100);
    expect(new Set(natif.writeFile.mock.calls.map(([options]) => options.path)).size).toBe(100);
    expect(await demandes[100]).toMatchObject({ message: 'L’espace temporaire des PDF partagés est plein. Réessayez plus tard pour ouvrir une autre copie.' });
    expect(natif.deleteFile).not.toHaveBeenCalled();
    terminer(); await Promise.all(demandes);
  });

  it('après redémarrage, purge seulement les noms reconnus strictement âgés de plus de 24 h', async () => {
    const ancien = nom(maintenant - 25 * heure), limite = nom(maintenant - 24 * heure), futur = nom(maintenant + heure);
    const horsDossier = 'autre-document.pdf', ancienFormat = `${dossier}/copie-paie-confidentielle.pdf`, repertoire = nom(maintenant - 30 * heure);
    for (const path of [ancien, limite, futur, horsDossier, ancienFormat]) disque.set(path, { type: 'file' });
    disque.set(repertoire, { type: 'directory' });
    const { partagerPdfCopieNatif } = await import('../copiesBulletinsPartageNatif');
    await partagerPdfCopieNatif('nouveau');
    expect(natif.deleteFile).toHaveBeenCalledExactlyOnceWith({ path: ancien, directory: 'CACHE' });
    for (const path of [limite, futur, horsDossier, ancienFormat, repertoire]) expect(disque.has(path)).toBe(true);
  });

  it('ne remplace pas une erreur Share par une erreur de nettoyage et garde aussi le fichier après annulation', async () => {
    const annulation = new Error('Share canceled'); natif.share.mockRejectedValue(annulation);
    const { partagerPdfCopieNatif } = await import('../copiesBulletinsPartageNatif');
    await expect(partagerPdfCopieNatif('pdf')).rejects.toBe(annulation);
    expect(natif.deleteFile).not.toHaveBeenCalled();
    await vi.advanceTimersByTimeAsync(heure); expect(disque.size).toBe(0);
  });

  it('supprime sans attendre une écriture qui n’a jamais été proposée au partage', async () => {
    const panne = new Error('URI indisponible'); natif.getUri.mockRejectedValue(panne);
    const { partagerPdfCopieNatif } = await import('../copiesBulletinsPartageNatif');
    await expect(partagerPdfCopieNatif('pdf')).rejects.toBe(panne);
    expect(natif.share).not.toHaveBeenCalled(); expect(disque.size).toBe(0);
  });

  it('une suppression échouée conserve son poids dans la limite de 50 Mio', async () => {
    for (let i = 0; i < 5; i++) disque.set(nom(maintenant - 25 * heure), { type: 'file' });
    natif.deleteFile.mockRejectedValue(new Error('Nettoyage indisponible'));
    const { partagerPdfCopieNatif } = await import('../copiesBulletinsPartageNatif');
    await expect(partagerPdfCopieNatif('pdf')).rejects.toThrow('L’espace temporaire des PDF partagés est plein');
    expect(natif.writeFile).not.toHaveBeenCalled(); expect(disque.size).toBe(5);
  });

  it('compte les octets décodés du nouveau PDF et autorise exactement 50 Mio, jamais davantage', async () => {
    disque.set(nom(maintenant), { type: 'file', size: 50 * 1024 * 1024 - 3 });
    const { partagerPdfCopieNatif } = await import('../copiesBulletinsPartageNatif');
    await partagerPdfCopieNatif('cGRm'); // Three decoded bytes, four base64 characters.
    expect(natif.writeFile).toHaveBeenCalledTimes(1);
    await expect(partagerPdfCopieNatif('YQ==')).rejects.toThrow('L’espace temporaire des PDF partagés est plein');
    expect(natif.writeFile).toHaveBeenCalledTimes(1); expect(natif.deleteFile).not.toHaveBeenCalled();
  });

  it.each([undefined, NaN, -1])('compte conservativement 10 Mio par PDF si sa taille est %s', async size => {
    for (let i = 0; i < 5; i++) disque.set(nom(maintenant), { type: 'file', size });
    const { partagerPdfCopieNatif } = await import('../copiesBulletinsPartageNatif');
    await expect(partagerPdfCopieNatif('YQ==')).rejects.toThrow('L’espace temporaire des PDF partagés est plein');
    expect(natif.writeFile).not.toHaveBeenCalled(); expect(natif.deleteFile).not.toHaveBeenCalled();
  });

  it('reprend au partage suivant un nettoyage différé en échec sans rejet non traité', async () => {
    const { partagerPdfCopieNatif } = await import('../copiesBulletinsPartageNatif');
    await partagerPdfCopieNatif('premier');
    const path = natif.writeFile.mock.calls[0][0].path;
    natif.deleteFile.mockRejectedValueOnce(new Error('Cache occupé'));
    await vi.advanceTimersByTimeAsync(heure);
    expect(disque.has(path)).toBe(true);
    await partagerPdfCopieNatif('second');
    expect(disque.has(path)).toBe(false); expect(disque.size).toBe(1);
  });

  it('refuse toute écriture si le contenu du cache ne peut pas être vérifié', async () => {
    natif.readdir.mockRejectedValue(new Error('Cache indisponible'));
    const { partagerPdfCopieNatif } = await import('../copiesBulletinsPartageNatif');
    await expect(partagerPdfCopieNatif('pdf')).rejects.toThrow('Cache indisponible');
    expect(natif.writeFile).not.toHaveBeenCalled(); expect(natif.share).not.toHaveBeenCalled();
  });

  it('reprend après une écriture partielle en échec sans bloquer la file du cache', async () => {
    const panne = new Error('Écriture interrompue');
    natif.writeFile.mockImplementationOnce(async ({ path }) => { disque.set(path, { type: 'file' }); throw panne; });
    const { partagerPdfCopieNatif } = await import('../copiesBulletinsPartageNatif');
    await expect(partagerPdfCopieNatif('partiel')).rejects.toBe(panne);
    expect(disque.size).toBe(0);
    await partagerPdfCopieNatif('complet'); expect(disque.size).toBe(1); expect(natif.share).toHaveBeenCalledTimes(1);
  });
});
