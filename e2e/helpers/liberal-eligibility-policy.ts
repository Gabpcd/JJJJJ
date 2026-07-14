export const PGRST202_FALLBACK_FLAG = 'E2E_ALLOW_PGRST202_ELIGIBILITY_FALLBACK';

type CiEnvironment = Readonly<Record<string, string | undefined>>;

/**
 * Le repli sur les colonnes historiques n'existe que pour une PR testée avant
 * le déploiement de sa migration. `main`, workflow_dispatch et les exécutions
 * locales doivent obligatoirement passer par la RPC canonique.
 */
export function isPgrst202EligibilityFallbackAllowed(
  env: CiEnvironment = process.env,
): boolean {
  const flag = env[PGRST202_FALLBACK_FLAG];
  if (flag === undefined || flag === '' || flag === 'false') return false;
  if (flag !== 'true') {
    throw new Error(`${PGRST202_FALLBACK_FLAG} doit valoir exactement "true" ou être absent.`);
  }
  if (env.GITHUB_EVENT_NAME !== 'pull_request' || env.GITHUB_BASE_REF !== 'main') {
    throw new Error(
      `${PGRST202_FALLBACK_FLAG}=true est interdit hors pull_request vers main.`,
    );
  }
  return true;
}
