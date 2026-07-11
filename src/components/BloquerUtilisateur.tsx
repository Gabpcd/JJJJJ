import { useEffect, useState } from 'react';
import { Ban, ShieldCheck } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { toast } from 'sonner';

interface Props {
  /** user_id de la cible (auth.users.id). */
  cibleId: string;
  /** Rendu compact (lien texte) au lieu d'un bouton plein. */
  variant?: 'bouton' | 'lien';
}

/**
 * Bouton Bloquer / Débloquer un utilisateur (App Store Guideline 1.2 — UGC :
 * report ET block). Un blocage coupe la messagerie dans les deux sens
 * (fn_envoyer_message refuse). Complète SignalerUtilisateur.
 */
export function BloquerUtilisateur({ cibleId, variant = 'lien' }: Props) {
  const [bloque, setBloque] = useState<boolean | null>(null);
  const [busy, setBusy] = useState(false);
  const [confirm, setConfirm] = useState(false);

  useEffect(() => {
    let alive = true;
    supabase.rpc('fn_est_bloque' as any, { p_cible_id: cibleId }).then(({ data }) => {
      if (alive) setBloque(data === true);
    });
    return () => { alive = false; };
  }, [cibleId]);

  const basculer = async () => {
    setBusy(true);
    try {
      const rpc = bloque ? 'fn_debloquer_utilisateur' : 'fn_bloquer_utilisateur';
      const { data, error } = await supabase.rpc(rpc as any, { p_cible_id: cibleId });
      if (error || (data as any)?.error) {
        toast.error((data as any)?.error || 'Action impossible pour le moment.');
        return;
      }
      setBloque(!bloque);
      setConfirm(false);
      toast.success(bloque ? 'Utilisateur débloqué.' : 'Utilisateur bloqué — vous ne recevrez plus ses messages.');
    } finally {
      setBusy(false);
    }
  };

  if (bloque === null) return null;

  const label = bloque ? 'Débloquer' : 'Bloquer';
  const Icone = bloque ? ShieldCheck : Ban;

  // Blocage : confirmation en 2 temps (action modératrice). Déblocage : direct.
  if (!bloque && confirm) {
    return (
      <span className="inline-flex items-center gap-2 text-xs">
        <span className="text-muted-foreground">Bloquer cet utilisateur ?</span>
        <button type="button" disabled={busy} onClick={basculer} className="font-semibold text-destructive hover:underline disabled:opacity-50">Confirmer</button>
        <button type="button" onClick={() => setConfirm(false)} className="text-muted-foreground hover:underline">Annuler</button>
      </span>
    );
  }

  const onClick = () => (bloque ? basculer() : setConfirm(true));

  if (variant === 'bouton') {
    return (
      <button type="button" disabled={busy} onClick={onClick}
        className="inline-flex items-center gap-1.5 rounded-lg border border-border px-3 py-1.5 text-xs font-medium text-foreground hover:bg-muted disabled:opacity-50">
        <Icone className="h-3.5 w-3.5" />{label}
      </button>
    );
  }
  return (
    <button type="button" disabled={busy} onClick={onClick}
      className="inline-flex items-center gap-1 text-xs text-muted-foreground hover:text-foreground disabled:opacity-50">
      <Icone className="h-3 w-3" />{label}
    </button>
  );
}
