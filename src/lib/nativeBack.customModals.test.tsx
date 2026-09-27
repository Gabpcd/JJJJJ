import { useState } from 'react';
import { act, cleanup, fireEvent, render, screen } from '@testing-library/react';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { createNativeBackHandler } from './nativeBack';
import { ModalNoterMission } from '@/components/ModalNoterMission';
import { CelebrationMatch } from '@/components/swipe/CelebrationMatch';
import { QRPointageEtab } from '@/components/etablissement/QRPointageEtab';

const mocks = vi.hoisted(() => ({ rpc: vi.fn(), notification: vi.fn() }));
vi.mock('@/integrations/supabase/client', () => ({ supabase: {
  rpc: mocks.rpc,
  from: () => {
    const query = { select: () => query, eq: () => query, order: () => query, limit: () => query,
      maybeSingle: async () => ({ data: { id: 'simulation', token: 'qr-fictif', type: 'UNIVERSEL',
        expire_le: '2099-01-01T12:00:00Z', nb_scans: 0, dernier_scan_le: null, actif: true,
        genere_le: '2026-09-27T12:00:00Z' }, error: null }) };
    return query;
  },
} }));
vi.mock('@/contexts/NotificationContext', () => ({ useNotification: () => ({ afficherNotification: mocks.notification }) }));
vi.mock('@/components/mascotte/Mascotte', () => ({ Mascotte: () => null }));
vi.mock('@/components/swipe/ConfettiSwipe', () => ({ ConfettiSwipe: () => null }));

beforeEach(() => {
  vi.clearAllMocks();
  vi.spyOn(HTMLElement.prototype, 'getClientRects').mockImplementation(function (this: HTMLElement) {
    return [this.getBoundingClientRect()] as unknown as DOMRectList;
  });
});
afterEach(() => { cleanup(); vi.restoreAllMocks(); });

function backHandler() {
  const back = vi.fn();
  const exit = vi.fn();
  const handler = createNativeBackHandler({ document, pathname: () => '/mission/simulation', back, exit, notify: vi.fn() });
  return { back, exit, press: () => act(() => handler({ canGoBack: true })) };
}
function Rating() {
  const [open, setOpen] = useState(true);
  return open ? <ModalNoterMission missionId="simulation" sens="SOIGNANT_VERS_ETAB" onClose={() => setOpen(false)} /> : null;
}

describe('retour natif dans les modales métier personnalisées', () => {
  it('ferme la notation sans envoyer de note', () => {
    const flow = backHandler();
    render(<Rating />);
    flow.press();
    expect(screen.queryByRole('dialog')).not.toBeInTheDocument();
    expect(mocks.rpc).not.toHaveBeenCalled();
    expect(flow.back).not.toHaveBeenCalled();
  });

  it('respecte le verrou pendant l’envoi de la notation', async () => {
    const flow = backHandler();
    let finish!: (result: unknown) => void;
    mocks.rpc.mockReturnValue(new Promise((resolve) => { finish = resolve; }));
    render(<Rating />);
    for (const star of screen.getAllByRole('button', { name: 'Note 5 étoiles' })) fireEvent.click(star);
    fireEvent.click(screen.getByRole('button', { name: 'Envoyer la notation' }));
    expect(screen.getByRole('button', { name: 'Envoi…' })).toBeDisabled();
    flow.press();
    flow.press();
    expect(screen.getByRole('dialog')).toBeVisible();
    expect(flow.back).not.toHaveBeenCalled();
    expect(flow.exit).not.toHaveBeenCalled();
    expect(mocks.rpc).toHaveBeenCalledOnce();
    await act(async () => { finish({ data: { success: false, error: 'Erreur simulée' }, error: null }); });
    flow.press();
    expect(screen.queryByRole('dialog')).not.toBeInTheDocument();
  });

  it('ferme la célébration sans signer ni ouvrir la conversation', () => {
    const flow = backHandler();
    const sign = vi.fn();
    const conversation = vi.fn();
    function Fixture() {
      const [open, setOpen] = useState(true);
      return <CelebrationMatch open={open} missionTitre="Mission fictive" etablissementNom="Établissement fictif"
        onClose={() => setOpen(false)} onSigner={sign} onVoirConversation={conversation} />;
    }
    render(<Fixture />);
    flow.press();
    expect(screen.queryByRole('dialog')).not.toBeInTheDocument();
    expect(sign).not.toHaveBeenCalled();
    expect(conversation).not.toHaveBeenCalled();
    expect(flow.back).not.toHaveBeenCalled();
  });

  it('ferme le QR plein écran sans régénérer le QR ni naviguer', async () => {
    const flow = backHandler();
    render(<QRPointageEtab missionId="simulation" missionIntitule="Mission fictive" />);
    fireEvent.click(await screen.findByRole('button', { name: 'Plein écran' }));
    expect(screen.getByRole('dialog', { name: 'QR code de pointage en plein écran' })).toBeVisible();
    flow.press();
    expect(screen.queryByRole('dialog')).not.toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Plein écran' })).toBeVisible();
    expect(mocks.rpc).not.toHaveBeenCalled();
    expect(flow.back).not.toHaveBeenCalled();
  });
});
