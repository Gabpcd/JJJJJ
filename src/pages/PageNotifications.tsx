import React, { useState, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import { LayoutApp } from '@/components/LayoutApp';
import { ChargementPage } from '@/components/ChargementPage';
import { EtatVide } from '@/components/EtatVide';
import { useAuth } from '@/contexts/AuthContext';
import { supabase } from '@/integrations/supabase/client';
import { ExternalLink, Trash2 } from 'lucide-react';
import { IllustrationCloche } from '@/components/EtatVide';
import { formatDistanceToNow } from 'date-fns';
import { fr } from 'date-fns/locale';
import { UserRole } from '@/lib/types';

const FILTRES = ['Toutes', 'Missions', 'Documents', 'Finance', 'Système'] as const;
type Filtre = typeof FILTRES[number];

const TYPE_MAP: Record<Filtre, string[]> = {
  Toutes: [],
  Missions: ['MISSION_ACCEPTEE', 'MISSION_ANNULEE', 'MISSION_TERMINEE', 'MISSION_RAPPEL'],
  Documents: ['DOCUMENT_EXPIRE', 'DOCUMENT_VALIDE', 'DOCUMENT_REJETE'],
  Finance: ['FACTURE_GENEREE', 'FACTURE_PAYEE', 'NOTE_HONORAIRES'],
  Système: ['SYSTEME', 'BIENVENUE', 'CONTRAT_GENERE', 'CONTRAT_SIGNE'],
};

export default function PageNotifications({ role }: { role: UserRole }) {
  const { user } = useAuth();
  const navigate = useNavigate();
  const [notifications, setNotifications] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [filtre, setFiltre] = useState<Filtre>('Toutes');

  useEffect(() => {
    if (!user) return;
    const load = async () => {
      const { data } = await supabase
        .from('notifications')
        .select('id, titre, corps, type, lien, lue, cree_le, type_ressource, id_ressource')
        .eq('destinataire_id', user.id)
        .order('cree_le', { ascending: false })
        .limit(200);
      setNotifications(data || []);
      setLoading(false);
    };
    load();
  }, [user]);

  // Realtime
  useEffect(() => {
    if (!user) return;
    const channel = supabase
      .channel('notif-page-live')
      .on('postgres_changes', {
        event: 'INSERT',
        schema: 'public',
        table: 'notifications',
        filter: `destinataire_id=eq.${user.id}`,
      }, (payload) => {
        setNotifications(prev => [payload.new as any, ...prev]);
      })
      .subscribe();
    return () => { supabase.removeChannel(channel); };
  }, [user]);

  const handleClick = async (n: any) => {
    if (!n.lue) {
      await supabase.from('notifications').update({ lue: true, lue_le: new Date().toISOString() } as any).eq('id', n.id);
      setNotifications(prev => prev.map(x => x.id === n.id ? { ...x, lue: true } : x));
    }
    if (n.lien) navigate(n.lien);
  };

  const supprimerLues = async () => {
    const ids = notifications.filter(n => n.lue).map(n => n.id);
    if (ids.length === 0) return;
    // Suppression locale uniquement — les notifications lues sont masquées côté client
    // La purge définitive est gérée par un job serveur (admin only via RLS)
    setNotifications(prev => prev.filter(n => !n.lue));
  };

  const filtered = filtre === 'Toutes' ? notifications : notifications.filter(n => TYPE_MAP[filtre].includes(n.type));

  if (loading) return <LayoutApp role={role}><ChargementPage /></LayoutApp>;

  return (
    <LayoutApp role={role}>
      <div className="flex items-center justify-between mb-4">
        <h1 className="text-xl font-bold text-foreground">Notifications</h1>
        <button onClick={supprimerLues} className="text-xs text-muted-foreground hover:text-destructive flex items-center gap-1">
          <Trash2 className="h-3.5 w-3.5" /> Supprimer les lues
        </button>
      </div>

      <div className="flex gap-2 mb-4 flex-wrap">
        {FILTRES.map(f => (
          <button key={f} onClick={() => setFiltre(f)} className={`badge-base transition-colors ${filtre === f ? 'bg-primary text-primary-foreground' : 'bg-muted text-muted-foreground hover:bg-accent'}`}>
            {f}
          </button>
        ))}
      </div>

      {filtered.length === 0 ? (
        <EtatVide icone={Bell} titre="Aucune notification" sousTitre="Vous serez notifié(e) ici en temps réel." />
      ) : (
        <div className="space-y-2">
          {filtered.map((n: any) => (
            <button
              key={n.id}
              onClick={() => handleClick(n)}
              className={`w-full text-left card-base hover:shadow-md transition-all ${!n.lue ? 'border-l-4 border-l-primary bg-primary/5' : ''}`}
            >
              <div className="flex items-start justify-between gap-2">
                <div className="flex items-center gap-2">
                  <div className={`h-2 w-2 rounded-full shrink-0 ${!n.lue ? 'bg-destructive' : 'bg-muted-foreground/30'}`} />
                  <span className={`text-sm ${!n.lue ? 'font-semibold' : ''} text-foreground`}>{n.titre}</span>
                </div>
                <span className="text-[10px] text-muted-foreground whitespace-nowrap">
                  {formatDistanceToNow(new Date(n.cree_le), { addSuffix: true, locale: fr })}
                </span>
              </div>
              <p className="text-xs text-muted-foreground mt-1 ml-4">{n.corps}</p>
              {n.lien && <span className="text-[10px] text-primary ml-4 mt-1 inline-flex items-center gap-1">Voir <ExternalLink className="h-2.5 w-2.5" /></span>}
            </button>
          ))}
        </div>
      )}
    </LayoutApp>
  );
}
