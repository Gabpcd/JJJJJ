import { useEffect, useState } from 'react';
import { Ban, ShieldCheck } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { toast } from 'sonner';

interface Props {
  /** user_id de la cible (auth.users.id). */
  cibleId: string;
  /** Rendu compact (lien texte) au lieu d'un bouton plein. */
  variant?: 'bouton' | 'lien';
  /** Libellé métier lorsque la cible représente une équipe partagée. */
  libelleCible?: string;
}

/**
 * Bouton Bloquer / Débloquer un utilisateur (App Store Guideline 1.2 — UGC :
 * report ET block). Un blocage coupe la messagerie dans les deux sens
 * (fn_envoyer_message refuse). Complète SignalerUtilisateur.
 */
export function BloquerUtilisateur({ cibleId, variant = 'lien', libelleCible = 'cet utilisateur' }: Props) {
  const [bloque, setBloque] = useState<boolean | null>(null);
  const [busy, setBusy] = useState(false);
  const [confirm, setConfirm] = useState(false);
  const [erreurLecture, setErreurLecture] = useState(false);
  const [tentativeLecture, setTentativeLecture] = useState(0);

  useEffect(() => {
    let alive = true;
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 10_000);
    setBloque(null);
    setConfirm(false);
    setErreurLecture(false);
    void (async () => {
      try {
        const { data, error } = await supabase.rpc('fn_est_bloque' as any, { p_cible_id: cibleId }).abortSignal(controller.signal);
        if (!alive) return;
        if (error || typeof data !== 'boolean') setErreurLecture(true);
        else setBloque(data);
      } catch {
        if (alive) setErreurLecture(true);
      } finally {
        clearTimeout(timeout);
      }
    })();
    return () => { alive = false; clearTimeout(timeout); controller.abort(); };
  }, [cibleId, tentativeLecture]);

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
      toast.success(
        bloque
          ? `${libelleCible.charAt(0).toUpperCase()}${libelleCible.slice(1)} débloqué${libelleCible === 'l’établissement' ? '' : '·e'}.`
          : `${libelleCible.charAt(0).toUpperCase()}${libelleCible.slice(1)} bloqué${libelleCible === 'l’établissement' ? '' : '·e'} — les nouveaux messages sont coupés dans les deux sens.`,
      );
    } catch {
      toast.error('Action impossible pour le moment. Réessayez.');
    } finally {
      setBusy(false);
    }
  };

  if (erreurLecture) return (
    <span className="inline-flex flex-wrap items-center gap-2 text-xs text-muted-foreground">
      <span role="status">Statut de blocage indisponible.</span>
      <button type="button" onClick={() => setTentativeLecture(n => n + 1)} className="underline">Réessayer le statut de blocage</button>
    </span>
  );
  if (bloque === null) return null;

  const label = bloque ? 'Débloquer' : 'Bloquer';
  const Icone = bloque ? ShieldCheck : Ban;

  // Blocage : confirmation en 2 temps (action modératrice). Déblocage : direct.
  if (!bloque && confirm) {
    return (
      <span className="inline-flex items-center gap-2 text-xs">
        <span className="text-muted-foreground">Bloquer {libelleCible} ?</span>
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
