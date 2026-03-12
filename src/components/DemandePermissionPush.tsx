import React, { useState, useEffect } from 'react';
import { Bell, X } from 'lucide-react';
import { useAuth } from '@/contexts/AuthContext';
import { supabase } from '@/integrations/supabase/client';
import { demanderPermissionPush } from '@/lib/firebase';
import { useNotification } from '@/contexts/NotificationContext';

const STORAGE_KEY = 'push_permission_asked';

export function DemandePermissionPush() {
  const [visible, setVisible] = useState(false);
  const { user } = useAuth();
  const { afficherNotification } = useNotification();

  useEffect(() => {
    if (!user) return;
    if (localStorage.getItem(STORAGE_KEY)) return;
    if (!('Notification' in window)) return;
    if (Notification.permission === 'granted') return;

    const timer = setTimeout(() => setVisible(true), 5000);
    return () => clearTimeout(timer);
  }, [user]);

  const handleActiver = async () => {
    if (!user) return;
    localStorage.setItem(STORAGE_KEY, 'accepted');
    setVisible(false);
    try {
      const token = await demanderPermissionPush(user.id, supabase);
      if (token) {
        afficherNotification({ type: 'succes', message: 'Alertes push activées !' });
      }
    } catch {
      afficherNotification({ type: 'erreur', message: 'Impossible d\'activer les notifications.' });
    }
  };

  const handlePlusTard = () => {
    localStorage.setItem(STORAGE_KEY, 'later');
    setVisible(false);
  };

  if (!visible) return null;

  return (
    <div className="fixed bottom-6 right-6 z-50 max-w-sm animate-in slide-in-from-bottom-4 fade-in duration-500">
      <div className="bg-card border border-border rounded-2xl shadow-2xl p-5 relative">
        <button
          onClick={handlePlusTard}
          className="absolute top-3 right-3 text-muted-foreground hover:text-foreground transition-colors"
          aria-label="Fermer"
        >
          <X className="h-4 w-4" />
        </button>

        <div className="flex items-start gap-3 mb-4">
          <div className="flex-shrink-0 w-10 h-10 rounded-full bg-primary/10 flex items-center justify-center">
            <Bell className="h-5 w-5 text-primary" />
          </div>
          <div>
            <h3 className="font-semibold text-foreground text-sm">
              🔔 Recevoir les alertes ?
            </h3>
            <p className="text-muted-foreground text-xs mt-1 leading-relaxed">
              Soyez prévenu(e) instantanément quand une mission urgente est publiée.
            </p>
          </div>
        </div>

        <div className="flex gap-2">
          <button
            onClick={handleActiver}
            className="flex-1 px-4 py-2 rounded-lg text-sm font-medium text-white transition-colors"
            style={{ backgroundColor: 'hsl(174, 62%, 38%)' }}
          >
            Activer les alertes
          </button>
          <button
            onClick={handlePlusTard}
            className="flex-1 px-4 py-2 rounded-lg text-sm font-medium bg-secondary text-secondary-foreground hover:bg-secondary/80 transition-colors"
          >
            Plus tard
          </button>
        </div>
      </div>
    </div>
  );
}
