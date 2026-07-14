interface RpcClient {
  rpc: (
    functionName: string,
    params: Record<string, unknown>,
  ) => PromiseLike<{ data: unknown; error: { code?: string; message?: string } | null }>;
}

export type EstablishmentReviewService =
  | 'VERIFY_PIECE_IDENTITE_ETAB'
  | 'VERIFY_JUSTIFICATIF_FONCTION'
  | 'VERIFY_FINESS_RECOUPEMENT'
  | 'VERIFY_RIB_ETABLISSEMENT';

export async function openEstablishmentReview(
  admin: RpcClient,
  etablissementId: string,
  service: EstablishmentReviewService,
  motif: string,
  context: Record<string, unknown> = {},
): Promise<string> {
  const { data, error } = await admin.rpc(
    'fn_ouvrir_revue_verification_etablissement',
    {
      p_etablissement_id: etablissementId,
      p_service: service,
      p_motif: motif,
      p_donnees: context,
      p_priorite: 4,
    },
  );
  if (error) {
    throw new Error(`Ouverture revue impossible: ${error.code || error.message || 'UNKNOWN'}`);
  }
  const result = data && typeof data === 'object'
    ? data as Record<string, unknown>
    : {};
  if (result.success !== true || typeof result.revue_id !== 'string') {
    throw new Error('Ouverture revue non confirmee');
  }
  return result.revue_id;
}

export async function resolveEstablishmentReview(
  admin: RpcClient,
  etablissementId: string,
  service: EstablishmentReviewService,
): Promise<void> {
  const { error } = await admin.rpc(
    'fn_resoudre_revue_verification_etablissement',
    {
      p_etablissement_id: etablissementId,
      p_service: service,
    },
  );
  if (error) {
    // La preuve est valide ; une panne de nettoyage de la file ne doit pas
    // inverser ce verdict, mais elle reste visible dans les logs serveur.
    console.error('[establishment-review] resolution impossible', error.code || error.message);
  }
}
