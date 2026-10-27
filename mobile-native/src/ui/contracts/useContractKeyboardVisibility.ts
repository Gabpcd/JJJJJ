import { useCallback, useEffect, useRef } from 'react';
import { Keyboard, Platform, type KeyboardMetrics, ScrollView, TextInput, View } from 'react-native';

// Layout spacing, not a keyboard/device-height estimate.
const FIELD_CLEARANCE = 12;

/** iOS automatic insets follow the caret. Keep the whole OTP field and, when
 * space permits, its explicit signing action above the measured keyboard. */
export function useContractKeyboardVisibility() {
  const scrollRef = useRef<ScrollView>(null);
  // RN 0.86 types innerViewRef as RefObject<View>; the initial null is checked
  // before every measurement, as are the ordinary nullable native refs below.
  const contentRef = useRef<View>(null!);
  const inputRef = useRef<TextInput>(null);
  const signatureRef = useRef<View>(null);
  const keyboard = useRef<KeyboardMetrics | undefined>(Keyboard.metrics());
  const frame = useRef<number | null>(null);
  const generation = useRef(0);

  const cancel = useCallback(() => {
    generation.current += 1;
    if (frame.current !== null) cancelAnimationFrame(frame.current);
    frame.current = null;
  }, []);

  const reveal = useCallback(() => {
    if (Platform.OS !== 'ios') return;
    cancel();
    const request = generation.current;
    frame.current = requestAnimationFrame(() => {
      frame.current = null;
      const scroll = scrollRef.current;
      const viewport = scroll?.getNativeScrollRef();
      const content = contentRef.current;
      const input = inputRef.current;
      const signature = signatureRef.current;
      const metrics = keyboard.current;
      const current = () => generation.current === request && inputRef.current === input && input?.isFocused();
      if (!scroll || !viewport || !content || !input || !signature || !metrics || metrics.height <= 0 || !current()) return;
      // RCTKeyboardObserver converts endCoordinates to the current UIWindow;
      // measureInWindow uses that same coordinate space, including stack headers.
      viewport.measureInWindow((_sx, sy, _sw, sh) => {
        if (!current() || sh <= 0) return;
        input.measureLayout(content, (ix, iy, iw, ih) => {
          if (!current() || ih <= 0) return;
          const visibleBottom = Math.min(sy + sh, metrics.screenY) - FIELD_CLEARANCE;
          const visibleTop = sy + FIELD_CLEARANCE;
          // A floating keyboard can leave too little room above it. Do not move
          // an entire field into a gap that cannot contain it.
          if (visibleBottom - visibleTop < ih) return;
          signature.measureLayout(content, (_gx, gy, _gw, gh) => {
            if (!current()) return;
            // A small landscape viewport may fit the field but not both controls.
            const wholeGroupFits = gh > 0 && gh <= visibleBottom - visibleTop;
            const targetTop = wholeGroupFits ? gy : iy;
            const targetBottom = wholeGroupFits ? gy + gh : iy + ih;
            content.measureInWindow((cx, cy) => {
              if (!current()) return;
              const overlapsHorizontally = cx + ix < metrics.screenX + metrics.width && cx + ix + iw > metrics.screenX;
              const belowFloatingKeyboard = cy + targetTop >= metrics.screenY + metrics.height;
              if (!overlapsHorizontally || belowFloatingKeyboard || cy + targetBottom <= visibleBottom) return;
              // Absolute content-space target: duplicate notifications converge,
              // without adding a delta to an asynchronously delivered onScroll.
              // Clamp so a very tall field is not clipped at its top instead.
              const target = Math.max(0, Math.min(targetBottom - (visibleBottom - sy), targetTop - FIELD_CLEARANCE));
              scroll.scrollTo({ y: target, animated: true });
            });
          }, () => {});
        }, () => {});
      });
    });
  }, [cancel]);

  useEffect(() => {
    if (Platform.OS !== 'ios') return;
    const shown = Keyboard.addListener('keyboardDidShow', event => {
      keyboard.current = event.endCoordinates; reveal();
    });
    const changed = Keyboard.addListener('keyboardDidChangeFrame', event => {
      keyboard.current = event.endCoordinates; reveal();
    });
    const hidden = Keyboard.addListener('keyboardDidHide', () => {
      keyboard.current = undefined; cancel();
    });
    return () => { shown.remove(); changed.remove(); hidden.remove(); cancel(); };
  }, [cancel, reveal]);

  return { scrollRef, contentRef, inputRef, signatureRef, reveal, cancel };
}
