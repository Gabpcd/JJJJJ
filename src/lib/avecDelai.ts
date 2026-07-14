export class ErreurDelaiDepasse extends Error {
  constructor(message = 'Le délai de réponse a été dépassé') {
    super(message);
    this.name = 'ErreurDelaiDepasse';
  }
}

/** Borne une opération distante sans laisser son minuteur survivre à la réponse. */
export async function avecDelai<T>(
  operation: PromiseLike<T>,
  delaiMs: number,
  message?: string,
): Promise<T> {
  let minuteur: ReturnType<typeof setTimeout> | undefined;
  try {
    return await Promise.race([
      Promise.resolve(operation),
      new Promise<never>((_, reject) => {
        minuteur = setTimeout(
          () => reject(new ErreurDelaiDepasse(message)),
          delaiMs,
        );
      }),
    ]);
  } finally {
    if (minuteur !== undefined) clearTimeout(minuteur);
  }
}
