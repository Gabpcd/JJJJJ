export interface DocumentVisibility { active: boolean; revision: number }

/** Preserve the interruption even if React batches inactive → active into one render. */
export function advanceDocumentVisibility(previous: DocumentVisibility, active: boolean): DocumentVisibility {
  return active === previous.active ? previous : { active, revision: previous.revision + 1 };
}
