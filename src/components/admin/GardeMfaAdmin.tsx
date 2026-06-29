import { useEffect, useState, useCallback } from 'react';
import { ShieldCheck, Loader2, Mail } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { toast } from 'sonner';

/**
 * Garde 2FA obligatoire pour les administrateurs — par EMAIL (gratuit).
 *
 * À l'accès admin, si la session n'a pas été vérifiée récemment (12 h, et après la
 * dernière connexion), un code à 6 chiffres est envoyé par email ; l'admin le saisit
 * pour accéder. Aucune app d'authentification ni SMS payant.
 *
 * Conçu pour ne jamais verrouiller : on peut toujours redemander un code. Toute la
 * logique (génération, envoi, vérification) est dans l'edge function admin-2fa.
 */
export function GardeMfaAdmin({ children }: { children: React.ReactNode }) {
  const [etat, setEtat] = useState<'chargement' | 'ok' | 'code'>('chargement');
  const [code, setCode] = useState('');
  const [emailMasque, setEmailMasque] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [envoiInitial, setEnvoiInitial] = useState(false);

  const demanderCode = useCallback(async () => {
    setBusy(true);
    const { data, error } = await supabase.functions.invoke('admin-2fa', { body: { action: 'request' } });
    setBusy(false);
    if (error || !(data as any)?.success) {
      toast.error((data as any)?.error || "Impossible d'envoyer le code par email.");
      return;
    }
    setEmailMasque((data as any)?.email_masque || null);
    setEnvoiInitial(true);
    toast.success('Code envoyé par email.');
  }, []);

  const evaluer = useCallback(async () => {
    setEtat('chargement');
    try {
      const { data, error } = await supabase.functions.invoke('admin-2fa', { body: { action: 'status' } });
      if (error) { toast.error('Erreur de vérification 2FA.'); setEtat('code'); return; }
      if ((data as any)?.valid) { setEtat('ok'); return; }
      setEtat('code');
      if (!envoiInitial) await demanderCode();
    } catch {
      toast.error('Erreur 2FA.');
      setEtat('code');
    }
  }, [demanderCode, envoiInitial]);

  useEffect(() => { evaluer(); }, [evaluer]);

  async function verifier() {
    if (code.trim().length < 6) { toast.error('Saisissez le code à 6 chiffres reçu par email.'); return; }
    setBusy(true);
    const { data, error } = await supabase.functions.invoke('admin-2fa', { body: { action: 'verify', code: code.trim() } });
    setBusy(false);
    if (error || !(data as any)?.success) {
      toast.error((data as any)?.error || 'Code incorrect.');
      return;
    }
    toast.success('Identité vérifiée.');
    setCode('');
    setEtat('ok');
  }

  if (etat === 'ok') return <>{children}</>;
  if (etat === 'chargement') {
    return <div className="min-h-[60vh] flex items-center justify-center"><Loader2 className="h-6 w-6 animate-spin text-primary" /></div>;
  }

  return (
    <div className="min-h-[100dvh] flex items-center justify-center p-4 bg-background">
      <div className="card-base max-w-md w-full space-y-4">
        <div className="flex items-center gap-2">
          <ShieldCheck className="h-6 w-6 text-primary" />
          <h1 className="text-xl font-bold text-foreground">Vérification administrateur</h1>
        </div>
        <p className="text-sm text-muted-foreground">
          Pour des raisons de sécurité, l'accès administrateur exige une double vérification.
          {envoiInitial
            ? ` Un code à 6 chiffres a été envoyé par email${emailMasque ? ` à ${emailMasque}` : ''}. Saisissez-le ci-dessous.`
            : ' Demandez un code email pour continuer.'}
        </p>
        <p className="text-xs text-muted-foreground">
          Si aucun email n'arrive, vérifiez la configuration Resend avant de réessayer.
        </p>
        <input
          value={code}
          onChange={(e) => setCode(e.target.value.replace(/\D/g, '').slice(0, 6))}
          inputMode="numeric"
          placeholder="123456"
          className="input-base text-center text-lg tracking-[0.4em] font-mono"
          onKeyDown={(e) => { if (e.key === 'Enter') verifier(); }}
        />
        <button type="button" onClick={verifier} disabled={busy || code.length < 6}
          className="btn-primary w-full disabled:opacity-50 inline-flex items-center justify-center gap-2">
          {busy ? <Loader2 className="h-4 w-4 animate-spin" /> : <ShieldCheck className="h-4 w-4" />} Valider
        </button>
        <button type="button" onClick={demanderCode} disabled={busy}
          className="text-xs text-muted-foreground hover:text-foreground w-full text-center inline-flex items-center justify-center gap-1">
          <Mail className="h-3 w-3" /> Renvoyer le code
        </button>
      </div>
    </div>
  );
}
