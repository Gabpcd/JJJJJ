import { useState, useEffect } from 'react';
import { CreditCard, Banknote, FileText, Loader2, Eye, CheckCircle, Edit2 } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Dialog, DialogContent, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { toast } from 'sonner';

interface Props {
  missionId: string;
  soignantAssigneId: string;
  etablissementId: string;
  onStartConnectPay: () => void;
  soignantHasConnect: boolean;
}

type ModeRecommande = 'STRIPE_CONNECT' | 'VIREMENT_PAIE' | 'VIREMENT_NOTE_HONORAIRES';

interface InfoPaiement {
  mode_recommande: ModeRecommande;
  montant_soignant: number;
  commission_ttc: number;
  total: number;
  iban_soignant?: string;
  type_exercice?: string;
}

const isRefValid = (ref: string) => ref.trim().length >= 5 && /\d/.test(ref);

export function WorkflowPaiementMission({ missionId, soignantAssigneId, etablissementId, onStartConnectPay, soignantHasConnect }: Props) {
  const [info, setInfo] = useState<InfoPaiement | null>(null);
  const [loading, setLoading] = useState(true);
  const [declaring, setDeclaring] = useState(false);
  const [reference, setReference] = useState('');
  const [ribLoading, setRibLoading] = useState(false);
  const [ribData, setRibData] = useState<string | null>(null);
  const [paiementExistant, setPaiementExistant] = useState<any>(null);
  const [showModifRef, setShowModifRef] = useState(false);
  const [newRef, setNewRef] = useState('');
  const [modifLoading, setModifLoading] = useState(false);

  useEffect(() => {
    const load = async () => {
      const [{ data: modeData, error: modeErr }, { data: paiementData }] = await Promise.all([
        supabase.rpc('fn_mode_paiement_mission' as any, { p_mission_id: missionId }),
        supabase.from('paiements_soignant')
          .select('*')
          .eq('mission_id', missionId)
          .in('statut', ['DECLARE', 'CONFIRME', 'CONTESTE'])
          .order('cree_le', { ascending: false })
          .limit(1),
      ]);
      if (!modeErr && modeData) {
        setInfo(modeData as unknown as InfoPaiement);
      }
      if (paiementData && paiementData.length > 0) {
        setPaiementExistant(paiementData[0]);
      }
      setLoading(false);
    };
    load();
  }, [missionId]);

  const consulterRib = async () => {
    setRibLoading(true);
    try {
      const { data, error } = await supabase.rpc('fn_consulter_rib_soignant' as any, { p_mission_id: missionId });
      if (error) throw error;
      const result = data as any;
      if (result?.error) throw new Error(result.error);
      if (result?.s3_cle && result?.s3_bucket) {
        const { data: urlData } = await supabase.storage.from(result.s3_bucket).createSignedUrl(result.s3_cle, 300);
        if (urlData?.signedUrl) {
          window.open(urlData.signedUrl, '_blank');
          setRibData('opened');
          return;
        }
      }
      setRibData(result?.iban || result);
    } catch (e: any) {
      toast.error(e?.message || 'Impossible de consulter le RIB');
    }
    setRibLoading(false);
  };

  const declarerPaiement = async () => {
    if (!isRefValid(reference)) {
      toast.error('La référence doit contenir au moins 5 caractères dont 1 chiffre');
      return;
    }
    setDeclaring(true);
    try {
      const { data, error } = await supabase.rpc('fn_declarer_paiement_soignant' as any, {
        p_mission_id: missionId,
        p_montant: info?.montant_soignant || 0,
        p_reference: reference.trim(),
      });
      if (error) throw error;
      const result = data as any;
      if (result?.error) {
        if (result?.use_stripe_connect) {
          toast.info('Ce soignant utilise Stripe Connect — redirection vers le paiement par carte');
          onStartConnectPay();
          return;
        }
        throw new Error(result.error);
      }
      toast.success('Paiement déclaré — le soignant sera notifié');
      setReference('');
      // Reload payment status
      const { data: pData } = await supabase.from('paiements_soignant')
        .select('*').eq('mission_id', missionId)
        .in('statut', ['DECLARE', 'CONFIRME', 'CONTESTE'])
        .order('cree_le', { ascending: false }).limit(1);
      if (pData?.length) setPaiementExistant(pData[0]);
    } catch (e: any) {
      toast.error(e?.message || 'Erreur lors de la déclaration');
    }
    setDeclaring(false);
  };

  const modifierReference = async () => {
    if (!isRefValid(newRef) || !paiementExistant) return;
    setModifLoading(true);
    try {
      const { data, error } = await supabase.rpc('fn_modifier_reference_paiement' as any, {
        p_paiement_id: paiementExistant.id,
        p_nouvelle_reference: newRef.trim(),
      });
      if (error) throw error;
      if ((data as any)?.error) throw new Error((data as any).error);
      toast.success('Référence modifiée');
      setPaiementExistant({ ...paiementExistant, reference_virement: newRef.trim() });
      setShowModifRef(false);
    } catch (e: any) {
      toast.error(e?.message || 'Erreur');
    }
    setModifLoading(false);
  };

  if (loading) {
    return (
      <div className="card-base flex items-center justify-center py-4">
        <Loader2 className="h-4 w-4 animate-spin text-muted-foreground" />
      </div>
    );
  }

  if (!info) return null;

  const fmt = (v: number) => new Intl.NumberFormat('fr-FR', { style: 'currency', currency: 'EUR' }).format(v);

  // If payment already declared, show status
  if (paiementExistant) {
    const p = paiementExistant;
    const statutLabel = p.statut === 'CONFIRME' ? 'Confirmé ✅' : p.statut === 'CONTESTE' ? 'Contesté ⚠️' : 'En attente de confirmation du soignant';
    const statutColor = p.statut === 'CONFIRME' ? 'text-success' : p.statut === 'CONTESTE' ? 'text-warning' : 'text-muted-foreground';
    const canModifyRef = p.statut === 'DECLARE' && !p.confirme_par_soignant;

    return (
      <div className="card-base border-success/20 space-y-2">
        <p className="text-sm font-semibold text-foreground flex items-center gap-2">
          <CheckCircle className="h-4 w-4 text-success" /> Paiement déclaré
        </p>
        <div className="text-xs space-y-1">
          <p className="text-muted-foreground">Méthode : <span className="text-foreground font-medium">{p.methode === 'NOTE_HONORAIRES' ? "Note d'honoraires" : 'Virement'}</span></p>
          <p className="text-muted-foreground">Référence : <span className="text-foreground font-medium">{p.reference_virement}</span></p>
          <p className="text-muted-foreground">Montant : <span className="text-foreground font-medium">{fmt(p.montant_net)}</span></p>
          <p className={`font-medium ${statutColor}`}>Statut : {statutLabel}</p>
        </div>
        {canModifyRef && (
          <Button size="sm" variant="outline" className="gap-1.5 text-xs" onClick={() => { setNewRef(p.reference_virement || ''); setShowModifRef(true); }}>
            <Edit2 className="h-3 w-3" /> Modifier la référence
          </Button>
        )}
        <Dialog open={showModifRef} onOpenChange={setShowModifRef}>
          <DialogContent>
            <DialogHeader><DialogTitle>Modifier la référence de paiement</DialogTitle></DialogHeader>
            <div className="space-y-3 mt-2">
              <Input value={newRef} onChange={e => setNewRef(e.target.value)} placeholder="Ex: VIR-2026-03-001" />
              <div className="flex justify-end gap-2">
                <Button variant="ghost" onClick={() => setShowModifRef(false)}>Annuler</Button>
                <Button onClick={modifierReference} disabled={modifLoading || !isRefValid(newRef)}>
                  {modifLoading ? 'Modification…' : 'Enregistrer'}
                </Button>
              </div>
            </div>
          </DialogContent>
        </Dialog>
      </div>
    );
  }

  // Stripe Connect: paiement automatique
  if (info.mode_recommande === 'STRIPE_CONNECT' && soignantHasConnect) {
    return (
      <div className="card-base border-primary/20 space-y-3">
        <p className="text-sm font-semibold text-foreground flex items-center gap-2">
          <CreditCard className="h-4 w-4 text-primary" /> Paiement Stripe Connect
        </p>
        <div className="text-xs text-muted-foreground space-y-1">
          <p>Commission Jolene : {fmt(info.commission_ttc)}</p>
          <p>Honoraires soignant : {fmt(info.montant_soignant)}</p>
          <p className="font-semibold text-foreground">Total : {fmt(info.total)}</p>
        </div>
        <Button size="sm" onClick={onStartConnectPay} className="gap-2">
          <CreditCard className="h-4 w-4" /> 💳 Payer via Stripe
        </Button>
      </div>
    );
  }

  // Manual payment with required reference
  const methodeLabel = info.mode_recommande === 'VIREMENT_NOTE_HONORAIRES' ? "Note d'honoraires" : 'Bulletin de paie';
  const icone = info.mode_recommande === 'VIREMENT_NOTE_HONORAIRES' ? FileText : Banknote;
  const Icone = icone;
  const trimmedRef = reference.trim();
  const refTooShort = trimmedRef.length > 0 && trimmedRef.length < 5;
  const refNoDigit = trimmedRef.length >= 5 && !/\d/.test(trimmedRef);

  return (
    <div className="card-base border-primary/20 space-y-3">
      <p className="text-sm font-semibold text-foreground flex items-center gap-2">
        <Icone className="h-4 w-4 text-primary" /> Paiement par {methodeLabel.toLowerCase()}
      </p>
      <div className="text-xs text-muted-foreground space-y-1">
        <p>Net à payer au soignant : {fmt(info.montant_soignant)}</p>
        <p>Méthode : <span className="font-medium text-foreground">{methodeLabel}</span></p>
      </div>

      {/* RIB soignant — uniquement pour les missions salariées (bulletin de paie) */}
      {info.mode_recommande === 'VIREMENT_PAIE' && (
        info.iban_soignant ? (
          <p className="text-xs text-muted-foreground">
            RIB : ****{info.iban_soignant}
          </p>
        ) : (
          <div className="flex items-center gap-2">
            {ribData ? (
              ribData === 'opened' ? (
                <p className="text-xs text-success">📄 RIB ouvert dans un nouvel onglet</p>
              ) : (
                <p className="text-xs text-muted-foreground">IBAN : {ribData}</p>
              )
            ) : (
              <Button size="sm" variant="ghost" className="gap-1 text-xs h-7" onClick={consulterRib} disabled={ribLoading}>
                {ribLoading ? <Loader2 className="h-3 w-3 animate-spin" /> : <Eye className="h-3 w-3" />}
                📄 Voir le RIB (PDF)
              </Button>
            )}
          </div>
        )
      )}

      <div className="space-y-2">
        <label className="text-xs font-medium text-foreground">Référence de paiement *</label>
        <Input
          placeholder="Ex: VIR-2026-03-001"
          value={reference}
          onChange={e => setReference(e.target.value)}
          className="text-sm"
        />
        <p className="text-[10px] text-muted-foreground">Numéro de virement bancaire, référence de chèque ou numéro de facture</p>
        {refTooShort && (
          <p className="text-[10px] text-destructive">Minimum 5 caractères</p>
        )}
        {refNoDigit && (
          <p className="text-[10px] text-destructive">La référence doit contenir au moins 1 chiffre</p>
        )}
      </div>
      <Button size="sm" variant="outline" onClick={declarerPaiement} disabled={declaring || !isRefValid(reference)} className="gap-2">
        <Banknote className="h-4 w-4" /> {declaring ? 'Déclaration…' : 'Déclarer le paiement effectué'}
      </Button>
    </div>
  );
}
