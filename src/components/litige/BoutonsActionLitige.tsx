import { useState } from 'react';
import { Handshake, ShieldAlert, CheckCircle, Gavel, Loader2 } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Textarea } from '@/components/ui/textarea';
import { Dialog, DialogContent, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { RadioGroup, RadioGroupItem } from '@/components/ui/radio-group';
import { Label } from '@/components/ui/label';
import { supabase } from '@/integrations/supabase/client';
import { toast } from 'sonner';
import { peutProposerMediation, peutConfirmerAccord, estResolu, type StatutLitige } from '@/lib/statutLitige';

type Role = 'SOIGNANT' | 'ETABLISSEMENT' | 'ADMIN_PLATEFORME';
type DecisionAdmin = 'FAVEUR_SOIGNANT' | 'FAVEUR_ETAB' | 'PARTAGE';

interface Props {
  litige: {
    id: string;
    statut: string;
    accord_soignant?: boolean | null;
    accord_etablissement?: boolean | null;
    accord_soignant_le?: string | null;
    accord_etablissement_le?: string | null;
  };
  role: Role;
  onUpdate: () => void;
}

export function BoutonsActionLitige({ litige, role, onUpdate }: Props) {
  const [loadingAction, setLoadingAction] = useState<string | null>(null);
  const [showTrancher, setShowTrancher] = useState(false);
  const [decision, setDecision] = useState<DecisionAdmin>('FAVEUR_SOIGNANT');
  const [motif, setMotif] = useState('');
  const [trancherLoading, setTrancherLoading] = useState(false);

  const statut = litige.statut as StatutLitige;
  const monAccord = role === 'SOIGNANT' ? litige.accord_soignant : role === 'ETABLISSEMENT' ? litige.accord_etablissement : false;
  const autreAccord = role === 'SOIGNANT' ? litige.accord_etablissement : role === 'ETABLISSEMENT' ? litige.accord_soignant : false;

  const proposerMediation = async () => {
    setLoadingAction('proposer');
    const { data, error } = await supabase.rpc('fn_proposer_accord_partie' as any, { p_litige_id: litige.id });
    setLoadingAction(null);
    if (error || !(data as any)?.success) {
      toast.error((data as any)?.error || 'Erreur lors de la proposition de médiation.');
      return;
    }
    toast.success('Médiation amiable proposée. L\'autre partie est notifiée.');
    onUpdate();
  };

  const confirmerAccord = async () => {
    setLoadingAction('confirmer');
    const { data, error } = await supabase.rpc('fn_confirmer_accord_partie' as any, { p_litige_id: litige.id });
    setLoadingAction(null);
    if (error || !(data as any)?.success) {
      toast.error((data as any)?.error || 'Erreur lors de la confirmation d\'accord.');
      return;
    }
    if (autreAccord) {
      toast.success('✅ Accord mutuel confirmé — litige résolu sans pénalité.');
    } else {
      toast.success('Votre accord est enregistré. En attente de l\'autre partie.');
    }
    onUpdate();
  };

  const trancher = async () => {
    if (motif.trim().length < 50) {
      toast.error('Le motif de décision doit contenir au moins 50 caractères.');
      return;
    }
    setTrancherLoading(true);
    const { data, error } = await supabase.rpc('fn_admin_trancher_litige' as any, {
      p_litige_id: litige.id,
      p_decision: decision,
      p_motif: motif.trim(),
    });
    setTrancherLoading(false);
    if (error || !(data as any)?.success) {
      toast.error((data as any)?.error || 'Erreur lors de la décision.');
      return;
    }
    toast.success('Décision enregistrée et parties notifiées.');
    setShowTrancher(false);
    setMotif('');
    onUpdate();
  };

  if (estResolu(statut)) return null;

  // Admin : REVUE_ADMIN → Trancher
  if (role === 'ADMIN_PLATEFORME') {
    if (statut !== 'REVUE_ADMIN') return null;
    return (
      <>
        <Button size="sm" onClick={() => setShowTrancher(true)} className="gap-1.5 bg-destructive hover:bg-destructive/90 text-destructive-foreground">
          <Gavel className="h-3.5 w-3.5" /> Trancher
        </Button>

        <Dialog open={showTrancher} onOpenChange={setShowTrancher}>
          <DialogContent>
            <DialogHeader>
              <DialogTitle>Trancher le litige (revue admin)</DialogTitle>
            </DialogHeader>
            <div className="space-y-4 mt-2">
              <div className="rounded-xl bg-warning/5 border border-warning/20 p-3">
                <p className="text-xs text-warning font-medium">
                  ⚠️ Cette décision est définitive et notifie immédiatement les deux parties. Elle entraîne un malus scoring pour la partie défavorable (sauf PARTAGE).
                </p>
              </div>

              <div>
                <Label className="text-sm font-medium mb-2 block">Décision</Label>
                <RadioGroup value={decision} onValueChange={(v) => setDecision(v as DecisionAdmin)} className="space-y-2">
                  <div className="flex items-start gap-2">
                    <RadioGroupItem value="FAVEUR_SOIGNANT" id="d-soignant" className="mt-0.5" />
                    <Label htmlFor="d-soignant" className="text-sm font-normal cursor-pointer">
                      <span className="font-medium">En faveur du soignant</span>
                      <span className="block text-xs text-muted-foreground">L'établissement subit le malus scoring.</span>
                    </Label>
                  </div>
                  <div className="flex items-start gap-2">
                    <RadioGroupItem value="FAVEUR_ETAB" id="d-etab" className="mt-0.5" />
                    <Label htmlFor="d-etab" className="text-sm font-normal cursor-pointer">
                      <span className="font-medium">En faveur de l'établissement</span>
                      <span className="block text-xs text-muted-foreground">Le soignant subit le malus scoring.</span>
                    </Label>
                  </div>
                  <div className="flex items-start gap-2">
                    <RadioGroupItem value="PARTAGE" id="d-partage" className="mt-0.5" />
                    <Label htmlFor="d-partage" className="text-sm font-normal cursor-pointer">
                      <span className="font-medium">Décision partagée</span>
                      <span className="block text-xs text-muted-foreground">Aucun malus scoring (responsabilités partagées).</span>
                    </Label>
                  </div>
                </RadioGroup>
              </div>

              <div>
                <Label className="text-sm font-medium mb-1.5 block">Motif de la décision (min. 50 caractères)</Label>
                <Textarea
                  value={motif}
                  onChange={(e) => setMotif(e.target.value)}
                  placeholder="Expliquez les raisons de votre décision (visible par les deux parties)..."
                  rows={4}
                  maxLength={2000}
                />
                <p className="text-[10px] text-muted-foreground mt-1 text-right">
                  {motif.length}/2000 — min. 50
                </p>
              </div>

              <div className="flex justify-end gap-2">
                <Button variant="ghost" onClick={() => setShowTrancher(false)} disabled={trancherLoading}>Annuler</Button>
                <Button onClick={trancher} disabled={trancherLoading || motif.trim().length < 50}>
                  {trancherLoading ? <><Loader2 className="h-3.5 w-3.5 mr-1 animate-spin" /> Décision…</> : <><Gavel className="h-3.5 w-3.5 mr-1" /> Confirmer la décision</>}
                </Button>
              </div>
            </div>
          </DialogContent>
        </Dialog>
      </>
    );
  }

  // Soignant / Etablissement
  if (statut === 'REVUE_ADMIN') {
    return (
      <div className="rounded-xl bg-destructive/5 border border-destructive/20 px-3 py-2 text-xs text-destructive font-medium">
        ⚖️ Litige en revue admin — un administrateur va trancher.
      </div>
    );
  }

  return (
    <div className="flex flex-wrap gap-2">
      {peutProposerMediation(statut) && (
        <Button
          size="sm"
          variant="outline"
          className="gap-1.5 border-warning/30 text-warning hover:bg-warning/10"
          disabled={loadingAction !== null}
          onClick={proposerMediation}
        >
          <ShieldAlert className="h-3.5 w-3.5" />
          {loadingAction === 'proposer' ? 'Envoi…' : 'Proposer médiation amiable'}
        </Button>
      )}

      {peutConfirmerAccord(statut) && !monAccord && (
        <Button
          size="sm"
          className="gap-1.5 bg-success hover:bg-success/90 text-success-foreground"
          disabled={loadingAction !== null}
          onClick={confirmerAccord}
        >
          <Handshake className="h-3.5 w-3.5" />
          {loadingAction === 'confirmer' ? 'En cours…' : (autreAccord ? 'Accepter l\'accord' : 'Confirmer un accord')}
        </Button>
      )}

      {monAccord && !autreAccord && peutConfirmerAccord(statut) && (
        <div className="inline-flex items-center gap-1.5 text-xs text-primary font-medium px-3 py-2 rounded-lg bg-primary/5 border border-primary/20">
          <CheckCircle className="h-3.5 w-3.5" />
          Votre accord est enregistré — en attente de l'autre partie
        </div>
      )}
    </div>
  );
}
