import { supabase } from '@/integrations/supabase/client';

export interface InterlocuteurConversation {
  conversation_id: string;
  participant_id: string;
  prenom: string;
  nom: string;
  avatar_url: string | null;
  est_jolene: boolean;
}

export function cleInterlocuteur(conversationId: string, participantId: string): string {
  return `${conversationId}:${participantId}`;
}

export function indexerInterlocuteurs(
  lignes: InterlocuteurConversation[],
): Map<string, InterlocuteurConversation> {
  return new Map(
    lignes.map((ligne) => [
      cleInterlocuteur(ligne.conversation_id, ligne.participant_id),
      ligne,
    ]),
  );
}

export async function chargerInterlocuteursConversations(
  conversationIds: string[],
): Promise<Map<string, InterlocuteurConversation>> {
  const ids = [...new Set(conversationIds)].slice(0, 100);
  if (ids.length === 0) return new Map();

  const { data, error } = await supabase.rpc('fn_interlocuteurs_conversations', {
    p_conversation_ids: ids,
  });

  if (error) throw error;
  return indexerInterlocuteurs((data || []) as InterlocuteurConversation[]);
}
