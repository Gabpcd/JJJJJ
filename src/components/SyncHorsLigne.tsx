import { useEffect, useRef } from 'react';
import { getPointagesEnAttente, sauvegarderPointagesRestants, PointageHorsLigne } from '@/lib/horsLigne';
import { supabase } from '@/integrations/supabase/client';
import { toast } from 'sonner';

export function SyncHorsLigne() {
  const syncing = useRef(false);

  const sync = async () => {
    if (syncing.current) return;
    const pointages = getPointagesEnAttente();
    if (pointages.length === 0) return;

    syncing.current = true;
    const echoues: PointageHorsLigne[] = [];
    let synced = 0;

    for (const p of pointages) {
      try {
        if (p.type === 'arrivee') {
          const { data, error } = await supabase.rpc('fn_pointer_arrivee' as any, {
            p_mission_id: p.missionId,
            p_lat: p.lat,
            p_lng: p.lng,
            p_precision: p.precision,
            p_terminal_id: p.idTerminal,
            p_modele: navigator.userAgent.slice(0, 100),
            p_code_arrivee: null,
          });
          if (error || (data as any)?.error || (data as any)?.success === false) throw error || new Error((data as any)?.error || 'Pointage refusé');
        } else {
          const { data, error } = await supabase.rpc('fn_pointer_depart' as any, {
            p_presence_id: p.presenceId || null,
            p_lat: p.lat,
            p_lng: p.lng,
            p_precision: p.precision,
            p_terminal_id: p.idTerminal,
            p_modele: navigator.userAgent.slice(0, 100),
            p_code_depart: null,
          });
          if (error || (data as any)?.error || (data as any)?.success === false) throw error || new Error((data as any)?.error || 'Pointage refusé');
        }
        synced++;
      } catch {
        echoues.push(p);
      }
    }

    // Only keep failed ones in localStorage
    sauvegarderPointagesRestants(echoues);

    if (synced > 0) {
      toast.success(
        `${synced} action${synced > 1 ? 's' : ''} synchronisée${synced > 1 ? 's' : ''}`,
        { description: echoues.length > 0
          ? `${echoues.length} action(s) en attente de réessai.`
          : 'Vos pointages hors-ligne ont été envoyés.' }
      );
    }
    syncing.current = false;
  };

  useEffect(() => {
    if (navigator.onLine) sync();

    const handleOnline = () => {
      setTimeout(sync, 1500);
    };

    window.addEventListener('online', handleOnline);
    return () => window.removeEventListener('online', handleOnline);
  }, []);

  return null;
}
