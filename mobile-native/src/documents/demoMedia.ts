import type { DocumentMediaScope, ManagedDocumentMediaAdapter } from '../media/documents/types';
import { DocumentMediaError, type DocumentSelection } from '../ui/documents/adapters';
import { createDemoDocumentFile } from '../workflows/documents/demoFixture';
import { createDemoDocumentChoices, createDemoDocumentScenarioMedia } from '../workflows/documents/demoScenario';
import type { DemoDocumentSession } from '../workflows/documents/demoGateway';

/** No OS picker, camera, personal file, network, or pretend original viewer in demonstration. */
export function createDemoDocumentMedia(input: {
  scope: DocumentMediaScope;
  currentSession: () => DemoDocumentSession | null;
  scenario: boolean;
}): ManagedDocumentMediaAdapter {
  let disposed = false;
  let sequence = 0;
  const selections = new Set<DocumentSelection>();
  const current = (signal?: AbortSignal) => {
    const session = input.currentSession();
    if (signal?.aborted || disposed || session?.userId !== input.scope.userId || session.epoch !== input.scope.epoch) {
      throw Object.assign(new Error('La sélection fictive a été annulée.'), { name: 'AbortError' });
    }
  };
  const scripted = input.scenario ? createDemoDocumentScenarioMedia({
    identity: input.scope, currentSession: input.currentSession, choices: createDemoDocumentChoices(),
  }) : null;
  return {
    sources: ['file'],
    async prepare() { current(); },
    async pick(source, signal) {
      current(signal);
      if (source !== 'file') throw new DocumentMediaError('UNAVAILABLE', 'La démonstration fournit seulement un fichier fictif.');
      const selected = scripted ? await scripted.pick(source, signal)
        : { file: createDemoDocumentFile(`document-fictif-demo-${++sequence}.png`) };
      try { current(signal); } catch (error) { selected?.file.bytes.fill(0); throw error; }
      if (selected) selections.add(selected);
      return selected;
    },
    async release(selection) {
      if (selections.delete(selection)) selection.file.bytes.fill(0);
    },
    async dispose() {
      disposed = true;
      selections.forEach(selection => selection.file.bytes.fill(0));
      selections.clear();
    },
  };
}
