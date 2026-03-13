import { useEffect, useRef } from 'react';
import { getPointagesEnAttente, clearPointagesEnAttente, PointageHorsLigne } from '@/lib/horsLigne';
import { supabase } from '@/integrations/supabase/client';
import { toast } from '@/hooks/use-toast';

export function SyncHorsLigne() {
  const syncing = useRef(false);

  const sync = async () => {
    if (syncing.current) return;
    const pointages = getPointagesEnAttente();
    if (pointages.length === 0) return;

    syncing.current = true;
    let synced = 0;

    for (const p of pointages) {
      try {
        if (p.type === 'arrivee') {
          await supabase.rpc('fn_pointer_arrivee' as any, {
            p_mission_id: p.missionId,
            p_lat: p.lat,
            p_lng: p.lng,
            p_precision_m: p.precision,
            p_id_terminal: p.idTerminal,
          });
        } else {
          await supabase.rpc('fn_pointer_depart' as any, {
            p_presence_id: p.presenceId || null,
            p_lat: p.lat,
            p_lng: p.lng,
            p_precision_m: p.precision,
            p_id_terminal: p.idTerminal,
          });
        }
        synced++;
      } catch {
        // keep going, failed ones will be retried
      }
    }

    if (synced > 0) {
      clearPointagesEnAttente();
      toast({
        title: `✅ ${synced} action${synced > 1 ? 's' : ''} synchronisée${synced > 1 ? 's' : ''}`,
        description: 'Vos pointages hors-ligne ont été envoyés.',
      });
    }
    syncing.current = false;
  };

  useEffect(() => {
    // Sync on mount if online
    if (navigator.onLine) sync();

    const handleOnline = () => {
      setTimeout(sync, 1500); // small delay to let network stabilize
    };

    window.addEventListener('online', handleOnline);
    return () => window.removeEventListener('online', handleOnline);
  }, []);

  return null;
}
