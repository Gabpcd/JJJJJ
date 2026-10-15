import { useCallback, useEffect, useId, useRef, useState } from 'react';
import { Capacitor } from '@capacitor/core';
import { App } from '@capacitor/app';
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

type RealtimeStatus = 'connecting' | 'reconnecting' | 'SUBSCRIBED' | 'CHANNEL_ERROR' | 'TIMED_OUT' | 'CLOSED';
const etatInitial = {
  notifications: [] as NotificationItem[], count: 0, hasLoaded: false, loading: true,
  readError: null as string | null, realtimeStatus: 'connecting' as RealtimeStatus,
};
// Signaux de relecture locaux, sans données partagées entre comptes.
const lecteursParCompte = new Map<string, Set<() => Promise<void>>>();
const erreurLecture = 'Impossible d’actualiser les notifications. Les dernières données affichées sont conservées.';
const erreurConnexion = 'Connexion aux notifications interrompue. Réessayez pour actualiser la liste.';
const delaiLecture = 15_000;
const intervalleReprise = 5_000;

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
    // Une coupure du flux ne rend pas périmée une lecture HTTP en cours.
    let versionLecture = 0;
    let versionCanal = 0;
    let channel: ReturnType<typeof supabase.channel> | undefined;
    let lecture: AbortController | undefined;
    let subscribed = false;
    let statut: RealtimeStatus = 'connecting';
    let liveReady = false;
    let nativeForeground: boolean | undefined;
    let repriseTimer: ReturnType<typeof setTimeout> | undefined;
    let derniereReprise = Number.NEGATIVE_INFINITY;
    const seen = new Set<string>();
    const remember = (id: string) => {
      seen.add(id);
      if (seen.size > 1000) seen.delete(seen.values().next().value!);
    };
    const refresh = async () => {
      if (!active) return;
      const request = ++versionLecture;
      lecture?.abort();
      const abort = new AbortController();
      lecture = abort;
      let timeout: ReturnType<typeof setTimeout> | undefined;
      let interrompre: (() => void) | undefined;
      setEtat(prev => ({ ...prev, loading: true }));
      try {
        const requetes = Promise.all([
          supabase.from('notifications')
            .select('id, titre, corps, type, lue, lien, cree_le')
            .eq('destinataire_id', userId).order('cree_le', { ascending: false }).limit(50).abortSignal(abort.signal),
          supabase.from('notifications').select('id', { count: 'exact', head: true })
            .eq('destinataire_id', userId).eq('lue', false).abortSignal(abort.signal),
        ]);
        const expiration = new Promise<never>((_, reject) => {
          interrompre = () => reject(new Error('lecture'));
          abort.signal.addEventListener('abort', interrompre, { once: true });
          timeout = setTimeout(() => abort.abort(), delaiLecture);
        });
        const [liste, compteur] = await Promise.race([requetes, expiration]);
        if (!active || request !== versionLecture) return;
        if (liste.error || compteur.error || !Array.isArray(liste.data)
          || !Number.isSafeInteger(compteur.count) || compteur.count! < 0) throw new Error('lecture');
        const notifications = [...new Map((liste.data as NotificationItem[]).map(n => [n.id, n])).values()];
        notifications.forEach(n => remember(n.id));
        liveReady = subscribed;
        setEtat(prev => ({ ...prev, notifications, count: compteur.count!, hasLoaded: true, loading: false, readError: null }));
      } catch {
        if (!active || request !== versionLecture) return;
        setEtat(prev => ({ ...prev, loading: false, readError: erreurLecture }));
      } finally {
        clearTimeout(timeout);
        if (interrompre) abort.signal.removeEventListener('abort', interrompre);
        if (lecture === abort) lecture = undefined;
      }
    };
    const ouvrirCanal = (reprise = false) => {
      const ancien = channel;
      const generation = ++versionCanal;
      subscribed = false;
      liveReady = false;
      statut = reprise ? 'reconnecting' : 'connecting';
      setEtat(prev => ({ ...prev, realtimeStatus: statut }));
      // Le nouveau canal est enregistré avant le retrait de l'ancien. Aucune
      // déconnexion du client partagé (chat, présence, autres notifications).
      try {
        channel = supabase.channel(`notifications:${userId}:${channelId}:${generation}`);
        channel.on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'notifications', filter: `destinataire_id=eq.${userId}` }, payload => {
          if (!active || generation !== versionCanal || payload.new.destinataire_id !== userId || typeof payload.new.id !== 'string') return;
          const notification = payload.new as NotificationItem;
          if (seen.has(notification.id)) return;
          remember(notification.id);
          if (liveReady) onLiveRef.current(notification);
          // Un INSERT ou une lecture plus récente invalide les réponses anciennes.
          void refresh();
        })
        .subscribe(status => {
          if (!active || generation !== versionCanal) return;
          liveReady = false;
          subscribed = status === 'SUBSCRIBED';
          statut = status;
          setEtat(prev => ({ ...prev, realtimeStatus: status }));
          if (subscribed) {
            // Aussi à la première souscription : couvre l'intervalle lecture → connexion.
            void refresh();
          }
        });
      } catch {
        subscribed = false;
        liveReady = false;
        statut = 'CHANNEL_ERROR';
        setEtat(prev => ({ ...prev, realtimeStatus: statut }));
      }
      if (ancien && channel !== ancien) void supabase.removeChannel(ancien).catch(() => undefined);
    };
    const actualiser = async () => {
      if (!active) return;
      clearTimeout(repriseTimer);
      repriseTimer = undefined;
      derniereReprise = Date.now();
      if (statut !== 'SUBSCRIBED' && statut !== 'connecting') ouvrirCanal(true);
      await refresh();
    };
    const auPremierPlan = () => nativeForeground ?? document.visibilityState === 'visible';
    const demanderReprise = () => {
      if (!active || !auPremierPlan() || repriseTimer !== undefined) return;
      // App, visibilitychange et online peuvent annoncer le même retour.
      // Une seule tentative par groupe de signaux, au plus une toutes les 5 s.
      const delai = Math.max(250, intervalleReprise - (Date.now() - derniereReprise));
      repriseTimer = setTimeout(() => {
        repriseTimer = undefined;
        if (active && auPremierPlan()) void actualiser();
      }, delai);
    };
    const visibility = () => {
      if (auPremierPlan()) demanderReprise();
      else { clearTimeout(repriseTimer); repriseTimer = undefined; }
    };
    document.addEventListener('visibilitychange', visibility);
    window.addEventListener('online', demanderReprise);
    let removeNative: (() => Promise<void>) | undefined;
    if (Capacitor.isNativePlatform()) {
      void App.addListener('appStateChange', ({ isActive }) => {
        if (!active) return;
        nativeForeground = isActive;
        visibility();
      }).then(handle => {
        if (!active) void handle.remove();
        else removeNative = () => handle.remove();
      }).catch(() => undefined);
    }
    const lecteurs = lecteursParCompte.get(userId) ?? new Set<() => Promise<void>>();
    lecteurs.add(refresh);
    lecteursParCompte.set(userId, lecteurs);
    controller.current = {
      refresh: actualiser,
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
          await Promise.all([...lecteurs].map(relire => relire()));
          return active ? true : undefined;
        } catch { return active ? false : undefined; }
      },
    };
    ouvrirCanal();
    void refresh();
    return () => {
      active = false;
      versionLecture += 1;
      versionCanal += 1;
      lecture?.abort();
      clearTimeout(repriseTimer);
      document.removeEventListener('visibilitychange', visibility);
      window.removeEventListener('online', demanderReprise);
      void removeNative?.().catch(() => undefined);
      controller.current = null;
      lecteurs.delete(refresh);
      if (lecteurs.size === 0) lecteursParCompte.delete(userId);
      if (channel) void supabase.removeChannel(channel).catch(() => undefined);
    };
  }, [userId, channelId]);

  const actualiser = useCallback(() => controller.current?.refresh(), []);
  const marquerLues = useCallback((ids?: string[]) => controller.current?.markRead(ids), []);
  const realtimeError = etat.realtimeStatus !== 'connecting' && etat.realtimeStatus !== 'SUBSCRIBED' ? erreurConnexion : null;
  const error = [etat.readError, realtimeError].filter(Boolean).join(' ') || null;
  return { ...etat, error, actualiser, marquerLues };
}
