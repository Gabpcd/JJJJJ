import { useState, useEffect } from 'react';
import { CreditCard, Banknote, FileText, Loader2 } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
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

export function WorkflowPaiementMission({ missionId, soignantAssigneId, etablissementId, onStartConnectPay, soignantHasConnect }: Props) {
  const [info, setInfo] = useState<InfoPaiement | null>(null);
  const [loading, setLoading] = useState(true);
  const [declaring, setDeclaring] = useState(false);
  const [reference, setReference] = useState('');

  useEffect(() => {
    const load = async () => {
      const { data, error } = await supabase.rpc('fn_mode_paiement_mission' as any, { p_mission_id: missionId });
      if (!error && data) {
        setInfo(data as unknown as InfoPaiement);
      }
      setLoading(false);
    };
    load();
  }, [missionId]);

  const declarerPaiement = async () => {
    if (!reference.trim()) {
      toast.error('Veuillez saisir une référence de paiement');
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
    } catch (e: any) {
      toast.error(e?.message || 'Erreur lors de la déclaration');
    }
    setDeclaring(false);
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

  return (
    <div className="card-base border-primary/20 space-y-3">
      <p className="text-sm font-semibold text-foreground flex items-center gap-2">
        <Icone className="h-4 w-4 text-primary" /> Paiement par {methodeLabel.toLowerCase()}
      </p>
      <div className="text-xs text-muted-foreground space-y-1">
        <p>Net à payer au soignant : {fmt(info.montant_soignant)}</p>
        <p>Méthode : <span className="font-medium text-foreground">{methodeLabel}</span></p>
      </div>
      {info.iban_soignant && (
        <p className="text-xs text-muted-foreground">
          RIB : ****{info.iban_soignant}
        </p>
      )}
      <div className="space-y-2">
        <label className="text-xs font-medium text-foreground">Référence de paiement *</label>
        <Input
          placeholder="Numéro de virement, référence chèque, etc."
          value={reference}
          onChange={e => setReference(e.target.value)}
          className="text-sm"
        />
      </div>
      <Button size="sm" variant="outline" onClick={declarerPaiement} disabled={declaring || !reference.trim()} className="gap-2">
        <Banknote className="h-4 w-4" /> {declaring ? 'Déclaration…' : 'Déclarer le paiement effectué'}
      </Button>
    </div>
  );
}
