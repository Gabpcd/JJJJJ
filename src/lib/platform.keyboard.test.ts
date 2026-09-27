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
let input: HTMLInputElement;

beforeEach(() => {
  vi.useFakeTimers();
  vi.resetAllMocks();
  callbacks = new Map();
  handles = [];
  focusListeners = [];
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
  vi.spyOn(window, 'innerHeight', 'get').mockReturnValue(900);
  vi.spyOn(window, 'requestAnimationFrame').mockImplementation(callback =>
    window.setTimeout(() => callback(0), 0));
  const add = document.addEventListener.bind(document);
  vi.spyOn(document, 'addEventListener').mockImplementation((event, listener, options) => {
    if (event === 'focusin') focusListeners.push(listener);
    add(event, listener, options);
  });
});

afterEach(() => {
  for (const listener of focusListeners) document.removeEventListener('focusin', listener);
  document.body.classList.remove('keyboard-is-open');
  vi.clearAllTimers();
  vi.useRealTimers();
  vi.restoreAllMocks();
});

function montrerClavier() {
  callbacks.get('keyboardDidShow')!({ keyboardHeight: 300 });
  vi.runAllTimers();
  expect(mocks.keepNativeFieldVisible).toHaveBeenLastCalledWith(input, 600);
}

describe('configuration du clavier natif par plateforme', () => {
  it('laisse le navigateur sans réglage ni listener natif', async () => {
    mocks.isNative.mockReturnValue(false);
    await configurerClavier();
    expect(mocks.setResizeMode).not.toHaveBeenCalled();
    expect(mocks.addListener).not.toHaveBeenCalled();
    expect(focusListeners).toHaveLength(0);
  });

  it('conserve le resize Native iOS et recalcule le viewport après fermeture', async () => {
    await configurerClavier();
    expect(mocks.setResizeMode).toHaveBeenCalledExactlyOnceWith({ mode: 'native' });
    expect([...callbacks.keys()]).toEqual(['keyboardDidShow', 'keyboardDidHide']);
    montrerClavier();
    // Le prochain show doit utiliser la hauteur restaurée.
    vi.spyOn(window, 'innerHeight', 'get').mockReturnValue(1000);
    callbacks.get('keyboardDidHide')!({ keyboardHeight: 0 });
    vi.runAllTimers();
    callbacks.get('keyboardDidShow')!({ keyboardHeight: 300 });
    vi.runAllTimers();
    expect(mocks.keepNativeFieldVisible).toHaveBeenLastCalledWith(input, 700);
  });

  it('Android installe les listeners sans appeler le réglage UNIMPLEMENTED', async () => {
    mocks.getPlatform.mockReturnValue('android');
    mocks.setResizeMode.mockRejectedValue({ code: 'UNIMPLEMENTED' });
    await configurerClavier();
    expect(mocks.setResizeMode).not.toHaveBeenCalled();
    expect([...callbacks.keys()]).toEqual(['keyboardDidShow', 'keyboardDidHide']);
    montrerClavier();
    document.body.classList.add('keyboard-is-open');
    document.dispatchEvent(new FocusEvent('focusin'));
    vi.runAllTimers();
    expect(mocks.keepNativeFieldVisible).toHaveBeenCalledTimes(2);
  });

  it('un refus du réglage iOS ne supprime pas la remise en vue du champ', async () => {
    mocks.setResizeMode.mockRejectedValue(new Error('Réglage indisponible'));
    await configurerClavier();
    expect(mocks.setResizeMode).toHaveBeenCalledOnce();
    expect(focusListeners).toHaveLength(1);
    montrerClavier();
  });

  it('retire le premier listener si le second ne peut pas être installé', async () => {
    mocks.addListener.mockImplementationOnce(async (_event: string, callback: Callback) => {
      const handle = { remove: vi.fn().mockResolvedValue(undefined) };
      handles.push(handle);
      callback({ keyboardHeight: 300 }); // Un événement peut précéder la fin du montage.
      return handle;
    }).mockRejectedValueOnce(new Error('Plugin interrompu'));
    await expect(configurerClavier()).resolves.toBeUndefined();
    expect(handles[0].remove).toHaveBeenCalledOnce();
    expect(focusListeners).toHaveLength(0);
    vi.runAllTimers();
    expect(mocks.keepNativeFieldVisible).not.toHaveBeenCalled();
  });

  it('un échec du nettoyage ne rejette pas la configuration lancée au démarrage', async () => {
    const remove = vi.fn().mockRejectedValue(new Error('Plugin déconnecté'));
    mocks.addListener.mockResolvedValueOnce({ remove }).mockRejectedValueOnce(new Error('Plugin interrompu'));
    await expect(configurerClavier()).resolves.toBeUndefined();
    expect(remove).toHaveBeenCalledOnce();
    expect(focusListeners).toHaveLength(0);
  });
});
