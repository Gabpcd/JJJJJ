import { useState, useEffect } from 'react';
import { usePageTitle } from '@/hooks/usePageTitle';
import { LayoutApp } from '@/components/LayoutApp';
import { ChargementPage } from '@/components/ChargementPage';
import { EtatVide } from '@/components/EtatVide';
import { useAuth } from '@/contexts/AuthContext';
import { supabase } from '@/integrations/supabase/client';
import { Scale, MessageCircle, Send } from 'lucide-react';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Textarea } from '@/components/ui/textarea';
import { format } from 'date-fns';
import { fr } from 'date-fns/locale';
import { toast } from 'sonner';

const STATUT_COLORS: Record<string, string> = {
  OUVERT: 'bg-warning/10 text-warning',
  EN_DISCUSSION: 'bg-primary/10 text-primary',
  RESOLU: 'bg-success/10 text-success',
  FERME: 'bg-muted text-muted-foreground',
};

export default function LitigesEtablissement() {
  usePageTitle('Litiges');
  const { user } = useAuth();
  const [litiges, setLitiges] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [replyId, setReplyId] = useState<string | null>(null);
  const [replyText, setReplyText] = useState('');
  const [sending, setSending] = useState(false);

  const charger = async () => {
    if (!user) return;
    const { data } = await supabase
      .from('litiges')
      .select('*, missions(intitule, debut_le)')
      .eq('etablissement_id', user.id)
      .order('cree_le', { ascending: false });
    setLitiges(data || []);
    setLoading(false);
  };

  useEffect(() => { charger(); }, [user]);

  const repondre = async () => {
    if (!replyId || !replyText.trim()) return;
    setSending(true);
    const { error } = await supabase.from('litiges').update({
      reponse: replyText.trim(),
      statut: 'EN_DISCUSSION',
    } as any).eq('id', replyId);
    setSending(false);
    if (error) { toast.error('Erreur'); return; }
    toast.success('Réponse envoyée');
    setReplyId(null);
    setReplyText('');
    charger();
  };

  if (loading) return <LayoutApp role="ADMIN_ETABLISSEMENT"><ChargementPage /></LayoutApp>;

  return (
    <LayoutApp role="ADMIN_ETABLISSEMENT">
      <div className="mb-6">
        <h1 className="text-xl font-bold text-foreground flex items-center gap-2">
          <Scale className="h-6 w-6 text-primary" /> Litiges
        </h1>
        <p className="text-sm text-muted-foreground mt-1">Gérez les contestations de vos missions</p>
      </div>

      {litiges.length === 0 ? (
        <EtatVide icone={Scale} titre="Aucun litige" sousTitre="Aucun litige sur vos missions." />
      ) : (
        <div className="space-y-4">
          {litiges.map(l => (
            <div key={l.id} className="card-base">
              <div className="flex items-start justify-between mb-2">
                <div>
                  <h3 className="font-semibold text-sm text-foreground">{l.missions?.intitule || 'Mission'}</h3>
                  <p className="text-xs text-muted-foreground mt-0.5">
                    📅 {l.cree_le ? format(new Date(l.cree_le), 'd MMM yyyy', { locale: fr }) : '—'}
                  </p>
                </div>
                <Badge className={STATUT_COLORS[l.statut] || ''}>{l.statut}</Badge>
              </div>

              <div className="space-y-2 text-sm">
                <div><span className="text-muted-foreground">Motif :</span> <span className="text-foreground">{l.motif}</span></div>
                {l.reponse && <div><span className="text-muted-foreground">Réponse :</span> <span className="text-foreground">{l.reponse}</span></div>}
                {l.resolution && <div className="bg-success/5 border border-success/20 rounded-lg p-2"><span className="text-muted-foreground">Résolution admin :</span> <span className="text-success font-medium">{l.resolution}</span></div>}
              </div>

              {(l.statut === 'OUVERT' || l.statut === 'EN_DISCUSSION') && (
                <div className="mt-3 pt-3 border-t border-border">
                  {replyId === l.id ? (
                    <div className="space-y-2">
                      <Textarea value={replyText} onChange={e => setReplyText(e.target.value)} placeholder="Votre réponse..." rows={3} />
                      <div className="flex gap-2">
                        <Button size="sm" onClick={repondre} disabled={sending} className="gap-1.5">
                          <Send className="h-3.5 w-3.5" /> Envoyer
                        </Button>
                        <Button size="sm" variant="ghost" onClick={() => setReplyId(null)}>Annuler</Button>
                      </div>
                    </div>
                  ) : (
                    <Button size="sm" variant="outline" className="gap-1.5" onClick={() => setReplyId(l.id)}>
                      <MessageCircle className="h-3.5 w-3.5" /> Répondre
                    </Button>
                  )}
                </div>
              )}
            </div>
          ))}
        </div>
      )}
    </LayoutApp>
  );
}
