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
  const ids = [...new Set(conversationIds)];
  if (ids.length === 0) return new Map();

  const resultat = new Map<string, InterlocuteurConversation>();
  for (let index = 0; index < ids.length; index += 100) {
    const lot = ids.slice(index, index + 100);
    const { data, error } = await supabase.rpc('fn_interlocuteurs_conversations', {
      p_conversation_ids: lot,
    });

    if (error) throw error;
    indexerInterlocuteurs((data || []) as InterlocuteurConversation[])
      .forEach((valeur, cle) => resultat.set(cle, valeur));
  }
  return resultat;
}
