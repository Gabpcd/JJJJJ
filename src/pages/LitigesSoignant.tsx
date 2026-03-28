import { useState, useEffect } from 'react';
import { usePageTitle } from '@/hooks/usePageTitle';
import { LayoutApp } from '@/components/LayoutApp';
import { ChargementPage } from '@/components/ChargementPage';
import { EtatVide } from '@/components/EtatVide';
import { useAuth } from '@/contexts/AuthContext';
import { supabase } from '@/integrations/supabase/client';
import { Scale, MessageCircle, Send, PlusCircle, Handshake, ShieldAlert } from 'lucide-react';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Textarea } from '@/components/ui/textarea';
import { Dialog, DialogContent, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { format } from 'date-fns';
import { fr } from 'date-fns/locale';
import { toast } from 'sonner';
import { logger } from '@/lib/logger';

const STATUT_COLORS: Record<string, string> = {
  OUVERT: 'bg-warning/10 text-warning',
  EN_DISCUSSION: 'bg-primary/10 text-primary',
  RESOLU: 'bg-success/10 text-success',
  FERME: 'bg-muted text-muted-foreground',
};

export default function LitigesSoignant() {
  usePageTitle('Mes litiges');
  const { user } = useAuth();
  const [litiges, setLitiges] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [replyId, setReplyId] = useState<string | null>(null);
  const [replyText, setReplyText] = useState('');
  const [sending, setSending] = useState(false);
  const [clotureLoading, setClotureLoading] = useState<string | null>(null);
  const [mediationId, setMediationId] = useState<string | null>(null);
  const [mediationMsg, setMediationMsg] = useState('');
  const [mediationSending, setMediationSending] = useState(false);

  // New dispute modal
  const [showNew, setShowNew] = useState(false);
  const [missionsTerminees, setMissionsTerminees] = useState<any[]>([]);
  const [selectedMissionId, setSelectedMissionId] = useState('');
  const [newMotif, setNewMotif] = useState('');
  const [creating, setCreating] = useState(false);

  const charger = async () => {
    if (!user) return;
    const { data } = await supabase
      .from('litiges')
      .select('*, missions(intitule, debut_le)')
      .eq('soignant_id', user.id)
      .order('cree_le', { ascending: false });
    setLitiges(data || []);
    setLoading(false);
  };

  useEffect(() => { charger(); }, [user]);

  const openNewLitige = async () => {
    if (!user) return;
    // Load terminated missions that don't already have a litige
    const [{ data: missions }, { data: existingLitiges }] = await Promise.all([
      supabase.from('missions')
        .select('id, intitule, debut_le, fin_le, etablissement_id')
        .eq('soignant_assigne_id', user.id)
        .in('statut', ['TERMINEE', 'EN_COURS'])
        .order('fin_le', { ascending: false })
        .limit(50),
      supabase.from('litiges')
        .select('mission_id')
        .eq('soignant_id', user.id),
    ]);
    const litigesMissionIds = new Set((existingLitiges || []).map((l: any) => l.mission_id));
    setMissionsTerminees((missions || []).filter((m: any) => !litigesMissionIds.has(m.id)));
    setSelectedMissionId('');
    setNewMotif('');
    setShowNew(true);
  };

  const creerLitige = async () => {
    if (!selectedMissionId || !newMotif.trim()) {
      toast.error('Veuillez sélectionner une mission et saisir un motif.');
      return;
    }
    setCreating(true);
    const mission = missionsTerminees.find(m => m.id === selectedMissionId);
    if (!mission) { setCreating(false); return; }

    // Get or create a presence for this mission
    const { data: presenceData } = await supabase
      .from('presences')
      .select('id')
      .eq('mission_id', selectedMissionId)
      .eq('soignant_id', user!.id)
      .limit(1)
      .maybeSingle();

    const presenceId = presenceData?.id;
    if (!presenceId) {
      toast.error('Aucune présence trouvée pour cette mission. Un pointage est nécessaire pour ouvrir un litige.');
      setCreating(false);
      return;
    }

    const { data, error } = await supabase.rpc('fn_ouvrir_litige_rate_limited' as any, {
      p_mission_id: selectedMissionId,
      p_motif: newMotif.trim(),
    });
    setCreating(false);
    if (error) { toast.error('Erreur lors de la création du litige.'); logger.error('fn_ouvrir_litige_rate_limited error', error); return; }
    if (data?.error) { toast.error(data.error); return; }
    toast.success('Litige ouvert avec succès.');
    setShowNew(false);
    charger();
  };

  const repondre = async () => {
    if (!replyId || !replyText.trim()) return;
    if (replyText.trim().length < 10) {
      toast.error('La réponse doit contenir au moins 10 caractères.');
      return;
    }
    setSending(true);
    const { data, error } = await supabase.rpc('fn_repondre_litige' as any, {
      p_litige_id: replyId,
      p_reponse: replyText.trim(),
    });
    setSending(false);
    if (error || (data as any)?.error) { toast.error((data as any)?.error || 'Erreur lors de l\'envoi de la réponse.'); return; }
    toast.success('Réponse envoyée');
    setReplyId(null);
    setReplyText('');
    charger();
  };

  const renderReponses = (reponse: string | null) => {
    if (!reponse) return null;
    const entries = reponse.split('\n---\n').filter(Boolean);
    if (entries.length <= 1 && !reponse.includes('[')) {
      return <div className="text-sm"><span className="text-muted-foreground">Réponse établissement :</span> <span className="text-foreground">{reponse}</span></div>;
    }
    return (
      <div className="space-y-2 mt-2">
        <p className="text-xs font-semibold text-muted-foreground uppercase tracking-wide">Fil de discussion</p>
        {entries.map((entry, i) => {
          const match = entry.match(/^\[(.+?)\]\s*(.+?):\s*([\s\S]*)$/);
          if (!match) return <div key={i} className="text-sm text-foreground bg-muted/30 rounded-lg p-2">{entry}</div>;
          const [, date, auteur, texte] = match;
          return (
            <div key={i} className="bg-muted/30 rounded-lg p-3 text-sm">
              <div className="flex items-center gap-2 mb-1">
                <span className="font-semibold text-foreground text-xs">{auteur}</span>
                <span className="text-[10px] text-muted-foreground">{date}</span>
              </div>
              <p className="text-foreground">{texte.trim()}</p>
            </div>
          );
        })}
      </div>
    );
  };

  if (loading) return <LayoutApp role="SOIGNANT"><ChargementPage /></LayoutApp>;

  return (
    <LayoutApp role="SOIGNANT">
      <div className="flex items-center justify-between mb-6">
        <div>
          <h1 className="text-xl font-bold text-foreground flex items-center gap-2">
            <Scale className="h-6 w-6 text-primary" /> Mes litiges
          </h1>
          <p className="text-sm text-muted-foreground mt-1">Suivez vos contestations de missions</p>
        </div>
        <Button onClick={openNewLitige} className="gap-1.5">
          <PlusCircle className="h-4 w-4" /> Ouvrir un litige
        </Button>
      </div>

      {litiges.length === 0 ? (
        <EtatVide icone={Scale} titre="Aucun litige" sousTitre="Vous n'avez aucun litige en cours. Cliquez sur « Ouvrir un litige » pour contester une mission." />
      ) : (
        <div className="space-y-4">
          {litiges.map(l => (
            <div key={l.id} className="card-base">
              <div className="flex items-start justify-between mb-2">
                <div>
                  <h3 className="font-semibold text-sm text-foreground">{l.missions?.intitule || 'Mission'}</h3>
                  <p className="text-xs text-muted-foreground mt-0.5">
                    📅 {l.cree_le ? format(new Date(l.cree_le), 'd MMM yyyy', { locale: fr }) : '—'}
                    {l.missions?.debut_le && ` · Mission du ${format(new Date(l.missions.debut_le), 'd MMM yyyy', { locale: fr })}`}
                  </p>
                </div>
                <Badge className={STATUT_COLORS[l.statut] || ''}>{l.statut}</Badge>
              </div>

              <div className="space-y-2 text-sm">
                <div><span className="text-muted-foreground">Motif :</span> <span className="text-foreground">{l.motif}</span></div>
                {renderReponses(l.reponse)}
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

      {/* Modal nouveau litige */}
      <Dialog open={showNew} onOpenChange={setShowNew}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Ouvrir un nouveau litige</DialogTitle>
          </DialogHeader>
          <div className="space-y-4 mt-2">
            <div>
              <label className="text-sm font-medium text-foreground mb-1.5 block">Mission concernée</label>
              {missionsTerminees.length === 0 ? (
                <p className="text-sm text-muted-foreground">Aucune mission éligible (missions sans litige existant)</p>
              ) : (
                <Select value={selectedMissionId} onValueChange={setSelectedMissionId}>
                  <SelectTrigger><SelectValue placeholder="Sélectionner une mission" /></SelectTrigger>
                  <SelectContent>
                    {missionsTerminees.map(m => (
                      <SelectItem key={m.id} value={m.id}>
                        {m.intitule} — {m.debut_le ? format(new Date(m.debut_le), 'd MMM yyyy', { locale: fr }) : ''}
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              )}
            </div>
            <div>
              <label className="text-sm font-medium text-foreground mb-1.5 block">Motif du litige</label>
              <Textarea value={newMotif} onChange={e => setNewMotif(e.target.value)} placeholder="Décrivez le problème rencontré..." rows={4} />
            </div>
            <div className="flex justify-end gap-2">
              <Button variant="ghost" onClick={() => setShowNew(false)}>Annuler</Button>
              <Button onClick={creerLitige} disabled={creating || !selectedMissionId || !newMotif.trim()}>
                {creating ? 'Création…' : '⚠️ Ouvrir le litige'}
              </Button>
            </div>
          </div>
        </DialogContent>
      </Dialog>
    </LayoutApp>
  );
}
