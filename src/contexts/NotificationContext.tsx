import React, { createContext, useContext, useState, useCallback, useRef, useEffect, ReactNode } from 'react';
import { CheckCircle, XCircle, AlertTriangle, Info, X } from 'lucide-react';

type TypeNotification = 'succes' | 'erreur' | 'avertissement' | 'info';

/**
 * Hiérarchie durées Sprint 8 PR 3 (chantier 3.3) :
 * - info : 3000ms (lecture rapide)
 * - succes : 4000ms (confirmation)
 * - avertissement : 5000ms (action peut être nécessaire)
 * - erreur : 7000ms (lecture obligatoire, action probable)
 *
 * Override via `duree` explicite (utile pour notifications longues avec CTA).
 */
const DUREES_PAR_DEFAUT: Record<TypeNotification, number> = {
  info: 3000,
  succes: 4000,
  avertissement: 5000,
  erreur: 7000,
};

type ActionNotification = {
  label: string;
  onClick: () => void;
};

interface Notification {
  id: string;
  type: TypeNotification;
  message: string;
  duree?: number;
  action?: ActionNotification;
}

interface NotificationContextType {
  afficherNotification: (n: Omit<Notification, 'id'>) => void;
}

const NotificationContext = createContext<NotificationContextType | null>(null);

const ICONS: Record<TypeNotification, React.ReactNode> = {
  succes: <CheckCircle className="h-5 w-5 text-success flex-shrink-0" aria-hidden="true" />,
  erreur: <XCircle className="h-5 w-5 text-destructive flex-shrink-0" aria-hidden="true" />,
  avertissement: <AlertTriangle className="h-5 w-5 text-warning flex-shrink-0" aria-hidden="true" />,
  info: <Info className="h-5 w-5 text-info flex-shrink-0" aria-hidden="true" />,
};

const BG_CLASSES: Record<TypeNotification, string> = {
  succes: 'bg-success/5 border-l-success',
  erreur: 'bg-destructive/5 border-l-destructive',
  avertissement: 'bg-warning/5 border-l-warning',
  info: 'bg-info/5 border-l-info',
};

const LIBELLES_TYPE: Record<TypeNotification, string> = {
  succes: 'Succès',
  erreur: 'Erreur',
  avertissement: 'Avertissement',
  info: 'Information',
};

export function NotificationProvider({ children }: { children: ReactNode }) {
  const [notifications, setNotifications] = useState<Notification[]>([]);
  const timersRef = useRef<Map<string, ReturnType<typeof setTimeout>>>(new Map());

  useEffect(() => {
    const timers = timersRef.current;
    return () => {
      timers.forEach(timer => clearTimeout(timer));
      timers.clear();
    };
  }, []);

  const retirer = useCallback((id: string) => {
    setNotifications(prev => prev.filter(n => n.id !== id));
    const timer = timersRef.current.get(id);
    if (timer) {
      clearTimeout(timer);
      timersRef.current.delete(id);
    }
  }, []);

  const afficherNotification = useCallback((n: Omit<Notification, 'id'>) => {
    const id = crypto.randomUUID();
    const duree = n.duree ?? DUREES_PAR_DEFAUT[n.type];

    setNotifications(prev => {
      const next = [...prev, { ...n, id }];
      return next.slice(-3); // max 3 simultanés
    });

    const timer = setTimeout(() => {
      retirer(id);
    }, duree);
    timersRef.current.set(id, timer);
  }, [retirer]);

  return (
    <NotificationContext.Provider value={{ afficherNotification }}>
      {children}
      {/*
        Position responsive Sprint 8 PR 3 (chantier 3.2) :
        - Mobile (< 768px) : bottom-center, AU-DESSUS de la bottom-nav.
          9.5 — la bottom-nav mesure 4rem + safe-area-inset-bottom ; on place le
          toast à 5rem + safe-area pour dégager la nav même sur les appareils à
          grande safe-area (l'ancien `bottom-20` = 5rem sec pouvait chevaucher).
        - Desktop : bottom-right, hors de la zone des KPI et CTA du haut de page.
      */}
      <div
        role="region"
        className="pointer-events-none fixed z-[100] flex flex-col gap-2 inset-x-4 bottom-[calc(5rem+env(safe-area-inset-bottom))] md:bottom-4 md:right-4 md:left-auto md:w-96"
        aria-live="polite"
        aria-label="Notifications"
        data-toast-safe-zone="bottom"
      >
        {notifications.map((n) => (
          <div
            key={n.id}
            role={n.type === 'erreur' ? 'alert' : 'status'}
            data-notification-type={n.type}
            className={`pointer-events-auto animate-slide-in rounded-xl border-l-4 p-4 shadow-lg bg-card ${BG_CLASSES[n.type]} flex items-start gap-3`}
          >
            {ICONS[n.type]}
            <div className="flex-1 min-w-0">
              <span className="sr-only">{LIBELLES_TYPE[n.type]} : </span>
              <p className="text-sm text-foreground break-words">{n.message}</p>
              {n.action && (
                <button
                  type="button"
                  onClick={() => {
                    n.action!.onClick();
                    retirer(n.id);
                  }}
                  className="mt-2 text-sm font-semibold text-primary hover:underline focus:outline-none focus-visible:ring-2 focus-visible:ring-primary rounded"
                >
                  {n.action.label}
                </button>
              )}
            </div>
            <button
              type="button"
              onClick={() => retirer(n.id)}
              aria-label="Fermer la notification"
              className="text-muted-foreground hover:text-foreground flex-shrink-0 min-h-[24px] min-w-[24px] flex items-center justify-center rounded focus:outline-none focus-visible:ring-2 focus-visible:ring-primary"
            >
              <X className="h-4 w-4" aria-hidden="true" />
            </button>
          </div>
        ))}
      </div>
    </NotificationContext.Provider>
  );
}

export function useNotification() {
  const ctx = useContext(NotificationContext);
  if (!ctx) throw new Error('useNotification must be used within NotificationProvider');
  return ctx;
}
