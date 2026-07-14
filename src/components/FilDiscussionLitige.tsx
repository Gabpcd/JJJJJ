import { useState, useEffect, useRef, useCallback } from 'react';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/contexts/AuthContext';
import { BoutonY2K } from '@/components/y2k/BoutonY2K';
import { Textarea } from '@/components/ui/textarea';
import { Send, ShieldAlert, Handshake, Shield, Loader2, AlertTriangle, CheckCircle } from 'lucide-react';
import { Badge } from '@/components/ui/badge';
import { format } from 'date-fns';
import { fr } from 'date-fns/locale';
import { toast } from 'sonner';
import { FormulaireAccord } from '@/components/litige/FormulaireAccord';

interface Props {
  litige: any;
  onUpdate: () => void;
  roleUtilisateur?: 'soignant' | 'etablissement';
}

const STATUT_LABELS: Record<string, { label: string; classes: string }> = {
  OUVERT: { label: 'Ouvert', classes: 'bg-warning/10 text-warning border-warning/30' },
  EN_COURS: { label: 'En cours', classes: 'bg-primary/10 text-primary border-primary/30' },
  EN_DISCUSSION: { label: 'En discussion', classes: 'bg-primary/10 text-primary border-primary/30' },
  EN_MEDIATION: { label: 'Médiation Jolene', classes: 'bg-info/10 text-info border-info/30' },
  MEDIATION_EN_COURS: { label: 'Médiation en cours', classes: 'bg-info/10 text-info border-info/30' },
  REVUE_ADMIN: { label: 'Revue admin', classes: 'bg-destructive/10 text-destructive border-destructive/30' },
  RESOLU_ACCORD_PARTIES: { label: 'Accord mutuel ✅', classes: 'bg-success/10 text-success border-success/30' },
  RESOLU_FAVEUR_SOIGNANT: { label: 'Tranché — soignant', classes: 'bg-success/5 text-foreground border-border' },
  RESOLU_FAVEUR_ETAB: { label: 'Tranché — établissement', classes: 'bg-success/5 text-foreground border-border' },
  RESOLU_PARTAGE: { label: 'Décision partagée', classes: 'bg-success/5 text-foreground border-border' },
  RESOLU_ADMIN: { label: 'Résolu admin', classes: 'bg-muted text-muted-foreground border-border' },
  RESOLU_SOIGNANT: { label: 'Résolu (soignant)', classes: 'bg-success/5 text-foreground border-border' },
  RESOLU_ETABLISSEMENT: { label: 'Résolu (étab)', classes: 'bg-success/5 text-foreground border-border' },
  CONTESTEE: { label: 'Contesté', classes: 'bg-warning/10 text-warning border-warning/30' },
  RESOLU: { label: 'Résolu', classes: 'bg-success/10 text-success border-success/30' },
  CLOTURE: { label: 'Clôturé', classes: 'bg-success/10 text-success border-success/30' },
  FERME: { label: 'Fermé', classes: 'bg-muted text-muted-foreground border-border' },
};

export function FilDiscussionLitige({ litige, onUpdate, roleUtilisateur }: Props) {
  const { user } = useAuth();
  const [messages, setMessages] = useState<any[]>([]);
  const [loadingMsgs, setLoadingMsgs] = useState(true);
  const [newMsg, setNewMsg] = useState('');
  const [sending, setSending] = useState(false);
  const bottomRef = useRef<HTMLDivElement>(null);

  const chargerMessages = useCallback(async () => {
    const { data } = await supabase
      .from('messages_litige')
      .select('*')
      .eq('litige_id', litige.id)
      .order('cree_le', { ascending: true });
    setMessages(data || []);
    setLoadingMsgs(false);
    setTimeout(() => bottomRef.current?.scrollIntoView({ behavior: 'smooth' }), 100);
  }, [litige.id]);

  useEffect(() => { void chargerMessages(); }, [chargerMessages]);

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
    await chargerMessages();
    onUpdate();
  };

  const isOpen = ['OUVERT', 'EN_COURS', 'EN_DISCUSSION', 'EN_MEDIATION', 'MEDIATION_EN_COURS', 'CONTESTEE'].includes(litige.statut);
  const isClosed = ['CLOTURE', 'RESOLU', 'FERME', 'RESOLU_ACCORD_PARTIES', 'RESOLU_FAVEUR_SOIGNANT', 'RESOLU_FAVEUR_ETAB', 'RESOLU_PARTAGE', 'RESOLU_SOIGNANT', 'RESOLU_ETABLISSEMENT', 'RESOLU_ADMIN'].includes(litige.statut);
  const isRevueAdmin = litige.statut === 'REVUE_ADMIN';

  // Determine if the OTHER party has requested closure
  const iAmSoignant = litige.soignant_id === user?.id;
  const autrePartieAccepte = iAmSoignant ? litige.accord_etablissement : litige.accord_soignant;
  const monAccord = iAmSoignant ? litige.accord_soignant : litige.accord_etablissement;
  const clotureEnAttente = isOpen && (litige.accord_soignant || litige.accord_etablissement) && !isClosed;

  const statutInfo = STATUT_LABELS[litige.statut] || { label: litige.statut, classes: 'bg-muted text-muted-foreground' };

  return (
    <div className="space-y-3">
      {/* Header */}
      <div className="flex items-start justify-between">
        <div>
          <h3 className="font-semibold text-sm text-foreground">{litige.missions?.intitule || 'Mission'}</h3>
          <p className="text-xs text-muted-foreground mt-0.5">
            {litige.cree_le ? format(new Date(litige.cree_le), 'd MMM yyyy', { locale: fr }) : '—'}
          </p>
        </div>
        <Badge variant="outline" className={statutInfo.classes}>{statutInfo.label}</Badge>
      </div>

      {/* Motif */}
      <div className="text-sm">
        <span className="text-muted-foreground">Motif :</span>{' '}
        <span className="text-foreground">{litige.motif}</span>
      </div>

      {/* ── CLOSURE REQUEST BANNER — prominent alert ── */}
      {clotureEnAttente && autrePartieAccepte && !monAccord && (
        <div className="rounded-xl border-2 border-success/40 bg-success/5 p-4">
          <div className="flex items-start gap-3">
            <Handshake className="h-5 w-5 text-success shrink-0 mt-0.5" />
            <div className="flex-1">
              <p className="text-sm font-bold text-success">
                L'{iAmSoignant ? 'établissement' : 'soignant(e)'} propose un accord
              </p>
              <p className="text-xs text-muted-foreground mt-1">
                Utilisez le bouton « Accepter l'accord » ci-dessus pour confirmer.
              </p>
            </div>
          </div>
        </div>
      )}

      {/* Mediation banner */}
      {(litige.statut === 'EN_MEDIATION' || litige.statut === 'MEDIATION_EN_COURS') && (
        <div className="bg-info/10 border border-info/30 rounded-xl p-3 flex items-center gap-2">
          <Shield className="h-4 w-4 text-info" />
          <p className="text-sm text-info font-medium">En médiation amiable — vous avez 7 jours pour vous accorder</p>
        </div>
      )}

      {litige.statut === 'REVUE_ADMIN' && (
        <div className="bg-destructive/10 border border-destructive/30 rounded-xl p-3 flex items-center gap-2">
          <ShieldAlert className="h-4 w-4 text-destructive" />
          <p className="text-sm text-destructive font-medium">En revue admin — un administrateur va trancher</p>
        </div>
      )}

      {/* Closed */}
      {isClosed && (
        <div className="bg-success/10 border border-success/30 rounded-xl p-3">
          <p className="text-sm text-success font-medium">Litige clôturé</p>
          {litige.resolution && <p className="text-xs text-foreground mt-1">{litige.resolution}</p>}
        </div>
      )}

      {/* Messages thread */}
      <div className="space-y-2 max-h-none rounded-xl bg-muted/10 p-2">
        {loadingMsgs ? (
          <div className="flex justify-center py-4"><Loader2 className="h-4 w-4 animate-spin text-muted-foreground" /></div>
        ) : messages.length === 0 ? (
          <p className="text-xs text-muted-foreground text-center py-4">Aucun message pour le moment</p>
        ) : (
          messages.map((msg) => {
            const isMe = msg.auteur_id === user?.id;
            const isAdmin = msg.type_auteur === 'ADMIN';
            return (
              <div key={msg.id} className={`rounded-xl p-3 text-sm ${isAdmin ? 'bg-primary/5 border border-primary/20' : isMe ? 'bg-muted/40 ml-4' : 'bg-background border border-border mr-4'}`}>
                <div className="flex items-center gap-2 mb-1">
                  <span className="font-semibold text-foreground text-xs">
                    {isAdmin ? '🛡️ Jolene' : isMe ? 'Vous' : msg.type_auteur === 'SOIGNANT' ? 'Soignant(e)' : 'Établissement'}
                  </span>
                  <span className="text-[11px] text-muted-foreground">
                    {msg.cree_le ? format(new Date(msg.cree_le), 'd MMM HH:mm', { locale: fr }) : ''}
                  </span>
                </div>
                <p className="text-foreground">{msg.contenu}</p>
              </div>
            );
          })
        )}
        <div ref={bottomRef} />
      </div>

      {/* Accord progress */}
      {isOpen && (litige.accord_soignant || litige.accord_etablissement) && (
        <div className="flex gap-4 text-xs px-1">
          <span className={`flex items-center gap-1 ${litige.accord_soignant ? 'text-success font-medium' : 'text-muted-foreground'}`}>
            {litige.accord_soignant ? <CheckCircle className="h-3 w-3" /> : <AlertTriangle className="h-3 w-3" />}
            Soignant(e) : {litige.accord_soignant ? 'Accepte' : 'En attente'}
          </span>
          <span className={`flex items-center gap-1 ${litige.accord_etablissement ? 'text-success font-medium' : 'text-muted-foreground'}`}>
            {litige.accord_etablissement ? <CheckCircle className="h-3 w-3" /> : <AlertTriangle className="h-3 w-3" />}
            Établissement : {litige.accord_etablissement ? 'Accepte' : 'En attente'}
          </span>
        </div>
      )}

      {/* Actions */}
      {(isOpen || isRevueAdmin) && (
        <div className="space-y-2 pt-2 border-t border-border">
          <Textarea
            value={newMsg}
            onChange={e => setNewMsg(e.target.value)}
            placeholder="Votre message (min. 10 caractères)..."
            rows={2}
            maxLength={1000}
          />
          <div className="flex flex-wrap gap-2">
            <BoutonY2K size="sm" onClick={envoyerMessage} disabled={sending || newMsg.trim().length < 10} loading={sending} className="gap-1.5" iconeGauche={sending ? undefined : <Send className="h-3.5 w-3.5" />}>
              {sending ? 'Envoi…' : 'Envoyer'}
            </BoutonY2K>
          </div>
        </div>
      )}

      {/* PR 3 Sprint 3.5 — Formulaire d'accord structuré */}
      {isOpen && (() => {
        const monRole = roleUtilisateur || (
          litige.soignant_id === user?.id
            ? 'soignant'
            : (litige.etablissement_id === user?.id ? 'etablissement' : null)
        );
        if (!monRole) return null;
        const proposition = litige.payload_modifications;
        const dejaAccordSoignant = !!litige.accord_soignant;
        const dejaAccordEtab = !!litige.accord_etablissement;
        const propositionExistante = proposition ? {
          ...proposition,
          proposeur_role: dejaAccordSoignant && !dejaAccordEtab ? 'soignant' as const
            : (dejaAccordEtab && !dejaAccordSoignant ? 'etablissement' as const : monRole),
        } : null;
        return (
          <FormulaireAccord
            litigeId={litige.id}
            propositionExistante={propositionExistante}
            roleUtilisateur={monRole}
            onResolu={onUpdate}
          />
        );
      })()}
    </div>
  );
}
