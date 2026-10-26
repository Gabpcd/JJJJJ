import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

const mocks = vi.hoisted(() => ({
  isNative: vi.fn(),
  getPlatform: vi.fn(),
  setResizeMode: vi.fn(),
  addListener: vi.fn(),
  activeEditableField: vi.fn(),
  keepNativeFieldVisible: vi.fn(),
}));

vi.mock('@capacitor/core', () => ({
  Capacitor: { isNativePlatform: mocks.isNative, getPlatform: mocks.getPlatform },
}));
vi.mock('@capacitor/keyboard', () => ({
  KeyboardResize: { Native: 'native' },
  Keyboard: { setResizeMode: mocks.setResizeMode, addListener: mocks.addListener },
}));
vi.mock('./nativeKeyboardViewport', () => ({
  activeEditableField: mocks.activeEditableField,
  keepNativeFieldVisible: mocks.keepNativeFieldVisible,
}));

import { configurerClavier } from './platform';

type Callback = (event: { keyboardHeight: number }) => void;
let callbacks: Map<string, Callback>;
let handles: Array<{ remove: ReturnType<typeof vi.fn> }>;
let focusListeners: EventListenerOrEventListenerObject[];
let resizeListeners: EventListenerOrEventListenerObject[];
let viewportSize: { width: number; height: number };
let visualViewport: EventTarget & { height: number };
let input: HTMLInputElement;

beforeEach(() => {
  vi.useFakeTimers();
  vi.resetAllMocks();
  callbacks = new Map();
  handles = [];
  focusListeners = [];
  resizeListeners = [];
  viewportSize = { width: 390, height: 900 };
  visualViewport = Object.assign(new EventTarget(), { height: 900 });
  vi.stubGlobal('visualViewport', visualViewport);
  input = document.createElement('input');
  mocks.isNative.mockReturnValue(true);
  mocks.getPlatform.mockReturnValue('ios');
  mocks.setResizeMode.mockResolvedValue(undefined);
  mocks.activeEditableField.mockReturnValue(input);
  mocks.addListener.mockImplementation(async (event: string, callback: Callback) => {
    callbacks.set(event, callback);
    const handle = { remove: vi.fn().mockResolvedValue(undefined) };
    handles.push(handle);
    return handle;
  });
  vi.spyOn(window, 'innerHeight', 'get').mockImplementation(() => viewportSize.height);
  vi.spyOn(window, 'innerWidth', 'get').mockImplementation(() => viewportSize.width);
  vi.spyOn(window, 'requestAnimationFrame').mockImplementation(callback =>
    window.setTimeout(() => callback(0), 0));
  const add = document.addEventListener.bind(document);
  vi.spyOn(document, 'addEventListener').mockImplementation((event, listener, options) => {
    if (event === 'focusin') focusListeners.push(listener);
    add(event, listener, options);
  });
  const addWindow = window.addEventListener.bind(window);
  vi.spyOn(window, 'addEventListener').mockImplementation((event, listener, options) => {
    if (event === 'resize') resizeListeners.push(listener);
    addWindow(event, listener, options);
  });
  vi.spyOn(document, 'removeEventListener');
  vi.spyOn(window, 'removeEventListener');
  vi.spyOn(visualViewport, 'removeEventListener');
});

afterEach(() => {
  for (const listener of focusListeners) document.removeEventListener('focusin', listener);
  for (const listener of resizeListeners) window.removeEventListener('resize', listener);
  document.body.classList.remove('keyboard-is-open');
  vi.clearAllTimers();
  vi.useRealTimers();
  vi.restoreAllMocks();
  vi.unstubAllGlobals();
});

function redimensionner(width: number, height: number) {
  viewportSize = { width, height };
  visualViewport.height = height;
  window.dispatchEvent(new Event('resize'));
}

function montrerClavier(keyboardHeight = 300, expectedHeight = 600) {
  callbacks.get('keyboardWillShow')?.({ keyboardHeight });
  callbacks.get('keyboardDidShow')!({ keyboardHeight });
  vi.runAllTimers();
  expect(mocks.keepNativeFieldVisible).toHaveBeenLastCalledWith(input, expectedHeight);
}

describe('configuration du clavier natif par plateforme', () => {
  it('laisse le navigateur sans réglage ni listener natif', async () => {
    mocks.isNative.mockReturnValue(false);
    await configurerClavier();
    expect(mocks.setResizeMode).not.toHaveBeenCalled();
    expect(mocks.addListener).not.toHaveBeenCalled();
    expect(focusListeners).toHaveLength(0);
    expect(resizeListeners).toHaveLength(0);
  });

  it('conserve le resize Native iOS et recalcule le viewport après fermeture', async () => {
    await configurerClavier();
    expect(mocks.setResizeMode).toHaveBeenCalledExactlyOnceWith({ mode: 'native' });
    expect([...callbacks.keys()]).toEqual(['keyboardWillShow', 'keyboardDidShow', 'keyboardWillHide', 'keyboardDidHide']);
    montrerClavier();
    // Le prochain show doit utiliser la hauteur restaurée.
    callbacks.get('keyboardWillHide')!({ keyboardHeight: 0 });
    redimensionner(390, 1000);
    callbacks.get('keyboardDidHide')!({ keyboardHeight: 0 });
    vi.runAllTimers();
    montrerClavier(300, 700);
  });

  it.each([
    { initialWidth: 844, initialHeight: 390, width: 390, height: 844, keyboardHeight: 300, visibleHeight: 544 },
    { initialWidth: 390, initialHeight: 844, width: 844, height: 390, keyboardHeight: 200, visibleHeight: 190 },
  ])('actualise la référence après rotation avant le premier clavier : $width × $height', async scenario => {
    viewportSize = { width: scenario.initialWidth, height: scenario.initialHeight };
    visualViewport.height = scenario.initialHeight;
    await configurerClavier();

    redimensionner(scenario.width, scenario.height);
    vi.runAllTimers();
    expect(mocks.keepNativeFieldVisible).not.toHaveBeenCalled();
    // Le resize natif peut arriver après didShow : il faut déjà employer
    // la hauteur de la nouvelle orientation pour déduire le clavier.
    montrerClavier(scenario.keyboardHeight, scenario.visibleHeight);
  });

  it('ne retranche pas deux fois le clavier si le resize Native précède didShow', async () => {
    await configurerClavier();
    callbacks.get('keyboardWillShow')!({ keyboardHeight: 300 });
    redimensionner(390, 600);
    callbacks.get('keyboardDidShow')!({ keyboardHeight: 300 });
    vi.runAllTimers();

    expect(mocks.keepNativeFieldVisible).toHaveBeenLastCalledWith(input, 600);
  });

  it.each([600, 620])('conserve la référence si le viewport est réduit à %i avant willShow', async height => {
    await configurerClavier();
    redimensionner(390, height);
    vi.runAllTimers();

    montrerClavier();
  });

  it('conserve la remise en vue si seul didShow est reçu', async () => {
    await configurerClavier();
    callbacks.get('keyboardDidShow')!({ keyboardHeight: 300 });
    vi.runAllTimers();

    expect(mocks.keepNativeFieldVisible).toHaveBeenLastCalledWith(input, 600);
  });

  it('réévalue la géométrie quand le resize arrive après didShow', async () => {
    await configurerClavier();
    montrerClavier();

    redimensionner(390, 590);
    vi.runAllTimers();
    expect(mocks.keepNativeFieldVisible).toHaveBeenLastCalledWith(input, 590);

    visualViewport.height = 580;
    visualViewport.dispatchEvent(new Event('resize'));
    vi.runAllTimers();
    expect(mocks.keepNativeFieldVisible).toHaveBeenLastCalledWith(input, 580);
  });

  it('Android installe les listeners sans appeler le réglage UNIMPLEMENTED', async () => {
    mocks.getPlatform.mockReturnValue('android');
    mocks.setResizeMode.mockRejectedValue({ code: 'UNIMPLEMENTED' });
    await configurerClavier();
    expect(mocks.setResizeMode).not.toHaveBeenCalled();
    document.dispatchEvent(new FocusEvent('focusin'));
    vi.runAllTimers();
    expect(mocks.keepNativeFieldVisible).not.toHaveBeenCalled();
    montrerClavier();
    // La remise en vue dépend des événements natifs, sans classe CSS externe.
    expect(document.body.classList.contains('keyboard-is-open')).toBe(false);
    document.dispatchEvent(new FocusEvent('focusin'));
    vi.runAllTimers();
    expect(mocks.keepNativeFieldVisible).toHaveBeenCalledTimes(2);

    callbacks.get('keyboardWillHide')!({ keyboardHeight: 0 });
    document.body.classList.add('keyboard-is-open');
    document.dispatchEvent(new FocusEvent('focusin'));
    vi.runAllTimers();
    expect(mocks.keepNativeFieldVisible).toHaveBeenCalledTimes(2);
  });

  it('annule la remise en vue différée quand le clavier se ferme', async () => {
    await configurerClavier();
    montrerClavier();
    mocks.keepNativeFieldVisible.mockClear();

    document.dispatchEvent(new FocusEvent('focusin'));
    callbacks.get('keyboardWillHide')!({ keyboardHeight: 0 });
    redimensionner(390, 900);
    callbacks.get('keyboardDidHide')!({ keyboardHeight: 0 });
    vi.runAllTimers();

    expect(mocks.keepNativeFieldVisible).not.toHaveBeenCalled();
  });

  it.each([false, true])('conserve la référence après didHide reçu avant le resize de fermeture (rAF exécuté : %s)', async runHideFrame => {
    await configurerClavier();
    montrerClavier();
    redimensionner(390, 600);
    vi.runAllTimers();
    callbacks.get('keyboardWillHide')!({ keyboardHeight: 0 });
    callbacks.get('keyboardDidHide')!({ keyboardHeight: 0 });
    if (runHideFrame) vi.runAllTimers();
    callbacks.get('keyboardWillShow')!({ keyboardHeight: 300 });
    callbacks.get('keyboardDidShow')!({ keyboardHeight: 300 });
    vi.runAllTimers();

    expect(mocks.keepNativeFieldVisible).toHaveBeenLastCalledWith(input, 600);
  });

  it.each([800, 900])('conserve la référence pendant la restauration progressive du WebView jusqu’à %i', async restoredHeight => {
    await configurerClavier();
    montrerClavier();
    redimensionner(390, 600);
    vi.runAllTimers();
    callbacks.get('keyboardWillHide')!({ keyboardHeight: 0 });
    callbacks.get('keyboardDidHide')!({ keyboardHeight: 0 });
    redimensionner(390, 700);
    redimensionner(390, restoredHeight);
    vi.runAllTimers();

    montrerClavier();
  });

  it('un refus du réglage iOS ne supprime pas la remise en vue du champ', async () => {
    mocks.setResizeMode.mockRejectedValue(new Error('Réglage indisponible'));
    await configurerClavier();
    expect(mocks.setResizeMode).toHaveBeenCalledOnce();
    expect(focusListeners).toHaveLength(1);
    montrerClavier();
  });

  it('retire tous les handlers après une installation partielle, même avec une remise en vue en attente', async () => {
    mocks.addListener.mockImplementation(async (event: string, callback: Callback) => {
      if (event === 'keyboardDidHide') throw new Error('Plugin interrompu');
      const handle = { remove: vi.fn().mockResolvedValue(undefined) };
      handles.push(handle);
      if (event === 'keyboardWillShow' || event === 'keyboardDidShow') callback({ keyboardHeight: 300 });
      return handle;
    });
    await expect(configurerClavier()).resolves.toBeUndefined();
    expect(handles).toHaveLength(3);
    for (const handle of handles) expect(handle.remove).toHaveBeenCalledOnce();
    expect(document.removeEventListener).toHaveBeenCalledWith('focusin', focusListeners[0]);
    expect(window.removeEventListener).toHaveBeenCalledWith('resize', resizeListeners[0]);
    expect(visualViewport.removeEventListener).toHaveBeenCalledWith('resize', resizeListeners[0]);
    redimensionner(390, 600);
    document.dispatchEvent(new FocusEvent('focusin'));
    vi.runAllTimers();
    expect(mocks.keepNativeFieldVisible).not.toHaveBeenCalled();
  });

  it('un échec du nettoyage ne rejette pas la configuration lancée au démarrage', async () => {
    const remove = vi.fn().mockRejectedValue(new Error('Plugin déconnecté'));
    mocks.addListener.mockResolvedValueOnce({ remove }).mockRejectedValueOnce(new Error('Plugin interrompu'));
    await expect(configurerClavier()).resolves.toBeUndefined();
    expect(remove).toHaveBeenCalledOnce();
    expect(document.removeEventListener).toHaveBeenCalledWith('focusin', focusListeners[0]);
    expect(window.removeEventListener).toHaveBeenCalledWith('resize', resizeListeners[0]);
  });
});
