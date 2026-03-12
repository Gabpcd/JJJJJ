import { useState } from 'react';
import { Landmark, Loader2 } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/contexts/AuthContext';
import { useNotification } from '@/contexts/NotificationContext';

interface Props {
  facture: any;
  onUpdate: () => void;
}

export function FactureChorus({ facture, onUpdate }: Props) {
  const { user } = useAuth();
  const { afficherNotification } = useNotification();
  const [loading, setLoading] = useState(false);
  const [open, setOpen] = useState(false);

  const deposer = async () => {
    if (!user) return;
    setLoading(true);
    await supabase.from('factures').update({
      chorus_pro_statut: 'DEPOSEE',
      chorus_pro_deposee_le: new Date().toISOString(),
    } as any).eq('id', facture.id);

    await supabase.rpc('fn_ecrire_audit_safe', {
      p_acteur_id: user.id,
      p_type_acteur: 'ADMIN_ETABLISSEMENT',
      p_action: 'FINANCE_CHORUS_DEPOSE',
      p_type_ressource: 'facture',
      p_id_ressource: facture.id,
      p_cle_s3: null,
      p_details: { numero: facture.numero_facture },
      p_ip: null,
      p_navigateur: navigator.userAgent,
    });

    setLoading(false);
    setOpen(false);
    afficherNotification({ type: 'succes', message: '✅ Facture marquée comme déposée sur Chorus Pro' });
    onUpdate();
  };

  if (facture.chorus_pro_statut === 'DEPOSEE') {
    return (
      <span className="text-xs text-muted-foreground flex items-center gap-1">
        <Landmark className="h-3.5 w-3.5" /> Déposée sur Chorus
      </span>
    );
  }

  if (!open) {
    return (
      <button onClick={() => setOpen(true)} className="btn-secondary text-xs flex items-center gap-1">
        <Landmark className="h-3.5 w-3.5" /> Chorus Pro
      </button>
    );
  }

  return (
    <div className="card-base p-3 space-y-2 mt-2 w-full">
      <p className="text-sm font-semibold text-foreground flex items-center gap-1">
        <Landmark className="h-4 w-4 text-primary" /> Facture secteur public — Chorus Pro
      </p>
      <p className="text-xs text-muted-foreground">
        Cette facture doit être déposée sur Chorus Pro. Délai de paiement estimé : 30-60 jours.
      </p>
      <div className="flex gap-2">
        <button onClick={deposer} disabled={loading} className="btn-primary text-xs flex items-center gap-1 disabled:opacity-50">
          {loading ? <Loader2 className="h-3.5 w-3.5 animate-spin" /> : <Landmark className="h-3.5 w-3.5" />}
          📤 Marquer comme déposée
        </button>
        <button onClick={() => setOpen(false)} className="btn-secondary text-xs">Annuler</button>
      </div>
    </div>
  );
}
