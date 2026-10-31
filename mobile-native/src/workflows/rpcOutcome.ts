export type DefiniteTransactionRollbackCode = '40P01' | '40001' | '57014';

/** Only explicit PostgreSQL error replies from a transactional PostgREST RPC.
 * Never apply this to transport exceptions or a local abort: their outcome is unknown.
 * https://docs.postgrest.org/en/stable/references/transactions.html#aborting-transactions
 */
export function isDefiniteTransactionRollback(code: unknown): code is DefiniteTransactionRollbackCode {
  return code === '40P01' || code === '40001' || code === '57014';
}
