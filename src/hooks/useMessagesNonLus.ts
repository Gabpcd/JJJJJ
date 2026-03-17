import { useState, useEffect } from 'react';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/contexts/AuthContext';

export function useMessagesNonLus() {
  const { user } = useAuth();
  const [count, setCount] = useState(0);

  useEffect(() => {
    if (!user) return;

    const load = async () => {
      const { data, error } = await supabase.rpc('fn_messages_non_lus');
      if (!error && typeof data === 'number') setCount(data);
    };
    load();

    // Realtime: listen for new messages_chat inserts
    const channel = supabase
      .channel('unread-messages-global')
      .on('postgres_changes', {
        event: 'INSERT',
        schema: 'public',
        table: 'messages_chat',
      }, (payload) => {
        const msg = payload.new as any;
        // If the message is not from me, increment
        if (msg.auteur_id !== user.id) {
          setCount(prev => prev + 1);
        }
      })
      .subscribe();

    return () => { supabase.removeChannel(channel); };
  }, [user]);

  const decrement = (n = 1) => setCount(prev => Math.max(0, prev - n));
  const refresh = async () => {
    const { data } = await supabase.rpc('fn_messages_non_lus');
    if (typeof data === 'number') setCount(data);
  };

  return { count, decrement, refresh };
}
