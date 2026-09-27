import { useState } from 'react';
import * as Dialog from '@radix-ui/react-dialog';
import * as AlertDialog from '@radix-ui/react-alert-dialog';
import * as DropdownMenu from '@radix-ui/react-dropdown-menu';
import { act, cleanup, fireEvent, render, screen } from '@testing-library/react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { createNativeBackHandler } from './nativeBack';

beforeEach(() => {
  // JSDOM has no layout; only geometry is supplied, Radix behavior is real.
  vi.spyOn(HTMLElement.prototype, 'getClientRects').mockImplementation(function (this: HTMLElement) {
    return [this.getBoundingClientRect()] as unknown as DOMRectList;
  });
});
afterEach(() => { cleanup(); document.body.style.pointerEvents = ''; vi.restoreAllMocks(); });

function setup(path = '/soignant/explorer') {
  let pathname = path;
  let time = 10_000;
  const back = vi.fn();
  const exit = vi.fn();
  const notify = vi.fn();
  const handler = createNativeBackHandler({ document, pathname: () => pathname, back, exit, notify, now: () => time });
  return { back, exit, notify, press: (canGoBack = true) => act(() => handler({ canGoBack })),
    path: (value: string) => { pathname = value; }, time: (value: number) => { time = value; } };
}

function Mission({ prevent = false, modal = true }: { prevent?: boolean; modal?: boolean }) {
  const [open, setOpen] = useState(true);
  return <Dialog.Root open={open} onOpenChange={setOpen} modal={modal}>
    <Dialog.Trigger>Ouvrir mission</Dialog.Trigger>
    <Dialog.Portal><Dialog.Overlay /><Dialog.Content onEscapeKeyDown={(event) => { if (prevent) event.preventDefault(); }}>
      <Dialog.Title>Mission</Dialog.Title><Dialog.Description>Détail de mission</Dialog.Description>
      <Dialog.Close>Fermer</Dialog.Close>
    </Dialog.Content></Dialog.Portal>
  </Dialog.Root>;
}

function NestedDialogs({ onConfirm }: { onConfirm: () => void }) {
  return <Dialog.Root defaultOpen>
    <Dialog.Trigger>Ouvrir mission</Dialog.Trigger>
    <Dialog.Portal><Dialog.Overlay /><Dialog.Content>
      <Dialog.Title>Mission</Dialog.Title><Dialog.Description>Détail de mission</Dialog.Description>
      <AlertDialog.Root>
        <AlertDialog.Trigger>Annuler la mission</AlertDialog.Trigger>
        <AlertDialog.Portal><AlertDialog.Overlay /><AlertDialog.Content>
          <AlertDialog.Title>Confirmer l’annulation</AlertDialog.Title>
          <AlertDialog.Description>Cette action annule la mission</AlertDialog.Description>
          <AlertDialog.Cancel>Revenir</AlertDialog.Cancel>
          <AlertDialog.Action onClick={onConfirm}>Confirmer</AlertDialog.Action>
        </AlertDialog.Content></AlertDialog.Portal>
      </AlertDialog.Root>
    </Dialog.Content></Dialog.Portal>
  </Dialog.Root>;
}

describe('retour natif Android', () => {
  it('ferme la fiche mission avant de parcourir l’historique', () => {
    const flow = setup();
    render(<Mission />);
    expect(screen.getByRole('dialog', { name: 'Mission' })).toBeVisible();
    flow.press();
    expect(screen.queryByRole('dialog')).not.toBeInTheDocument();
    expect(flow.back).not.toHaveBeenCalled();
    expect(flow.exit).not.toHaveBeenCalled();
    flow.press();
    expect(flow.back).toHaveBeenCalledOnce();
  });

  it('ne ferme que la confirmation supérieure sans déclencher son action', () => {
    const flow = setup();
    const confirm = vi.fn();
    render(<NestedDialogs onConfirm={confirm} />);
    fireEvent.click(screen.getByRole('button', { name: 'Annuler la mission' }));
    expect(screen.getByRole('alertdialog')).toBeVisible();
    flow.press();
    expect(screen.queryByRole('alertdialog')).not.toBeInTheDocument();
    expect(screen.getByRole('dialog', { name: 'Mission' })).toBeVisible();
    expect(confirm).not.toHaveBeenCalled();
    expect(flow.back).not.toHaveBeenCalled();
    flow.press();
    expect(screen.queryByRole('dialog')).not.toBeInTheDocument();
    expect(flow.back).not.toHaveBeenCalled();
  });

  it('respecte preventDefault et ne quitte pas un formulaire qui refuse Escape', () => {
    const flow = setup('/');
    render(<Mission prevent />);
    flow.press();
    flow.press();
    expect(screen.getByRole('dialog')).toBeVisible();
    expect(flow.back).not.toHaveBeenCalled();
    expect(flow.notify).not.toHaveBeenCalled();
    expect(flow.exit).not.toHaveBeenCalled();
  });

  it('absorbe un second Retour pendant la fermeture animée de la couche supérieure', () => {
    const computedStyle = window.getComputedStyle.bind(window);
    vi.spyOn(window, 'getComputedStyle').mockImplementation((element) => new Proxy(computedStyle(element), {
      get(style, key) {
        if (key === 'animationName' && element.getAttribute('role') === 'alertdialog') {
          return element.getAttribute('data-state') === 'closed' ? 'exit' : 'enter';
        }
        const value = Reflect.get(style, key);
        return typeof value === 'function' ? value.bind(style) : value;
      },
    }));
    const flow = setup();
    render(<NestedDialogs onConfirm={vi.fn()} />);
    fireEvent.click(screen.getByRole('button', { name: 'Annuler la mission' }));
    const confirmation = screen.getByRole('alertdialog');
    flow.press();
    expect(confirmation).toHaveAttribute('data-state', 'closed');
    expect(document.querySelector('[role="dialog"]')).toHaveAttribute('data-state', 'open');
    flow.press();
    expect(flow.back).not.toHaveBeenCalled();
    expect(flow.exit).not.toHaveBeenCalled();
    const animationEnd = new Event('animationend', { bubbles: true });
    Object.defineProperty(animationEnd, 'animationName', { value: 'exit' });
    fireEvent(confirmation, animationEnd);
    expect(confirmation).not.toBeInTheDocument();
    flow.press();
    expect(document.querySelector('[role="dialog"]')).toBeNull();
    expect(flow.back).not.toHaveBeenCalled();
  });

  it('ferme un menu Radix sans sélectionner d’action', () => {
    const flow = setup();
    const action = vi.fn();
    render(<DropdownMenu.Root defaultOpen>
      <DropdownMenu.Trigger>Options</DropdownMenu.Trigger>
      <DropdownMenu.Portal><DropdownMenu.Content>
        <DropdownMenu.Item onSelect={action}>Supprimer</DropdownMenu.Item>
      </DropdownMenu.Content></DropdownMenu.Portal>
    </DropdownMenu.Root>);
    expect(screen.getByRole('menu')).toBeVisible();
    flow.press();
    expect(screen.queryByRole('menu')).not.toBeInTheDocument();
    expect(action).not.toHaveBeenCalled();
    expect(flow.back).not.toHaveBeenCalled();
  });

  it('laisse le menu personnalisé fermer sa couche via son propre Escape', () => {
    const flow = setup();
    render(<div role="dialog" aria-modal="true" aria-label="Menu principal" tabIndex={-1}>Menu</div>);
    const menu = screen.getByRole('dialog');
    const close = (event: KeyboardEvent) => { if (event.key === 'Escape') { event.preventDefault(); menu.hidden = true; } };
    document.addEventListener('keydown', close);
    try {
      flow.press();
      expect(menu).not.toBeVisible();
      expect(flow.back).not.toHaveBeenCalled();
    } finally { document.removeEventListener('keydown', close); }
  });

  it('ne ferme pas aussi un menu parent lorsqu’une couche Radix consomme Escape', () => {
    const flow = setup();
    const parentClose = vi.fn();
    // Same bubble listener as the custom mobile navigation menu.
    const close = (event: KeyboardEvent) => { if (event.key === 'Escape') { event.preventDefault(); parentClose(); } };
    document.addEventListener('keydown', close);
    try {
      render(<Mission />);
      flow.press();
      expect(screen.queryByRole('dialog')).not.toBeInTheDocument();
      expect(parentClose).not.toHaveBeenCalled();
      expect(flow.back).not.toHaveBeenCalled();
    } finally { document.removeEventListener('keydown', close); }
  });

  it('ne bloque pas l’historique pour un dialogue Radix non modal persistant', () => {
    const flow = setup();
    render(<Mission modal={false} />);
    flow.press();
    expect(flow.back).toHaveBeenCalledOnce();
    expect(screen.getByRole('dialog')).toBeVisible();
  });

  it('ignore les couches cachées ou en fin de fermeture', () => {
    const flow = setup();
    render(<><div hidden><div role="dialog" aria-modal="true">Caché</div></div>
      <div role="dialog" aria-modal="true" data-state="closed">Fermeture</div>
      <div style={{ visibility: 'hidden' }}><div role="dialog" aria-modal="true">Invisible</div></div></>);
    flow.press();
    expect(flow.back).toHaveBeenCalledOnce();
  });

  it.each(['/', '/soignant/tableau-de-bord/', '/etablissement/tableau-de-bord', '/groupe/tableau-de-bord', '/admin'])
  ('demande deux retours à l’accueil %s, sans revenir à la connexion', (path) => {
    const flow = setup(path);
    flow.press();
    expect(flow.notify).toHaveBeenCalledOnce();
    expect(flow.exit).not.toHaveBeenCalled();
    flow.time(11_000);
    flow.press();
    expect(flow.exit).toHaveBeenCalledOnce();
    expect(flow.back).not.toHaveBeenCalled();
  });

  it('redemande confirmation après deux secondes, y compris sans historique', () => {
    const flow = setup();
    flow.time(0);
    flow.press(false);
    expect(flow.exit).not.toHaveBeenCalled();
    flow.time(2_000);
    flow.press(false);
    expect(flow.notify).toHaveBeenCalledTimes(2);
    expect(flow.exit).not.toHaveBeenCalled();
    flow.time(2_001);
    flow.press(false);
    expect(flow.exit).toHaveBeenCalledOnce();
  });

  it('désarme la sortie après une fermeture de dialogue ou un retour d’historique', () => {
    const flow = setup('/');
    flow.press();
    render(<Mission />);
    flow.press();
    flow.press();
    expect(flow.notify).toHaveBeenCalledTimes(2);
    expect(flow.exit).not.toHaveBeenCalled();
    flow.path('/soignant/explorer');
    flow.press();
    expect(flow.back).toHaveBeenCalledOnce();
    flow.path('/');
    flow.press();
    expect(flow.notify).toHaveBeenCalledTimes(3);
    expect(flow.exit).not.toHaveBeenCalled();
  });
});
