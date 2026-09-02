import { beforeEach, describe, expect, it, vi } from 'vitest';

const mocks = vi.hoisted(() => ({
  isNative: vi.fn(() => true),
  share: vi.fn(),
  writeFile: vi.fn(),
  getUri: vi.fn(),
}));

vi.mock('./platform', () => ({ isNative: mocks.isNative }));
vi.mock('@capacitor/share', () => ({ Share: { share: mocks.share } }));
vi.mock('@capacitor/filesystem', () => ({
  Filesystem: { writeFile: mocks.writeFile, getUri: mocks.getUri },
  Directory: { Cache: 'CACHE' },
  Encoding: { UTF8: 'utf8' },
}));

import { telechargerOuPartager, telechargerOuPartagerPdf } from './telechargement';

describe('partage natif', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mocks.isNative.mockReturnValue(true);
    mocks.writeFile.mockResolvedValue(undefined);
    mocks.getUri.mockResolvedValue({ uri: 'file:///mission.ics' });
  });

  it('ne relance pas un partage texte lorsque l’utilisateur annule', async () => {
    mocks.share.mockRejectedValueOnce(new Error('Share canceled'));
    const open = vi.spyOn(window, 'open').mockImplementation(() => null);

    await telechargerOuPartager('BEGIN:VCALENDAR', 'mission.ics', 'text/calendar');

    expect(mocks.share).toHaveBeenCalledOnce();
    expect(open).not.toHaveBeenCalled();
    open.mockRestore();
  });

  it('ne transforme pas l’annulation du partage PDF en ouverture WebView', async () => {
    mocks.share.mockRejectedValueOnce(new Error('Share canceled'));
    const open = vi.spyOn(window, 'open').mockImplementation(() => null);
    const save = vi.fn();

    await telechargerOuPartagerPdf({
      save,
      output: vi.fn((type: string) => type === 'datauristring'
        ? 'data:application/pdf;base64,AAAA'
        : 'data:application/pdf;base64,AAAA'),
    }, 'document.pdf');

    expect(mocks.share).toHaveBeenCalledOnce();
    expect(open).not.toHaveBeenCalled();
    expect(save).not.toHaveBeenCalled();
    open.mockRestore();
  });
});
