import { useState } from 'react';
import { Loader2, Phone, ShieldCheck, AlertCircle } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { useNotification } from '@/contexts/NotificationContext';

interface Props {
  /** Téléphone à vérifier (sera saisi dans le composant si non passé) */
  telephoneInitial?: string;
  /** Callback quand la vérification OTP réussit avec le téléphone vérifié */
  onVerifie?: (telephone: string) => void;
  /** Variant compact (sans titre) */
  compact?: boolean;
}

/**
 * Composant verification téléphone par OTP SMS.
 *
 * Sprint 6 PR 9 — Fix P1-12 audit Sprint 5.
 *
 * Workflow :
 * 1. Utilisateur saisit/confirme son téléphone
 * 2. Click "Envoyer le code SMS" → fn_envoyer_otp_telephone (rate limit 3/24h)
 * 3. Saisie code 6 chiffres reçu par SMS
 * 4. Click "Vérifier" → fn_verifier_otp_telephone (5 tentatives max, expiration 10min)
 * 5. Au succès : telephone_verifie=true côté DB
 */
export function VerificationTelephoneOTP({ telephoneInitial = '', onVerifie, compact = false }: Props) {
  const { afficherNotification } = useNotification();
  const [etape, setEtape] = useState<'saisie' | 'verification'>('saisie');
  const [telephone, setTelephone] = useState(telephoneInitial);
  const [code, setCode] = useState('');
  const [loading, setLoading] = useState(false);

  async function envoyerOtp() {
    if (!telephone.trim()) {
      afficherNotification({ type: 'erreur', message: 'Saisis un numéro de téléphone.' });
      return;
    }
    setLoading(true);
    const { data, error } = await supabase.rpc('fn_envoyer_otp_telephone' as any, {
      p_telephone: telephone.trim(),
    });
    setLoading(false);
    const result = data as any;
    if (error || !result?.success) {
      const code = result?.error_code;
      const msg = code === 'RATE_LIMIT'
        ? "Trop d'envois SMS (3/24h max). Réessaie demain."
        : code === 'TELEPHONE_INVALIDE'
          ? "Téléphone invalide. Format attendu : +33 6 12 34 56 78"
          : error?.message || result?.error || 'Erreur envoi SMS.';
      afficherNotification({ type: 'erreur', message: msg });
      return;
    }
    afficherNotification({ type: 'succes', message: 'Code SMS envoyé. Vérifie ton téléphone.' });
    setEtape('verification');
  }

  async function verifierCode() {
    if (!/^\d{6}$/.test(code)) {
      afficherNotification({ type: 'erreur', message: 'Le code doit comporter 6 chiffres.' });
      return;
    }
    setLoading(true);
    const { data, error } = await supabase.rpc('fn_verifier_otp_telephone' as any, {
      p_code: code,
    });
    setLoading(false);
    const result = data as any;
    if (error || !result?.success) {
      const errCode = result?.error_code;
      let msg = 'Erreur vérification.';
      if (errCode === 'CODE_INCORRECT') {
        msg = `Code incorrect. ${result.tentatives_restantes ?? 0} tentative(s) restante(s).`;
      } else if (errCode === 'OTP_INEXISTANT_OU_EXPIRE') {
        msg = 'Code expiré (10 min). Demande un nouveau code.';
      } else if (errCode === 'TROP_TENTATIVES') {
        msg = 'Trop de tentatives. Demande un nouveau code SMS.';
      } else if (error?.message) {
        msg = error.message;
      }
      afficherNotification({ type: 'erreur', message: msg });
      return;
    }
    afficherNotification({ type: 'succes', message: 'Téléphone vérifié ✓' });
    onVerifie?.(result.telephone);
    setEtape('saisie');
    setCode('');
  }

  return (
    <div className={compact ? 'space-y-2' : 'card-base space-y-3'}>
      {!compact && (
        <div className="flex items-center gap-2">
          <Phone className="h-5 w-5 text-primary" />
          <h3 className="text-sm font-bold text-foreground">Vérifier mon téléphone</h3>
        </div>
      )}

      {etape === 'saisie' ? (
        <>
          <label className="block">
            <span className="text-xs font-medium text-foreground mb-1 block">Numéro de téléphone</span>
            <input
              type="tel"
              value={telephone}
              onChange={(e) => setTelephone(e.target.value)}
              className="input-base"
              placeholder="+33 6 12 34 56 78"
              autoComplete="tel"
              disabled={loading}
            />
          </label>
          <p className="text-[11px] text-muted-foreground inline-flex items-start gap-1">
            <AlertCircle className="h-3 w-3 shrink-0 mt-0.5" />
            Un SMS contenant un code à 6 chiffres sera envoyé. Limite : 3 SMS / 24h par numéro.
          </p>
          <button
            type="button"
            onClick={envoyerOtp}
            disabled={loading || !telephone.trim()}
            className="btn-primary text-sm inline-flex items-center gap-2 disabled:opacity-50"
          >
            {loading && <Loader2 className="h-4 w-4 animate-spin" />}
            Envoyer le code SMS
          </button>
        </>
      ) : (
        <>
          <p className="text-xs text-muted-foreground">
            Code envoyé au <strong>{telephone}</strong>. Valide 10 minutes, 5 tentatives max.
          </p>
          <label className="block">
            <span className="text-xs font-medium text-foreground mb-1 block">Code à 6 chiffres</span>
            <input
              type="text"
              inputMode="numeric"
              pattern="\d{6}"
              maxLength={6}
              value={code}
              onChange={(e) => setCode(e.target.value.replace(/\D/g, ''))}
              className="input-base font-mono text-center text-lg tracking-widest"
              placeholder="000000"
              autoComplete="one-time-code"
              disabled={loading}
            />
          </label>
          <div className="flex gap-2">
            <button
              type="button"
              onClick={() => { setEtape('saisie'); setCode(''); }}
              disabled={loading}
              className="btn-secondary text-sm disabled:opacity-50"
            >
              Changer de numéro
            </button>
            <button
              type="button"
              onClick={verifierCode}
              disabled={loading || code.length !== 6}
              className="btn-primary text-sm inline-flex items-center gap-2 disabled:opacity-50 flex-1"
            >
              {loading ? <Loader2 className="h-4 w-4 animate-spin" /> : <ShieldCheck className="h-4 w-4" />}
              Vérifier
            </button>
          </div>
        </>
      )}
    </div>
  );
}
