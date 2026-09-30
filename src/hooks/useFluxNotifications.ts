import { useCallback, useEffect, useId, useRef, useState } from 'react';
import { supabase } from '@/integrations/supabase/client';

export interface NotificationItem {
  id: string;
  titre: string;
  corps: string;
  type: string;
  lue: boolean;
  lien: string | null;
  cree_le: string;
}

const etatInitial = { notifications: [] as NotificationItem[], count: 0, loading: true, error: null as string | null };
// Signaux de relecture locaux, sans données partagées entre comptes.
const lecteursParCompte = new Map<string, Set<() => Promise<void>>>();

const erreurLecture = 'Impossible d’actualiser les notifications. Les dernières données affichées sont conservées.';

/** Liste et compteur relus ensemble ; aucun événement ancien n'est transformé en alerte. */
export function useFluxNotifications(userId: string | undefined, onLiveInsert: (notification: NotificationItem) => void) {
  const channelId = useId();
  const [etat, setEtat] = useState(etatInitial);
  const onLiveRef = useRef(onLiveInsert);
  onLiveRef.current = onLiveInsert;
  const controller = useRef<{
    refresh: () => Promise<void>;
    markRead: (ids?: string[]) => Promise<boolean | undefined>;
  } | null>(null);

  useEffect(() => {
    setEtat(etatInitial);
    if (!userId) {
      setEtat({ ...etatInitial, loading: false });
      return;
    }
    let active = true;
    let version = 0;
    let subscribed = false;
    let liveReady = false;
    const seen = new Set<string>();
    const remember = (id: string) => {
      seen.add(id);
      if (seen.size > 1000) seen.delete(seen.values().next().value!);
    };
    const refresh = async () => {
      if (!active) return;
      const request = ++version;
      setEtat(prev => ({ ...prev, loading: true }));
      try {
        const [liste, compteur] = await Promise.all([
          supabase.from('notifications')
            .select('id, titre, corps, type, lue, lien, cree_le')
            .eq('destinataire_id', userId).order('cree_le', { ascending: false }).limit(50),
          supabase.from('notifications').select('id', { count: 'exact', head: true })
            .eq('destinataire_id', userId).eq('lue', false),
        ]);
        if (!active || request !== version) return;
        if (liste.error || compteur.error || compteur.count === null) throw new Error('lecture');
        const notifications = [...new Map(((liste.data ?? []) as NotificationItem[]).map(n => [n.id, n])).values()];
        notifications.forEach(n => remember(n.id));
        liveReady = subscribed;
        setEtat({ notifications, count: compteur.count, loading: false, error: null });
      } catch {
        if (!active || request !== version) return;
        setEtat(prev => ({ ...prev, loading: false, error: erreurLecture }));
      }
    };
    const lecteurs = lecteursParCompte.get(userId) ?? new Set<() => Promise<void>>();
    lecteurs.add(refresh);
    lecteursParCompte.set(userId, lecteurs);
    controller.current = {
      refresh,
      markRead: async ids => {
        if (!active || ids?.length === 0) return;
        try {
          let query = supabase.from('notifications')
            .update({ lue: true, lue_le: new Date().toISOString() })
            .eq('destinataire_id', userId);
          query = ids ? query.in('id', ids) : query.eq('lue', false);
          const { error } = await query;
          if (!active) return;
          if (error) return false;
          // Mobile et desktop sont montés ensemble : chacun doit relire la mutation.
          await Promise.all([...lecteurs].map(actualiser => actualiser()));
          return active ? true : undefined;
        } catch { return active ? false : undefined; }
      },
    };
    const channel = supabase.channel(`notifications:${userId}:${channelId}`)
      .on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'notifications', filter: `destinataire_id=eq.${userId}` }, payload => {
        if (!active || payload.new.destinataire_id !== userId || typeof payload.new.id !== 'string') return;
        const notification = payload.new as NotificationItem;
        if (seen.has(notification.id)) return;
        remember(notification.id);
        if (liveReady) onLiveRef.current(notification);
        // Une lecture commencée avant cet INSERT ne doit jamais écraser le nouvel état.
        void refresh();
      })
      .subscribe(status => {
        if (!active) return;
        liveReady = false;
        subscribed = status === 'SUBSCRIBED';
        if (subscribed) {
          // Aussi à la première souscription : couvre l'intervalle lecture → connexion.
          void refresh();
        } else {
          version += 1;
          setEtat(prev => ({ ...prev, loading: false, error: 'Connexion aux notifications interrompue. Réessayez pour actualiser la liste.' }));
        }
      });
    void refresh();
    return () => {
      active = false;
      version += 1;
      controller.current = null;
      lecteurs.delete(refresh);
      if (lecteurs.size === 0) lecteursParCompte.delete(userId);
      void supabase.removeChannel(channel);
    };
  }, [userId, channelId]);

  const actualiser = useCallback(() => controller.current?.refresh(), []);
  const marquerLues = useCallback((ids?: string[]) => controller.current?.markRead(ids), []);
  return { ...etat, actualiser, marquerLues };
}
