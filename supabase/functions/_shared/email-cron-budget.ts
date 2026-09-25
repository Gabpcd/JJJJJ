/** Bornes conservatrices : 30 appels Edge imbriqués/trace et pg_net à 55 s.
 * La cadence du scheduler écoule plusieurs petits lots, jamais un fan-out illimité.
 */
export function configurationDebitEmail(lire: (cle: string) => string | undefined) {
  const entier = (cle: string, defaut: number, min: number, max: number) => {
    const raw = lire(cle);
    const valeur = raw?.trim() ? Number(raw) : NaN;
    return Number.isInteger(valeur) ? Math.min(max, Math.max(min, valeur)) : defaut;
  };
  return {
    queue: entier('EMAIL_CRON_QUEUE_BATCH_SIZE', 20, 1, 20),
    onboarding: entier('EMAIL_CRON_ONBOARDING_BATCH_SIZE', 5, 1, 5),
    budgetMs: entier('EMAIL_CRON_BUDGET_MS', 40_000, 5_000, 40_000),
  };
}

export function creerBudgetEnvoi(
  debut: number,
  budgetMs: number,
  maintenant: () => number = Date.now,
  attendre: (ms: number) => Promise<void> = ms => new Promise(resolve => setTimeout(resolve, ms)),
) {
  const fin = debut + budgetMs;
  let appels = 0;
  let prochain = debut;
  const peutCommencer = () => appels < 25 && Math.max(maintenant(), prochain) < fin - 1_000;
  return {
    peutCommencer,
    get appels() { return appels; },
    async reserver(): Promise<number | null> {
      if (!peutCommencer()) return null;
      const delai = Math.max(0, prochain - maintenant());
      if (delai) await attendre(delai);
      if (!peutCommencer()) return null;
      appels++;
      prochain = maintenant() + 600;
      return Math.min(8_000, Math.max(1, fin - maintenant()));
    },
  };
}
export type BudgetEnvoi = ReturnType<typeof creerBudgetEnvoi>;

/** Un délai client ne prouve pas l'échec du fournisseur. Rejouer la même clé
 * permettra d'acquitter l'envoi s'il a fini après l'annulation HTTP locale.
 */
export function transportInterrompu(erreur: unknown): boolean {
  if (!erreur || typeof erreur !== 'object') return false;
  const e = erreur as { name?: unknown; context?: { name?: unknown } };
  return e.name === 'AbortError' || e.name === 'TimeoutError'
    || (e.name === 'FunctionsFetchError'
      && (e.context?.name === 'AbortError' || e.context?.name === 'TimeoutError'));
}
