import React, { useState, useEffect, useId, useRef } from 'react';
import { createPortal } from 'react-dom';
import { Bell, X, ExternalLink } from 'lucide-react';
import { useNavigate, useLocation } from 'react-router-dom';
import { useAuth } from '@/contexts/AuthContext';
import { useFluxNotifications, type NotificationItem } from '@/hooks/useFluxNotifications';
import { toast } from 'sonner';
import { formatDistanceToNow } from 'date-fns';
import { fr } from 'date-fns/locale';
import { normaliserLienJolene } from '@/lib/nativeLinks';

interface PanneauNotificationsProps {
  open: boolean;
  onClose: () => void;
  flux: ReturnType<typeof useFluxNotifications>;
}

export function PanneauNotifications({ open, onClose, flux }: PanneauNotificationsProps) {
  const navigate = useNavigate();
  const { notifications, loading, error, actualiser, marquerLues } = flux;
  const panelRef = useRef<HTMLDivElement>(null);
  const closeButtonRef = useRef<HTMLButtonElement>(null);
  const previousFocusRef = useRef<HTMLElement | null>(null);
  const onCloseRef = useRef(onClose);
  const titleId = useId();

  useEffect(() => {
    onCloseRef.current = onClose;
  }, [onClose]);

  useEffect(() => {
    if (!open) return;
    previousFocusRef.current = document.activeElement instanceof HTMLElement
      ? document.activeElement
      : null;
    const frame = window.requestAnimationFrame(() => closeButtonRef.current?.focus());
    const handleKeyDown = (event: KeyboardEvent) => {
      if (event.key === 'Escape') {
        event.preventDefault();
        onCloseRef.current();
        return;
      }
      if (event.key !== 'Tab') return;
      const panel = panelRef.current;
      if (!panel) return;
      const focusables = Array.from(panel.querySelectorAll<HTMLElement>(
        'a[href], button:not([disabled]), input:not([disabled]), select:not([disabled]), textarea:not([disabled]), [tabindex]:not([tabindex="-1"])',
      ));
      if (focusables.length === 0) {
        event.preventDefault();
        panel.focus();
        return;
      }
      const first = focusables[0];
      const last = focusables[focusables.length - 1];
      if (!panel.contains(document.activeElement)) {
        event.preventDefault();
        first.focus();
      } else if (event.shiftKey && document.activeElement === first) {
        event.preventDefault();
        last.focus();
      } else if (!event.shiftKey && document.activeElement === last) {
        event.preventDefault();
        first.focus();
      }
    };
    document.addEventListener('keydown', handleKeyDown);
    return () => {
      window.cancelAnimationFrame(frame);
      document.removeEventListener('keydown', handleKeyDown);
      previousFocusRef.current?.focus();
    };
  }, [open]);

  useEffect(() => {
    if (open) void actualiser();
  }, [open, actualiser]);

  const marquerToutLu = async () => {
    const ids = notifications.filter(n => !n.lue).map(n => n.id);
    if (ids.length && await marquerLues(ids) === false) {
      toast.error('Impossible de marquer les notifications comme lues');
    }
  };

  const handleClick = (n: NotificationItem) => {
    const route = n.lien ? normaliserLienJolene(n.lien) : null;
    if (n.lien && !route) {
      toast.error('Lien non autorisé');
    }

    if (!n.lue) {
      void marquerLues([n.id])?.then(success => {
        if (success === false) toast.error('Impossible de marquer cette notification comme lue');
      });
    }

    if (route) {
      onClose();
      navigate(route);
    }
  };

  if (!open) return null;

  return createPortal(
    <>
      <div className="fixed inset-0 bg-foreground/30 z-[70]" onClick={onClose} aria-hidden="true" />
      <div
        ref={panelRef}
        role="dialog"
        aria-modal="true"
        aria-labelledby={titleId}
        tabIndex={-1}
        className="fixed right-0 top-0 bottom-0 !max-h-none w-full max-w-md !p-0 bg-card shadow-2xl z-[70] flex flex-col animate-slide-in"
      >
        <div
          className="flex items-center justify-between p-4 border-b border-border"
          style={{ paddingTop: 'calc(env(safe-area-inset-top) + 1rem)' }}
        >
          <h2 id={titleId} className="text-lg font-bold text-foreground">Notifications</h2>
          <div className="flex items-center gap-2">
            <button
              type="button"
              onClick={marquerToutLu}
              disabled={!notifications.some((notification) => !notification.lue)}
              className="min-h-[44px] rounded-lg px-2 text-xs text-primary font-medium hover:underline disabled:cursor-not-allowed disabled:opacity-50"
            >
              Tout marquer comme lu
            </button>
            <button
              ref={closeButtonRef}
              type="button"
              onClick={onClose}
              aria-label="Fermer les notifications"
              className="inline-flex min-h-[44px] min-w-[44px] items-center justify-center rounded-lg text-muted-foreground hover:bg-muted hover:text-foreground"
            >
              <X className="h-5 w-5" aria-hidden="true" />
            </button>
          </div>
        </div>
        <div
          className="flex-1 overflow-y-auto"
          aria-busy={loading}
          style={{ paddingBottom: 'env(safe-area-inset-bottom)' }}
        >
          {error && (
            <div className="p-4 text-sm" role="alert">
              <p>{error}</p>
              <button type="button" onClick={() => void actualiser()} disabled={loading}
                className="mt-2 min-h-[44px] rounded-lg px-3 font-medium text-primary hover:underline disabled:opacity-50">
                Réessayer
              </button>
            </div>
          )}
          {loading && <div className="p-4 text-center text-muted-foreground text-sm" role="status">Actualisation...</div>}
          {notifications.length === 0 && !loading && !error ? (
            <div className="p-8 text-center text-muted-foreground text-sm">Aucune notification</div>
          ) : (
            <div className="divide-y divide-border">
              {notifications.map(n => (
                <button
                  key={n.id}
                  type="button"
                  onClick={() => handleClick(n)}
                  className={`w-full text-left p-4 hover:bg-accent/50 transition-colors ${!n.lue ? 'bg-primary/5 border-l-4 border-l-primary' : ''}`}
                >
                  <div className="flex items-start justify-between gap-2">
                    <div className="flex items-center gap-2">
                      <div className={`h-2 w-2 rounded-full shrink-0 ${!n.lue ? 'bg-destructive' : 'bg-muted-foreground/30'}`} />
                      <span className="text-sm font-semibold text-foreground">{n.titre}</span>
                      {!n.lue && <span className="sr-only">Non lue</span>}
                    </div>
                    <time dateTime={n.cree_le} className="text-[10px] text-muted-foreground whitespace-nowrap">
                      {formatDistanceToNow(new Date(n.cree_le), { addSuffix: true, locale: fr })}
                    </time>
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
  // Une nouvelle identité ne doit jamais afficher l'état ni reprendre les callbacks du compte précédent.
  return <BadgeNotificationCompte key={user?.id ?? 'anonyme'} userId={user?.id} />;
}

function BadgeNotificationCompte({ userId }: { userId: string | undefined }) {
  const location = useLocation();
  const buttonRef = useRef<HTMLButtonElement>(null);
  const [open, setOpen] = useState(false);
  const [bouncing, setBouncing] = useState(false);
  const [soundEnabled, setSoundEnabled] = useState(() => {
    try { return localStorage.getItem('notif_sound') !== 'off'; } catch { return true; }
  });

  // Persist sound preference
  useEffect(() => {
    try { localStorage.setItem('notif_sound', soundEnabled ? 'on' : 'off'); } catch { /* stockage indisponible (Safari privé) — préférence non persistée */ }
  }, [soundEnabled]);

  const flux = useFluxNotifications(userId, n => {
    // Les en-têtes mobile et desktop sont montés ensemble ; seul le visible alerte.
    if (!buttonRef.current?.getClientRects().length) return;
    setBouncing(true);
    setTimeout(() => setBouncing(false), 350);
    if (document.visibilityState === 'visible' && soundEnabled) playNotifSound();
    toast.info(n.titre, { description: n.corps?.substring(0, 80) });
    if (document.visibilityState !== 'visible' && 'Notification' in window && Notification.permission === 'granted') {
      const notification = new Notification(n.titre || 'Nouveau message', { body: n.corps || '' });
      notification.onclick = () => {
        window.focus();
        const route = n.lien ? normaliserLienJolene(n.lien) : null;
        if (route) window.location.href = route;
        notification.close();
      };
    }
  });
  const { count, error, marquerLues } = flux;
  useEffect(() => {
    if (userId && location.pathname.endsWith('/notifications')) void marquerLues();
  }, [location.pathname, userId, marquerLues]);

  return (
    <>
      <button
        ref={buttonRef}
        onClick={() => setOpen(true)}
        aria-label={`${count > 0 ? `Notifications, ${count} non lue${count > 1 ? 's' : ''}` : 'Notifications'}${error ? ', actualisation nécessaire' : ''}`}
        aria-haspopup="dialog"
        aria-expanded={open}
        className="relative inline-flex min-h-[44px] min-w-[44px] items-center justify-center text-sidebar-foreground/70 hover:text-sidebar-foreground transition-colors p-2"
      >
        <Bell className="h-5 w-5" aria-hidden="true" />
        {error && <span aria-hidden="true" className="absolute -right-1 -bottom-1 text-destructive font-bold">!</span>}
        {count > 0 && (
          <span className={`absolute -top-0.5 -right-0.5 h-[18px] min-w-[18px] flex items-center justify-center rounded-full bg-[#EF4444] text-white text-[10px] font-bold px-1 leading-none ${bouncing ? 'animate-bounce-badge' : ''}`}>
            {count > 9 ? '9+' : count}
          </span>
        )}
      </button>
      <PanneauNotifications
        open={open}
        onClose={() => setOpen(false)}
        flux={flux}
      />
    </>
  );
}
