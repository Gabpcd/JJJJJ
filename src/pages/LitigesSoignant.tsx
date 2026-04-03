import { useState, useEffect } from 'react';
import { usePageTitle } from '@/hooks/usePageTitle';
import { LayoutApp } from '@/components/LayoutApp';
import { ChargementPage } from '@/components/ChargementPage';
import { EtatVide } from '@/components/EtatVide';
import { useAuth } from '@/contexts/AuthContext';
import { supabase } from '@/integrations/supabase/client';
import { Scale, PlusCircle } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Textarea } from '@/components/ui/textarea';
import { Dialog, DialogContent, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { format } from 'date-fns';
import { fr } from 'date-fns/locale';
import { toast } from 'sonner';
import { FilDiscussionLitige } from '@/components/FilDiscussionLitige';

export default function LitigesSoignant() {
  usePageTitle('Mes litiges');
  const { user } = useAuth();
  const [litiges, setLitiges] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);

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
    if (newMotif.trim().length < 10) {
      toast.error('Le motif doit contenir au moins 10 caractères.');
      return;
    }
    setCreating(true);
    const { data, error } = await supabase.rpc('fn_ouvrir_litige_rate_limited' as any, {
      p_mission_id: selectedMissionId,
      p_motif: newMotif.trim(),
    });
    setCreating(false);
    if (error) { toast.error('Une erreur est survenue. Veuillez réessayer.'); return; }
    if ((data as any)?.error) { toast.error((data as any).error); return; }
    toast.success('Litige ouvert avec succès.');
    setShowNew(false);
    charger();
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
        <EtatVide icone={Scale} titre="Aucun litige" sousTitre="Vous n'avez aucun litige en cours." />
      ) : (
        <div className="space-y-4">
          {litiges.map(l => (
            <div key={l.id} className="card-base">
              <FilDiscussionLitige litige={l} onUpdate={charger} />
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
