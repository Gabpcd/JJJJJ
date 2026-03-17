import { useNavigate } from 'react-router-dom';
import { supabase } from '@/integrations/supabase/client';
import { toast } from 'sonner';

/**
 * Returns a function that opens/creates a conversation with another user
 * and navigates to the messaging page.
 */
export function useOuvrirConversation(baseRoute: string) {
  const navigate = useNavigate();

  const ouvrir = async (autreId: string, missionId?: string) => {
    const { data, error } = await supabase.rpc('fn_obtenir_conversation', {
      p_autre_id: autreId,
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
