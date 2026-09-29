import { act, cleanup, fireEvent, render, screen, waitFor } from '@testing-library/react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { ApercuPdfCopie } from '../ApercuPdfCopie';

const banc = vi.hoisted(() => ({ charger: vi.fn() }));
vi.mock('@/lib/apercuPdfCopie', () => ({ chargerApercuPdf: banc.charger }));
const file = new File(['%PDF-fixture'], 'document.pdf', { type: 'application/pdf' });

beforeEach(() => {
  banc.charger.mockReset();
  vi.spyOn(HTMLElement.prototype, 'getBoundingClientRect').mockReturnValue({ width: 360 } as DOMRect);
  vi.stubGlobal('ResizeObserver', class { observe() {} disconnect() {} });
});
afterEach(() => { cleanup(); vi.restoreAllMocks(); vi.unstubAllGlobals(); });

describe('aperçu : disponibilité réelle du rendu et reprise', () => {
  it('ne donne le feu vert qu’après le rendu, invalide ce feu vert à chaque changement de page et nettoie', async () => {
    let finir!: () => void;
    const rendrePage = vi.fn().mockImplementation(() => new Promise<void>(resolve => { finir = resolve; }));
    const detruire = vi.fn();
    banc.charger.mockResolvedValue({ nombrePages: 2, rendrePage, detruire });
    const pret = vi.fn();
    const vue = render(<ApercuPdfCopie file={file} onPretChange={pret} />);
    await waitFor(() => expect(rendrePage).toHaveBeenCalledOnce());
    expect(pret).not.toHaveBeenCalledWith(true);
    expect(screen.getByTestId('apercu-pdf-canvas')).toHaveAttribute('data-ready', 'false');
    await act(async () => finir());
    expect(pret).toHaveBeenLastCalledWith(true);
    expect(screen.getByTestId('apercu-pdf-canvas')).toHaveAttribute('data-ready', 'true');
    fireEvent.click(screen.getByRole('button', { name: 'Page suivante' }));
    expect(pret).toHaveBeenLastCalledWith(false);
    await waitFor(() => expect(rendrePage).toHaveBeenCalledTimes(2));
    expect(screen.getByTestId('apercu-pdf-pagination')).toHaveTextContent('Page 2 sur 2');
    await act(async () => finir());
    expect(pret).toHaveBeenLastCalledWith(true);
    vue.unmount(); expect(detruire).toHaveBeenCalledOnce(); expect(pret).toHaveBeenLastCalledWith(false);
  });

  it('une erreur de lecture garde la publication bloquée et permet un rechargement explicite', async () => {
    banc.charger.mockRejectedValueOnce(new Error('invalid')).mockResolvedValueOnce({ nombrePages: 1, rendrePage: vi.fn().mockResolvedValue(undefined), detruire: vi.fn() });
    const pret = vi.fn();
    render(<ApercuPdfCopie file={file} onPretChange={pret} />);
    expect(await screen.findByRole('alert')).toHaveTextContent('L’aperçu du PDF est indisponible');
    expect(pret).not.toHaveBeenCalledWith(true);
    fireEvent.click(screen.getByRole('button', { name: 'Réessayer l’aperçu' }));
    await waitFor(() => expect(pret).toHaveBeenLastCalledWith(true));
    expect(banc.charger).toHaveBeenCalledTimes(2);
  });

  it('un échec de rendu ne présente pas un canvas blanc comme aperçu prêt', async () => {
    banc.charger.mockResolvedValue({ nombrePages: 1, rendrePage: vi.fn().mockRejectedValue(new Error('render')), detruire: vi.fn() });
    const pret = vi.fn();
    render(<ApercuPdfCopie file={file} onPretChange={pret} />);
    expect(await screen.findByRole('alert')).toHaveTextContent('Cette page ne peut pas être affichée');
    expect(screen.getByTestId('apercu-pdf-canvas')).toHaveAttribute('data-ready', 'false');
    expect(pret).not.toHaveBeenCalledWith(true);
  });
});
