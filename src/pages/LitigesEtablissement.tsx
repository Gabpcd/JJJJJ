import { useState, useEffect } from 'react';
import { usePageTitle } from '@/hooks/usePageTitle';
import { useNavigate } from 'react-router-dom';
import { LayoutApp } from '@/components/LayoutApp';
import { ChargementPage } from '@/components/ChargementPage';
import { EtatVide } from '@/components/EtatVide';
import { useAuth } from '@/contexts/AuthContext';
import { supabase } from '@/integrations/supabase/client';
import { Scale, PlusCircle, MessageCircle } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Textarea } from '@/components/ui/textarea';
import { Badge } from '@/components/ui/badge';
import { Dialog, DialogContent, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { format } from 'date-fns';
import { fr } from 'date-fns/locale';
import { toast } from 'sonner';
import { useEtablissementScope } from '@/hooks/useEtablissementScope';
import { FilDiscussionLitige } from '@/components/FilDiscussionLitige';

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

export default function LitigesEtablissement() {
  usePageTitle('Litiges');
  const navigate = useNavigate();
  const { user, etablissementId } = useEtablissementScope();
  const [litiges, setLitiges] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [expandedId, setExpandedId] = useState<string | null>(null);

  // New dispute modal
  const [showNew, setShowNew] = useState(false);
  const [missionsTerminees, setMissionsTerminees] = useState<any[]>([]);
  const [selectedMissionId, setSelectedMissionId] = useState('');
  const [newMotif, setNewMotif] = useState('');
  const [creating, setCreating] = useState(false);

  const charger = async () => {
    if (!user || !etablissementId) return;
    const { data, error } = await supabase.rpc('fn_litiges_etablissement' as any);
    if (error) {
      toast.error('Erreur lors du chargement des litiges.');
      setLoading(false);
      return;
    }
    setLitiges(Array.isArray(data) ? data : []);
    setLoading(false);
  };

  useEffect(() => { charger(); }, [user, etablissementId]);

  const openNewLitige = async () => {
    if (!user || !etablissementId) return;
    const [{ data: missions }, { data: existingLitiges }] = await Promise.all([
      supabase.from('missions')
        .select('id, intitule, debut_le, fin_le, soignant_assigne_id')
        .eq('etablissement_id', etablissementId)
        .not('soignant_assigne_id', 'is', null)
        .in('statut', ['TERMINEE', 'EN_COURS'])
        .order('fin_le', { ascending: false })
        .limit(50),
      supabase.from('litiges')
        .select('mission_id')
        .eq('etablissement_id', etablissementId),
    ]);
    const litigesMissionIds = new Set((existingLitiges || []).map((l: any) => l.mission_id));
    setMissionsTerminees((missions || []).filter((m: any) => !litigesMissionIds.has(m.id)));
    setSelectedMissionId('');
    setNewMotif('');
    setShowNew(true);
  };

  const creerLitige = async () => {
    if (!selectedMissionId || !newMotif.trim() || !etablissementId) {
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

  if (loading) return <LayoutApp role="ADMIN_ETABLISSEMENT"><ChargementPage /></LayoutApp>;

  return (
    <LayoutApp role="ADMIN_ETABLISSEMENT">
      <div className="flex items-center justify-between mb-6">
        <div>
          <h1 className="text-xl font-bold text-foreground flex items-center gap-2">
            <Scale className="h-6 w-6 text-primary" /> Litiges
          </h1>
          <p className="text-sm text-muted-foreground mt-1">Gérez les contestations de vos missions</p>
        </div>
        <Button onClick={openNewLitige} className="gap-1.5">
          <PlusCircle className="h-4 w-4" /> Ouvrir un litige
        </Button>
      </div>

      {litiges.length === 0 ? (
        <EtatVide icone={Scale} titre="Aucun litige" sousTitre="Aucun litige sur vos missions. Cliquez sur « Ouvrir un litige » pour contester une mission." />
      ) : (
        <div className="space-y-4">
          {litiges.map((l: any) => {
            const isExpanded = expandedId === l.litige_id;
            return (
              <div key={l.litige_id} className="card-base">
                {/* Summary row */}
                <div className="flex items-start justify-between gap-3">
                  <div className="flex-1 min-w-0">
                    <button
                      onClick={() => navigate(`/etablissement/missions/${l.mission_id}`)}
                      className="font-semibold text-sm text-foreground hover:text-primary hover:underline text-left"
                    >
                      {l.mission_intitule || 'Mission'}
                    </button>
                    <p className="text-xs text-muted-foreground mt-0.5">
                      👤 {l.soignant_nom} · {l.soignant_profession}
                      {l.mission_debut && ` · ${format(new Date(l.mission_debut), 'd MMM yyyy', { locale: fr })}`}
                    </p>
                    <p className="text-xs text-muted-foreground mt-1 truncate">
                      <span className="font-medium">Motif :</span> {l.motif}
                    </p>
                    {l.dernier_message && (
                      <p className="text-xs text-muted-foreground mt-1 truncate flex items-center gap-1">
                        <MessageCircle className="h-3 w-3" />
                        {l.dernier_message}
                      </p>
                    )}
                  </div>
                  <div className="flex flex-col items-end gap-2 shrink-0">
                    <Badge className={STATUT_COLORS[l.statut] || ''}>{l.statut}</Badge>
                    {l.nb_messages > 0 && (
                      <span className="text-[10px] text-muted-foreground">{l.nb_messages} message{l.nb_messages > 1 ? 's' : ''}</span>
                    )}
                  </div>
                </div>

                {/* Toggle discussion */}
                <div className="mt-3 pt-2 border-t border-border">
                  <button
                    onClick={() => setExpandedId(isExpanded ? null : l.litige_id)}
                    className="text-xs font-medium text-primary hover:underline"
                  >
                    {isExpanded ? '▲ Masquer la discussion' : '▼ Voir le litige'}
                  </button>
                </div>

                {isExpanded && (
                  <div className="mt-3">
                    <FilDiscussionLitige
                      litige={{
                        id: l.litige_id,
                        statut: l.statut,
                        motif: l.motif,
                        cree_le: l.cree_le,
                        accord_soignant: l.accord_soignant,
                        accord_etablissement: l.accord_etablissement,
                        resolution: l.resolution,
                        missions: { intitule: l.mission_intitule },
                      }}
                      onUpdate={charger}
                    />
                  </div>
                )}
              </div>
            );
          })}
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
