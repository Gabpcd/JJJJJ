import { DocumentMediaError, type DocumentMediaAdapter, type DocumentSource } from '../../ui/documents/adapters';
import { createDemoDocumentFile } from './demoFixture';
import type { DemoDocumentOutcome, DemoDocumentSession } from './demoGateway';
import type { NativeDocumentFile } from './types';

/** Explicitly opt-in for the separate UI scenario; never used by the TEST runtime. */
export const DEMO_DOCUMENT_SCENARIO_OUTCOMES: readonly DemoDocumentOutcome[] = [
  { userId: 'demo-soignant', typeDocument: 'RCP_ASSURANCE', kind: 'uncertain_committed' },
];
export type DemoDocumentChoice = { kind: 'file'; file: NativeDocumentFile } | { kind: 'cancel' }
  | { kind: 'error'; code: 'PERMISSION_DENIED' | 'UNAVAILABLE' | 'INVALID_FILE'; message: string };

export function createDemoDocumentChoices(): DemoDocumentChoice[] {
  return [
    { kind: 'file', file: createDemoDocumentFile('remplacement-annule-demo.png') },
    { kind: 'file', file: createDemoDocumentFile('diplome-remplace-demo.png') },
    { kind: 'file', file: createDemoDocumentFile('rcp-incertaine-demo.png') },
  ];
}

/**
 * A deterministic file-selection adapter for the explicitly named demo scenario.
 * It does not open or simulate OS permissions/camera. No open() => no inactive viewer button.
 */
export function createDemoDocumentScenarioMedia(input: {
  identity: DemoDocumentSession; currentSession: () => DemoDocumentSession | null;
  choices: readonly DemoDocumentChoice[];
}): DocumentMediaAdapter {
  const owner = { userId: input.identity.userId, epoch: input.identity.epoch };
  const choices = input.choices.map(choice => choice.kind === 'file'
    ? { ...choice, file: { ...choice.file, bytes: new Uint8Array(choice.file.bytes) } } : { ...choice });
  const current = (signal: AbortSignal) => {
    if (signal.aborted) { const error = new Error('Sélection fictive annulée.'); error.name = 'AbortError'; throw error; }
    const session = input.currentSession();
    if (!session || session.userId !== owner.userId || session.epoch !== owner.epoch) {
      throw new DocumentMediaError('UNAVAILABLE', 'Le compte de démonstration a changé.');
    }
  };
  return {
    sources: ['file'],
    async pick(source: DocumentSource, signal: AbortSignal) {
      current(signal);
      if (source !== 'file') throw new DocumentMediaError('UNAVAILABLE', 'Ce scénario fournit seulement des fichiers fictifs.');
      const choice = choices.shift();
      if (!choice) throw new DocumentMediaError('UNAVAILABLE', 'Les sélections de ce scénario fictif sont terminées.');
      if (choice.kind === 'cancel') return null;
      if (choice.kind === 'error') throw new DocumentMediaError(choice.code, choice.message);
      return { file: { ...choice.file, bytes: new Uint8Array(choice.file.bytes) } };
    },
  };
}
