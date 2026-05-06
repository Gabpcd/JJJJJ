import { useState, useEffect } from 'react';
import { Bell, X } from 'lucide-react';
import { useAuth } from '@/contexts/AuthContext';
import { supabase } from '@/integrations/supabase/client';
import { useNotification } from '@/contexts/NotificationContext';
import { Capacitor } from '@capacitor/core';
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogDescription,
} from '@/components/ui/dialog';

const STORAGE_KEY = 'push_permission_asked';

export function DemandePermissionPush() {
  const [visible, setVisible] = useState(false);
  const { user } = useAuth();
  const { afficherNotification } = useNotification();

  useEffect(() => {
    if (!user) return;
    if (localStorage.getItem(STORAGE_KEY)) return;

    // On native, push is handled via initNativePush after login
    if (Capacitor.isNativePlatform()) return;

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
      const { demanderPermissionPush } = await import('@/lib/firebase');
      const token = await demanderPermissionPush(user.id, supabase as any);
      if (token) {
        afficherNotification({ type: 'succes', message: 'Alertes push activées !' });
      }
    } catch {
      afficherNotification({ type: 'erreur', message: "Impossible d'activer les notifications." });
    }
  };

  const handlePlusTard = () => {
    localStorage.setItem(STORAGE_KEY, 'later');
    setVisible(false);
  };

  if (!visible) return null;

  return (
    <Dialog open={visible} onOpenChange={(open) => { if (!open) handlePlusTard(); }}>
      <DialogContent className="sm:max-w-md">
        <DialogHeader>
          <div className="mx-auto w-12 h-12 rounded-full bg-primary/10 flex items-center justify-center mb-2">
            <Bell className="h-6 w-6 text-primary" />
          </div>
          <DialogTitle className="text-center text-lg">
            Recevoir les alertes missions ?
          </DialogTitle>
          <DialogDescription className="text-center text-sm text-muted-foreground leading-relaxed">
            Jolene vous envoie des notifications pour les nouvelles missions,
            les rappels de pointage et les mises à jour de vos contrats.
          </DialogDescription>
        </DialogHeader>

        <div className="space-y-3 pt-2">
          <div className="bg-muted/50 border border-border rounded-xl p-3 text-xs text-muted-foreground space-y-1">
            <p>✅ Nouvelles missions correspondant à votre profil</p>
            <p>✅ Rappels de pointage avant vos missions</p>
            <p>✅ Mises à jour de contrats et paiements</p>
            <p className="text-muted-foreground/70 italic mt-2">
              Vous pouvez désactiver les notifications à tout moment depuis les réglages de votre téléphone.
            </p>
          </div>

          <div className="flex gap-3">
            <button
              onClick={handlePlusTard}
              className="flex-1 min-h-[44px] px-4 py-2.5 rounded-lg text-sm font-medium bg-secondary text-secondary-foreground hover:bg-secondary/80 transition-colors"
            >
              Plus tard
            </button>
            <button
              onClick={handleActiver}
              className="flex-1 min-h-[44px] px-4 py-2.5 rounded-lg text-sm font-medium bg-primary text-primary-foreground hover:bg-primary/90 transition-colors"
            >
              Activer les notifications
            </button>
          </div>
        </div>
      </DialogContent>
    </Dialog>
  );
}
