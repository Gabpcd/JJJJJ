import React from 'react';
import { act, cleanup, fireEvent, render, screen } from '@testing-library/react';
import { Link, MemoryRouter } from 'react-router-dom';
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it, vi } from 'vitest';
import { BandeauOnboardingEtab } from './BandeauOnboardingEtab';

type Resultat = { data: { contrat_service_signe: boolean } | null; error: { message: string } | null };
type Lecture = {
  etablissementId: string;
  signal: AbortSignal;
  terminer: (resultat: Resultat) => void;
  rejeter: (erreur: Error) => void;
};
const mocks = vi.hoisted(() => ({
  etablissementId: 'etab-a' as string | null,
  resolved: true,
  error: null as Error | null,
  from: vi.fn(),
}));
vi.mock('@/integrations/supabase/client', () => ({ supabase: { from: mocks.from } }));
vi.mock('@/hooks/useEtablissementScope', () => ({ useEtablissementScope: () => mocks }));

let lectures: Lecture[];
const annulationNative = Object.getOwnPropertyDescriptor(AbortSignal.prototype, 'throwIfAborted');
beforeAll(() => {
  Object.defineProperty(AbortSignal.prototype, 'throwIfAborted', { configurable: true, value: undefined });
});
afterAll(() => {
  if (annulationNative) Object.defineProperty(AbortSignal.prototype, 'throwIfAborted', annulationNative);
  else Reflect.deleteProperty(AbortSignal.prototype, 'throwIfAborted');
});
afterEach(() => { cleanup(); vi.restoreAllMocks(); });
beforeEach(() => {
  vi.clearAllMocks();
  mocks.etablissementId = 'etab-a';
  mocks.resolved = true;
  mocks.error = null;
  lectures = [];
  mocks.from.mockImplementation((table: string) => {
    expect(table).toBe('etablissements');
    let etablissementId = '';
    let signal: AbortSignal;
    const builder: Record<string, any> = {
      select: (colonnes: string) => { expect(colonnes).toBe('contrat_service_signe'); return builder; },
      eq: (colonne: string, valeur: string) => { expect(colonne).toBe('id'); etablissementId = valeur; return builder; },
      abortSignal: (valeur: AbortSignal) => { signal = valeur; return builder; },
      maybeSingle: () => new Promise<Resultat>((terminer, rejeter) => {
        // Le transport peut livrer/rejeter une réponse après l'annulation :
        // le composant doit protéger son état, pas dépendre du double réseau.
        lectures.push({ etablissementId, signal, terminer, rejeter });
      }),
    };
    return builder;
  });
});

function afficher(pathname = '/etablissement/dashboard') {
  const arbre = () => <MemoryRouter initialEntries={[pathname]}>
    <BandeauOnboardingEtab />
    <Link to="/etablissement/activer">Aller à l'activation</Link>
    <Link to="/etablissement/facturation">Aller aux factures</Link>
  </MemoryRouter>;
  const vue = render(arbre());
  return { ...vue, actualiser: () => vue.rerender(arbre()) };
}
const bandeau = () => screen.queryByTestId('onboarding-etab-banner');
async function terminer(index: number, signe: boolean) {
  await act(async () => lectures[index].terminer({ data: { contrat_service_signe: signe }, error: null }));
}

describe('Bandeau établissement : lecture liée au compte, à la route et au document', () => {
  it('affiche le contrat non signé puis rejoint l’activation sans API récente iOS', async () => {
    afficher();
    expect(lectures).toHaveLength(1);
    expect(lectures[0].signal.throwIfAborted).toBeUndefined();
    await terminer(0, false);
    expect(bandeau()).toBeVisible();
    expect(screen.getByText('Signez le contrat de service pour publier des missions.')).toBeInTheDocument();
    fireEvent.click(screen.getByRole('button', { name: 'Compléter maintenant' }));
    expect(bandeau()).not.toBeInTheDocument();
    expect(lectures).toHaveLength(1);
  });

  it('ignore la réponse tardive de l’ancien établissement après la réponse du nouveau', async () => {
    const vue = afficher();
    mocks.etablissementId = 'etab-b';
    vue.actualiser();
    expect(lectures.map(l => l.etablissementId)).toEqual(['etab-a', 'etab-b']);
    expect(lectures[0].signal.aborted).toBe(true);
    expect(lectures[1].signal.aborted).toBe(false);
    await terminer(1, true);
    await terminer(0, false);
    expect(bandeau()).not.toBeInTheDocument();
  });

  it('efface immédiatement le bandeau de l’ancien établissement pendant la nouvelle lecture', async () => {
    const vue = afficher();
    await terminer(0, false);
    expect(bandeau()).toBeVisible();
    mocks.etablissementId = 'etab-b';
    vue.actualiser();
    expect(bandeau()).not.toBeInTheDocument();
    await terminer(1, true);
    expect(bandeau()).not.toBeInTheDocument();
  });

  it('annule au changement de route et ne restaure pas un ancien résultat sur l’activation', async () => {
    afficher();
    fireEvent.click(screen.getByRole('link', { name: 'Aller aux factures' }));
    expect(lectures).toHaveLength(2);
    expect(lectures[0].signal.aborted).toBe(true);
    fireEvent.click(screen.getByRole('link', { name: "Aller à l'activation" }));
    expect(lectures[1].signal.aborted).toBe(true);
    await terminer(0, false);
    await terminer(1, false);
    expect(bandeau()).not.toBeInTheDocument();
    expect(lectures).toHaveLength(2);
    fireEvent.focus(window);
    expect(lectures).toHaveLength(2);
  });

  it.each(['non résolu', 'erreur', 'sans établissement'] as const)('ferme le bandeau avec un périmètre %s', async (cas) => {
    const vue = afficher();
    await terminer(0, false);
    if (cas === 'non résolu') mocks.resolved = false;
    if (cas === 'erreur') mocks.error = new Error('Périmètre refusé');
    if (cas === 'sans établissement') mocks.etablissementId = null;
    vue.actualiser();
    expect(bandeau()).not.toBeInTheDocument();
    fireEvent(window, new PageTransitionEvent('pageshow', { persisted: true }));
    expect(lectures).toHaveLength(1);
  });

  it('annule au démontage, retire les reprises et accepte le rejet tardif sans fuite', async () => {
    const vue = afficher();
    vue.unmount();
    expect(lectures[0].signal.aborted).toBe(true);
    await act(async () => lectures[0].rejeter(new TypeError('Load failed')));
    fireEvent(window, new PageTransitionEvent('pageshow', { persisted: true }));
    fireEvent.focus(window);
    fireEvent.pointerDown(window);
    fireEvent.keyDown(window);
    expect(lectures).toHaveLength(1);
    afficher();
    expect(lectures).toHaveLength(2);
    await terminer(1, false);
    expect(bandeau()).toBeVisible();
  });

  it.each(['focus', 'pointerdown', 'keydown'])('reprend un départ refusé sur %s sans lecture concurrente', async (evenement) => {
    afficher();
    const refuser = (event: Event) => event.preventDefault();
    window.addEventListener('beforeunload', refuser);
    try {
      const depart = new Event('beforeunload', { cancelable: true });
      fireEvent(window, depart);
      expect(depart.defaultPrevented).toBe(true);
      expect(lectures[0].signal.aborted).toBe(true);
      expect(lectures).toHaveLength(1);
      fireEvent(window, new Event(evenement));
      fireEvent(window, new Event(evenement));
      expect(lectures).toHaveLength(2);
      expect(lectures[1].signal.aborted).toBe(false);
      await terminer(1, true);
      await terminer(0, false);
      expect(bandeau()).not.toBeInTheDocument();
    } finally { window.removeEventListener('beforeunload', refuser); }
  });

  it('reprend au retour bfcache sans relancer pendant que le document est caché', async () => {
    afficher();
    fireEvent(window, new PageTransitionEvent('pagehide', { persisted: true }));
    expect(lectures[0].signal.aborted).toBe(true);
    const visibilite = vi.spyOn(document, 'visibilityState', 'get').mockReturnValue('hidden');
    fireEvent.focus(window);
    expect(lectures).toHaveLength(1);
    visibilite.mockReturnValue('visible');
    fireEvent(window, new PageTransitionEvent('pageshow', { persisted: true }));
    expect(lectures).toHaveLength(2);
    await act(async () => lectures[0].rejeter(new TypeError('access control checks')));
    await terminer(1, false);
    expect(bandeau()).toBeVisible();
    fireEvent(window, new PageTransitionEvent('pageshow', { persisted: false }));
    expect(lectures).toHaveLength(2);
  });

  it('ne traite plus beforeunload une fois la lecture achevée, mais recharge après pagehide', async () => {
    afficher();
    await terminer(0, false);
    fireEvent(window, new Event('beforeunload'));
    fireEvent.focus(window);
    expect(lectures).toHaveLength(1);
    fireEvent(window, new PageTransitionEvent('pagehide', { persisted: true }));
    fireEvent(window, new PageTransitionEvent('pageshow', { persisted: true }));
    expect(lectures).toHaveLength(2);
    await terminer(1, true);
    expect(bandeau()).not.toBeInTheDocument();
  });

  it.each(['error', 'absence', 'rejet'])('conserve le bandeau fermé en cas de %s et relit à la prochaine route', async (cas) => {
    afficher();
    await act(async () => {
      if (cas === 'rejet') lectures[0].rejeter(new TypeError('Load failed'));
      else lectures[0].terminer(cas === 'error'
        ? { data: { contrat_service_signe: false }, error: { message: 'Lecture refusée' } }
        : { data: null, error: null });
    });
    expect(bandeau()).not.toBeInTheDocument();
    fireEvent.click(screen.getByRole('link', { name: 'Aller aux factures' }));
    expect(lectures).toHaveLength(2);
    await terminer(1, false);
    expect(bandeau()).toBeVisible();
  });
});
