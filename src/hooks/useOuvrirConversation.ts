import { useNavigate } from 'react-router-dom';
import { supabase } from '@/integrations/supabase/client';
import { toast } from 'sonner';

/**
 * Resolves an établissement record ID to the managing user's auth.users ID.
 * Returns null if resolution fails.
 */
export async function resoudreUserIdEtablissement(etablissementId: string): Promise<string | null> {
  const { data, error } = await supabase.rpc('fn_user_id_pour_etablissement' as any, { p_etablissement_id: etablissementId });
  if (error || !data) {
    console.error('fn_user_id_pour_etablissement error:', error);
    return null;
  }
  return data as string;
}

/**
 * Returns a function that opens/creates a conversation with another user
 * and navigates to the messaging page.
 * 
 * If isEtablissement is true, resolves the établissement record ID to user ID first.
 */
export function useOuvrirConversation(baseRoute: string) {
  const navigate = useNavigate();

  const ouvrir = async (autreId: string, missionId?: string, isEtablissement?: boolean) => {
    let userId = autreId;

    if (isEtablissement) {
      const resolved = await resoudreUserIdEtablissement(autreId);
      if (!resolved) {
        toast.error("Impossible de trouver l'interlocuteur de l'établissement.");
        return;
      }
      userId = resolved;
    }

    const { data, error } = await supabase.rpc('fn_obtenir_conversation', {
      p_autre_id: userId,
      p_mission_id: missionId ?? null,
    });

    if (error || !data) {
      toast.error("Impossible d'ouvrir la conversation.");
      console.error('fn_obtenir_conversation error:', error);
      return;
    }

    navigate(`${baseRoute}?conv=${data}`);
  };

  return ouvrir;
}
