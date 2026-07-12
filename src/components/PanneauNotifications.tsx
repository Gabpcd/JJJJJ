import React, { useState, useEffect, useRef } from 'react';
import { createPortal } from 'react-dom';
import { Bell, X, Check, ExternalLink } from 'lucide-react';
import { useNavigate, useLocation } from 'react-router-dom';
import { useAuth } from '@/contexts/AuthContext';
import { supabase } from '@/integrations/supabase/client';
import { toast } from 'sonner';
import { formatDistanceToNow } from 'date-fns';
import { fr } from 'date-fns/locale';
import { normaliserLienJolene } from '@/lib/nativeLinks';

interface NotificationItem {
  id: string;
  titre: string;
  corps: string;
  type: string;
  lue: boolean;
  lien: string | null;
  cree_le: string;
}

interface PanneauNotificationsProps {
  open: boolean;
  onClose: () => void;
}

export function PanneauNotifications({ open, onClose }: PanneauNotificationsProps) {
  const { user } = useAuth();
  const navigate = useNavigate();
  const [notifications, setNotifications] = useState<NotificationItem[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (!user || !open) return;
    const load = async () => {
      const { data } = await supabase
        .from('notifications')
        .select('id, titre, corps, type, lue, lien, cree_le')
        .eq('destinataire_id', user.id)
        .order('cree_le', { ascending: false })
        .limit(50);
      setNotifications((data as unknown as NotificationItem[]) || []);
      setLoading(false);
    };
    load();
  }, [user, open]);

  // Realtime
  useEffect(() => {
    if (!user) return;
    const channel = supabase
      .channel('notifications-realtime')
      .on('postgres_changes', {
        event: 'INSERT',
        schema: 'public',
        table: 'notifications',
        filter: `destinataire_id=eq.${user.id}`,
      }, (payload) => {
        setNotifications(prev => [payload.new as NotificationItem, ...prev]);
      })
      .subscribe();
    return () => { supabase.removeChannel(channel); };
  }, [user]);

  const marquerToutLu = async () => {
    if (!user) return;
    const ids = notifications.filter(n => !n.lue).map(n => n.id);
    if (ids.length === 0) return;
    await supabase.from('notifications').update({ lue: true, lue_le: new Date().toISOString() } as any).in('id', ids);
    setNotifications(prev => prev.map(n => ({ ...n, lue: true })));
  };

  const handleClick = async (n: NotificationItem) => {
    if (!n.lue) {
      await supabase.from('notifications').update({ lue: true, lue_le: new Date().toISOString() } as any).eq('id', n.id);
      setNotifications(prev => prev.map(x => x.id === n.id ? { ...x, lue: true } : x));
    }
    if (n.lien) {
      const route = normaliserLienJolene(n.lien);
      if (route) {
        onClose();
        navigate(route);
      } else {
        toast.error('Lien non autorisé');
      }
    }
  };

  if (!open) return null;

  return createPortal(
    <>
      <div className="fixed inset-0 bg-foreground/30 z-[70]" onClick={onClose} />
      <div className="fixed right-0 top-0 bottom-0 w-full max-w-md bg-card shadow-2xl z-[70] flex flex-col animate-slide-in">
        <div
          className="flex items-center justify-between p-4 border-b border-border"
          style={{ paddingTop: 'calc(env(safe-area-inset-top) + 1rem)' }}
        >
          <h2 className="text-lg font-bold text-foreground">Notifications</h2>
          <div className="flex items-center gap-2">
            <button onClick={marquerToutLu} className="text-xs text-primary font-medium hover:underline">Tout marquer comme lu</button>
            <button onClick={onClose} className="text-muted-foreground hover:text-foreground"><X className="h-5 w-5" /></button>
          </div>
        </div>
        <div className="flex-1 overflow-y-auto">
          {loading ? (
            <div className="p-8 text-center text-muted-foreground text-sm">Chargement...</div>
          ) : notifications.length === 0 ? (
            <div className="p-8 text-center text-muted-foreground text-sm">Aucune notification</div>
          ) : (
            <div className="divide-y divide-border">
              {notifications.map(n => (
                <button
                  key={n.id}
                  onClick={() => handleClick(n)}
                  className={`w-full text-left p-4 hover:bg-accent/50 transition-colors ${!n.lue ? 'bg-primary/5 border-l-4 border-l-primary' : ''}`}
                >
                  <div className="flex items-start justify-between gap-2">
                    <div className="flex items-center gap-2">
                      <div className={`h-2 w-2 rounded-full shrink-0 ${!n.lue ? 'bg-destructive' : 'bg-muted-foreground/30'}`} />
                      <span className="text-sm font-semibold text-foreground">{n.titre}</span>
                    </div>
                    <span className="text-[10px] text-muted-foreground whitespace-nowrap">
                      {formatDistanceToNow(new Date(n.cree_le), { addSuffix: true, locale: fr })}
                    </span>
                  </div>
                  <p className="text-xs text-muted-foreground mt-1 ml-4">{n.corps}</p>
                  {n.lien && normaliserLienJolene(n.lien) && <span className="text-[10px] text-primary ml-4 mt-1 inline-flex items-center gap-1">Voir <ExternalLink className="h-2.5 w-2.5" /></span>}
                </button>
              ))}
            </div>
          )}
        </div>
      </div>
    </>,
    document.body
  );
}

function playNotifSound() {
  try {
    const ctx = new AudioContext();
    const osc = ctx.createOscillator();
    const gain = ctx.createGain();
    osc.connect(gain);
    gain.connect(ctx.destination);
    osc.frequency.value = 880;
    osc.type = 'sine';
    gain.gain.setValueAtTime(0.15, ctx.currentTime);
    gain.gain.exponentialRampToValueAtTime(0.001, ctx.currentTime + 0.15);
    osc.start(ctx.currentTime);
    osc.stop(ctx.currentTime + 0.15);
    setTimeout(() => ctx.close(), 300);
  } catch { /* silence errors */ }
}

export function BadgeNotification() {
  const { user } = useAuth();
  
  const location = useLocation();
  const [count, setCount] = useState(0);
  const [open, setOpen] = useState(false);
  const [bouncing, setBouncing] = useState(false);
  const [soundEnabled, setSoundEnabled] = useState(() => {
    try { return localStorage.getItem('notif_sound') !== 'off'; } catch { return true; }
  });

  // Persist sound preference
  useEffect(() => {
    try { localStorage.setItem('notif_sound', soundEnabled ? 'on' : 'off'); } catch { /* stockage indisponible (Safari privé) — préférence non persistée */ }
  }, [soundEnabled]);

  // Load count + realtime
  useEffect(() => {
    if (!user) return;
    const load = async () => {
      const { count: c } = await supabase
        .from('notifications')
        .select('id', { count: 'exact', head: true })
        .eq('destinataire_id', user.id)
        .eq('lue', false);
      setCount(c || 0);
    };
    load();

    const channel = supabase
      .channel('notif-count')
      .on('postgres_changes', {
        event: 'INSERT',
        schema: 'public',
        table: 'notifications',
        filter: `destinataire_id=eq.${user.id}`,
      }, (payload) => {
        setCount(prev => prev + 1);
        setBouncing(true);
        setTimeout(() => setBouncing(false), 350);
        if (document.visibilityState === 'visible' && soundEnabled) {
          playNotifSound();
        }
        const n = payload.new as any;
        toast.info(n.titre, { description: n.corps?.substring(0, 80) });
        if (document.visibilityState !== 'visible' && typeof window !== 'undefined' && 'Notification' in window && Notification.permission === 'granted') {
          const notification = new Notification(n.titre || 'Nouveau message', {
            body: n.corps || '',
          });
          notification.onclick = () => {
            window.focus();
            const route = typeof n.lien === 'string' ? normaliserLienJolene(n.lien) : null;
            if (route) {
              window.location.href = route;
            }
            notification.close();
          };
        }
      })
      .subscribe();
    return () => { supabase.removeChannel(channel); };
  }, [user, soundEnabled]);

  // Reset count when visiting /notifications
  useEffect(() => {
    if (!user) return;
    if (location.pathname.endsWith('/notifications')) {
      setCount(0);
      supabase
        .from('notifications')
        .update({ lue: true, lue_le: new Date().toISOString() } as any)
        .eq('destinataire_id', user.id)
        .eq('lue', false)
        .then();
    }
  }, [location.pathname, user]);

  return (
    <>
      <button
        onClick={() => setOpen(true)}
        aria-label={count > 0 ? `Notifications, ${count} non lue${count > 1 ? 's' : ''}` : 'Notifications'}
        aria-haspopup="dialog"
        aria-expanded={open}
        className="relative text-sidebar-foreground/70 hover:text-sidebar-foreground transition-colors p-2"
      >
        <Bell className="h-5 w-5" aria-hidden="true" />
        {count > 0 && (
          <span className={`absolute -top-0.5 -right-0.5 h-[18px] min-w-[18px] flex items-center justify-center rounded-full bg-[#EF4444] text-white text-[10px] font-bold px-1 leading-none ${bouncing ? 'animate-bounce-badge' : ''}`}>
            {count > 9 ? '9+' : count}
          </span>
        )}
      </button>
      <PanneauNotifications open={open} onClose={() => { setOpen(false); setCount(0); }} />
    </>
  );
}
