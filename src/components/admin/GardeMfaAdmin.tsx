import { useEffect, useState, useCallback } from 'react';
import { ShieldCheck, Loader2, Smartphone } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { toast } from 'sonner';

/**
 * Garde MFA obligatoire pour les administrateurs plateforme — par SMS (code à 6
 * chiffres envoyé sur le téléphone).
 *
 * Tant que la session admin n'est pas au niveau AAL2, on demande le numéro (1re
 * fois) puis on envoie/valide un code SMS. Conçu pour NE JAMAIS verrouiller :
 * l'enrôlement reste accessible, et un facteur peut être supprimé depuis le
 * dashboard Supabase (Authentication > Users) en dernier recours.
 *
 * Prérequis projet : un fournisseur SMS configuré dans Supabase Auth + le facteur
 * « Phone » MFA activé (Dashboard > Authentication > Multi-Factor).
 */
export function GardeMfaAdmin({ children }: { children: React.ReactNode }) {
  const [etat, setEtat] = useState<'chargement' | 'ok' | 'saisie_tel' | 'code'>('chargement');
  const [factorId, setFactorId] = useState<string | null>(null);
  const [challengeId, setChallengeId] = useState<string | null>(null);
  const [tel, setTel] = useState('');
  const [code, setCode] = useState('');
  const [telMasque, setTelMasque] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  // Envoie un challenge SMS pour un facteur téléphone vérifié.
  const envoyerSms = useCallback(async (fid: string) => {
    const { data: ch, error } = await supabase.auth.mfa.challenge({ factorId: fid });
    if (error || !ch?.id) { toast.error("Échec de l'envoi du code SMS."); return; }
    setChallengeId(ch.id);
    setEtat('code');
  }, []);

  const evaluer = useCallback(async () => {
    setEtat('chargement');
    try {
      const { data: aal } = await supabase.auth.mfa.getAuthenticatorAssuranceLevel();
      if (aal?.currentLevel === 'aal2') { setEtat('ok'); return; }

      const { data: factorsData } = await supabase.auth.mfa.listFactors();
      const phones = (factorsData?.all || []).filter((f: any) => f.factor_type === 'phone');
      const verified = phones.find((f: any) => f.status === 'verified');
      if (verified) {
        setFactorId(verified.id);
        setTelMasque((verified as any).phone ? `•••• ${String((verified as any).phone).slice(-2)}` : null);
        await envoyerSms(verified.id);
      } else {
        // Nettoie les facteurs non vérifiés en attente.
        for (const f of phones.filter((p: any) => p.status === 'unverified')) {
          try { await supabase.auth.mfa.unenroll({ factorId: f.id }); } catch { /* ignore */ }
        }
        setEtat('saisie_tel');
      }
    } catch {
      toast.error('Erreur lors de la vérification MFA.');
      setEtat('saisie_tel');
    }
  }, [envoyerSms]);

  useEffect(() => { evaluer(); }, [evaluer]);

  async function enroler() {
    const num = tel.trim();
    if (!/^\+?[0-9\s]{8,15}$/.test(num)) { toast.error('Numéro invalide (format international, ex. +33612345678).'); return; }
    setBusy(true);
    try {
      const { data: enroll, error } = await supabase.auth.mfa.enroll({ factorType: 'phone', phone: num.replace(/\s/g, '') } as any);
      if (error || !enroll) { toast.error(error?.message || "Impossible d'initialiser le MFA SMS."); setBusy(false); return; }
      setFactorId((enroll as any).id);
      await envoyerSms((enroll as any).id);
    } catch (e: any) {
      toast.error(e?.message || 'Erreur enrôlement.');
    }
    setBusy(false);
  }

  async function verifier() {
    if (!factorId || !challengeId || code.trim().length < 6) { toast.error('Saisissez le code à 6 chiffres reçu par SMS.'); return; }
    setBusy(true);
    try {
      const { error } = await supabase.auth.mfa.verify({ factorId, challengeId, code: code.trim() });
      if (error) { toast.error('Code incorrect ou expiré. Réessayez.'); setBusy(false); return; }
      toast.success('Double authentification validée.');
      setCode('');
      await evaluer();
    } catch {
      toast.error('Erreur de vérification.');
    }
    setBusy(false);
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
          <h1 className="text-xl font-bold text-foreground">Double authentification (SMS)</h1>
        </div>

        {etat === 'saisie_tel' ? (
          <>
            <p className="text-sm text-muted-foreground">L'accès administrateur exige une double authentification. Saisissez votre numéro de mobile : un code de validation vous sera envoyé par SMS à chaque connexion.</p>
            <label className="block">
              <span className="text-xs font-medium text-foreground mb-1 block inline-flex items-center gap-1"><Smartphone className="h-3.5 w-3.5" /> Numéro de mobile</span>
              <input value={tel} onChange={(e) => setTel(e.target.value)} placeholder="+33 6 12 34 56 78" className="input-base"
                onKeyDown={(e) => { if (e.key === 'Enter') enroler(); }} />
            </label>
            <button type="button" onClick={enroler} disabled={busy} className="btn-primary w-full disabled:opacity-50 inline-flex items-center justify-center gap-2">
              {busy ? <Loader2 className="h-4 w-4 animate-spin" /> : <Smartphone className="h-4 w-4" />} Recevoir le code par SMS
            </button>
          </>
        ) : (
          <>
            <p className="text-sm text-muted-foreground">Un code à 6 chiffres a été envoyé par SMS{telMasque ? ` au numéro ${telMasque}` : ''}. Saisissez-le pour accéder à l'administration.</p>
            <input value={code} onChange={(e) => setCode(e.target.value.replace(/\D/g, '').slice(0, 6))} inputMode="numeric" placeholder="123456"
              className="input-base text-center text-lg tracking-[0.4em] font-mono" onKeyDown={(e) => { if (e.key === 'Enter') verifier(); }} />
            <button type="button" onClick={verifier} disabled={busy || code.length < 6} className="btn-primary w-full disabled:opacity-50 inline-flex items-center justify-center gap-2">
              {busy ? <Loader2 className="h-4 w-4 animate-spin" /> : <ShieldCheck className="h-4 w-4" />} Valider
            </button>
            <button type="button" onClick={() => factorId && envoyerSms(factorId)} disabled={busy} className="text-xs text-muted-foreground hover:text-foreground w-full text-center">
              Renvoyer le code
            </button>
          </>
        )}
      </div>
    </div>
  );
}
