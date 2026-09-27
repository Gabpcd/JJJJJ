import { supabase } from '@/integrations/supabase/client';
import { avecDelai } from '@/lib/avecDelai';

/** Une réponse HTTP 2xx peut aussi signaler un envoi ignoré ou encore en cours. */
export async function envoyerEmailConfirme(body: Record<string, unknown>, cle: string): Promise<void> {
  const { data, error } = await avecDelai(supabase.functions.invoke('send-email', {
    body: { ...body, idempotency_key: cle },
  }), 15_000);
  if (error || data?.success !== true || data?.pending
    || (data?.skipped && data.reason !== 'idempotency_already_sent')) {
    throw new Error("L'envoi de cet email n'a pas été confirmé. Vous pouvez réessayer.");
  }
}
