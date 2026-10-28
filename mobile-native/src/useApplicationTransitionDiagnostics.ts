import { useEffect, useRef } from 'react';
import { Platform } from 'react-native';
import { useTransitionProgress } from 'react-native-screens';
import type { NativeStackScreenProps } from '@react-navigation/native-stack';
import type { NativeStackParams } from './ui/navigation';

const enabled = Platform.OS === 'ios' && process.env.EXPO_PUBLIC_JOLENE_MODE === 'demo'
  && process.env.EXPO_PUBLIC_JOLENE_NAVIGATION_DIAGNOSTICS === '1';
const MAX_TOTAL_EVENTS = 64;
const MAX_INSTANCE_EVENTS = 24;
let totalEvents = 0;
type Screen = 'Exploration/Candidature' | 'Suivi/Candidature' | 'Compte/Documents';
type Navigation = Pick<NativeStackScreenProps<NativeStackParams, 'Candidature'>['navigation'], 'addListener'>;
type Field = 'progress' | 'closing' | 'goingForward';
type Sample = { value: number; atMs: number };

/** Observe the existing native transition. Never drive an animation or navigation action. */
export function useApplicationTransitionDiagnostics(screen: Screen, navigation: Navigation) {
  // Every observed screen is rendered inside ScreenStackItem's native transition provider.
  const { progress, closing, goingForward } = useTransitionProgress();
  const startedAtMs = useRef(Date.now());
  const sequence = useRef(0);
  useEffect(() => {
    if (!enabled) return;
    const latest: Partial<Record<Field, Sample>> = {};
    let windowStartedAtMs = Date.now();
    let sampleCount = 0;
    let progressCount = 0;
    let minProgress: number | null = null;
    let maxProgress: number | null = null;
    const observe = (field: Field, value: number) => {
      if (!Number.isFinite(value) || value < 0 || value > 1) return;
      latest[field] = { value: Math.round(value * 1000) / 1000, atMs: Date.now() };
      sampleCount += 1;
      if (field === 'progress') {
        progressCount += 1;
        minProgress = Math.min(minProgress ?? value, value);
        maxProgress = Math.max(maxProgress ?? value, value);
      }
    };
    const report = (event: string) => {
      if (totalEvents >= MAX_TOTAL_EVENTS || sequence.current >= MAX_INSTANCE_EVENTS) return;
      totalEvents += 1;
      try {
        console.log('[jolene-native-transition]', JSON.stringify({
          sequence: ++sequence.current, startedAtMs: startedAtMs.current, atMs: Date.now(),
          screen, event, windowStartedAtMs, sampleCount, progressCount,
          minProgress, maxProgress, latest,
        }));
      } catch { /* Diagnostics cannot change the gesture's result. */ }
    };
    const progressID = progress.addListener(({ value }) => observe('progress', value));
    const closingID = closing.addListener(({ value }) => observe('closing', value));
    const forwardID = goingForward.addListener(({ value }) => observe('goingForward', value));
    const removeStart = navigation.addListener('transitionStart', ({ data }) => {
      windowStartedAtMs = Date.now();
      sampleCount = 0;
      progressCount = 0;
      minProgress = null;
      maxProgress = null;
      report(data.closing ? 'transitionStart:pop' : 'transitionStart:push');
    });
    const removeEnd = navigation.addListener('transitionEnd', ({ data }) => {
      report(data.closing ? 'transitionEnd:pop' : 'transitionEnd:push');
    });
    const removeCancel = navigation.addListener('gestureCancel', () => report('gestureCancel'));
    return () => {
      report('observerCleanup');
      removeStart();
      removeEnd();
      removeCancel();
      progress.removeListener(progressID);
      closing.removeListener(closingID);
      goingForward.removeListener(forwardID);
    };
  }, [screen, navigation, progress, closing, goingForward]);
}
