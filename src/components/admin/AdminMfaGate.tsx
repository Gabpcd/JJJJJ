import { type ReactNode, useCallback, useEffect, useState } from 'react';
import { Copy, Loader2, LogOut, ShieldCheck } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { useAuth } from '@/contexts/AuthContext';
import { toast } from 'sonner';

type Etat = 'CHARGEMENT' | 'ENROLEMENT' | 'CHALLENGE' | 'VERIFIE' | 'ERREUR';

interface EnrolementTotp {
  id: string;
  qrCode: string;
  secret: string;
}
export function AdminMfaGate({ children }: { children: ReactNode }) {
  const { user, deconnexion } = useAuth();
  const [etat, setEtat] = useState<Etat>('CHARGEMENT');
  const [factorId, setFactorId] = useState<string | null>(null);
  const [enrolement, setEnrolement] = useState<EnrolementTotp | null>(null);
  const [code, setCode] = useState('');
  const [envoi, setEnvoi] = useState(false);
  const [erreur, setErreur] = useState<string | null>(null);
  const [bypassDev, setBypassDev] = useState(
    () => import.meta.env.DEV && sessionStorage.getItem('jolene_admin_mfa_dev_bypass') === '1',
  );

  const verifierNiveau = useCallback(async () => {
    if (!user) return;
    setErreur(null);
    setEtat('CHARGEMENT');

    const [{ data: facteurs, error: facteursErreur }, { data: niveau, error: niveauErreur }] = await Promise.all([
      supabase.auth.mfa.listFactors(),
      supabase.auth.mfa.getAuthenticatorAssuranceLevel(),
    ]);

    if (facteursErreur || niveauErreur) {
      setErreur('Impossible de vérifier la protection multifacteur de cette session.');
      setEtat('ERREUR');
      return;
    }

    if (niveau?.currentLevel === 'aal2') {
      setEtat('VERIFIE');
      return;
    }

    const facteurVerifie = facteurs?.totp?.find((facteur) => facteur.status === 'verified');
    if (facteurVerifie) {
      setFactorId(facteurVerifie.id);
      setEtat('CHALLENGE');
      return;
    }

    setEtat('ENROLEMENT');
  }, [user]);

  useEffect(() => {
    if (bypassDev) return;
    verifierNiveau();
  }, [bypassDev, verifierNiveau]);

  const commencerEnrolement = async () => {
    setEnvoi(true);
    setErreur(null);
    const { data, error } = await supabase.auth.mfa.enroll({
      factorType: 'totp',
      friendlyName: 'Administration Jolene',
    });
    setEnvoi(false);

    if (error || !data?.id || !data.totp?.qr_code || !data.totp?.secret) {
      setErreur('La configuration de l’authentificateur a échoué. Réessayez ou contactez le support technique.');
      return;
    }

    setFactorId(data.id);
    setEnrolement({ id: data.id, qrCode: data.totp.qr_code, secret: data.totp.secret });
  };

  const validerCode = async () => {
    if (!factorId || !/^\d{6}$/.test(code)) return;
    setEnvoi(true);
    setErreur(null);
    const { error } = await supabase.auth.mfa.challengeAndVerify({ factorId, code });
    setEnvoi(false);

    if (error) {
      setErreur('Code invalide ou expiré. Saisissez le code actuel de votre authentificateur.');
      setCode('');
      return;
    }

    await supabase.auth.refreshSession();
    setEtat('VERIFIE');
    toast.success('Session administrateur protégée');
  };

  const activerBypassDev = () => {
    sessionStorage.setItem('jolene_admin_mfa_dev_bypass', '1');
    setBypassDev(true);
  };

  if (bypassDev || etat === 'VERIFIE') return <>{children}</>;

  return (
    <section className="mx-auto mt-10 max-w-lg rounded-2xl border border-border bg-card p-5 shadow-sm" aria-labelledby="admin-mfa-title">
      <div className="mb-4 flex items-start gap-3">
        <div className="rounded-xl bg-primary/10 p-2 text-primary">
          <ShieldCheck className="h-6 w-6" aria-hidden="true" />
        </div>
        <div>
          <h1 id="admin-mfa-title" className="text-lg font-bold text-foreground">Double authentification requise</h1>
          <p className="mt-1 text-sm text-muted-foreground">Les données et actions d’administration nécessitent un second facteur TOTP.</p>
        </div>
      </div>

      {etat === 'CHARGEMENT' && (
        <div className="flex min-h-24 items-center justify-center gap-2 text-sm text-muted-foreground" role="status">
          <Loader2 className="h-4 w-4 animate-spin" aria-hidden="true" /> Vérification de la session…
        </div>
      )}

      {etat === 'ENROLEMENT' && !enrolement && (
        <div className="space-y-4">
          <p className="text-sm text-foreground">Associez une application d’authentification avant d’accéder à l’interface admin.</p>
          <button type="button" onClick={commencerEnrolement} disabled={envoi} className="btn-primary w-full disabled:opacity-50">
            {envoi ? 'Préparation…' : 'Configurer mon authentificateur'}
          </button>
        </div>
      )}

      {etat === 'ENROLEMENT' && enrolement && (
        <div className="space-y-4">
          <div className="mx-auto w-fit rounded-xl border border-border bg-white p-3">
            <img src={enrolement.qrCode} alt="QR code de configuration de l’authentificateur Jolene" className="h-44 w-44" />
          </div>
          <p className="text-sm text-foreground">Scannez ce QR code, puis saisissez le code à six chiffres affiché par l’application.</p>
          <div>
            <p className="mb-1 text-xs font-medium text-muted-foreground">Clé de saisie manuelle</p>
            <div className="flex items-center gap-2 rounded-lg bg-muted px-3 py-2">
              <code className="min-w-0 flex-1 break-all text-xs text-foreground">{enrolement.secret}</code>
              <button
                type="button"
                onClick={() => navigator.clipboard.writeText(enrolement.secret).then(() => toast.success('Clé copiée'))}
                className="inline-flex min-h-11 min-w-11 items-center justify-center rounded-lg hover:bg-background"
                aria-label="Copier la clé de configuration"
              >
                <Copy className="h-4 w-4" aria-hidden="true" />
              </button>
            </div>
          </div>
        </div>
      )}

      {(etat === 'CHALLENGE' || enrolement) && (
        <form className="mt-4 space-y-3" onSubmit={(event) => { event.preventDefault(); validerCode(); }}>
          <label htmlFor="admin-mfa-code" className="block text-sm font-medium text-foreground">Code de sécurité</label>
          <input
            id="admin-mfa-code"
            value={code}
            onChange={(event) => setCode(event.target.value.replace(/\D/g, '').slice(0, 6))}
            inputMode="numeric"
            autoComplete="one-time-code"
            pattern="[0-9]{6}"
            className="input-base w-full text-center font-mono text-xl tracking-[0.4em]"
            aria-describedby={erreur ? 'admin-mfa-error' : undefined}
            autoFocus
          />
          <button type="submit" disabled={envoi || code.length !== 6} className="btn-primary w-full disabled:opacity-50">
            {envoi ? 'Vérification…' : enrolement ? 'Activer et continuer' : 'Vérifier et continuer'}
          </button>
        </form>
      )}

      {erreur && <p id="admin-mfa-error" className="mt-3 text-sm font-medium text-destructive" role="alert">{erreur}</p>}

      {etat === 'ERREUR' && (
        <button type="button" onClick={verifierNiveau} className="btn-secondary mt-4 w-full">Réessayer</button>
      )}

      <div className="mt-5 flex flex-col gap-2 border-t border-border pt-4 sm:flex-row">
        <button type="button" onClick={deconnexion} className="btn-secondary inline-flex flex-1 items-center justify-center gap-2">
          <LogOut className="h-4 w-4" aria-hidden="true" /> Se déconnecter
        </button>
        {import.meta.env.DEV && (
          <button type="button" onClick={activerBypassDev} className="btn-secondary flex-1">Continuer en local</button>
        )}
      </div>
    </section>
  );
}
