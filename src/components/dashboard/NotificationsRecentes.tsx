import React, { useEffect, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { Bell, ArrowRight, Circle } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/contexts/AuthContext';
import { format } from 'date-fns';
import { fr } from 'date-fns/locale';
import { normaliserLienJolene } from '@/lib/nativeLinks';

interface Notif {
  id: string;
  type: string;
  titre: string;
  corps: string | null;
  lien: string | null;
  lue: boolean;
  cree_le: string;
}

export function NotificationsRecentes() {
  const navigate = useNavigate();
  const { user } = useAuth();
  const [items, setItems] = useState<Notif[]>([]);
  const [loading, setLoading] = useState(true);

  const charger = async () => {
    if (!user) return;
    setLoading(true);
    const { data } = await supabase
      .from('notifications')
      .select('id, type, titre, corps, lien, lue, cree_le')
      .eq('destinataire_id', user.id)
      .order('cree_le', { ascending: false })
      .limit(5);
    setItems((data ?? []) as Notif[]);
    setLoading(false);
  };

  useEffect(() => { charger(); }, [user?.id]);

  const ouvrir = async (n: Notif) => {
    if (!n.lue) {
      await supabase.from('notifications').update({ lue: true, lue_le: new Date().toISOString() }).eq('id', n.id);
    }
    const route = n.lien ? normaliserLienJolene(n.lien) : null;
    if (route) navigate(route);
  };

  if (loading || items.length === 0) return null;

  return (
    <div className="card-base mb-6">
      <div className="flex items-center justify-between mb-3">
        <h2 className="text-base font-bold text-foreground inline-flex items-center gap-2">
          <Bell className="h-4 w-4 text-primary" /> Notifications récentes
        </h2>
        <button
          type="button"
          onClick={() => navigate('/soignant/notifications')}
          className="text-xs text-primary hover:underline inline-flex items-center gap-1"
        >
          Tout voir <ArrowRight className="h-3 w-3" />
        </button>
      </div>
      <div className="space-y-1">
        {items.map((n) => (
          <button
            key={n.id}
            type="button"
            onClick={() => ouvrir(n)}
            className={`w-full text-left rounded-xl p-2.5 transition-colors hover:bg-muted/50 ${n.lue ? '' : 'bg-primary/5'}`}
          >
            <div className="flex items-start gap-2">
              <Circle className={`h-2 w-2 mt-1.5 shrink-0 ${n.lue ? 'text-muted-foreground/30' : 'text-primary fill-primary'}`} />
              <div className="flex-1 min-w-0">
                <p className="text-sm font-medium text-foreground truncate">{n.titre}</p>
                {n.corps && <p className="text-xs text-muted-foreground line-clamp-1 mt-0.5">{n.corps}</p>}
              </div>
              <span className="text-[10px] text-muted-foreground shrink-0 mt-0.5">
                {format(new Date(n.cree_le), 'd MMM', { locale: fr })}
              </span>
            </div>
          </button>
        ))}
      </div>
    </div>
  );
}
