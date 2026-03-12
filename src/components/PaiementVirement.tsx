import { useState } from 'react';
import { Banknote, Loader2 } from 'lucide-react';
import { ENTREPRISE } from '@/constantes/entreprise';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/contexts/AuthContext';
import { useNotification } from '@/contexts/NotificationContext';

interface Props {
  facture: any;
  onUpdate: () => void;
}

export function PaiementVirement({ facture, onUpdate }: Props) {
  const { user } = useAuth();
  const { afficherNotification } = useNotification();
  const [open, setOpen] = useState(false);
  const [reference, setReference] = useState('');
  const [loading, setLoading] = useState(false);

  const confirmer = async () => {
    if (!user || !reference.trim()) return;
    setLoading(true);

    await supabase.from('factures').update({
      mode_paiement: 'VIREMENT',
      virement_reference: reference.trim(),
      virement_confirme_par: user.id,
      virement_confirme_le: new Date().toISOString(),
    } as any).eq('id', facture.id);

    await supabase.rpc('fn_ecrire_audit_safe', {
      p_acteur_id: user.id,
      p_type_acteur: 'ADMIN_ETABLISSEMENT',
      p_action: 'FINANCE_VIREMENT_CONFIRME',
      p_type_ressource: 'facture',
      p_id_ressource: facture.id,
      p_cle_s3: null,
      p_details: { numero: facture.numero_facture, reference: reference.trim() },
      p_ip: null,
      p_navigateur: navigator.userAgent,
    });

    setLoading(false);
    setOpen(false);
    afficherNotification({ type: 'succes', message: '✅ Virement déclaré — en attente de vérification' });
    onUpdate();
  };

  if (!open) {
    return (
      <button onClick={() => setOpen(true)} className="btn-secondary text-xs flex items-center gap-1">
        <Banknote className="h-3.5 w-3.5" /> Virement
      </button>
    );
  }

  return (
    <div className="card-base p-3 space-y-3 mt-2 w-full">
      <p className="text-sm font-semibold text-foreground flex items-center gap-1">
        <Banknote className="h-4 w-4 text-primary" /> Paiement par virement
      </p>
      <div className="text-xs text-muted-foreground space-y-1 bg-muted/50 rounded-lg p-3">
        <p><strong>Bénéficiaire :</strong> {ENTREPRISE.nom}</p>
        <p><strong>IBAN :</strong> {ENTREPRISE.iban}</p>
        <p><strong>BIC :</strong> {ENTREPRISE.bic}</p>
        <p><strong>Référence :</strong> {facture.numero_facture}</p>
      </div>
      <div>
        <label className="text-xs font-medium text-foreground block mb-1">Référence de votre virement</label>
        <input
          value={reference}
          onChange={e => setReference(e.target.value)}
          placeholder="Ex: VIR-20260312-001"
          className="input-base text-sm"
        />
      </div>
      <div className="flex gap-2">
        <button onClick={confirmer} disabled={loading || !reference.trim()} className="btn-primary text-xs flex items-center gap-1 disabled:opacity-50">
          {loading ? <Loader2 className="h-3.5 w-3.5 animate-spin" /> : null}
          ✅ J'ai effectué le virement
        </button>
        <button onClick={() => setOpen(false)} className="btn-secondary text-xs">Annuler</button>
      </div>
    </div>
  );
}
