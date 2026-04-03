import { useState, useEffect, useRef } from 'react';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/contexts/AuthContext';
import { Button } from '@/components/ui/button';
import { Textarea } from '@/components/ui/textarea';
import { Send, ShieldAlert, Handshake, Shield, Loader2 } from 'lucide-react';
import { Badge } from '@/components/ui/badge';
import { format } from 'date-fns';
import { fr } from 'date-fns/locale';
import { toast } from 'sonner';

interface Props {
  litige: any;
  onUpdate: () => void;
}

const STATUT_COLORS: Record<string, string> = {
  OUVERT: 'bg-warning/10 text-warning',
  EN_COURS: 'bg-primary/10 text-primary',
  EN_DISCUSSION: 'bg-primary/10 text-primary',
  EN_MEDIATION: 'bg-info/10 text-info',
  CONTESTEE: 'bg-warning/10 text-warning',
  RESOLU: 'bg-success/10 text-success',
  CLOTURE: 'bg-success/10 text-success',
  FERME: 'bg-muted text-muted-foreground',
};

export function FilDiscussionLitige({ litige, onUpdate }: Props) {
  const { user } = useAuth();
  const [messages, setMessages] = useState<any[]>([]);
  const [loadingMsgs, setLoadingMsgs] = useState(true);
  const [newMsg, setNewMsg] = useState('');
  const [sending, setSending] = useState(false);
  const [clotureLoading, setClotureLoading] = useState(false);
  const [mediationLoading, setMediationLoading] = useState(false);
  const [showMediation, setShowMediation] = useState(false);
  const [mediationMsg, setMediationMsg] = useState('');
  const bottomRef = useRef<HTMLDivElement>(null);

  const chargerMessages = async () => {
    const { data } = await supabase
      .from('messages_litige')
      .select('*')
      .eq('litige_id', litige.id)
      .order('cree_le', { ascending: true });
    setMessages(data || []);
    setLoadingMsgs(false);
    setTimeout(() => bottomRef.current?.scrollIntoView({ behavior: 'smooth' }), 100);
  };

  useEffect(() => { chargerMessages(); }, [litige.id]);

  const envoyerMessage = async () => {
    if (!newMsg.trim() || newMsg.trim().length < 10) {
      toast.error('Le message doit contenir au moins 10 caractères.');
      return;
    }
    setSending(true);
    const { data, error } = await supabase.rpc('fn_ajouter_message_litige' as any, {
      p_litige_id: litige.id,
      p_contenu: newMsg.trim(),
    });
    setSending(false);
    if (error || (data as any)?.error) {
      toast.error((data as any)?.error || 'Erreur lors de l\'envoi');
      return;
    }
    setNewMsg('');
    chargerMessages();
    onUpdate();
  };

  const demanderCloture = async () => {
    setClotureLoading(true);
    const { data, error } = await supabase.rpc('fn_cloturer_litige' as any, { p_litige_id: litige.id });
    setClotureLoading(false);
    if (error || (data as any)?.error) {
      toast.error((data as any)?.error || 'Erreur');
      return;
    }
    if ((data as any)?.cloture) {
      toast.success('Litige clôturé d\'un commun accord !');
    } else {
      toast.success('Votre accord a été enregistré. En attente de l\'accord de l\'autre partie.');
    }
    onUpdate();
  };

  const demanderMediation = async () => {
    setMediationLoading(true);
    const { data, error } = await supabase.rpc('fn_demander_mediation_litige' as any, {
      p_litige_id: litige.id,
    });
    setMediationLoading(false);
    if (error || (data as any)?.error) {
      toast.error((data as any)?.error || 'Erreur');
      return;
    }
    toast.success('Demande de médiation envoyée à l\'équipe Jolene.');
    setShowMediation(false);
    onUpdate();
  };

  const isOpen = ['OUVERT', 'EN_COURS', 'EN_DISCUSSION', 'EN_MEDIATION', 'CONTESTEE'].includes(litige.statut);
  const isClosed = litige.statut === 'CLOTURE' || litige.statut === 'RESOLU' || litige.statut === 'FERME';

  return (
    <div className="space-y-3">
      {/* Header */}
      <div className="flex items-start justify-between">
        <div>
          <h3 className="font-semibold text-sm text-foreground">{litige.missions?.intitule || 'Mission'}</h3>
          <p className="text-xs text-muted-foreground mt-0.5">
            📅 {litige.cree_le ? format(new Date(litige.cree_le), 'd MMM yyyy', { locale: fr }) : '—'}
          </p>
        </div>
        <Badge className={STATUT_COLORS[litige.statut] || ''}>{litige.statut}</Badge>
      </div>

      {/* Motif */}
      <div className="text-sm">
        <span className="text-muted-foreground">Motif :</span>{' '}
        <span className="text-foreground">{litige.motif}</span>
      </div>

      {/* Mediation banner */}
      {litige.statut === 'EN_MEDIATION' && (
        <div className="bg-info/10 border border-info/30 rounded-lg p-3 flex items-center gap-2">
          <Shield className="h-4 w-4 text-info" />
          <p className="text-sm text-info font-medium">🏥 En médiation — L'équipe Jolene examine ce litige</p>
        </div>
      )}

      {/* Closed */}
      {isClosed && (
        <div className="bg-success/10 border border-success/30 rounded-lg p-3">
          <p className="text-sm text-success font-medium">✅ Litige clôturé</p>
          {litige.resolution && <p className="text-xs text-foreground mt-1">{litige.resolution}</p>}
        </div>
      )}

      {/* Messages thread */}
      <div className="space-y-2 max-h-80 overflow-y-auto rounded-lg bg-muted/10 p-2">
        {loadingMsgs ? (
          <div className="flex justify-center py-4"><Loader2 className="h-4 w-4 animate-spin text-muted-foreground" /></div>
        ) : messages.length === 0 ? (
          <p className="text-xs text-muted-foreground text-center py-4">Aucun message pour le moment</p>
        ) : (
          messages.map((msg) => {
            const isMe = msg.auteur_id === user?.id;
            const isAdmin = msg.type_auteur === 'ADMIN';
            return (
              <div key={msg.id} className={`rounded-lg p-3 text-sm ${isAdmin ? 'bg-primary/5 border border-primary/20' : isMe ? 'bg-muted/40 ml-4' : 'bg-background border border-border mr-4'}`}>
                <div className="flex items-center gap-2 mb-1">
                  <span className="font-semibold text-foreground text-xs">
                    {isAdmin ? '🛡️ Jolene' : isMe ? 'Vous' : msg.type_auteur === 'SOIGNANT' ? 'Soignant(e)' : 'Établissement'}
                  </span>
                  <span className="text-[10px] text-muted-foreground">
                    {msg.cree_le ? format(new Date(msg.cree_le), 'd MMM yyyy HH:mm', { locale: fr }) : ''}
                  </span>
                </div>
                <p className="text-foreground">{msg.contenu}</p>
              </div>
            );
          })
        )}
        <div ref={bottomRef} />
      </div>

      {/* Accord status */}
      {isOpen && (litige.accord_soignant || litige.accord_etablissement) && (
        <div className="flex gap-2 text-xs">
          <span className={litige.accord_soignant ? 'text-success' : 'text-muted-foreground'}>
            {litige.accord_soignant ? '✅' : '⏳'} Soignant(e)
          </span>
          <span className={litige.accord_etablissement ? 'text-success' : 'text-muted-foreground'}>
            {litige.accord_etablissement ? '✅' : '⏳'} Établissement
          </span>
        </div>
      )}

      {/* Actions */}
      {isOpen && (
        <div className="space-y-2 pt-2 border-t border-border">
          {/* Message input */}
          <Textarea
            value={newMsg}
            onChange={e => setNewMsg(e.target.value)}
            placeholder="Votre message (min. 10 caractères)..."
            rows={2}
          />
          <div className="flex flex-wrap gap-2">
            <Button size="sm" onClick={envoyerMessage} disabled={sending || newMsg.trim().length < 10} className="gap-1.5">
              <Send className="h-3.5 w-3.5" /> {sending ? 'Envoi…' : 'Envoyer'}
            </Button>
            <Button
              size="sm"
              variant="outline"
              className="gap-1.5 border-success/30 text-success hover:bg-success/10"
              disabled={clotureLoading}
              onClick={demanderCloture}
            >
              <Handshake className="h-3.5 w-3.5" />
              {clotureLoading ? 'En cours…' : '✅ Accepter la clôture'}
            </Button>
            {litige.statut !== 'EN_MEDIATION' && (
              <Button
                size="sm"
                variant="outline"
                className="gap-1.5 border-warning/30 text-warning hover:bg-warning/10"
                onClick={() => setShowMediation(!showMediation)}
              >
                <ShieldAlert className="h-3.5 w-3.5" /> 🏥 Demander la médiation Jolene
              </Button>
            )}
          </div>
          {showMediation && (
            <div className="space-y-2">
              <Button size="sm" onClick={demanderMediation} disabled={mediationLoading} className="gap-1.5">
                <ShieldAlert className="h-3.5 w-3.5" /> {mediationLoading ? 'Envoi…' : 'Confirmer la demande de médiation'}
              </Button>
              <Button size="sm" variant="ghost" onClick={() => setShowMediation(false)}>Annuler</Button>
            </div>
          )}
        </div>
      )}
    </div>
  );
}
