type ReponseLecture = { status?: number; error: unknown };

/** Une seule reprise d'une lecture idempotente après une coupure de transport.
 * Ne jamais utiliser pour une mutation : l'absence de réponse ne prouve pas
 * que le serveur n'a pas exécuté l'opération.
 */
export async function relancerLectureReseau<T extends ReponseLecture>(
  lire: () => PromiseLike<T>,
  estToujoursActive: () => boolean,
): Promise<T> {
  const reponse = await lire();
  const erreur = reponse.error;
  const message = erreur && typeof erreur === 'object' && 'message' in erreur
    ? String(erreur.message)
    : '';
  // PostgREST réserve status=0 aux échecs sans réponse HTTP. Les erreurs
  // d'autorisation, SQL, métier et les annulations ne sont pas relancées.
  if (reponse.status !== 0
    || !/^(?:TypeError: )?(?:Load failed|Failed to fetch|NetworkError when attempting to fetch resource\.?)$/.test(message)
    || !estToujoursActive()) return reponse;

  await new Promise(resolve => setTimeout(resolve, 300));
  return estToujoursActive() ? lire() : reponse;
}
