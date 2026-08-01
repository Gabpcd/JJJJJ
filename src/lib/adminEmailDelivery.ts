export type EmailDeliveryStatus = 'sent' | 'skipped' | 'pending' | 'failed';

type EdgeEmailPayload = {
  success?: boolean;
  skipped?: boolean;
  test_skipped?: boolean;
  pending?: boolean;
  error?: unknown;
};

/**
 * Classifie explicitement le retour de send-email.
 * Un HTTP 2xx sans `success: true` n'est jamais considéré comme un envoi.
 */
export function getEmailDeliveryStatus(
  data: unknown,
  error: unknown,
): EmailDeliveryStatus {
  if (error || !data || typeof data !== 'object') return 'failed';

  const payload = data as EdgeEmailPayload;
  if (payload.error || payload.success === false) return 'failed';
  if (payload.skipped || payload.test_skipped) return 'skipped';
  if (payload.pending) return 'pending';
  return payload.success === true ? 'sent' : 'failed';
}
