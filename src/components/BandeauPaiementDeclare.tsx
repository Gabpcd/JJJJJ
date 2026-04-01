import { useState, useEffect } from 'react';
import { Banknote, Check, X } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { fetchEtablissementsSafe } from '@/lib/etablissements';
import { useAuth } from '@/contexts/AuthContext';
import { Button } from '@/components/ui/button';
import { toast } from 'sonner';

interface PaiementDeclare {
  id: string;
  montant: number;
  mission_id: string;
  etablissement_nom: string;
}

export function BandeauPaiementDeclare() {
  const { user } = useAuth();
  const [paiements, setPaiements] = useState<PaiementDeclare[]>([]);
  const [processing, setProcessing] = useState<string | null>(null);

  useEffect(() => {
    if (!user) return;
    const load = async () => {
      const { data } = await supabase
        .from('paiements_soignant' as any)
        .select('id, montant_net, mission_id, etablissement_id')
        .eq('soignant_id', user.id)
        .eq('statut', 'DECLARE') as any;

      if (!data || data.length === 0) return;

      // Enrich with establishment names via secure RPC
      const etabIds = [...new Set(data.map((p: any) => p.etablissement_id))] as string[];
      const safeMap = await fetchEtablissementsSafe(etabIds);
      const etabMap: Record<string, string> = {};
      Object.entries(safeMap).forEach(([id, e]) => { etabMap[id] = e.nom; });

      setPaiements(data.map((p: any) => ({
        id: p.id,
        montant: p.montant_net,
        mission_id: p.mission_id,
        etablissement_nom: etabMap[p.etablissement_id] || 'Établissement',
      })));
    };
    load();
  }, [user]);

  const traiter = async (paiementId: string, confirme: boolean) => {
    setProcessing(paiementId);
    try {
      if (confirme) {
        const { error } = await (supabase.from('paiements_soignant' as any) as any)
          .update({
            statut: 'CONFIRME',
            confirme_par_soignant: true,
            confirme_par_soignant_le: new Date().toISOString(),
          })
          .eq('id', paiementId);
        if (error) throw error;
      } else {
        const { data, error } = await supabase.rpc('fn_contester_paiement_soignant' as any, {
          p_paiement_id: paiementId,
          p_motif: 'Contesté par le soignant',
        });
        if (error) throw error;
        if ((data as any)?.error) throw new Error((data as any).error);
      }
      toast.success(confirme ? 'Paiement confirmé ✅' : 'Contestation envoyée');
      setPaiements(prev => prev.filter(p => p.id !== paiementId));
    } catch {
      toast.error('Erreur lors du traitement');
    }
    setProcessing(null);
  };

  if (paiements.length === 0) return null;

  return (
    <div className="space-y-3 mb-4">
      {paiements.map(p => (
        <div key={p.id} className="rounded-xl border border-primary/30 bg-primary/5 p-4">
          <div className="flex items-start gap-3">
            <Banknote className="h-5 w-5 text-primary shrink-0 mt-0.5" />
            <div className="flex-1 min-w-0">
              <p className="text-sm font-semibold text-foreground">
                💰 {p.etablissement_nom} déclare vous avoir payé{' '}
                {new Intl.NumberFormat('fr-FR', { style: 'currency', currency: 'EUR' }).format(p.montant)}
              </p>
              <p className="text-xs text-muted-foreground mt-1">
                Confirmez la réception ou contestez si ce n'est pas correct.
              </p>
              <div className="flex gap-2 mt-3">
                <Button
                  size="sm"
                  onClick={() => traiter(p.id, true)}
                  disabled={processing === p.id}
                  className="gap-1.5"
                >
                  <Check className="h-3.5 w-3.5" /> Confirmer
                </Button>
                <Button
                  variant="outline"
                  size="sm"
                  onClick={() => traiter(p.id, false)}
                  disabled={processing === p.id}
                  className="gap-1.5"
                >
                  <X className="h-3.5 w-3.5" /> Contester
                </Button>
              </div>
            </div>
          </div>
        </div>
      ))}
    </div>
  );
}
