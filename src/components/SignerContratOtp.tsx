import { useState, useEffect } from 'react';
import { Loader2, ShieldCheck, MessageSquare, Clock, AlertCircle } from 'lucide-react';
import { supabase } from '@/integrations/supabase/client';
import { useNotification } from '@/contexts/NotificationContext';

interface Props {
  contratId: string;
  /** Hash SHA-256 du PDF/HTML affiché à l'utilisateur (preuve d'intégrité). */
  hashDocument?: string | null;
  /** Image base64 de la signature manuscrite (optionnel, complément). */
  signatureImage?: string | null;
  /** Callback appelé après signature réussie. */
  onSigne?: (params: { role: string; contratComplet: boolean }) => void;
}

type Etape = 'idle' | 'otp_envoye' | 'signe';

const OTP_DUREE_SEC = 10 * 60;

/**
 * Module signature électronique sécurisée Jolene avec OTP SMS systématique
 * (PR 4 Sprint 1).
 *
 * Flow utilisateur :
 *   1. Coche "j'ai lu et j'accepte" → clic "Recevoir code SMS"
 *   2. SMS reçu avec OTP 6 chiffres (valide 10 min, max 5 tentatives)
 *   3. Saisit OTP + clic "Signer"
 *   4. Backend valide OTP + hash + insère signatures_contrats + update
 *      contrats_mission (mode_signature='JOLENE_OTP')
 *
 * Sécurité : OTP SMS (Option A max), hash SHA-256 du document, IP/UA
 * capturés serveur via request.headers, audit dans signatures_contrats.
 *
 * Mention juridique art. 1366-1367 Code civil (signature électronique
 * simple/avancée renforcée par OTP + horodatage + IP).
 */
export function SignerContratOtp({ contratId, hashDocument, signatureImage, onSigne }: Props) {
  const { afficherNotification } = useNotification();
  const [etape, setEtape] = useState<Etape>('idle');
  const [otp, setOtp] = useState('');
  const [accepte, setAccepte] = useState(false);
  const [loading, setLoading] = useState(false);
  const [telMasked, setTelMasked] = useState<string | null>(null);
  const [tentativesRestantes, setTentativesRestantes] = useState<number | null>(null);
  const [secondesRestantes, setSecondesRestantes] = useState(0);

  // Timer countdown 10 min après envoi OTP
  useEffect(() => {
    if (etape !== 'otp_envoye' || secondesRestantes <= 0) return;
    const interval = setInterval(() => {
      setSecondesRestantes(s => Math.max(0, s - 1));
    }, 1000);
    return () => clearInterval(interval);
  }, [etape, secondesRestantes]);

  const otpExpire = etape === 'otp_envoye' && secondesRestantes === 0;
  const mmss = `${String(Math.floor(secondesRestantes / 60)).padStart(2, '0')}:${String(secondesRestantes % 60).padStart(2, '0')}`;

  async function envoyerOtp() {
    setLoading(true);
    setTentativesRestantes(null);
    try {
      const { data, error } = await supabase.rpc('fn_envoyer_otp_signature' as any, { p_contrat_id: contratId });
      if (error) throw error;
      const result = data as any;
      if (!result?.success) {
        afficherNotification({ type: 'erreur', message: result?.error || 'Erreur envoi OTP' });
        return;
      }
      setTelMasked(result.telephone_masked || null);
      setSecondesRestantes(OTP_DUREE_SEC);
      setOtp('');
      setEtape('otp_envoye');
      afficherNotification({ type: 'succes', message: `Code envoyé au ${result.telephone_masked}. Valide ${result.expire_dans_minutes} min.` });
    } catch (err: any) {
      afficherNotification({ type: 'erreur', message: err?.message || 'Erreur envoi OTP' });
    } finally {
      setLoading(false);
    }
  }

  async function signer() {
    if (!/^[0-9]{6}$/.test(otp)) {
      afficherNotification({ type: 'erreur', message: 'Code à 6 chiffres requis.' });
      return;
    }
    if (!accepte) {
      afficherNotification({ type: 'erreur', message: 'Vous devez accepter les termes du contrat avant de signer.' });
      return;
    }
    setLoading(true);
    try {
      const { data, error } = await supabase.rpc('fn_signer_contrat_otp' as any, {
        p_contrat_id: contratId,
        p_otp_code: otp,
        p_hash_document: hashDocument || null,
        p_signature_image: signatureImage || null,
      });
      if (error) throw error;
      const result = data as any;
      if (!result?.success) {
        afficherNotification({ type: 'erreur', message: result?.error || 'Erreur de signature' });
        if (typeof result?.tentatives_restantes === 'number') {
          setTentativesRestantes(result.tentatives_restantes);
        }
        return;
      }
      setEtape('signe');
      afficherNotification({ type: 'succes', message: `Contrat signé ✅${result.contrat_complet ? ' — Mission confirmée par les 2 parties.' : ''}` });
      onSigne?.({ role: result.role, contratComplet: result.contrat_complet });
    } catch (err: any) {
      afficherNotification({ type: 'erreur', message: err?.message || 'Erreur de signature' });
    } finally {
      setLoading(false);
    }
  }

  if (etape === 'signe') {
    return (
      <div className="rounded-xl border border-emerald-200 dark:border-emerald-800 bg-emerald-50/60 dark:bg-emerald-950/30 p-4 flex items-start gap-3 animate-in fade-in duration-300">
        <ShieldCheck className="h-5 w-5 text-emerald-600 dark:text-emerald-400 shrink-0 mt-0.5" />
        <div>
          <p className="font-semibold text-emerald-900 dark:text-emerald-200">Signature électronique sécurisée Jolene</p>
          <p className="text-xs text-emerald-800 dark:text-emerald-300 mt-1">
            Signé avec succès. Horodatage, IP et hash du document conservés (art. 1366-1367 Code civil).
          </p>
        </div>
      </div>
    );
  }

  return (
    <div className="rounded-xl border border-border bg-card p-4 space-y-3">
      <div className="flex items-start gap-2">
        <MessageSquare className="h-5 w-5 text-primary shrink-0 mt-0.5" />
        <div>
          <p className="text-sm font-semibold text-foreground">Signature électronique sécurisée</p>
          <p className="text-xs text-muted-foreground mt-0.5">
            Recevez un code à 6 chiffres par SMS et saisissez-le ci-dessous pour signer.
            La signature inclut horodatage, IP et hash du document (preuve juridique art. 1366 Code civil).
          </p>
        </div>
      </div>

      <label className="flex items-start gap-2 cursor-pointer">
        <input
          type="checkbox"
          checked={accepte}
          onChange={e => setAccepte(e.target.checked)}
          className="mt-0.5 accent-primary"
        />
        <span className="text-xs text-foreground">
          J'ai lu l'intégralité du contrat affiché ci-dessus et j'accepte ses termes.
        </span>
      </label>

      {etape === 'idle' && (
        <button
          type="button"
          onClick={envoyerOtp}
          disabled={!accepte || loading}
          className="btn-primary w-full disabled:opacity-50 disabled:cursor-not-allowed inline-flex items-center justify-center gap-2"
        >
          {loading && <Loader2 className="h-4 w-4 animate-spin" />}
          Recevoir le code SMS pour signer
        </button>
      )}

      {etape === 'otp_envoye' && (
        <>
          <div className="flex items-center justify-between text-xs">
            <span className="text-muted-foreground">
              Code envoyé au <strong>{telMasked || 'numéro masqué'}</strong>
            </span>
            <span className={`inline-flex items-center gap-1 font-mono ${otpExpire ? 'text-destructive' : 'text-muted-foreground'}`}>
              <Clock className="h-3 w-3" />
              {otpExpire ? 'Expiré' : mmss}
            </span>
          </div>

          <input
            type="text"
            inputMode="numeric"
            pattern="[0-9]{6}"
            maxLength={6}
            value={otp}
            onChange={e => setOtp(e.target.value.replace(/\D/g, '').slice(0, 6))}
            placeholder="123456"
            disabled={otpExpire}
            className="input-base text-center text-lg tracking-widest font-mono disabled:opacity-50"
            aria-label="Code SMS à 6 chiffres"
          />

          {tentativesRestantes != null && tentativesRestantes < 5 && (
            <div className="flex items-center gap-1.5 text-xs text-warning">
              <AlertCircle className="h-3.5 w-3.5" />
              {tentativesRestantes > 0
                ? `Code incorrect. ${tentativesRestantes} tentative${tentativesRestantes > 1 ? 's' : ''} restante${tentativesRestantes > 1 ? 's' : ''}.`
                : `Trop de tentatives. Renvoyez un nouveau code SMS.`}
            </div>
          )}

          <div className="flex gap-2">
            <button
              type="button"
              onClick={envoyerOtp}
              disabled={loading}
              className="btn-secondary flex-1 disabled:opacity-50"
            >
              {otpExpire ? 'Recevoir un nouveau code' : 'Renvoyer le code'}
            </button>
            <button
              type="button"
              onClick={signer}
              disabled={!accepte || otp.length !== 6 || loading || otpExpire}
              className="btn-primary flex-1 disabled:opacity-50 disabled:cursor-not-allowed inline-flex items-center justify-center gap-2"
            >
              {loading && <Loader2 className="h-4 w-4 animate-spin" />}
              Signer
            </button>
          </div>
        </>
      )}
    </div>
  );
}
