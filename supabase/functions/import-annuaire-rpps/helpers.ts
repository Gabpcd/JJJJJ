const MOTIFS_ERREUR_REPRENABLE = [
  "statement timeout",
  "connection reset",
  "error sending request",
  "error reading a body from connection",
  "unexpected eof",
  "end of file before message length",
  "connection closed before message completed",
  "telechargement annuaire sante impossible",
  "téléchargement annuaire santé impossible",
  "abort",
] as const;

/** Les coupures de transport sont rejouées depuis la dernière tranche validée. */
export function erreurRppsReprenable(message: string): boolean {
  const messageNormalise = message.toLowerCase();
  return MOTIFS_ERREUR_REPRENABLE.some((motif) =>
    messageNormalise.includes(motif)
  );
}

/**
 * Une exécution ancienne ne doit pas publier son état après qu'une exécution
 * plus récente a démarré. Les données importées restent idempotentes, mais le
 * bandeau de supervision doit représenter le run le plus récent.
 */
export function peutPublierStatutSource(
  runId: string | null,
  runLePlusRecentId: string | null,
): boolean {
  if (!runId || !runLePlusRecentId) return true;
  return runId === runLePlusRecentId;
}
