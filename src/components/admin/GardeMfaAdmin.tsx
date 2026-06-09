import { useEffect, useState, useCallback } from 'react';
import { ShieldCheck, Loader2 } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { toast } from 'sonner';

/**
 * Garde MFA obligatoire pour les administrateurs plateforme.
 *
 * Tant que la session admin n'est pas au niveau AAL2 (double authentification
 * vérifiée), on affiche soit l'enrôlement TOTP (aucun facteur), soit le challenge
 * (facteur existant). Conçu pour NE JAMAIS verrouiller : l'enrôlement reste toujours
 * accessible. Une fois AAL2 atteint, le contenu admin est rendu normalement.
 *
 * Récupération en cas de souci : un facteur peut être supprimé depuis le dashboard
 * Supabase (Authentication > Users).
 */
export function GardeMfaAdmin({ children }: { children: React.ReactNode }) {
  const [etat, setEtat] = useState<'chargement' | 'ok' | 'enroll' | 'challenge'>('chargement');
  const [factorId, setFactorId] = useState<string | null>(null);
  const [qr, setQr] = useState<string | null>(null);
  const [secret, setSecret] = useState<string | null>(null);
  const [code, setCode] = useState('');
  const [busy, setBusy] = useState(false);
  const [challengeId, setChallengeId] = useState<string | null>(null);

  const evaluer = useCallback(async () => {
    setEtat('chargement');
    try {
      const { data: aal } = await supabase.auth.mfa.getAuthenticatorAssuranceLevel();
      if (aal?.currentLevel === 'aal2') { setEtat('ok'); return; }

      const { data: factorsData } = await supabase.auth.mfa.listFactors();
      const verified = (factorsData?.totp || []).find((f: any) => f.status === 'verified');
      if (verified) {
        setFactorId(verified.id);
        setEtat('challenge');
      } else {
        // Nettoie un éventuel facteur non vérifié resté en attente.
        const unverified = (factorsData?.all || []).filter((f: any) => f.status === 'unverified');
        for (const f of unverified) { try { await supabase.auth.mfa.unenroll({ factorId: f.id }); } catch { /* ignore */ } }
        const { data: enroll, error } = await supabase.auth.mfa.enroll({ factorType: 'totp', friendlyName: `admin-${Date.now()}` });
        if (error || !enroll) { toast.error("Impossible d'initialiser la double authentification."); setEtat('challenge'); return; }
        setFactorId(enroll.id);
        setQr((enroll as any).totp?.qr_code || null);
        setSecret((enroll as any).totp?.secret || null);
        setEtat('enroll');
      }
    } catch {
      toast.error('Erreur lors de la vérification MFA.');
      setEtat('challenge');
    }
  }, []);

  useEffect(() => { evaluer(); }, [evaluer]);

  async function verifier() {
    if (!factorId || code.trim().length < 6) { toast.error('Saisissez le code à 6 chiffres.'); return; }
    setBusy(true);
    try {
      const { data: ch, error: chErr } = await supabase.auth.mfa.challenge({ factorId });
      const cid = ch?.id || challengeId;
      if (chErr || !cid) { toast.error('Échec du challenge MFA.'); setBusy(false); return; }
      setChallengeId(cid);
      const { error: vErr } = await supabase.auth.mfa.verify({ factorId, challengeId: cid, code: code.trim() });
      if (vErr) { toast.error('Code incorrect. Réessayez.'); setBusy(false); return; }
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
          <h1 className="text-xl font-bold text-foreground">Double authentification requise</h1>
        </div>
        <p className="text-sm text-muted-foreground">
          L'accès administrateur est protégé par une double authentification (2FA) obligatoire.
          {etat === 'enroll'
            ? " Scannez ce QR code avec votre application d'authentification (Google Authenticator, Authy…), puis saisissez le code généré."
            : ' Saisissez le code à 6 chiffres de votre application d\'authentification.'}
        </p>

        {etat === 'enroll' && (
          <div className="space-y-2">
            {qr && (
              <div className="flex justify-center bg-white rounded-xl p-3">
                {/* qr_code Supabase = SVG (data URL ou markup) */}
                {qr.startsWith('data:') ? <img src={qr} alt="QR code MFA" className="h-44 w-44" /> : <div className="h-44 w-44" dangerouslySetInnerHTML={{ __html: qr }} />}
              </div>
            )}
            {secret && (
              <p className="text-xs text-muted-foreground text-center">
                Clé manuelle : <code className="bg-muted px-2 py-0.5 rounded text-foreground break-all">{secret}</code>
              </p>
            )}
          </div>
        )}

        <input
          value={code}
          onChange={(e) => setCode(e.target.value.replace(/\D/g, '').slice(0, 6))}
          inputMode="numeric"
          placeholder="123456"
          className="input-base text-center text-lg tracking-[0.4em] font-mono"
          onKeyDown={(e) => { if (e.key === 'Enter') verifier(); }}
        />
        <button
          type="button"
          onClick={verifier}
          disabled={busy || code.length < 6}
          className="btn-primary w-full disabled:opacity-50 inline-flex items-center justify-center gap-2"
        >
          {busy ? <Loader2 className="h-4 w-4 animate-spin" /> : <ShieldCheck className="h-4 w-4" />}
          {etat === 'enroll' ? 'Activer la 2FA' : 'Valider'}
        </button>
      </div>
    </div>
  );
}
