import { useState, useEffect } from 'react';
import { CreditCard, Banknote, FileText, Loader2, ExternalLink } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { Button } from '@/components/ui/button';
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
    setDeclaring(true);
    try {
      const { error } = await (supabase.from('paiements_soignant' as any) as any).insert({
        mission_id: missionId,
        soignant_id: soignantAssigneId,
        etablissement_id: etablissementId,
        montant: info?.montant_soignant || 0,
        mode: info?.mode_recommande || 'VIREMENT_PAIE',
        statut: 'DECLARE',
      });
      if (error) throw error;
      toast.success('Paiement déclaré — le soignant sera notifié');
    } catch {
      toast.error('Erreur lors de la déclaration');
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
          <CreditCard className="h-4 w-4" /> Payer commission + honoraires
        </Button>
      </div>
    );
  }

  if (info.mode_recommande === 'VIREMENT_NOTE_HONORAIRES') {
    return (
      <div className="card-base border-primary/20 space-y-3">
        <p className="text-sm font-semibold text-foreground flex items-center gap-2">
          <FileText className="h-4 w-4 text-primary" /> Paiement par note d'honoraires
        </p>
        <p className="text-xs text-muted-foreground">
          Ce soignant exerce en libéral. Il vous enverra une note d'honoraires de {fmt(info.montant_soignant)}.
        </p>
        {info.iban_soignant && (
          <p className="text-xs text-muted-foreground">
            IBAN : ****{info.iban_soignant}
          </p>
        )}
        <Button size="sm" variant="outline" onClick={declarerPaiement} disabled={declaring} className="gap-2">
          <Banknote className="h-4 w-4" /> {declaring ? 'Déclaration…' : 'Déclarer le paiement effectué'}
        </Button>
      </div>
    );
  }

  // VIREMENT_PAIE (default for salaried)
  return (
    <div className="card-base border-primary/20 space-y-3">
      <p className="text-sm font-semibold text-foreground flex items-center gap-2">
        <Banknote className="h-4 w-4 text-primary" /> Paiement par virement / paie
      </p>
      <div className="text-xs text-muted-foreground space-y-1">
        <p>Net à payer au soignant : {fmt(info.montant_soignant)}</p>
      </div>
      {info.iban_soignant && (
        <p className="text-xs text-muted-foreground">
          RIB : ****{info.iban_soignant}
        </p>
      )}
      <Button size="sm" variant="outline" onClick={declarerPaiement} disabled={declaring} className="gap-2">
        <Banknote className="h-4 w-4" /> {declaring ? 'Déclaration…' : 'Déclarer le paiement effectué'}
      </Button>
    </div>
  );
}
