import { supabase } from '@/integrations/supabase/client';

export type DetectedType = 'TELEPHONE' | 'EMAIL' | 'URL' | 'HANDLE' | 'KEYWORD';

export interface ResultatEnvoiMessage {
  success: boolean;
  messageId?: string;
  error?: string;
  detectedType?: DetectedType;
  transportError?: unknown;
}

interface PayloadEdge {
  success?: boolean;
  message_id?: string;
  error?: string;
  detected_type?: DetectedType;
}

async function lirePayloadErreur(error: unknown): Promise<PayloadEdge | null> {
  const context = (error as { context?: unknown } | null)?.context;
  if (!context) return null;

  if (typeof Response !== 'undefined' && context instanceof Response) {
    try {
      return await context.clone().json() as PayloadEdge;
    } catch {
      return null;
    }
  }

  const body = (context as { body?: unknown }).body;
  if (body && typeof body === 'object') return body as PayloadEdge;
  if (typeof body === 'string') {
    try {
      return JSON.parse(body) as PayloadEdge;
    } catch {
      return null;
    }
  }
  return null;
}

/**
 * Valide et insère le message dans une seule opération serveur. Le frontend ne
 * possède volontairement aucune voie RPC directe vers messages_chat.
 */
export async function envoyerMessageAvecAntiFuite(
  conversationId: string,
  contenu: string,
): Promise<ResultatEnvoiMessage> {
  const { data, error } = await supabase.functions.invoke('messagerie-validate', {
    body: { conversation_id: conversationId, content: contenu },
  });
  const payload = (data && typeof data === 'object' ? data : null) as PayloadEdge | null;

  if (error) {
    const payloadErreur = await lirePayloadErreur(error);
    const detail = payloadErreur || payload;
    return {
      success: false,
      error: detail?.error || 'VALIDATION_INDISPONIBLE',
      detectedType: detail?.detected_type,
      transportError: error,
    };
  }

  const messageId = typeof payload?.message_id === 'string'
    && payload.message_id.length > 0
    ? payload.message_id
    : undefined;
  return {
    success: payload?.success === true && messageId !== undefined,
    messageId,
    error: payload?.error || (payload?.success === true && messageId === undefined
      ? 'REPONSE_ENVOI_INVALIDE'
      : undefined),
    detectedType: payload?.detected_type,
  };
}
