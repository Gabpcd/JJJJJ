import React, { createContext, useContext, useState, useCallback, useRef, useEffect, ReactNode } from 'react';
import { CheckCircle, XCircle, AlertTriangle, Info, X } from 'lucide-react';

type TypeNotification = 'succes' | 'erreur' | 'avertissement' | 'info';

interface Notification {
  id: string;
  type: TypeNotification;
  message: string;
  duree?: number;
}

interface NotificationContextType {
  afficherNotification: (n: Omit<Notification, 'id'>) => void;
}

const NotificationContext = createContext<NotificationContextType | null>(null);

const ICONS: Record<TypeNotification, React.ReactNode> = {
  succes: <CheckCircle className="h-5 w-5 text-success flex-shrink-0" />,
  erreur: <XCircle className="h-5 w-5 text-destructive flex-shrink-0" />,
  avertissement: <AlertTriangle className="h-5 w-5 text-warning flex-shrink-0" />,
  info: <Info className="h-5 w-5 text-info flex-shrink-0" />,
};

const BG_CLASSES: Record<TypeNotification, string> = {
  succes: 'bg-success/5 border-l-success',
  erreur: 'bg-destructive/5 border-l-destructive',
  avertissement: 'bg-warning/5 border-l-warning',
  info: 'bg-info/5 border-l-info',
};

export function NotificationProvider({ children }: { children: ReactNode }) {
  const [notifications, setNotifications] = useState<Notification[]>([]);
  const timersRef = useRef<Map<string, ReturnType<typeof setTimeout>>>(new Map());

  // Cleanup all timers on unmount
  useEffect(() => {
    return () => {
      timersRef.current.forEach(timer => clearTimeout(timer));
      timersRef.current.clear();
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
    const duree = n.duree || (n.type === 'erreur' ? 8000 : 5000);

    setNotifications(prev => {
      const next = [...prev, { ...n, id }];
      return next.slice(-3); // max 3
    });

    const timer = setTimeout(() => {
      retirer(id);
    }, duree);
    timersRef.current.set(id, timer);
  }, [retirer]);

  return (
    <NotificationContext.Provider value={{ afficherNotification }}>
      {children}
      {/* Toast container */}
      <div className="fixed top-4 right-4 left-4 md:left-auto md:w-96 z-[100] flex flex-col gap-2">
        {notifications.map((n) => (
          <div
            key={n.id}
            className={`animate-slide-in rounded-xl border-l-4 p-4 shadow-lg bg-card ${BG_CLASSES[n.type]} flex items-start gap-3`}
          >
            {ICONS[n.type]}
            <p className="text-sm text-foreground flex-1">{n.message}</p>
            <button onClick={() => retirer(n.id)} className="text-muted-foreground hover:text-foreground flex-shrink-0">
              <X className="h-4 w-4" />
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
